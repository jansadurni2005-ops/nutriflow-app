-- Atomic, tenant-scoped ingestion. Existing lead fields are never overwritten.
alter table public.leads add column if not exists acquisition_type text;
alter table public.leads add column if not exists lead_interest text;

create table public.nf_manychat_links (
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id text not null,
  contact_id text not null,
  lead_id text,
  username text,
  contact_name text not null,
  acquisition_type text not null check (acquisition_type in ('mc_dm','mc_keyword','mc_unknown')),
  state text not null check (state in ('linked','review','deleted')),
  candidate_ids text[] not null default '{}',
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key(user_id,account_id,contact_id),
  foreign key(lead_id,user_id) references public.leads(id,user_id) on delete set null (lead_id)
);
create index nf_manychat_links_lead_idx on public.nf_manychat_links(lead_id);
alter table public.nf_manychat_links enable row level security;
revoke all on public.nf_manychat_links from public,anon,authenticated;
grant select on public.nf_manychat_links to authenticated;
grant all on public.nf_manychat_links to service_role;
create policy owner_read on public.nf_manychat_links for select to authenticated using (user_id=(select auth.uid()));

create or replace function public.nf_ingest_manychat(
  p_user uuid,p_account text,p_contact text,p_username text,p_name text,p_kind text,p_dry_run boolean default false
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  v_link public.nf_manychat_links%rowtype;
  v_lead public.leads%rowtype;
  v_ids text[] := '{}';
  v_user text := lower(trim(leading '@' from btrim(coalesce(p_username,''))));
  v_name text := btrim(coalesce(p_name,''));
  v_kind text := p_kind;
  v_id text;
  v_state text := 'linked';
  v_action text := 'existing';
  v_name_key text;
  v_user_key text;
begin
  if p_user is null or p_account is null or p_contact is null or p_kind is null or p_account !~ '^[0-9]{1,30}$' or p_contact !~ '^[0-9]{1,40}$' or v_kind not in ('mc_dm','mc_keyword','mc_unknown') then
    raise exception 'invalid_contact' using errcode='22023';
  end if;
  if length(v_name)>200 or length(v_user)>64 or (v_user<>'' and v_user !~ '^[a-z0-9_.]+$') then raise exception 'invalid_profile' using errcode='22023';end if;
  if v_name='' then v_name:=v_user;end if;
  if v_name='' then raise exception 'missing_name' using errcode='22023';end if;
  v_name_key:=regexp_replace(translate(lower(v_name),'áéíóúüñ','aeiouun'),'[^a-z0-9]','','g');
  v_user_key:=regexp_replace(v_user,'[^a-z0-9]','','g');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user::text,0));
  select * into v_link from public.nf_manychat_links where user_id=p_user and account_id=p_account and contact_id=p_contact for update;
  if found then
    if v_link.state='deleted' or (v_link.state='linked' and v_link.lead_id is null) then
      if not p_dry_run then update public.nf_manychat_links set state='deleted',last_seen=now() where user_id=p_user and account_id=p_account and contact_id=p_contact;end if;
      return jsonb_build_object('ok',true,'action','deleted_lead_not_recreated');
    end if;
    v_id:=v_link.lead_id;
    -- Keep the first known acquisition; upgrade only previously unknown contacts.
    if v_link.acquisition_type<>'mc_unknown' then v_kind:=v_link.acquisition_type;end if;
  end if;
  if v_id is null then
    if v_user<>'' then
      select coalesce(array_agg(l.id),'{}') into v_ids from public.leads l
      where l.user_id=p_user and (
        (lower(coalesce(l.source,'')) in ('instagram','manychat') and lower(trim(leading '@' from btrim(l.name)))=v_user)
        or (l.source='ManyChat' and lower(trim(leading '@' from btrim(split_part(split_part(coalesce(l.note,''),'·',2),'(',1))))=v_user)
      );
    end if;
    if cardinality(v_ids)=1 then v_id:=v_ids[1];v_action:='matched_existing';
    elsif cardinality(v_ids)>1 then v_state:='review';v_action:='review_required';
    else
      -- A display name is not an identity. Hold possible matches for review.
      select coalesce(array_agg(l.id),'{}') into v_ids from public.leads l where l.user_id=p_user and (
        lower(btrim(split_part(l.name,' · Protocolo',1)))=lower(v_name)
        or (length(regexp_replace(translate(lower(split_part(l.name,' · Protocolo',1)),'áéíóúüñ','aeiouun'),'[^a-z0-9]','','g'))>=5
          and regexp_replace(translate(lower(split_part(l.name,' · Protocolo',1)),'áéíóúüñ','aeiouun'),'[^a-z0-9]','','g') in (v_name_key,v_user_key))
      );
      if cardinality(v_ids)>0 then v_state:='review';v_action:='review_required';
      else v_id:='mc_'||p_account||'_'||p_contact;v_action:='created';end if;
    end if;
  end if;
  if p_dry_run then return jsonb_build_object('ok',true,'dry_run',true,'action',v_action,'lead_id',v_id,'candidates',cardinality(v_ids),'classification',v_kind);end if;
  if v_state='linked' then
    if v_action='created' then
      insert into public.leads(id,user_id,name,source,status,note,date,acquisition_type,lead_interest)
      values(v_id,p_user,v_name,'ManyChat',case when v_kind='mc_dm' then 'Contacted' else 'New' end,
        'ManyChat'||case when v_user<>'' then ' · @'||v_user else '' end,
        (now() at time zone 'Europe/Madrid')::date,v_kind,case when v_kind='mc_dm' then 'medium' else 'unknown' end);
    else
      select * into v_lead from public.leads where id=v_id and user_id=p_user;
      if not found then raise exception 'invalid_link';end if;
      update public.leads set acquisition_type=case when acquisition_type is null or acquisition_type='mc_unknown' then v_kind else acquisition_type end,
        lead_interest=coalesce(lead_interest,case when v_kind='mc_dm' then 'medium' else 'unknown' end)
      where id=v_id and user_id=p_user;
    end if;
  end if;
  insert into public.nf_manychat_links(user_id,account_id,contact_id,lead_id,username,contact_name,acquisition_type,state,candidate_ids)
  values(p_user,p_account,p_contact,v_id,nullif(v_user,''),v_name,v_kind,v_state,v_ids)
  on conflict(user_id,account_id,contact_id) do update set lead_id=excluded.lead_id,username=coalesce(excluded.username,nf_manychat_links.username),contact_name=excluded.contact_name,
    acquisition_type=excluded.acquisition_type,state=excluded.state,candidate_ids=excluded.candidate_ids,last_seen=now();
  return jsonb_build_object('ok',true,'action',v_action,'lead_id',v_id,'classification',v_kind,'needs_review',v_state='review');
