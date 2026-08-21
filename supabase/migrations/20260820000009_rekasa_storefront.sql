-- =============================================================================
-- Etalase Rekasa: katalog paket + fitur (nyala/mati) + beli langsung.
-- Apply setelah 000008. Jangan di-apply dari agent ke live.
-- =============================================================================

alter table public.tenant_plan_catalog
  add column if not exists blurb text,
  add column if not exists highlight text;

update public.tenant_plan_catalog set
  blurb = 'Mulai jualan: kasir, master barang, aplikasi member. Kulit Rekasa + kode usaha.',
  highlight = 'Paling hemat'
where plan_key = 'paket_c';

update public.tenant_plan_catalog set
  blurb = 'Toko berkembang: stok antar cabang, garansi, absensi, riwayat DP. Masih kulit Rekasa.',
  highlight = 'Paling laku'
where plan_key = 'paket_b';

update public.tenant_plan_catalog set
  blurb = 'Semua modul + APK & web nama+ikon merek sendiri. Paket tertinggi.',
  highlight = 'Tertinggi'
where plan_key = 'paket_a';

create table if not exists public.store_settings (
  id int primary key default 1 check (id = 1),
  white_label_addon_idr bigint not null default 200000 check (white_label_addon_idr >= 0)
);

insert into public.store_settings (id, white_label_addon_idr)
values (1, 200000)
on conflict (id) do nothing;

create table if not exists public.store_modules (
  module_key text primary key,
  label text not null,
  summary text not null default '',
  body text not null default '',
  video_url text,
  add_on_price_idr bigint not null default 50000 check (add_on_price_idr >= 0),
  sort_order int not null default 0
);

insert into public.store_modules (module_key, label, summary, body, add_on_price_idr, sort_order)
values
  (
    'pos', 'POS / Kasir',
    'Nota cepat, DP, struk, dan antrian toko.',
    'Kasir untuk penjualan harian: pilih barang, hitung uang, cetak/kirim struk, catat DP, dan simpan nota per toko. Data sekat per usaha — bukan cabang Optik.',
    50000, 10
  ),
  (
    'master_data', 'Master data barang',
    'SKU, harga, stok awal, dan katalog toko.',
    'Pusat data barang: kode, nama, harga, foto, dan stok per toko. Jadi sumber kasir, member, dan pesanan online. Ganti paket tidak menghapus barang lama.',
    50000, 20
  ),
  (
    'member_app', 'Aplikasi Member',
    'Pelanggan lihat pesanan, poin, dan garansi.',
    'Aplikasi/web member: daftar, login, lihat status nota, klaim garansi, dan promo. Di paket C/B member pakai kulit Rekasa + kode usaha. Paket A bisa merek sendiri.',
    75000, 30
  ),
  (
    'history_dp', 'Riwayat DP / nota',
    'Lacak uang muka dan sisa tagihan pelanggan toko.',
    'Daftar DP dan pelunasan per nota. Bukan tagihan Rekasa ke UMKM — ini piutang toko ke pelanggan. Cocok optik yang biasa DP frame/lensa.',
    40000, 40
  ),
  (
    'logistics', 'Logistik / stok antar toko',
    'Pindah barang pusat ↔ cabang, stok real.',
    'Mutasi stok antar toko dalam satu usaha. Pusat dan cabang punya kode sendiri di dalam tenant, bukan CABANG milik merek lain.',
    60000, 50
  ),
  (
    'warranty', 'Garansi',
    'Klaim garansi frame/lensa dengan batas waktu.',
    'Syarat garansi, klaim, dan status ambil. Member bisa ajukan dari aplikasinya. Riwayat tetap di usaha yang sama meski paket diubah.',
    50000, 60
  ),
  (
    'attendance', 'Absensi & geofence',
    'Hadir di lokasi toko, jadwal, dan pantauan.',
    'Absen masuk/keluar dengan batas lokasi toko, jadwal kerja, dan monitor admin. Cocok multi cabang yang ingin disiplin tanpa aplikasi HR terpisah.',
    60000, 70
  ),
  (
    'finance', 'Keuangan / buku besar',
    'Jurnal, periode, dan laporan owner.',
    'Buku besar, periode fiskal, dan laporan untuk owner. Hanya di paket atas / add-on. Tidak mencampur uang antar merek.',
    80000, 80
  ),
  (
    'online_orders', 'Pesanan online',
    'Order dari member, ongkir, dan pengiriman.',
    'Keranjang member, checkout, hold stok, dan status kirim. Membutuhkan kasir + master barang. Bukan marketplace Rekasa — ini toko Anda yang jualan ke pelanggan.',
    80000, 90
  )
on conflict (module_key) do update set
  label = excluded.label,
  summary = excluded.summary,
  body = excluded.body,
  add_on_price_idr = excluded.add_on_price_idr,
  sort_order = excluded.sort_order;

