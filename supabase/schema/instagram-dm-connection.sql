-- Separate from the metrics credential. No authenticated/anonymous Data API access.
create table public.nf_ig_dm_connection (
 account_id text primary key check(account_id='17841449201493232'),
 access_token text not null check(length(access_token)>0),
 expires_at timestamptz not null,
 connected_at timestamptz not null default now()
);
alter table public.nf_ig_dm_connection enable row level security;
revoke all on public.nf_ig_dm_connection from public,anon,authenticated;
grant select, insert, update, delete on public.nf_ig_dm_connection to service_role;
