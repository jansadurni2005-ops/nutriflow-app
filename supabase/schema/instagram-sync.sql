-- Single-account, server-only metadata. No DM bodies, no service keys in the browser.
create table public.nf_ig_sync_control (
 id int primary key check(id=1), sync_key text not null default encode(extensions.gen_random_bytes(32),'hex'),
 device_hash text, refresh_attempt timestamptz, cursor_value text, since_at timestamptz, pass_at timestamptz,
 lease_until timestamptz not null default '-infinity', last_ok timestamptz, last_error text, device_seen timestamptz
);
insert into public.nf_ig_sync_control(id) values(1);
create table public.nf_ig_sync_threads (
 thread_id text primary key, peer text not null unique, handle text not null default '', revision text not null, latest_at timestamptz not null,
 seen_count int not null default 0, outgoing_count int not null default 0, incoming_count int not null default 0,
 classified_revision text, level text check(level in ('hot','warm','neutral','cold','unknown')), flags text[] not null default '{}',
 review boolean not null default true, last_written_interest text
);
create table public.nf_ig_sync_observed (
 mid text primary key, thread_id text not null references public.nf_ig_sync_threads(thread_id) on delete cascade,
 sent_at timestamptz not null, outgoing boolean not null, manual boolean not null default false
);
create index nf_ig_observed_tid on public.nf_ig_sync_observed(thread_id,sent_at);
alter table public.nf_ig_sync_control enable row level security;
alter table public.nf_ig_sync_threads enable row level security;
alter table public.nf_ig_sync_observed enable row level security;
revoke all on public.nf_ig_sync_control,public.nf_ig_sync_threads,public.nf_ig_sync_observed from public,anon,authenticated;
grant select,insert,update,delete on public.nf_ig_sync_control,public.nf_ig_sync_threads,public.nf_ig_sync_observed to service_role;

create function public.nf_ig_project_interest(p_thread text) returns void language plpgsql security invoker set search_path='' as $$
declare t public.nf_ig_sync_threads%rowtype; lid text; v text; owner_id constant uuid:='f209b91f-607b-4b14-9305-6a7d567b90b5';
begin
 select * into t from public.nf_ig_sync_threads where thread_id=p_thread for update;
 if t.classified_revision is distinct from t.revision or t.level is null then return;end if;
 select c.lead_id into lid from public.nf_instagram_conversations c where c.account_id='17841449201493232' and c.user_id=owner_id and c.contact_id=t.peer and c.qualified_at is not null;
 if lid is null then return;end if;
 v:=case when t.flags && array['do_not_contact','current_client'] then 'low' when t.review then 'unknown' when t.level='hot' then 'high' when t.level='warm' then 'medium' when t.level='cold' then 'low' else 'unknown' end;
 update public.leads set lead_interest=v where id=lid and user_id=owner_id and status in ('Contacted','New') and (lead_interest is null or lead_interest='unknown' or lead_interest=t.last_written_interest);
 if found then update public.nf_ig_sync_threads set last_written_interest=v where thread_id=p_thread;end if;
end;$$;