end;$$;
revoke all on function public.nf_ingest_manychat(uuid,text,text,text,text,text,boolean) from public,anon,authenticated;
grant execute on function public.nf_ingest_manychat(uuid,text,text,text,text,text,boolean) to service_role;


create or replace function public.nf_resolve_manychat(p_user uuid,p_account text,p_contact text,p_lead text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v public.nf_manychat_links%rowtype; target text;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user::text,0));
 select * into v from public.nf_manychat_links where user_id=p_user and account_id=p_account and contact_id=p_contact for update;
 if not found or v.state<>'review' then raise exception 'not_pending';end if;
 if p_lead is null then
   target:='mc_'||p_account||'_'||p_contact;
   insert into public.leads(id,user_id,name,source,status,note,date,acquisition_type,lead_interest)
   values(target,p_user,v.contact_name,'ManyChat',case when v.acquisition_type='mc_dm' then 'Contacted' else 'New' end,
   'ManyChat'||coalesce(' · @'||v.username,''),(now() at time zone 'Europe/Madrid')::date,v.acquisition_type,'unknown');
 else
   select id into target from public.leads where user_id=p_user and id=p_lead;
   if not found then raise exception 'lead_not_found';end if;
   update public.leads set acquisition_type=coalesce(acquisition_type,v.acquisition_type) where user_id=p_user and id=target;
 end if;
 update public.nf_manychat_links set lead_id=target,state='linked',candidate_ids='{}',last_seen=now() where user_id=p_user and account_id=p_account and contact_id=p_contact;
 return jsonb_build_object('ok',true,'lead_id',target);
end;$$;
revoke all on function public.nf_resolve_manychat(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.nf_resolve_manychat(uuid,text,text,text) to service_role;
