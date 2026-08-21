-- =============================================================================
-- Bidang usaha (industri). Satu mesin Rekasa, spesifikasi paket per bidang.
-- Pola Odoo: bukan fork per klien. Apply setelah 000009. Jangan dari agent ke live.
-- =============================================================================

create table if not exists public.store_industries (
  industry_key text primary key,
  label text not null,
  blurb text not null default '',
  sort_order int not null default 0
);

insert into public.store_industries (industry_key, label, blurb, sort_order)
values
  ('optik', 'Optik / kacamata', 'Kasir frame-lensa, resep, garansi, member.', 10),
  ('retail', 'Toko retail / fashion', 'Kasir barang, stok cabang, member, order online.', 20),
  ('fnb', 'Kafe / resto / F&B', 'Kasir menu, stok outlet, pelanggan.', 30),
  ('jasa', 'Jasa (salon, laundry, studio)', 'Transaksi layanan, klien, DP booking.', 40),
  ('bengkel', 'Bengkel / otomotif', 'Servis, sparepart, garansi pengerjaan.', 50),
  ('klinik', 'Klinik / praktik', 'Kasir tindakan, layanan, rekam klien ringan.', 60),
  ('grosir', 'Grosir / distributor', 'Nota partai, gudang, piutang.', 70),
  ('umum', 'Usaha umum', 'Paket tipis, fitur dinyalakan sesuai kebutuhan.', 80)
on conflict (industry_key) do update set
  label = excluded.label,
  blurb = excluded.blurb,
  sort_order = excluded.sort_order;

create table if not exists public.store_industry_modules (
  industry_key text not null references public.store_industries (industry_key) on delete cascade,
  module_key text not null,
  label text not null,
  summary text not null default '',
  body text not null default '',
  video_url text,
  primary key (industry_key, module_key)
);

create table if not exists public.store_industry_plan_modules (
  industry_key text not null references public.store_industries (industry_key) on delete cascade,
  plan_key text not null,
  module_key text not null,
  primary key (industry_key, plan_key, module_key)
);

alter table public.tenants
  add column if not exists industry_key text not null default 'umum';

update public.tenants
set industry_key = 'optik'
where id = public.default_tenant_id();

alter table public.store_orders
  add column if not exists industry_key text;

alter table public.store_industries enable row level security;
alter table public.store_industry_modules enable row level security;
alter table public.store_industry_plan_modules enable row level security;

drop policy if exists store_industries_read on public.store_industries;
create policy store_industries_read on public.store_industries
  for select to anon, authenticated using (true);

drop policy if exists store_industry_modules_read on public.store_industry_modules;
create policy store_industry_modules_read on public.store_industry_modules
  for select to anon, authenticated using (true);

drop policy if exists store_industry_plan_read on public.store_industry_plan_modules;
create policy store_industry_plan_read on public.store_industry_plan_modules
  for select to anon, authenticated using (true);