create table if not exists public.store_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  plan_key text not null,
  modules jsonb not null default '{}'::jsonb,
  white_label boolean not null default false,
  amount_idr bigint not null default 0 check (amount_idr >= 0),
  display_name text not null,
  slug text,
  legal_name text,
  phone text,
  email text,
  signer_name text,
  status text not null default 'pending'
    check (status in ('pending', 'provisioned', 'paid', 'cancelled')),
  invoice_id uuid,
  contract_token text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists store_orders_created_idx on public.store_orders (created_at desc);

alter table public.store_settings enable row level security;
alter table public.store_modules enable row level security;
alter table public.store_orders enable row level security;

drop policy if exists store_modules_read on public.store_modules;
create policy store_modules_read on public.store_modules
  for select to anon, authenticated using (true);

drop policy if exists store_settings_read on public.store_settings;
create policy store_settings_read on public.store_settings
  for select to anon, authenticated using (true);

drop policy if exists store_orders_platform on public.store_orders;
create policy store_orders_platform on public.store_orders
  for all to authenticated
  using (public.is_platform_user())
  with check (public.is_platform_user());

-- -----------------------------------------------------------------------------
create or replace function public.list_store_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_wl bigint := 200000;
begin
  select s.white_label_addon_idr into v_wl from public.store_settings s where s.id = 1;
  return jsonb_build_object(
    'ok', true,
    'white_label_addon_idr', coalesce(v_wl, 200000),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'plan_key', c.plan_key,
        'label', c.label,
        'price_idr', c.price_idr,
        'white_label', c.white_label,
        'blurb', c.blurb,
        'highlight', c.highlight,
        'sort_order', c.sort_order,
        'modules', coalesce((
          select jsonb_agg(pm.module_key order by sm.sort_order)
          from public.tenant_plan_modules pm
          left join public.store_modules sm on sm.module_key = pm.module_key
          where pm.plan_key = c.plan_key
        ), '[]'::jsonb)
      ) order by c.sort_order)
      from public.tenant_plan_catalog c
      where c.plan_key in ('paket_c', 'paket_b', 'paket_a')
    ), '[]'::jsonb),
    'modules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', m.module_key,
        'label', m.label,
        'summary', m.summary,
        'body', m.body,
        'video_url', m.video_url,
        'add_on_price_idr', m.add_on_price_idr
      ) order by m.sort_order)
      from public.store_modules m
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.list_store_catalog() to anon, authenticated;

create or replace function public.quote_store_order(
  p_plan_key text,
  p_modules jsonb,
  p_white_label boolean default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_plan text := lower(trim(coalesce(p_plan_key, 'paket_c')));
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
    if exists (
      select 1 from public.tenant_plan_modules pm
      where pm.plan_key = v_plan and pm.module_key = v_key
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
    'base_idr', coalesce(v_base, 0),
    'add_on_idr', v_add,
    'white_label_idr', v_wl_fee,
    'white_label', v_wl,
    'amount_idr', coalesce(v_base, 0) + v_add + v_wl_fee
  );
end;
$$;

grant execute on function public.quote_store_order(text, jsonb, boolean)
  to anon, authenticated;

create or replace function public.apply_store_modules(
  p_tenant uuid,
  p_modules jsonb,
  p_white_label boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_on boolean;
  v_known text[] := array[
    'pos', 'logistics', 'history_dp', 'warranty', 'finance',
    'master_data', 'member_app', 'attendance', 'online_orders'
  ];
begin
  foreach v_key in array v_known loop
    v_on := coalesce((p_modules ->> v_key)::boolean, false);
    insert into public.tenant_modules (tenant_id, module_key, enabled)
    values (p_tenant, v_key, v_on)
    on conflict (tenant_id, module_key) do update set enabled = excluded.enabled;
  end loop;
  update public.tenants
  set white_label = coalesce(p_white_label, false), updated_at = now()
  where id = p_tenant;
end;
$$;

create or replace function public.submit_store_order(
  p_plan_key text,
  p_modules jsonb,
  p_white_label boolean,
  p_display_name text,
  p_slug text,
  p_phone text,
  p_email text default null,
  p_legal_name text default null,
  p_signer_name text default null
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

  v_quote := public.quote_store_order(v_plan, p_modules, p_white_label);
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

    insert into public.tenants (id, slug, legal_name, status, pusat_toko_id, plan_key, white_label)
    values (
      v_tid, v_slug,
      coalesce(nullif(trim(coalesce(p_legal_name, '')), ''), v_name),
      'trial', v_pusat, v_plan, coalesce(p_white_label, false)
    );
    insert into public.toko_id (id, toko_id, tenant_id, cabang_code, is_pusat)
    values (v_pusat, v_name || ' — Pusat', v_tid, 'PUSAT', true);
    insert into public.app_brand (id, tenant_id, display_name, short_name, assistant_name)
    values (
      v_tid::text, v_tid, v_name, left(v_name, 8), left(v_name, 4) || 'A'
    );
    insert into public.member_home_content (
      id, tenant_id, brand_label, greeting_guest, greeting_subtitle_guest
    ) values (
      v_tid::text, v_tid, upper(v_name), 'Hi!', 'Login untuk lihat pesanan & garansi'
    );
    insert into public.invoice_settings (toko_id, shop_name, tenant_id)
    values (v_pusat, v_name || ' PUSAT', v_tid)
    on conflict (toko_id) do nothing;
    perform public.apply_tenant_plan(v_tid, v_plan);
  else
    select t.slug into v_slug from public.tenants t where t.id = v_tid;
    update public.tenants
    set plan_key = v_plan, updated_at = now()
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
    'Pesanan etalase Rekasa'
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
    status, invoice_id, contract_token
  ) values (
    v_id, v_tid, v_plan, coalesce(p_modules, '{}'::jsonb),
    coalesce(p_white_label, false), v_amount,
    v_name, v_slug, p_legal_name, v_phone, p_email, p_signer_name,
    'provisioned', v_inv, v_token
  );

  return jsonb_build_object(
    'ok', true,
    'order_id', v_id,
    'tenant_id', v_tid,
    'slug', v_slug,
    'upgrade', v_upgrade,
    'amount_idr', v_amount,
    'invoice_no', v_inv_no,
    'invoice_id', v_inv,
    'contract_token', v_token,
    'status', 'provisioned'
  );
end;
$$;

grant execute on function public.submit_store_order(text, jsonb, boolean, text, text, text, text, text, text)
  to anon, authenticated;

create or replace function public.platform_list_store_orders()
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
      'id', o.id,
      'tenant_id', o.tenant_id,
      'plan_key', o.plan_key,
      'amount_idr', o.amount_idr,
      'display_name', o.display_name,
      'slug', o.slug,
      'phone', o.phone,
      'email', o.email,
      'status', o.status,
      'white_label', o.white_label,
      'invoice_id', o.invoice_id,
      'contract_token', o.contract_token,
      'created_at', o.created_at
    ) order by o.created_at desc)
    from public.store_orders o
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.platform_list_store_orders() to authenticated;

