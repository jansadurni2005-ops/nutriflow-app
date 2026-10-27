-- Durable, owner-scoped deletion markers prevent stale clients/backups re-inserting a deleted ID.
create table public.nf_deleted_leads (
 user_id uuid not null references auth.users(id) on delete cascade,
 lead_id text not null,
 instagram_handle_hash text,
 deleted_at timestamptz not null default now(),
 primary key(user_id,lead_id)
);
create index nf_deleted_leads_handle_idx on public.nf_deleted_leads(user_id,instagram_handle_hash) where instagram_handle_hash is not null;
alter table public.nf_deleted_leads enable row level security;
revoke all on public.nf_deleted_leads from public,anon,authenticated;
grant select,insert on public.nf_deleted_leads to authenticated;
grant all on public.nf_deleted_leads to service_role;
create policy deleted_leads_read on public.nf_deleted_leads for select to authenticated using (user_id=(select auth.uid()));
create policy deleted_leads_record on public.nf_deleted_leads for insert to authenticated with check (user_id=(select auth.uid()));

create function public.nf_prevent_deleted_lead_insert() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text,0));
 if exists(select 1 from public.nf_deleted_leads where user_id=new.user_id and lead_id=new.id) then return null;end if;
 return new;
end;$$;
revoke all on function public.nf_prevent_deleted_lead_insert() from public,anon,authenticated;
create trigger nf_prevent_deleted_lead_insert before insert on public.leads for each row execute function public.nf_prevent_deleted_lead_insert();

create function public.nf_remember_deleted_lead() returns trigger
language plpgsql security invoker set search_path='' as $$
declare handle text;
begin
 if pg_catalog.pg_trigger_depth()>1 then return old;end if;
 if old.source='ManyChat' then handle:=lower(trim(leading '@' from btrim(split_part(split_part(coalesce(old.note,''),'·',2),'(',1))));
 elsif lower(old.source)='instagram' and old.name like '@%' then handle:=lower(trim(leading '@' from btrim(old.name)));end if;
 if handle !~ '^[a-z0-9_.]{1,64}$' then handle:=null;end if;
 insert into public.nf_deleted_leads(user_id,lead_id,instagram_handle_hash) values(old.user_id,old.id,case when handle is not null then pg_catalog.md5(handle) end) on conflict do nothing;
 return old;
end;$$;
revoke all on function public.nf_remember_deleted_lead() from public,anon,authenticated;
create trigger nf_remember_deleted_lead after delete on public.leads for each row execute function public.nf_remember_deleted_lead();

create function public.nf_delete_lead(p_id text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare owner_id uuid:=(select auth.uid());
begin
 if owner_id is null then raise exception 'authentication_required' using errcode='42501';end if;
 if p_id is null or length(p_id)=0 or length(p_id)>300 then raise exception 'invalid_lead_id' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text,0));
 delete from public.leads where user_id=owner_id and id=p_id;
 insert into public.nf_deleted_leads(user_id,lead_id) values(owner_id,p_id) on conflict do nothing;
 return jsonb_build_object('deleted',true,'id',p_id);
end;$$;
revoke all on function public.nf_delete_lead(text) from public,anon;
grant execute on function public.nf_delete_lead(text) to authenticated;
