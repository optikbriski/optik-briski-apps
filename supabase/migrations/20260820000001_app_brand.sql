-- Merek aplikasi (bukan nama cabang). Nama toko tetap di invoice_settings.shop_name.
create table if not exists public.app_brand (
  id text primary key default 'default',
  display_name text not null,
  short_name text,
  assistant_name text,
  updated_at timestamptz not null default now(),
  constraint app_brand_singleton check (id = 'default')
);

insert into public.app_brand (id, display_name, short_name, assistant_name)
values ('default', 'Optik B. Riski', 'OBR', 'OBRA')
on conflict (id) do nothing;

alter table public.app_brand enable row level security;

drop policy if exists app_brand_anon_select on public.app_brand;
drop policy if exists app_brand_auth_select on public.app_brand;
drop policy if exists app_brand_auth_update on public.app_brand;

create policy app_brand_anon_select on public.app_brand
  for select to anon using (true);

create policy app_brand_auth_select on public.app_brand
  for select to authenticated using (true);

create policy app_brand_auth_update on public.app_brand
  for update to authenticated using (true) with check (true);

create or replace function public.app_brand_display_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(display_name), ''),
    'Optik B. Riski'
  )
  from public.app_brand
  where id = 'default';
$$;

grant execute on function public.app_brand_display_name() to anon, authenticated;

comment on table public.app_brand is
  'Tenant brand for white-label. Store/cabang names live in invoice_settings.shop_name.';
