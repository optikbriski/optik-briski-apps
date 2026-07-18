-- Fix RLS: login Admin upsert ke toko_id + profiles
-- Jalankan di SQL Editor project Optik B Riski Apps

-- Pastikan master toko ada
insert into public.toko_id (id, toko_id) values
  ('PUSAT', 'Optik B. Riski - Pusat'),
  ('CABANG-CIMAHI', 'Optik B. Riski - CABANG-CIMAHI')
on conflict (id) do nothing;

-- Policies toko_id
drop policy if exists toko_id_authenticated_all on public.toko_id;
drop policy if exists toko_id_anon_select on public.toko_id;
drop policy if exists toko_id_auth_select on public.toko_id;
drop policy if exists toko_id_auth_insert on public.toko_id;
drop policy if exists toko_id_auth_update on public.toko_id;

create policy toko_id_anon_select on public.toko_id
  for select to anon using (true);

create policy toko_id_auth_select on public.toko_id
  for select to authenticated using (true);

create policy toko_id_auth_insert on public.toko_id
  for insert to authenticated with check (true);

create policy toko_id_auth_update on public.toko_id
  for update to authenticated using (true) with check (true);

-- Policies profiles (login juga upsert di sini)
drop policy if exists profiles_authenticated_all on public.profiles;
drop policy if exists profiles_auth_select on public.profiles;
drop policy if exists profiles_auth_insert on public.profiles;
drop policy if exists profiles_auth_update on public.profiles;

create policy profiles_auth_select on public.profiles
  for select to authenticated using (true);

create policy profiles_auth_insert on public.profiles
  for insert to authenticated with check (true);

create policy profiles_auth_update on public.profiles
  for update to authenticated using (true) with check (true);
