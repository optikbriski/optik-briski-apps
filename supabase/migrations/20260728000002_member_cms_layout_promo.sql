-- =============================================================================
-- CMS Member: tata letak/hide-show fitur, banner image, promo detail + POS sync
-- Aman dijalankan meski migration member_app_features belum pernah di-run.
-- =============================================================================

-- 0) Pastikan tabel dasar ada (dari 20260727000002)
create table if not exists public.member_promos (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  toko_id text,
  voucher_code text,
  points_cost int not null default 0,
  active boolean not null default true,
  valid_until date,
  created_at timestamptz not null default now()
);

alter table public.member_promos enable row level security;

-- 1) Layout + feature flags di member_home_content
--    (buat tabel dulu jika 20260728000001 belum dijalankan)
create table if not exists public.member_home_content (
  id text primary key default 'default',
  brand_label text not null default 'OPTIK B. RISKI',
  slides jsonb not null default '[
    {
      "title": "Kacamata siap?\nLangsung tahu di sini",
      "subtitle": "Pantau status pesanan & ambil tanpa ribet"
    },
    {
      "title": "Garansi digital\nOptik B. Riski",
      "subtitle": "Data asli sistem · klaim wajib cek di toko"
    }
  ]'::jsonb,
  greeting_guest text not null default 'Hi, Teman Optik!',
  greeting_subtitle_guest text not null default 'Login untuk lihat pesanan & garansi',
  promo_title text not null default 'Promo & poin',
  promo_subtitle text not null default 'Voucher dan saldo poin kamu',
  updated_at timestamptz not null default now()
);

insert into public.member_home_content (id)
values ('default')
on conflict (id) do nothing;

alter table public.member_home_content enable row level security;

drop policy if exists member_home_content_read on public.member_home_content;
create policy member_home_content_read on public.member_home_content
  for select to anon, authenticated
  using (true);

drop policy if exists member_home_content_write_pusat on public.member_home_content;
create policy member_home_content_write_pusat on public.member_home_content
  for all to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
    )
  );

alter table public.member_home_content
  add column if not exists sections jsonb not null default '[
    {"key":"hero","label":"Header / Banner","visible":true,"order":0},
    {"key":"greeting","label":"Kartu sapaan","visible":true,"order":1},
    {"key":"promo","label":"Kartu promo","visible":true,"order":2},
    {"key":"reminders","label":"Pengingat","visible":true,"order":3},
    {"key":"store","label":"Cabang terkait","visible":true,"order":4},
    {"key":"services_main","label":"Layanan utama","visible":true,"order":5},
    {"key":"services_other","label":"Lainnya","visible":true,"order":6}
  ]'::jsonb;

alter table public.member_home_content
  add column if not exists feature_flags jsonb not null default '{
    "katalog": true,
    "janji_kontrol": true,
    "resep": true,
    "rating": true,
    "notif": true,
    "perawatan": true
  }'::jsonb;

-- Seed kolom baru pada row default (jika sudah ada sebelum alter default)
update public.member_home_content
set
  sections = coalesce(sections, '[
    {"key":"hero","label":"Header / Banner","visible":true,"order":0},
    {"key":"greeting","label":"Kartu sapaan","visible":true,"order":1},
    {"key":"promo","label":"Kartu promo","visible":true,"order":2},
    {"key":"reminders","label":"Pengingat","visible":true,"order":3},
    {"key":"store","label":"Cabang terkait","visible":true,"order":4},
    {"key":"services_main","label":"Layanan utama","visible":true,"order":5},
    {"key":"services_other","label":"Lainnya","visible":true,"order":6}
  ]'::jsonb),
  feature_flags = coalesce(feature_flags, '{
    "katalog": true,
    "janji_kontrol": true,
    "resep": true,
    "rating": true,
    "notif": true,
    "perawatan": true
  }'::jsonb)
where id = 'default';

-- 2) Promo detail + sinkron Member/POS
alter table public.member_promos
  add column if not exists image_url text,
  add column if not exists quantity int,
  add column if not exists quantity_remaining int,
  add column if not exists discount_type text not null default 'nominal',
  add column if not exists discount_value bigint not null default 0,
  add column if not exists show_on_member boolean not null default true,
  add column if not exists show_on_pos boolean not null default true,
  add column if not exists sort_order int not null default 0,
  add column if not exists terms text,
  add column if not exists updated_at timestamptz not null default now();

-- Constraint tipe diskon (idempotent)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'member_promos_discount_type_check'
  ) then
    alter table public.member_promos
      add constraint member_promos_discount_type_check
      check (discount_type in ('nominal', 'percent', 'info'));
  end if;
end $$;

comment on column public.member_promos.quantity is 'Kuota total promo (null = tanpa batas)';
comment on column public.member_promos.quantity_remaining is 'Sisa kuota (null = tanpa batas)';
comment on column public.member_promos.discount_type is 'nominal=Rp potongan POS; percent=%; info=hanya info Member';
comment on column public.member_promos.show_on_pos is 'Tampil / bisa dipakai di kasir POS';

-- Write policy untuk Admin Pusat
drop policy if exists member_promos_write_pusat on public.member_promos;
create policy member_promos_write_pusat on public.member_promos
  for all to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
    )
  );

-- Baca semua promo aktif (termasuk show flags) untuk Member/POS
drop policy if exists member_promos_read on public.member_promos;
create policy member_promos_read on public.member_promos
  for select to anon, authenticated
  using (active = true);

-- RPC lookup voucher POS (aman dipanggil kasir)
create or replace function public.lookup_member_promo(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.member_promos%rowtype;
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Kode kosong');
  end if;

  select * into v_row
  from public.member_promos
  where upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and show_on_pos = true
  order by sort_order, created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Voucher tidak ditemukan / tidak aktif di POS');
  end if;

  if v_row.valid_until is not null and v_row.valid_until < current_date then
    return jsonb_build_object('ok', false, 'error', 'Voucher kedaluwarsa');
  end if;

  if v_row.quantity_remaining is not null and v_row.quantity_remaining <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Kuota voucher habis');
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'title', v_row.title,
    'description', v_row.description,
    'voucher_code', v_row.voucher_code,
    'discount_type', v_row.discount_type,
    'discount_value', v_row.discount_value,
    'quantity_remaining', v_row.quantity_remaining,
    'points_cost', v_row.points_cost,
    'terms', v_row.terms
  );
end;
$$;

grant execute on function public.lookup_member_promo(text) to anon, authenticated;