-- Seed paket per bidang (C/B/A).
insert into public.store_industry_plan_modules (industry_key, plan_key, module_key)
values
  -- optik
  ('optik', 'paket_c', 'pos'), ('optik', 'paket_c', 'master_data'), ('optik', 'paket_c', 'member_app'),
  ('optik', 'paket_b', 'pos'), ('optik', 'paket_b', 'master_data'), ('optik', 'paket_b', 'member_app'),
  ('optik', 'paket_b', 'logistics'), ('optik', 'paket_b', 'warranty'), ('optik', 'paket_b', 'attendance'),
  ('optik', 'paket_b', 'history_dp'),
  ('optik', 'paket_a', 'pos'), ('optik', 'paket_a', 'master_data'), ('optik', 'paket_a', 'member_app'),
  ('optik', 'paket_a', 'logistics'), ('optik', 'paket_a', 'warranty'), ('optik', 'paket_a', 'attendance'),
  ('optik', 'paket_a', 'history_dp'), ('optik', 'paket_a', 'finance'), ('optik', 'paket_a', 'online_orders'),
  -- retail
  ('retail', 'paket_c', 'pos'), ('retail', 'paket_c', 'master_data'), ('retail', 'paket_c', 'member_app'),
  ('retail', 'paket_b', 'pos'), ('retail', 'paket_b', 'master_data'), ('retail', 'paket_b', 'member_app'),
  ('retail', 'paket_b', 'logistics'), ('retail', 'paket_b', 'history_dp'), ('retail', 'paket_b', 'attendance'),
  ('retail', 'paket_a', 'pos'), ('retail', 'paket_a', 'master_data'), ('retail', 'paket_a', 'member_app'),
  ('retail', 'paket_a', 'logistics'), ('retail', 'paket_a', 'history_dp'), ('retail', 'paket_a', 'attendance'),
  ('retail', 'paket_a', 'finance'), ('retail', 'paket_a', 'online_orders'),
  -- fnb
  ('fnb', 'paket_c', 'pos'), ('fnb', 'paket_c', 'master_data'), ('fnb', 'paket_c', 'member_app'),
  ('fnb', 'paket_b', 'pos'), ('fnb', 'paket_b', 'master_data'), ('fnb', 'paket_b', 'member_app'),
  ('fnb', 'paket_b', 'attendance'), ('fnb', 'paket_b', 'history_dp'), ('fnb', 'paket_b', 'logistics'),
  ('fnb', 'paket_a', 'pos'), ('fnb', 'paket_a', 'master_data'), ('fnb', 'paket_a', 'member_app'),
  ('fnb', 'paket_a', 'attendance'), ('fnb', 'paket_a', 'history_dp'), ('fnb', 'paket_a', 'logistics'),
  ('fnb', 'paket_a', 'finance'), ('fnb', 'paket_a', 'online_orders'),
  -- jasa
  ('jasa', 'paket_c', 'pos'), ('jasa', 'paket_c', 'master_data'), ('jasa', 'paket_c', 'member_app'),
  ('jasa', 'paket_b', 'pos'), ('jasa', 'paket_b', 'master_data'), ('jasa', 'paket_b', 'member_app'),
  ('jasa', 'paket_b', 'history_dp'), ('jasa', 'paket_b', 'attendance'),
  ('jasa', 'paket_a', 'pos'), ('jasa', 'paket_a', 'master_data'), ('jasa', 'paket_a', 'member_app'),
  ('jasa', 'paket_a', 'history_dp'), ('jasa', 'paket_a', 'attendance'), ('jasa', 'paket_a', 'finance'),
  -- bengkel
  ('bengkel', 'paket_c', 'pos'), ('bengkel', 'paket_c', 'master_data'), ('bengkel', 'paket_c', 'history_dp'),
  ('bengkel', 'paket_b', 'pos'), ('bengkel', 'paket_b', 'master_data'), ('bengkel', 'paket_b', 'history_dp'),
  ('bengkel', 'paket_b', 'warranty'), ('bengkel', 'paket_b', 'attendance'), ('bengkel', 'paket_b', 'logistics'),
  ('bengkel', 'paket_a', 'pos'), ('bengkel', 'paket_a', 'master_data'), ('bengkel', 'paket_a', 'history_dp'),
  ('bengkel', 'paket_a', 'warranty'), ('bengkel', 'paket_a', 'attendance'), ('bengkel', 'paket_a', 'logistics'),
  ('bengkel', 'paket_a', 'member_app'), ('bengkel', 'paket_a', 'finance'),
  -- klinik
  ('klinik', 'paket_c', 'pos'), ('klinik', 'paket_c', 'master_data'), ('klinik', 'paket_c', 'member_app'),
  ('klinik', 'paket_b', 'pos'), ('klinik', 'paket_b', 'master_data'), ('klinik', 'paket_b', 'member_app'),
  ('klinik', 'paket_b', 'history_dp'), ('klinik', 'paket_b', 'attendance'),
  ('klinik', 'paket_a', 'pos'), ('klinik', 'paket_a', 'master_data'), ('klinik', 'paket_a', 'member_app'),
  ('klinik', 'paket_a', 'history_dp'), ('klinik', 'paket_a', 'attendance'), ('klinik', 'paket_a', 'finance'),
  -- grosir
  ('grosir', 'paket_c', 'pos'), ('grosir', 'paket_c', 'master_data'), ('grosir', 'paket_c', 'logistics'),
  ('grosir', 'paket_b', 'pos'), ('grosir', 'paket_b', 'master_data'), ('grosir', 'paket_b', 'logistics'),
  ('grosir', 'paket_b', 'history_dp'), ('grosir', 'paket_b', 'attendance'), ('grosir', 'paket_b', 'finance'),
  ('grosir', 'paket_a', 'pos'), ('grosir', 'paket_a', 'master_data'), ('grosir', 'paket_a', 'logistics'),
  ('grosir', 'paket_a', 'history_dp'), ('grosir', 'paket_a', 'attendance'), ('grosir', 'paket_a', 'finance'),
  ('grosir', 'paket_a', 'member_app'), ('grosir', 'paket_a', 'online_orders'),
  -- umum
  ('umum', 'paket_c', 'pos'), ('umum', 'paket_c', 'master_data'),
  ('umum', 'paket_b', 'pos'), ('umum', 'paket_b', 'master_data'), ('umum', 'paket_b', 'member_app'),
  ('umum', 'paket_b', 'attendance'), ('umum', 'paket_b', 'history_dp'),
  ('umum', 'paket_a', 'pos'), ('umum', 'paket_a', 'master_data'), ('umum', 'paket_a', 'member_app'),
  ('umum', 'paket_a', 'attendance'), ('umum', 'paket_a', 'history_dp'), ('umum', 'paket_a', 'finance'),
  ('umum', 'paket_a', 'logistics'), ('umum', 'paket_a', 'online_orders')