create function public.nf_ig_observe(p_tid text,p_peer text,p_handle text,p_rev text,p_latest timestamptz,p_rows jsonb) returns void language plpgsql security invoker set search_path='' as $$
declare row_ jsonb; t public.nf_ig_sync_threads%rowtype; ts timestamptz; o boolean; owner_id constant uuid:='f209b91f-607b-4b14-9305-6a7d567b90b5';
begin
 if p_peer !~ '^[0-9]{1,40}$' or p_peer='17841449201493232' or p_rev !~ '^[0-9a-f]{64}$' or length(p_tid) not between 1 and 512 or p_handle !~ '^[a-z0-9_.]{0,64}$' or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>40 then raise exception 'invalid observation';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text,0));
 insert into public.nf_ig_sync_threads(thread_id,peer,handle,revision,latest_at) values(p_tid,p_peer,p_handle,p_rev,p_latest) on conflict(thread_id) do nothing;
 select * into strict t from public.nf_ig_sync_threads where thread_id=p_tid for update;
 if t.peer<>p_peer then raise exception 'conflicting participants';end if;
 if t.latest_at>p_latest then return;end if;
 update public.nf_ig_sync_threads set revision=p_rev,latest_at=p_latest,handle=coalesce(nullif(p_handle,''),handle) where thread_id=p_tid;
 for row_ in select value from jsonb_array_elements(p_rows) loop
   ts:=(row_->>'at')::timestamptz;o:=(row_->>'outgoing')::boolean;
   if length(row_->>'id') not between 1 and 300 or ts>now()+interval '5 minutes' then raise exception 'invalid observation';end if;
   insert into public.nf_ig_sync_observed values(row_->>'id',p_tid,ts,o,false) on conflict(mid) do nothing;
   if exists(select 1 from public.nf_ig_sync_observed where mid=row_->>'id' and (thread_id<>p_tid or sent_at<>ts or outgoing<>o)) then raise exception 'conflicting message';end if;
   if not o then perform public.nf_record_instagram_turn(owner_id,'17841449201493232',p_peer,row_->>'id',ts,'in',false,p_handle);
   elsif (row_->>'human')::boolean is true then
      perform public.nf_record_instagram_turn(owner_id,'17841449201493232',p_peer,row_->>'id',ts,'out',true,p_handle);
      update public.nf_ig_sync_observed set manual=true where mid=row_->>'id';
   end if;
 end loop;
 update public.nf_ig_sync_threads set (seen_count,outgoing_count,incoming_count)=(select count(*),count(*) filter(where outgoing),count(*) filter(where not outgoing) from public.nf_ig_sync_observed where thread_id=p_tid) where thread_id=p_tid;
 perform public.nf_ig_project_interest(p_tid);
end;$$;

-- Only the authenticated owner path may attest that particular observed OUTGOING IDs were typed by Jan.
create function public.nf_ig_confirm_outgoing(p_tid text,p_rev text,p_ids text[]) returns text language plpgsql security invoker set search_path='' as $$
declare t public.nf_ig_sync_threads%rowtype; m record; answer jsonb; owner_id constant uuid:='f209b91f-607b-4b14-9305-6a7d567b90b5';
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text,0));
 select * into strict t from public.nf_ig_sync_threads where thread_id=p_tid for update;
 if t.revision<>p_rev or cardinality(p_ids) not between 1 and 20 or cardinality(p_ids)<>(select count(*) from public.nf_ig_sync_observed where thread_id=p_tid and outgoing and mid=any(p_ids)) then raise exception 'invalid selection or stale thread';end if;
 for m in select * from public.nf_ig_sync_observed where thread_id=p_tid and outgoing and mid=any(p_ids) order by sent_at,mid loop
   answer:=public.nf_record_instagram_turn(owner_id,'17841449201493232',t.peer,m.mid,m.sent_at,'out',true,t.handle);
   update public.nf_ig_sync_observed set manual=true where mid=m.mid;
 end loop;
 perform public.nf_ig_project_interest(p_tid);
 return answer->>'action';
end;$$;

create function public.nf_ig_scored(p_tid text,p_rev text,p_level text,p_flags text[],p_review boolean) returns boolean language plpgsql security invoker set search_path='' as $$
begin
 if p_level not in ('hot','warm','neutral','cold','unknown') or p_flags is null or not(p_flags <@ array['has_nutritionist','call_accepted','call_scheduled','current_client','do_not_contact','price_objection']) then raise exception 'invalid classification';end if;
 update public.nf_ig_sync_threads set classified_revision=p_rev,level=p_level,review=p_review,flags=array(select distinct x from unnest(p_flags||array(select f from unnest(flags) f where f in ('do_not_contact','current_client'))) x)
 where thread_id=p_tid and revision=p_rev;
 if not found then return false;end if;perform public.nf_ig_project_interest(p_tid);return true;
end;$$;
revoke all on function public.nf_ig_project_interest(text),public.nf_ig_observe(text,text,text,text,timestamptz,jsonb),public.nf_ig_confirm_outgoing(text,text,text[]),public.nf_ig_scored(text,text,text,text[],boolean) from public,anon,authenticated;
grant execute on function public.nf_ig_project_interest(text),public.nf_ig_observe(text,text,text,text,timestamptz,jsonb),public.nf_ig_confirm_outgoing(text,text,text[]),public.nf_ig_scored(text,text,text,text[],boolean) to service_role;
create view public.nf_ig_sync_queue with (security_invoker=true) as select thread_id,revision,latest_at from public.nf_ig_sync_threads where classified_revision is distinct from revision;
revoke all on public.nf_ig_sync_queue from public,anon,authenticated;
grant select on public.nf_ig_sync_queue to service_role;
