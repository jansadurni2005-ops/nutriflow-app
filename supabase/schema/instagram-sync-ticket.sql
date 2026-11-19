-- The network queue never sees a reusable credential; each call can perform just one scheduled read.
alter table public.nf_ig_sync_control add column if not exists ticket_until timestamptz;
create or replace function public.nf_ig_schedule_read() returns void language plpgsql security invoker set search_path='' as $$
declare ticket text;
begin
 if not exists(select 1 from public.nf_ig_dm_connection where account_id='17841449201493232' and expires_at>now()) then return;end if;
 ticket:=encode(extensions.gen_random_bytes(32),'hex');
 update public.nf_ig_sync_control set sync_key=encode(extensions.digest(ticket,'sha256'),'hex'),ticket_until=now()+interval '55 seconds' where id=1 and lease_until<now() and (ticket_until is null or ticket_until<now());
 if not found then return;end if;
 perform net.http_post(url:='https://nrxltxmbpkplhgycodob.supabase.co/functions/v1/ig-crm-sync',headers:=jsonb_build_object('Content-Type','application/json','x-nf-sync',ticket),body:='{"op":"sync"}'::jsonb,timeout_milliseconds:=50000);
end;$$;
revoke all on function public.nf_ig_schedule_read() from public,anon,authenticated;
select cron.schedule('nf-ig-conversations-5min','*/5 * * * *','select public.nf_ig_schedule_read();');
update public.nf_ig_sync_control set sync_key=encode(extensions.gen_random_bytes(32),'hex'),ticket_until=null where id=1;