on conflict do nothing;

-- Copy per bidang: ambil label generik dulu, lalu overlay singkat.
insert into public.store_industry_modules (industry_key, module_key, label, summary, body)
select i.industry_key, m.module_key, m.label, m.summary, m.body
from public.store_industries i
join public.store_modules m on true
where exists (
  select 1 from public.store_industry_plan_modules p
  where p.industry_key = i.industry_key and p.module_key = m.module_key
)
   or m.module_key in ('warranty', 'logistics', 'online_orders', 'member_app')
on conflict (industry_key, module_key) do nothing;

-- Overlay nama biar tidak semua "POS optik".
update public.store_industry_modules set
  label = case module_key
    when 'pos' then 'Kasir toko'
    when 'master_data' then 'Master barang'
    when 'member_app' then 'Aplikasi pelanggan'
    when 'history_dp' then 'DP / indent'
    when 'logistics' then 'Stok antar toko'
    when 'warranty' then 'Garansi barang'
    when 'attendance' then 'Absensi staff'
    when 'finance' then 'Keuangan'
    when 'online_orders' then 'Order online'
    else label
  end
where industry_key = 'retail';

update public.store_industry_modules set
  label = case module_key
    when 'pos' then 'Kasir / meja'
    when 'master_data' then 'Menu & bahan'
    when 'member_app' then 'Pelanggan / loyalty'
    when 'history_dp' then 'Reservasi / DP acara'
    when 'logistics' then 'Stok antar outlet'
    when 'attendance' then 'Absensi kru'
    when 'finance' then 'Keuangan outlet'
    when 'online_orders' then 'Pesan antar / pickup'
    else label
  end
where industry_key = 'fnb';