create or replace function public.platform_activate_store_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv uuid;
  v_tid uuid;
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  select o.invoice_id, o.tenant_id into v_inv, v_tid
  from public.store_orders o where o.id = p_order_id;
  if v_tid is null then
    raise exception 'Pesanan tidak ada';
  end if;
  if v_inv is not null then
    perform public.platform_mark_invoice_paid(v_inv, 'etalase');
  else
    update public.tenants
    set status = 'aktif', suspend_reason = null, updated_at = now()
    where id = v_tid;
  end if;
  update public.store_orders
  set status = 'paid', updated_at = now()
  where id = p_order_id;
  return jsonb_build_object('ok', true, 'order_id', p_order_id, 'tenant_id', v_tid);
end;
$$;

grant execute on function public.platform_activate_store_order(uuid) to authenticated;

create or replace function public.platform_set_store_module(
  p_module_key text,
  p_video_url text default null,
  p_body text default null,
  p_summary text default null,
  p_add_on_price_idr bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  update public.store_modules
  set video_url = coalesce(nullif(trim(coalesce(p_video_url, '')), ''), video_url),
      body = coalesce(nullif(trim(coalesce(p_body, '')), ''), body),
      summary = coalesce(nullif(trim(coalesce(p_summary, '')), ''), summary),
      add_on_price_idr = coalesce(p_add_on_price_idr, add_on_price_idr)
  where module_key = p_module_key;
  if not found then
    raise exception 'Modul tidak ada';
  end if;
  return jsonb_build_object('ok', true, 'module_key', p_module_key);
end;
$$;

grant execute on function public.platform_set_store_module(text, text, text, text, bigint)
  to authenticated;

-- Lunas etalase: trial / suspend → aktif.
create or replace function public.platform_mark_invoice_paid(
  p_invoice_id uuid,
  p_method text default 'transfer'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_left int := 0;
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  update public.tenant_invoices
  set status = 'paid',
      paid_at = now(),
      paid_method = nullif(trim(coalesce(p_method, '')), ''),
      updated_at = now()
  where id = p_invoice_id
    and status in ('draft', 'sent', 'overdue')
  returning tenant_id into v_tenant;
  if v_tenant is null then
    raise exception 'Tagihan tidak ada / sudah lunas';
  end if;

  select count(*) into v_left
  from public.tenant_invoices i
  where i.tenant_id = v_tenant
    and i.status = 'overdue'
    and i.paid_at is null;

  if v_left = 0 then
    update public.tenants
    set status = 'aktif',
        suspend_reason = null,
        updated_at = now()
    where id = v_tenant
      and status in ('suspend', 'trial');
  end if;

  return jsonb_build_object('ok', true, 'id', p_invoice_id, 'tenant_id', v_tenant, 'reactivated', v_left = 0);
end;
$$;
