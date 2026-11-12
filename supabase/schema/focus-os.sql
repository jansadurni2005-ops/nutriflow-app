-- FOCUS OS · tablas para copia en la nube y avisos push (proyecto Supabase de Nutriflow).
-- Todas las tablas tienen RLS: cada usuario solo ve y modifica lo suyo.

-- 1) Estado completo de la app (JSON) por usuario.
create table if not exists public.focus_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null,
  client_updated_at bigint not null default 0,
  updated_at timestamptz not null default now(),
  device text
);
alter table public.focus_state enable row level security;
create policy "focus_state own select" on public.focus_state for select to authenticated using (auth.uid() = user_id);
create policy "focus_state own insert" on public.focus_state for insert to authenticated with check (auth.uid() = user_id);
create policy "focus_state own update" on public.focus_state for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "focus_state own delete" on public.focus_state for delete to authenticated using (auth.uid() = user_id);

-- 2) Suscripciones Web Push (un registro por dispositivo).
create table if not exists public.focus_push_subs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  last_ok_at timestamptz
);
alter table public.focus_push_subs enable row level security;
create policy "focus_push_subs own all" on public.focus_push_subs for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create index if not exists focus_push_subs_user_idx on public.focus_push_subs(user_id);

-- 3) Avisos programados que calcula la app (próximas 48 h).
create table if not exists public.focus_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fire_at timestamptz not null,
  title text not null,
  body text,
  tag text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.focus_alerts enable row level security;
create policy "focus_alerts own select" on public.focus_alerts for select to authenticated using (auth.uid() = user_id);
create index if not exists focus_alerts_due_idx on public.focus_alerts(fire_at) where sent_at is null;
create index if not exists focus_alerts_user_idx on public.focus_alerts(user_id);

-- Sustituye de forma atómica los avisos pendientes del usuario.
create or replace function public.focus_replace_alerts(alerts jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if jsonb_typeof(alerts) <> 'array' or jsonb_array_length(alerts) > 200 then raise exception 'invalid alerts'; end if;
  delete from public.focus_alerts where user_id = uid and sent_at is null;
  insert into public.focus_alerts(user_id, fire_at, title, body, tag)
  select uid, (a->>'fire_at')::timestamptz, left(a->>'title', 200), left(coalesce(a->>'body',''), 500), left(a->>'tag', 120)
  from jsonb_array_elements(alerts) a
  where (a->>'fire_at')::timestamptz > now() - interval '1 minute'
    and (a->>'fire_at')::timestamptz < now() + interval '3 days';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.focus_replace_alerts(jsonb) from public, anon;
grant execute on function public.focus_replace_alerts(jsonb) to authenticated;

-- 4) Claves del servidor (VAPID, secreto del cron). Sin acceso para anon/authenticated.
create table if not exists public.focus_server_keys (
  id text primary key,
  value text not null,
  created_at timestamptz not null default now()
);
alter table public.focus_server_keys enable row level security;
revoke all on public.focus_server_keys from anon, authenticated;
insert into public.focus_server_keys(id, value)
values ('cron_secret', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (id) do nothing;

-- 5) Cron: cada minuto, si hay avisos vencidos, llama a la función focus-push.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule(
  'focus-push-every-minute',
  '* * * * *',
  $cron$
  select net.http_post(
    url := 'https://nrxltxmbpkplhgycodob.supabase.co/functions/v1/focus-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-focus-cron', (select value from public.focus_server_keys where id = 'cron_secret')
    ),
    body := '{"action":"run"}'::jsonb
  )
  where exists (select 1 from public.focus_alerts where sent_at is null and fire_at <= now());
  $cron$
);