update public.store_industry_modules set
  label = case module_key
    when 'pos' then 'Transaksi jasa'
    when 'master_data' then 'Daftar layanan'
    when 'member_app' then 'Aplikasi klien'
    when 'history_dp' then 'DP / booking'
    when 'logistics' then 'Stok cabang (opsional)'
    when 'warranty' then 'Garansi layanan'
    when 'attendance' then 'Absensi kru'
    when 'online_orders' then 'Booking online'
    else label
  end
where industry_key = 'jasa';

update public.store_industry_modules set
  label = case module_key
    when 'pos' then 'Kasir servis'
    when 'master_data' then 'Sparepart & jasa'
    when 'member_app' then 'Aplikasi pelanggan'
    when 'history_dp' then 'DP pengerjaan'
    when 'logistics' then 'Stok antar bengkel'
    when 'warranty' then 'Garansi servis'
    when 'attendance' then 'Absensi mekanik'
    when 'finance' then 'Keuangan bengkel'
    when 'online_orders' then 'Booking servis online'
    else label
  end
where industry_key = 'bengkel';

update public.store_industry_modules set
  label = case module_key
    when 'pos' then 'Kasir klinik'
    when 'master_data' then 'Layanan & item'
    when 'member_app' then 'Aplikasi klien'
    when 'history_dp' then 'DP tindakan'
    when 'warranty' then 'Garansi tindakan'
    when 'online_orders' then 'Janji temu online'
    else label
  end
where industry_key = 'klinik';

update public.store_industry_modules set
  label = case module_key
    when 'pos' then 'Kasir / nota grosir'
    when 'master_data' then 'Master SKU gudang'
    when 'member_app' then 'Portal pelanggan toko'
    when 'history_dp' then 'Piutang / tempo'
    when 'logistics' then 'Mutasi gudang'
    when 'warranty' then 'Retur / klaim'
    when 'attendance' then 'Absensi gudang'
    when 'finance' then 'Keuangan distributor'
    when 'online_orders' then 'Order dari toko langganan'
    else label
  end
where industry_key = 'grosir';

update public.store_industry_modules set
  label = case module_key
    when 'pos' then 'POS / Kasir optik'
    when 'master_data' then 'Master frame & lensa'
    when 'member_app' then 'Aplikasi member optik'
    when 'warranty' then 'Garansi frame/lensa'
    else label
  end
where industry_key = 'optik';

create or replace function public.list_store_catalog(p_industry_key text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ind text := lower(trim(coalesce(p_industry_key, '')));
  v_wl bigint := 200000;
begin
  select s.white_label_addon_idr into v_wl from public.store_settings s where s.id = 1;
  if v_ind = '' then
    v_ind := null;
  end if;
  if v_ind is not null and not exists (
    select 1 from public.store_industries i where i.industry_key = v_ind
  ) then
    return jsonb_build_object('ok', false, 'error', 'Bidang tidak dikenal');
  end if;

  return jsonb_build_object(
    'ok', true,
    'industry_key', v_ind,
    'white_label_addon_idr', coalesce(v_wl, 200000),
    'industries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', i.industry_key,
        'label', i.label,
        'blurb', i.blurb
      ) order by i.sort_order)
      from public.store_industries i
    ), '[]'::jsonb),
    'plans', case when v_ind is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'plan_key', c.plan_key,
        'label', c.label,
        'price_idr', c.price_idr,
        'white_label', c.white_label,
        'blurb', c.blurb,
        'highlight', c.highlight,
        'sort_order', c.sort_order,
        'modules', coalesce((
          select jsonb_agg(pm.module_key)
          from public.store_industry_plan_modules pm
          where pm.industry_key = v_ind and pm.plan_key = c.plan_key
        ), '[]'::jsonb)
      ) order by c.sort_order)
      from public.tenant_plan_catalog c
      where c.plan_key in ('paket_c', 'paket_b', 'paket_a')
    ), '[]'::jsonb) end,
    'modules', case when v_ind is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', im.module_key,
        'label', im.label,
        'summary', coalesce(nullif(im.summary, ''), m.summary),
        'body', coalesce(nullif(im.body, ''), m.body),
        'video_url', coalesce(im.video_url, m.video_url),
        'add_on_price_idr', m.add_on_price_idr
      ) order by m.sort_order)
      from public.store_industry_modules im
      join public.store_modules m on m.module_key = im.module_key
      where im.industry_key = v_ind
    ), '[]'::jsonb) end
  );
