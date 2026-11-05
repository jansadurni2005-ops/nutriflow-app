-- Install only after connecting a trusted event source for native Instagram DMs.
-- Does not replace the ManyChat ingestion or infer manual messages from replies.
create table public.nf_instagram_turn_events (
 user_id uuid not null references auth.users(id) on delete cascade,
 account_id text not null,
 contact_id text not null,
 message_id text not null,
 sent_at timestamptz not null,
 direction text not null check(direction in ('out','in')),
 primary key(user_id,account_id,message_id)
);
create index nf_instagram_turn_events_thread_idx on public.nf_instagram_turn_events(user_id,account_id,contact_id,sent_at,message_id);
alter table public.nf_instagram_turn_events enable row level security;
revoke all on public.nf_instagram_turn_events from public,anon,authenticated;
grant all on public.nf_instagram_turn_events to service_role;

create table public.nf_instagram_conversations (
 user_id uuid not null references auth.users(id) on delete cascade,
 account_id text not null,
 contact_id text not null,
 username text,
 lead_id text,
 qualified_at timestamptz,
 primary key(user_id,account_id,contact_id),
 foreign key(lead_id,user_id) references public.leads(id,user_id) on delete set null (lead_id)
);
alter table public.nf_instagram_conversations enable row level security;
revoke all on public.nf_instagram_conversations from public,anon,authenticated;
grant all on public.nf_instagram_conversations to service_role;

create function public.nf_record_instagram_turn(
 p_user uuid,p_account text,p_contact text,p_message text,p_sent_at timestamptz,
 p_direction text,p_manual boolean,p_username text
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 v_handle text:=lower(trim(leading '@' from btrim(coalesce(p_username,''))));
 v_turns text; v_ids text[]; v_id text; v_qualified timestamptz;
begin
 if p_user is null or p_account is null or p_account !~ '^[0-9]{1,40}$'
 or p_contact is null or p_contact !~ '^[0-9]{1,40}$'
 or p_message is null or length(p_message) not between 1 and 300
 or p_sent_at is null or p_sent_at>now()+interval '5 minutes'
 or p_direction is null or p_direction not in ('out','in')
 or (v_handle<>'' and v_handle !~ '^[a-z0-9_.]{1,64}$') then
  raise exception 'invalid_event' using errcode='22023';
 end if;
 -- Unknown provenance must never count as a manual outbound message.
 if p_direction='out' and p_manual is distinct from true then
  return jsonb_build_object('action','ignored_non_manual');
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user::text,0));
 if exists(select 1 from public.nf_instagram_turn_events where user_id=p_user and account_id=p_account and message_id=p_message and (contact_id<>p_contact or direction<>p_direction or sent_at<>p_sent_at)) then
  raise exception 'conflicting_event' using errcode='22023';
 end if;
 insert into public.nf_instagram_turn_events values(p_user,p_account,p_contact,p_message,p_sent_at,p_direction) on conflict do nothing;
 insert into public.nf_instagram_conversations(user_id,account_id,contact_id,username)
 values(p_user,p_account,p_contact,nullif(v_handle,''))
 on conflict(user_id,account_id,contact_id) do update set username=coalesce(excluded.username,nf_instagram_conversations.username);
 select username,lead_id,qualified_at into v_handle,v_id,v_qualified from public.nf_instagram_conversations where user_id=p_user and account_id=p_account and contact_id=p_contact;
 -- Recompute in event time: retries and delayed delivery do not inflate turns.
 -- Several consecutive messages by the same person are one conversational turn.
 select string_agg(direction,',' order by sent_at,message_id) into v_turns from (
  select direction,sent_at,message_id,lag(direction) over(order by sent_at,message_id) as previous
  from public.nf_instagram_turn_events where user_id=p_user and account_id=p_account and contact_id=p_contact
 ) e where previous is distinct from direction;
 if v_turns not like '%out,in,out,in,out%' then return jsonb_build_object('action','waiting');end if;
 if v_qualified is not null then
  return jsonb_build_object('action',case when v_id is null then 'deleted_lead_not_recreated' else 'existing' end,'lead_id',v_id);
 end if;
 if v_handle is null then return jsonb_build_object('action','profile_required');end if;
 if exists(select 1 from public.nf_deleted_leads where user_id=p_user and instagram_handle_hash=pg_catalog.md5(v_handle)) then
  return jsonb_build_object('action','deleted_lead_not_recreated');
 end if;
 -- Stable Instagram handle or existing identity mapping only; never merge display names.
 select coalesce(array_agg(distinct id),'{}') into v_ids from (
  select l.id from public.leads l where l.user_id=p_user and (
   (lower(l.source)='instagram' and lower(trim(leading '@' from btrim(l.name)))=v_handle)
   or (l.source='ManyChat' and lower(trim(leading '@' from btrim(split_part(split_part(coalesce(l.note,''),'·',2),'(',1))))=v_handle)
  )
  union select lead_id from public.nf_manychat_links where user_id=p_user and username=v_handle and state='linked' and lead_id is not null
  union select lead_id from public.nf_instagram_conversations where user_id=p_user and username=v_handle and lead_id is not null
 ) candidates;
 if cardinality(v_ids)>1 then return jsonb_build_object('action','review_required');end if;
 v_id:=case when cardinality(v_ids)=1 then v_ids[1] else 'ig_'||p_account||'_'||p_contact end;
 if exists(select 1 from public.nf_deleted_leads where user_id=p_user and lead_id=v_id) then return jsonb_build_object('action','deleted_lead_not_recreated');end if;
 if cardinality(v_ids)=0 then
  insert into public.leads(id,user_id,name,source,status,note,date,acquisition_type,lead_interest)
  values(v_id,p_user,'@'||v_handle,'Instagram','Contacted','Conversación manual de Instagram: tú → respuesta → tú → respuesta → tú.',(now() at time zone 'Europe/Madrid')::date,'instagram','unknown');
 else
  -- Do not move scheduled calls, sales, or lost leads backwards in the pipeline.
  update public.leads set status='Contacted' where id=v_id and user_id=p_user and status='New';
 end if;
 update public.nf_instagram_conversations set lead_id=v_id,qualified_at=now() where user_id=p_user and account_id=p_account and contact_id=p_contact;
 return jsonb_build_object('action',case when cardinality(v_ids)=0 then 'created' else 'matched_existing' end,'lead_id',v_id);
end;$$;
revoke all on function public.nf_record_instagram_turn(uuid,text,text,text,timestamptz,text,boolean,text) from public,anon,authenticated;
grant execute on function public.nf_record_instagram_turn(uuid,text,text,text,timestamptz,text,boolean,text) to service_role;