end;
$$;

grant execute on function public.list_store_catalog(text) to anon, authenticated;

create or replace function public.quote_store_order(
  p_plan_key text,
  p_modules jsonb,
  p_white_label boolean default null,
  p_industry_key text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_plan text := lower(trim(coalesce(p_plan_key, 'paket_c')));
  v_ind text := lower(trim(coalesce(p_industry_key, '')));
  v_base bigint := 0;
  v_add bigint := 0;
  v_wl_fee bigint := 0;
  v_plan_wl boolean := false;
  v_wl boolean;
  v_key text;
  v_on boolean;
  v_addon bigint;
begin
  if not exists (select 1 from public.tenant_plan_catalog c where c.plan_key = v_plan) then
    raise exception 'Paket tidak dikenal';
  end if;
  select c.price_idr, c.white_label into v_base, v_plan_wl
  from public.tenant_plan_catalog c where c.plan_key = v_plan;
  v_wl := coalesce(p_white_label, v_plan_wl);

  for v_key, v_on in
    select e.key, coalesce(e.value::text, 'false') in ('true', 't', '1')
    from jsonb_each(coalesce(p_modules, '{}'::jsonb)) e
  loop
    if not v_on then
      continue;
    end if;
    if v_ind <> '' and exists (
      select 1 from public.store_industry_plan_modules pm
      where pm.industry_key = v_ind and pm.plan_key = v_plan and pm.module_key = v_key
    ) then
      continue;
    end if;
    if v_ind = '' and exists (
      select 1 from public.tenant_plan_modules pm
      where pm.plan_key = v_plan and pm.module_key = v_key
    ) then
      continue;
    end if;
    if v_ind <> '' and exists (
      select 1 from public.store_industry_plan_modules pm
      where pm.industry_key = v_ind and pm.plan_key = v_plan and pm.module_key = v_key
    ) then
      continue;
    end if;
    select m.add_on_price_idr into v_addon
    from public.store_modules m where m.module_key = v_key;
    v_add := v_add + coalesce(v_addon, 50000);
  end loop;

  if v_wl and not v_plan_wl then
    select s.white_label_addon_idr into v_wl_fee from public.store_settings s where s.id = 1;
    v_wl_fee := coalesce(v_wl_fee, 200000);
  end if;

  return jsonb_build_object(
    'ok', true,
    'plan_key', v_plan,
    'industry_key', nullif(v_ind, ''),
    'base_idr', coalesce(v_base, 0),
    'add_on_idr', v_add,
    'white_label_idr', v_wl_fee,
    'white_label', v_wl,
    'amount_idr', coalesce(v_base, 0) + v_add + v_wl_fee
  );
end;
$$;

grant execute on function public.quote_store_order(text, jsonb, boolean, text)
  to anon, authenticated;

create or replace function public.submit_store_order(
  p_plan_key text,
  p_modules jsonb,
  p_white_label boolean,
  p_display_name text,
  p_slug text,
  p_phone text,
  p_email text default null,
  p_legal_name text default null,
  p_signer_name text default null,
  p_industry_key text default 'umum'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote jsonb;
  v_amount bigint;
  v_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_slug text := public.normalize_tenant_slug(p_slug);
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
  v_id uuid := gen_random_uuid();
  v_tid uuid;
  v_pusat text;
  v_code text;
  v_plan text := lower(trim(coalesce(p_plan_key, 'paket_c')));
  v_ind text := lower(trim(coalesce(p_industry_key, 'umum')));
  v_inv uuid := gen_random_uuid();
  v_inv_no text;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_ctr_no text;
  v_body text;
  v_label text;
  v_upgrade boolean := false;
  v_existing uuid;
begin
  if v_name is null then
    raise exception 'Nama usaha wajib';
  end if;
  if v_slug is null or length(v_slug) < 3 then
    raise exception 'Kode usaha minimal 3 huruf';
  end if;
  if v_phone is null or length(v_phone) < 8 then
    raise exception 'Nomor WA / HP wajib';
  end if;
  if not exists (select 1 from public.store_industries i where i.industry_key = v_ind) then
    v_ind := 'umum';
  end if;

  v_quote := public.quote_store_order(v_plan, p_modules, p_white_label, v_ind);
  v_amount := (v_quote ->> 'amount_idr')::bigint;

  if auth.uid() is not null and not public.is_platform_user() then
    select p.tenant_id into v_existing from public.profiles p where p.id = auth.uid();
    if v_existing is not null then
      v_upgrade := true;
      v_tid := v_existing;
    end if;
  end if;

  if not v_upgrade then
    if exists (select 1 from public.tenants t where t.slug = v_slug) then
      raise exception 'Kode usaha sudah dipakai. Pilih slug lain.';
    end if;
    v_tid := gen_random_uuid();
    v_code := upper(regexp_replace(v_slug, '[^a-z0-9]', '', 'g'));
    if length(v_code) > 16 then
      v_code := substr(v_code, 1, 16);
    end if;
    v_pusat := v_code || '-PUSAT';
    if exists (select 1 from public.toko_id t where t.id = v_pusat) then
      v_pusat := substr(replace(v_tid::text, '-', ''), 1, 8) || '-PUSAT';
    end if;

    insert into public.tenants (
      id, slug, legal_name, status, pusat_toko_id, plan_key, white_label, industry_key
    ) values (
      v_tid, v_slug,
      coalesce(nullif(trim(coalesce(p_legal_name, '')), ''), v_name),
      'trial', v_pusat, v_plan, coalesce(p_white_label, false), v_ind
    );
    insert into public.toko_id (id, toko_id, tenant_id, cabang_code, is_pusat)
    values (v_pusat, v_name || ' — Pusat', v_tid, 'PUSAT', true);
    insert into public.app_brand (id, tenant_id, display_name, short_name, assistant_name)
    values (v_tid::text, v_tid, v_name, left(v_name, 8), left(v_name, 4) || 'A');
    insert into public.member_home_content (
      id, tenant_id, brand_label, greeting_guest, greeting_subtitle_guest
    ) values (
      v_tid::text, v_tid, upper(v_name), 'Hi!', 'Login untuk lihat pesanan'
    );
    insert into public.invoice_settings (toko_id, shop_name, tenant_id)
    values (v_pusat, v_name || ' PUSAT', v_tid)
    on conflict (toko_id) do nothing;
    perform public.apply_tenant_plan(v_tid, v_plan);
  else
    select t.slug into v_slug from public.tenants t where t.id = v_tid;
    update public.tenants
    set plan_key = v_plan, industry_key = v_ind, updated_at = now()
    where id = v_tid;
    perform public.apply_tenant_plan(v_tid, v_plan);
  end if;

  perform public.apply_store_modules(v_tid, coalesce(p_modules, '{}'::jsonb), coalesce(p_white_label, false));

  v_inv_no := 'RK-INV-' || to_char(now(), 'YYYYMM') || '-'
    || lpad(nextval('public.tenant_invoice_seq')::text, 4, '0');
  insert into public.tenant_invoices (
    id, tenant_id, invoice_no, period, amount_idr, due_at, status, notes
  ) values (
    v_inv, v_tid, v_inv_no,
    case
      when v_upgrade then to_char(now(), 'YYYY-MM') || '-U' || nextval('public.tenant_invoice_seq')::text
      else to_char(now(), 'YYYY-MM')
    end,
    v_amount,
    now() + interval '7 days', 'sent',
    'Pesanan etalase Rekasa · ' || v_ind
  );

  select c.label into v_label from public.tenant_plan_catalog c where c.plan_key = v_plan;
  v_body := public.rekasa_contract_template(v_name, p_legal_name, v_slug, v_label, v_amount);
  v_ctr_no := 'RK-KTR-' || to_char(now(), 'YYYY') || '-'
    || lpad(nextval('public.tenant_contract_seq')::text, 4, '0');
  insert into public.tenant_contracts (
    tenant_id, contract_no, public_token, title, body, plan_key, amount_idr, status
  ) values (
    v_tid, v_ctr_no, v_token,
    'Perjanjian langganan Rekasa — ' || v_name,
    v_body, v_plan, v_amount, 'sent'
  );

  insert into public.store_orders (
    id, tenant_id, plan_key, modules, white_label, amount_idr,
    display_name, slug, legal_name, phone, email, signer_name,
    status, invoice_id, contract_token, industry_key
  ) values (
    v_id, v_tid, v_plan, coalesce(p_modules, '{}'::jsonb),
    coalesce(p_white_label, false), v_amount,
    v_name, v_slug, p_legal_name, v_phone, p_email, p_signer_name,
    'provisioned', v_inv, v_token, v_ind
  );

  return jsonb_build_object(
    'ok', true,
    'order_id', v_id,
    'tenant_id', v_tid,
    'slug', v_slug,
    'industry_key', v_ind,
    'upgrade', v_upgrade,
    'amount_idr', v_amount,
    'invoice_no', v_inv_no,
    'invoice_id', v_inv,
    'contract_token', v_token,
    'status', 'provisioned'
  );
end;
$$;

grant execute on function public.submit_store_order(text, jsonb, boolean, text, text, text, text, text, text, text)
  to anon, authenticated;

create or replace function public.platform_set_tenant_industry(p_tenant_id uuid, p_industry_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ind text := lower(trim(coalesce(p_industry_key, 'umum')));
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  if not exists (select 1 from public.store_industries i where i.industry_key = v_ind) then
    raise exception 'Bidang tidak dikenal';
  end if;
  update public.tenants
  set industry_key = v_ind, updated_at = now()
  where id = p_tenant_id;
  if not found then
    raise exception 'Tenant tidak ada';
  end if;
  return jsonb_build_object('ok', true, 'tenant_id', p_tenant_id, 'industry_key', v_ind);
end;
$$;

grant execute on function public.platform_set_tenant_industry(uuid, text) to authenticated;

create or replace function public.platform_list_tenants()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id,
      'slug', t.slug,
      'legal_name', t.legal_name,
      'status', t.status,
      'suspend_reason', t.suspend_reason,
      'pusat_toko_id', t.pusat_toko_id,
      'display_name', b.display_name,
      'plan_key', t.plan_key,
      'plan_label', c.label,
      'plan_price_idr', c.price_idr,
      'white_label', t.white_label,
      'industry_key', t.industry_key,
      'industry_label', i.label,
      'created_at', t.created_at,
      'open_invoices', (
        select count(*) from public.tenant_invoices inv
        where inv.tenant_id = t.id and inv.status in ('sent', 'overdue')
      ),
      'overdue_invoices', (
        select count(*) from public.tenant_invoices inv
        where inv.tenant_id = t.id and inv.status = 'overdue'
      ),
      'latest_contract_status', (
        select x.status from public.tenant_contracts x
        where x.tenant_id = t.id and x.status <> 'void'
        order by x.created_at desc limit 1
      )
    ) order by t.created_at)
    from public.tenants t
    left join public.app_brand b on b.tenant_id = t.id
    left join public.tenant_plan_catalog c on c.plan_key = t.plan_key
    left join public.store_industries i on i.industry_key = t.industry_key
  ), '[]'::jsonb);
end;
$$;
