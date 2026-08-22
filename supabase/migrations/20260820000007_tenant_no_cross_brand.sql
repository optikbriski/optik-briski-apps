-- =============================================================================
-- Sekat sisa nabrak antar merek. Jangan diam-diam pakai tenant Optik.
-- Apply setelah 000001–000006. Jangan di-apply dari agent ke live.
-- =============================================================================

-- 1) Tenant wajib. Null ≠ Optik.
create or replace function public.require_member_tenant(p uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p is null then
    raise exception 'tenant wajib — jangan memakai data usaha lain';
  end if;
  if exists (
    select 1 from public.tenants t
    where t.id = p and t.status = 'aktif'
  ) then
    return p;
  end if;
  raise exception 'Kode usaha / tenant tidak valid';
end;
$$;

comment on function public.require_member_tenant(uuid) is
  'Fail-closed. Null tidak boleh jatuh ke Optik.';

-- 2) Buang default UUID Optik di argumen RPC.
-- Postgres tidak punya ALTER FUNCTION ... ALTER PARAMETER n DROP DEFAULT.
do $$
declare
  r record;
  v_def text;
  v_as int;
  v_head text;
  v_body text;
begin
  for r in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and coalesce(p.pronargdefaults, 0) > 0
      and pg_get_expr(p.proargdefaults, 0)
            like '%00000000-0000-0000-0000-000000000001%'
  loop
    v_def := pg_get_functiondef(r.oid);
    v_as := strpos(v_def, E'\nAS ');
    if v_as = 0 then
      continue;
    end if;
    v_head := left(v_def, v_as - 1);
    v_body := substr(v_def, v_as);
    v_head := regexp_replace(
      v_head,
      $re$DEFAULT\s+'00000000-0000-0000-0000-000000000001'(::uuid)?$re$,
      '',
      'gi'
    );
    execute v_head || v_body;
  end loop;
end
$$;

-- 3) Slug kosong ≠ Optik. Jangan resolve diam-diam.
create or replace function public.resolve_tenant(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_slug text := lower(trim(coalesce(p_slug, '')));
  v public.tenants%rowtype;
  v_brand public.app_brand%rowtype;
begin
  if v_slug = '' then
    return jsonb_build_object('ok', false, 'error', 'Kode usaha wajib');
  end if;
  select * into v from public.tenants where slug = v_slug and status = 'aktif';
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Kode usaha tidak ditemukan');
  end if;
  select * into v_brand from public.app_brand where tenant_id = v.id;
  return jsonb_build_object(
    'ok', true,
    'id', v.id,
    'slug', v.slug,
    'legal_name', v.legal_name,
    'pusat_toko_id', v.pusat_toko_id,
    'display_name', coalesce(v_brand.display_name, v.legal_name),
    'short_name', v_brand.short_name,
    'assistant_name', v_brand.assistant_name
  );
end;
$$;

-- 4) Jangan default kolom ke Optik.
alter table public.members alter column tenant_id drop default;
alter table public.toko_id alter column tenant_id drop default;

-- 5) RPC Member 000002: pakai require_member_tenant (bukan coalesce Optik).
create or replace function public.list_tenant_stores(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id,
      'toko_id', t.toko_id,
      'cabang_code', t.cabang_code,
      'is_pusat', t.is_pusat,
      'latitude', t.latitude,
      'longitude', t.longitude
    ) order by t.is_pusat desc, t.id)
    from public.toko_id t
    where t.tenant_id = v_tenant
  ), '[]'::jsonb);
end;
$$;

create or replace function public.member_login(
  p_identifier text,
  p_password text,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id text := trim(coalesce(p_identifier, ''));
  v_pass text := coalesce(p_password, '');
  v_member public.members%rowtype;
  v_phone text;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_id = '' or v_pass = '' then
    return jsonb_build_object('ok', false, 'error', 'Isi email/HP dan password');
  end if;
  if position('@' in v_id) > 0 then
    select * into v_member from public.members m
    where m.tenant_id = v_tenant and lower(trim(m.email)) = lower(v_id)
    limit 1;
  else
    v_phone := public.wa_digits(v_id);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
    end if;
    select * into v_member from public.members m
    where m.tenant_id = v_tenant and m.phone_e164 = v_phone
    limit 1;
  end if;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun tidak ditemukan di usaha ini. Daftar dulu.');
  end if;
  if v_member.password_hash is null or trim(v_member.password_hash) = '' then
    return jsonb_build_object('ok', false, 'error',
      'Akun ini belum punya password. Pakai OTP atau Lupa password.');
  end if;
  if crypt(v_pass, v_member.password_hash) <> v_member.password_hash then
    return jsonb_build_object('ok', false, 'error', 'Password salah');
  end if;
  update public.members set updated_at = now() where id = v_member.id;
  return jsonb_build_object('ok', true, 'member', public.member_public_row(v_member));
end;
$$;

create or replace function public.list_member_sales(p_phone text, p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null then return '[]'::jsonb; end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        s.id, s.no_invoice, s.toko_id, s.nama_pelanggan, s.status_pembayaran,
        s.tracking_status, s.diambil_at, s.foto_hasil_url, s.sisa_tagihan,
        s.total_harga, s.dibayarkan, s.created_at, s.lunas_at,
        s.channel, s.online_order_id, s.fulfillment, s.courier,
        (s.qr_dp_token is not null and length(trim(s.qr_dp_token)) >= 8) as has_qr_dp,
        (s.qr_lunas_token is not null and length(trim(s.qr_lunas_token)) >= 8) as has_qr_lunas,
        (s.qr_claim_token is not null and length(trim(s.qr_claim_token)) >= 8) as has_qr_claim
      from public.sales s
      where s.tenant_id = v_tenant
        and (
          public.wa_digits(s.no_wa) = v_phone
          or regexp_replace(coalesce(s.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
        )
      order by s.created_at desc
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

-- 6) Wrapper invoice tanpa tenant — buang (bocor ke Optik).
drop function if exists public.get_invoice_hub(text);

-- 7) Owner utama hanya cabang TENANT-nya, bukan seluruh project.
create or replace function public.owner_accessible_toko_ids()
returns setof text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner public.owners%rowtype;
  v_tenant uuid;
begin
  if not public.is_owner_role() then
    return;
  end if;
  select * into v_owner from public.owner_current();
  if v_owner.id is null then
    return;
  end if;
  v_tenant := coalesce(v_owner.tenant_id, public.current_tenant_id());
  if v_tenant is null then
    return;
  end if;

  if v_owner.owner_type = 'utama' then
    return query
      select t.id from public.toko_id t
      where t.tenant_id = v_tenant
      order by t.id;
    return;
  end if;

  return query
    select m.toko_id
    from public.owner_toko_map m
    join public.toko_id t on t.id = m.toko_id
    where m.owner_id = v_owner.id
      and t.tenant_id = v_tenant
    order by m.toko_id;
end;
$$;

-- 8) Stok/katalog: toko wajib milik tenant pemanggil. Copy SKU hanya dalam tenant.
create or replace function public.assert_toko_in_caller_tenant(p_toko text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko, '')));
  v_toko_tenant uuid;
  v_caller uuid := public.current_tenant_id();
begin
  if v_toko = '' then
    raise exception 'Toko wajib';
  end if;
  select tenant_id into v_toko_tenant
  from public.toko_id
  where upper(trim(id)) = v_toko;
  if v_toko_tenant is null then
    raise exception 'toko_id % tidak dikenal', v_toko;
  end if;
  if v_caller is not null
     and not public.is_platform_user()
     and v_toko_tenant <> v_caller then
    raise exception 'Toko bukan milik usaha ini';
  end if;
  return v_toko_tenant;
end;
$$;

grant execute on function public.assert_toko_in_caller_tenant(text)
  to anon, authenticated, service_role;

create or replace function public.ensure_product_at_toko(
  p_sku text,
  p_toko text,
  p_template jsonb default '{}'::jsonb
)
returns public.products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text := upper(trim(p_sku));
  v_toko text := upper(trim(p_toko));
  v_row public.products;
  v_src public.products;
  v_tenant uuid;
  v_pusat text;
begin
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  v_tenant := public.assert_toko_in_caller_tenant(v_toko);
  v_pusat := public.tenant_pusat_toko_id(v_tenant);

  select * into v_row
  from public.products
  where tenant_id = v_tenant
    and upper(trim(sku)) = v_sku
    and upper(trim(toko_id)) = v_toko
  limit 1;
  if found then
    return v_row;
  end if;

  select * into v_src
  from public.products
  where tenant_id = v_tenant
    and upper(trim(sku)) = v_sku
  order by case
    when v_pusat is not null and upper(trim(toko_id)) = upper(trim(v_pusat)) then 0
    else 1
  end, created_at
  limit 1;

  if not found then
    insert into public.products (
      nama, harga, harga_jual, harga_modal, kategori, sub_kategori,
      barcode, sku, warna, jenis_lensa, toko_id, stock, tenant_id
    ) values (
      coalesce(p_template->>'nama', v_sku),
      coalesce((p_template->>'harga')::bigint, 0),
      coalesce((p_template->>'harga_jual')::bigint, (p_template->>'harga')::bigint, 0),
      coalesce((p_template->>'harga_modal')::bigint, 0),
      coalesce(p_template->>'kategori', 'Lainnya'),
      p_template->>'sub_kategori',
      coalesce(nullif(p_template->>'barcode', ''), v_sku),
      v_sku,
      p_template->>'warna',
      p_template->>'jenis_lensa',
      v_toko,
      0,
      v_tenant
    )
    returning * into v_row;
    return v_row;
  end if;

  insert into public.products (
    nama, harga, harga_jual, harga_modal, kategori, sub_kategori,
    barcode, sku, warna, jenis_lensa, sph_r, sph_l, cyl_r, cyl_l, add_r, add_l,
    image_url, foto_url, toko_id, stock, tenant_id
  ) values (
    v_src.nama, v_src.harga, v_src.harga_jual, v_src.harga_modal,
    v_src.kategori, v_src.sub_kategori,
    v_src.barcode, v_src.sku, v_src.warna, v_src.jenis_lensa,
    v_src.sph_r, v_src.sph_l, v_src.cyl_r, v_src.cyl_l, v_src.add_r, v_src.add_l,
    v_src.image_url, v_src.foto_url, v_toko, 0, v_tenant
  )
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.propagate_pusat_sku_to_all_toko(p_sku text, p_tenant_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text := upper(trim(p_sku));
  v_toko record;
  v_n integer := 0;
  v_tenant uuid;
  v_pusat text;
begin
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  v_tenant := coalesce(p_tenant_id, public.current_tenant_id());
  if v_tenant is null then
    raise exception 'tenant wajib — katalog tidak boleh sebar ke merek lain';
  end if;
  if public.current_tenant_id() is not null
     and not public.is_platform_user()
     and public.current_tenant_id() <> v_tenant then
    raise exception 'Tenant bukan milik usaha ini';
  end if;
  v_pusat := public.tenant_pusat_toko_id(v_tenant);
  if v_pusat is null then
    raise exception 'Tenant belum punya toko PUSAT';
  end if;
  if not exists (
    select 1 from public.products
    where upper(trim(sku)) = v_sku
      and upper(trim(toko_id)) = upper(trim(v_pusat))
      and tenant_id = v_tenant
  ) then
    perform public.ensure_product_at_toko(v_sku, v_pusat, '{}'::jsonb);
  end if;
  for v_toko in
    select upper(trim(id)) as id
    from public.toko_id
    where tenant_id = v_tenant
      and coalesce(is_pusat, false) = false
      and nullif(trim(id), '') is not null
  loop
    perform public.ensure_product_at_toko(v_sku, v_toko.id, '{}'::jsonb);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

drop function if exists public.sync_catalog_metadata_from_pusat(text);
drop function if exists public.sync_catalog_metadata_from_pusat(text, uuid);

create or replace function public.sync_catalog_metadata_from_pusat(p_sku text, p_tenant_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text := upper(trim(p_sku));
  v_src public.products;
  v_n integer := 0;
  v_tenant uuid;
  v_pusat text;
begin
  if v_sku is null or v_sku = '' then
    raise exception 'SKU wajib';
  end if;
  v_tenant := coalesce(p_tenant_id, public.current_tenant_id());
  if v_tenant is null then
    raise exception 'tenant wajib';
  end if;
  v_pusat := public.tenant_pusat_toko_id(v_tenant);
  if v_pusat is null then
    return 0;
  end if;
  select * into v_src
  from public.products
  where tenant_id = v_tenant
    and upper(trim(sku)) = v_sku
    and upper(trim(toko_id)) = upper(trim(v_pusat))
  order by created_at
  limit 1;
  if not found then
    return 0;
  end if;
  update public.products p
  set
    nama = v_src.nama,
    harga = v_src.harga,
    harga_jual = v_src.harga_jual,
    harga_modal = v_src.harga_modal,
    kategori = v_src.kategori,
    sub_kategori = v_src.sub_kategori,
    barcode = v_src.barcode,
    sku = v_src.sku,
    warna = v_src.warna,
    jenis_lensa = v_src.jenis_lensa,
    sph_r = v_src.sph_r, sph_l = v_src.sph_l,
    cyl_r = v_src.cyl_r, cyl_l = v_src.cyl_l,
    add_r = v_src.add_r, add_l = v_src.add_l,
    image_url = v_src.image_url,
    foto_url = v_src.foto_url
  where p.tenant_id = v_tenant
    and upper(trim(p.sku)) = v_sku
    and upper(trim(p.toko_id)) <> upper(trim(v_pusat));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

create or replace function public.sync_catalog_metadata_from_pusat(p_sku text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.sync_catalog_metadata_from_pusat(p_sku, public.current_tenant_id());
end;
$$;

create or replace function public.enforce_catalog_parity()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_t record;
  v_sku record;
  v_skus_lifted integer := 0;
  v_skus_propagated integer := 0;
  v_n integer := 0;
begin
  if v_tenant is null and not public.is_platform_user() then
    raise exception 'tenant wajib — parity katalog tidak boleh lintas merek';
  end if;
  for v_t in
    select id from public.tenants
    where status = 'aktif'
      and (public.is_platform_user() or id = v_tenant)
  loop
    for v_sku in
      select distinct upper(trim(p.sku)) as sku
      from public.products p
      where p.tenant_id = v_t.id
        and nullif(trim(p.sku), '') is not null
        and upper(trim(p.toko_id)) is distinct from upper(trim(coalesce(public.tenant_pusat_toko_id(v_t.id), '')))
        and not exists (
          select 1 from public.products p2
          where p2.tenant_id = v_t.id
            and upper(trim(p2.sku)) = upper(trim(p.sku))
            and upper(trim(p2.toko_id)) = upper(trim(coalesce(public.tenant_pusat_toko_id(v_t.id), '')))
        )
    loop
      perform public.propagate_pusat_sku_to_all_toko(v_sku.sku, v_t.id);
      v_skus_lifted := v_skus_lifted + 1;
    end loop;
    for v_sku in
      select distinct upper(trim(p.sku)) as sku
      from public.products p
      where p.tenant_id = v_t.id
        and upper(trim(p.toko_id)) = upper(trim(coalesce(public.tenant_pusat_toko_id(v_t.id), '')))
        and nullif(trim(p.sku), '') is not null
    loop
      perform public.propagate_pusat_sku_to_all_toko(v_sku.sku, v_t.id);
      perform public.sync_catalog_metadata_from_pusat(v_sku.sku, v_t.id);
      v_skus_propagated := v_skus_propagated + 1;
    end loop;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object(
    'ok', true,
    'tenants', v_n,
    'skus_lifted', v_skus_lifted,
    'skus_propagated', v_skus_propagated
  );
end;
$$;

create or replace function public.trg_products_catalog_parity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pusat text;
begin
  v_pusat := public.tenant_pusat_toko_id(new.tenant_id);
  if v_pusat is not null
     and upper(trim(coalesce(new.toko_id, ''))) = upper(trim(v_pusat))
     and nullif(trim(coalesce(new.sku, '')), '') is not null then
    perform public.propagate_pusat_sku_to_all_toko(new.sku, new.tenant_id);
    perform public.sync_catalog_metadata_from_pusat(new.sku, new.tenant_id);
  end if;
  return new;
end;
$$;

-- 9) Ongkir: toko harus milik tenant.
drop function if exists public.quote_online_delivery(text, text);
create function public.quote_online_delivery(
  p_toko_id text,
  p_courier text,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_courier text := lower(trim(coalesce(p_courier, '')));
  v_row public.toko_delivery_settings%rowtype;
  v_fee bigint := 0;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'Cabang wajib dipilih');
  end if;
  if not exists (
    select 1 from public.toko_id t
    where upper(trim(t.id)) = v_toko and t.tenant_id = v_tenant
  ) then
    return jsonb_build_object('ok', false, 'error', 'Cabang bukan milik usaha ini');
  end if;

  select * into v_row from public.toko_delivery_settings where toko_id = v_toko;
  if not found then
    insert into public.toko_delivery_settings (toko_id) values (v_toko)
    returning * into v_row;
  end if;
  if not coalesce(v_row.online_selling_enabled, true) then
    return jsonb_build_object('ok', false, 'error', 'Cabang belum aktif jual online');
  end if;
  v_fee := case v_courier
    when 'grab' then coalesce(v_row.fee_grab, 0)
    when 'gojek' then coalesce(v_row.fee_gojek, 0)
    when 'other' then coalesce(v_row.fee_other, 0)
    when 'obr' then greatest(
      0,
      least(
        coalesce(v_row.fee_grab, 15000),
        coalesce(v_row.fee_gojek, 15000),
        coalesce(v_row.fee_other, 15000)
      ) - 2000
    )
    else -1
  end;
  if v_fee < 0 then
    return jsonb_build_object('ok', false, 'error', 'Kurir tidak valid');
  end if;
  return jsonb_build_object(
    'ok', true,
    'toko_id', v_toko,
    'courier', v_courier,
    'shipping_fee', v_fee,
    'pickup_enabled', v_row.pickup_enabled,
    'delivery_enabled', coalesce(v_row.online_selling_enabled, true)
  );
end;
$$;

grant execute on function public.quote_online_delivery(text, text, uuid)
  to anon, authenticated;

-- apply_stock_delta: toko wajib milik tenant (tanpa ganti rumus stok).
create or replace function public.apply_stock_delta(
  p_toko text,
  p_sku text,
  p_qty_delta integer,
  p_reason text,
  p_alasan_text text default null,
  p_ref_type text default null,
  p_ref_id text default null,
  p_actor_id uuid default null,
  p_actor_nama text default null,
  p_meta jsonb default '{}'::jsonb,
  p_allow_create boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(p_toko));
  v_sku text := trim(p_sku);
  v_row public.products;
  v_before integer;
  v_after integer;
  v_ledger_id uuid;
  v_tenant uuid;
begin
  v_tenant := public.assert_toko_in_caller_tenant(v_toko);
  if p_qty_delta is null or p_qty_delta = 0 then
    raise exception 'qty_delta tidak boleh 0';
  end if;
  if p_reason not in (
    'OPENING','TRANSFER_OUT','TRANSFER_IN','RETURN_OUT','RETURN_IN',
    'SALE','WRITE_OFF','ADJUST'
  ) then
    raise exception 'reason tidak valid: %', p_reason;
  end if;
  if p_reason in ('WRITE_OFF','ADJUST')
     and (p_alasan_text is null or trim(p_alasan_text) = '') then
    raise exception 'alasan_text wajib untuk %', p_reason;
  end if;

  if p_allow_create then
    v_row := public.ensure_product_at_toko(v_sku, v_toko, coalesce(p_meta->'product', '{}'::jsonb));
  else
    select * into v_row
    from public.products
    where tenant_id = v_tenant
      and upper(trim(sku)) = upper(trim(v_sku))
      and upper(trim(toko_id)) = v_toko
    for update;
    if not found then
      raise exception 'Produk % tidak ada di %', v_sku, v_toko;
    end if;
  end if;

  select * into v_row
  from public.products
  where id = v_row.id
  for update;

  v_before := coalesce(v_row.stock, 0);
  v_after := v_before + p_qty_delta;
  if v_after < 0 then
    raise exception 'Stok tidak cukup di % untuk SKU % (stok %, delta %)',
      v_toko, v_sku, v_before, p_qty_delta;
  end if;

  update public.products
  set stock = v_after
  where id = v_row.id
    and tenant_id = v_tenant;

  insert into public.product_stock_ledger (
    sku, toko_id, product_id, qty_delta, stock_before, stock_after,
    reason, alasan_text, ref_type, ref_id, actor_id, actor_nama, meta
  ) values (
    v_row.sku, v_toko, v_row.id, p_qty_delta, v_before, v_after,
    p_reason, p_alasan_text, p_ref_type, p_ref_id, p_actor_id, p_actor_nama,
    coalesce(p_meta, '{}'::jsonb)
  )
  returning id into v_ledger_id;

  return jsonb_build_object(
    'ok', true,
    'ledger_id', v_ledger_id,
    'product_id', v_row.id,
    'sku', v_row.sku,
    'toko_id', v_toko,
    'stock_before', v_before,
    'stock_after', v_after,
    'qty_delta', p_qty_delta,
    'reason', p_reason
  );
end;
$$;

-- 10) Poin member: HP unik per tenant, jangan ambil member merek lain.
create or replace function public.award_member_points_for_sale(p_sale_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_digits text;
  v_alt text;
  v_member_id uuid;
  v_points int;
begin
  if p_sale_id is null then
    return jsonb_build_object('ok', false, 'error', 'sale_id wajib');
  end if;
  select * into v_sale from public.sales where id = p_sale_id limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'nota tidak ditemukan');
  end if;
  if v_sale.tenant_id is null then
    return jsonb_build_object('ok', false, 'error', 'nota tanpa tenant');
  end if;
  if upper(trim(coalesce(v_sale.status_pembayaran, ''))) <> 'LUNAS'
     and coalesce(v_sale.sisa_tagihan, 0) > 0 then
    return jsonb_build_object('ok', false, 'error', 'belum lunas', 'skipped', true);
  end if;
  if exists (
    select 1 from public.member_points_ledger l
    where l.sale_id = v_sale.id and l.reason = 'purchase_10pct'
  ) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_awarded');
  end if;
  v_digits := public.wa_digits(v_sale.no_wa);
  if v_digits is null or length(v_digits) < 8 then
    return jsonb_build_object('ok', false, 'error', 'no_wa tidak valid', 'skipped', true);
  end if;
  v_alt := case
    when v_digits like '62%' then '0' || substr(v_digits, 3)
    when v_digits like '0%' then '62' || substr(v_digits, 2)
    else v_digits
  end;
  select m.id into v_member_id
  from public.members m
  where m.tenant_id = v_sale.tenant_id
    and (
      public.wa_digits(m.phone_e164) in (v_digits, v_alt)
      or regexp_replace(coalesce(m.phone_e164, ''), '\D', '', 'g') in (v_digits, v_alt)
      or regexp_replace(coalesce(m.phone_raw, ''), '\D', '', 'g') in (v_digits, v_alt)
    )
  order by m.created_at
  limit 1;
  if v_member_id is null then
    return jsonb_build_object('ok', false, 'error', 'member tidak terdaftar', 'skipped', true);
  end if;
  v_points := greatest(0, floor(coalesce(v_sale.total_harga, 0) * 0.10)::int);
  if v_points <= 0 then
    return jsonb_build_object('ok', false, 'error', 'poin 0', 'skipped', true);
  end if;
  begin
    insert into public.member_points_ledger (
      member_id, delta, reason, sale_id, meta
    ) values (
      v_member_id, v_points, 'purchase_10pct', v_sale.id,
      jsonb_build_object(
        'no_invoice', v_sale.no_invoice,
        'total_harga', v_sale.total_harga,
        'rate', 0.10,
        'tenant_id', v_sale.tenant_id
      )
    );
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_awarded');
  end;
  return jsonb_build_object('ok', true, 'member_id', v_member_id, 'points', v_points);
end;
$$;

-- 11) Redeem voucher: member lookup sekat tenant.
create or replace function public.lookup_member_id_in_tenant(p_phone text, p_tenant uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_digits text := public.wa_digits(p_phone);
  v_alt text;
  v_id uuid;
begin
  if p_tenant is null or v_digits is null or length(v_digits) < 8 then
    return null;
  end if;
  v_alt := case
    when v_digits like '62%' then '0' || substr(v_digits, 3)
    when v_digits like '0%' then '62' || substr(v_digits, 2)
    else v_digits
  end;
  select m.id into v_id
  from public.members m
  where m.tenant_id = p_tenant
    and (
      public.wa_digits(m.phone_e164) in (v_digits, v_alt)
      or regexp_replace(coalesce(m.phone_e164, ''), '\D', '', 'g') in (v_digits, v_alt)
      or regexp_replace(coalesce(m.phone_raw, ''), '\D', '', 'g') in (v_digits, v_alt)
    )
  order by m.created_at
  limit 1;
  return v_id;
end;
$$;

-- Patch redeem: ganti lookup global lewat helper di fungsi yang sudah ada
-- (fungsi penuh 000003 tetap; kita bungkus SELECT member).
create or replace function public.redeem_member_promo(
  p_code text,
  p_sale_id uuid default null,
  p_phone text default null,
  p_discount_applied bigint default 0,
  p_online_order_id uuid default null,
  p_channel text default 'pos',
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_row public.member_promos%rowtype;
  v_sale public.sales%rowtype;
  v_online public.online_orders%rowtype;
  v_member_id uuid;
  v_phone text := trim(coalesce(p_phone, ''));
  v_balance int := 0;
  v_points int := 0;
  v_disc bigint := greatest(0, coalesce(p_discount_applied, 0));
  v_updated int := 0;
  v_existing uuid;
  v_ch text := lower(trim(coalesce(p_channel, 'pos')));
  v_ref_label text;
  v_tenant uuid;
begin
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Kode voucher kosong');
  end if;
  if (p_sale_id is null and p_online_order_id is null)
     or (p_sale_id is not null and p_online_order_id is not null) then
    return jsonb_build_object('ok', false, 'error', 'Harus ada tepat satu: sale_id atau online_order_id');
  end if;
  v_tenant := coalesce(public.current_tenant_id(), p_tenant_id);
  if v_tenant is null then
    raise exception 'tenant wajib';
  end if;
  v_tenant := public.require_member_tenant(v_tenant);

  if v_ch not in ('pos', 'online', 'member', 'any') then
    v_ch := case when p_online_order_id is not null then 'online' else 'pos' end;
  end if;

  if p_sale_id is not null then
    select * into v_sale from public.sales where id = p_sale_id and tenant_id = v_tenant limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Nota penjualan tidak ditemukan');
    end if;
    v_ref_label := coalesce(v_sale.no_invoice, p_sale_id::text);
    select id into v_existing from public.member_promo_redemptions where sale_id = p_sale_id limit 1;
  else
    select * into v_online from public.online_orders where id = p_online_order_id and tenant_id = v_tenant limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Pesanan online tidak ditemukan');
    end if;
    v_ref_label := coalesce(v_online.midtrans_order_id, p_online_order_id::text);
    select id into v_existing from public.member_promo_redemptions where online_order_id = p_online_order_id limit 1;
  end if;
  if v_existing is not null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_redeemed', 'redemption_id', v_existing);
  end if;

  select * into v_row
  from public.member_promos
  where tenant_id = v_tenant
    and upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and (
      (v_ch = 'pos' and coalesce(show_on_pos, true) = true)
      or (v_ch in ('online', 'member') and coalesce(show_on_member, true) = true)
      or (v_ch = 'any' and (coalesce(show_on_pos, true) = true or coalesce(show_on_member, true) = true))
    )
  order by sort_order nulls last, created_at desc
  limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Voucher tidak ditemukan / tidak aktif');
  end if;
  if v_row.valid_until is not null and v_row.valid_until < current_date then
    return jsonb_build_object('ok', false, 'error', 'Voucher kedaluwarsa');
  end if;
  if lower(trim(coalesce(v_row.discount_type, 'nominal'))) = 'info' then
    return jsonb_build_object('ok', false, 'error', 'Voucher info tidak bisa di-redeem');
  end if;
  v_points := greatest(0, coalesce(v_row.points_cost, 0));
  if v_phone = '' then
    if p_sale_id is not null then
      v_phone := coalesce(v_sale.no_wa, '');
    else
      v_phone := coalesce(v_online.phone_e164, '');
    end if;
  end if;
  v_member_id := public.lookup_member_id_in_tenant(v_phone, v_tenant);

  if v_points > 0 then
    if v_member_id is null then
      return jsonb_build_object('ok', false, 'error',
        'Voucher butuh ' || v_points || ' poin — nomor WA harus terdaftar member');
    end if;
    select coalesce(sum(delta), 0)::int into v_balance
    from public.member_points_ledger where member_id = v_member_id;
    if v_balance < v_points then
      return jsonb_build_object('ok', false, 'error',
        'Poin member tidak cukup (saldo ' || v_balance || ', butuh ' || v_points || ')');
    end if;
  end if;
  if v_row.quantity_remaining is not null then
    update public.member_promos
    set quantity_remaining = quantity_remaining - 1
    where id = v_row.id and quantity_remaining is not null and quantity_remaining > 0;
    get diagnostics v_updated = row_count;
    if v_updated = 0 then
      return jsonb_build_object('ok', false, 'error', 'Kuota voucher habis');
    end if;
  end if;
  if v_points > 0 and v_member_id is not null then
    insert into public.member_points_ledger (member_id, delta, reason, sale_id, meta)
    values (
      v_member_id, -v_points, 'voucher_redeem', p_sale_id,
      jsonb_build_object(
        'voucher_code', v_code, 'promo_id', v_row.id, 'ref', v_ref_label,
        'channel', v_ch, 'online_order_id', p_online_order_id,
        'discount_applied', v_disc, 'tenant_id', v_tenant
      )
    );
  end if;
  insert into public.member_promo_redemptions (
    promo_id, sale_id, online_order_id, voucher_code,
    discount_applied, points_spent, member_id, channel
  ) values (
    v_row.id, p_sale_id, p_online_order_id, v_code,
    v_disc, v_points, v_member_id, v_ch
  );
  if p_sale_id is not null then
    update public.sales
    set voucher_code = v_code,
        voucher_discount = case
          when coalesce(voucher_discount, 0) > 0 then voucher_discount
          else v_disc
        end
    where id = p_sale_id and tenant_id = v_tenant;
  end if;
  return jsonb_build_object(
    'ok', true, 'promo_id', v_row.id, 'voucher_code', v_code,
    'points_spent', v_points, 'member_id', v_member_id, 'channel', v_ch,
    'quantity_remaining', (select quantity_remaining from public.member_promos where id = v_row.id)
  );
exception
  when unique_violation then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_redeemed_race');
end;
$$;

-- 12) RLS tabel anak tanpa tenant_id (using true = bocor).
drop policy if exists sales_karyawan_terlibat_auth_all on public.sales_karyawan_terlibat;
create policy sales_karyawan_terlibat_tenant on public.sales_karyawan_terlibat
  for all to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = sale_id and s.tenant_id = public.current_tenant_id()
    )
  )
  with check (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = sale_id and s.tenant_id = public.current_tenant_id()
    )
  );

drop policy if exists poin_logs_auth_all on public.poin_logs;
create policy poin_logs_tenant on public.poin_logs
  for all to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id and k.tenant_id = public.current_tenant_id()
    )
  )
  with check (
    public.is_platform_user()
    or exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id and k.tenant_id = public.current_tenant_id()
    )
  );

drop policy if exists sop_completions_auth_all on public.sop_completions;
create policy sop_completions_tenant on public.sop_completions
  for all to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id and k.tenant_id = public.current_tenant_id()
    )
  )
  with check (
    public.is_platform_user()
    or exists (
      select 1 from public.karyawan k
      where k.id = karyawan_id and k.tenant_id = public.current_tenant_id()
    )
  );

alter table public.sop_templates
  add column if not exists tenant_id uuid references public.tenants (id);
update public.sop_templates
set tenant_id = public.default_tenant_id()
where tenant_id is null;
drop policy if exists sop_templates_auth_all on public.sop_templates;
create policy sop_templates_tenant on public.sop_templates
  for all to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

drop policy if exists member_points_anon_all on public.member_points_ledger;
create policy member_points_ledger_tenant on public.member_points_ledger
  for all to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.members m
      where m.id = member_id and m.tenant_id = public.current_tenant_id()
    )
  )
  with check (
    public.is_platform_user()
    or exists (
      select 1 from public.members m
      where m.id = member_id and m.tenant_id = public.current_tenant_id()
    )
  );

drop policy if exists member_promo_redemptions_read on public.member_promo_redemptions;
create policy member_promo_redemptions_tenant on public.member_promo_redemptions
  for all to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = sale_id and s.tenant_id = public.current_tenant_id()
    )
    or exists (
      select 1 from public.member_promos p
      where p.id = promo_id and p.tenant_id = public.current_tenant_id()
    )
  )
  with check (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = sale_id and s.tenant_id = public.current_tenant_id()
    )
    or exists (
      select 1 from public.member_promos p
      where p.id = promo_id and p.tenant_id = public.current_tenant_id()
    )
  );

-- 13) Unique GL per tenant (periode + jurnal ref).
alter table public.fiscal_periods
  add column if not exists tenant_id uuid references public.tenants (id);
update public.fiscal_periods
set tenant_id = public.default_tenant_id()
where tenant_id is null;
alter table public.fiscal_periods drop constraint if exists fiscal_periods_tahun_bulan_key;
drop index if exists public.fiscal_periods_tahun_bulan_key;
create unique index if not exists fiscal_periods_tenant_ym_uidx
  on public.fiscal_periods (tenant_id, tahun, bulan);

drop index if exists public.journal_entries_sumber_ref_uidx;
create unique index if not exists journal_entries_tenant_sumber_ref_uidx
  on public.journal_entries (tenant_id, sumber, referensi_id)
  where referensi_id is not null
    and btrim(referensi_id) <> ''
    and status = 'POSTED';

drop policy if exists fiscal_periods_auth_all on public.fiscal_periods;
drop policy if exists fiscal_periods_select on public.fiscal_periods;
create policy fiscal_periods_tenant on public.fiscal_periods
  for all to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_user())
  with check (tenant_id = public.current_tenant_id() or public.is_platform_user());

-- 14) Anon tidak boleh daftar karyawan ke toko merek lain tanpa tenant cocok
-- (policy 000003 sudah cek toko; pastikan tenant_id baris = toko.tenant_id).
drop policy if exists karyawan_anon_insert_toko on public.karyawan;
create policy karyawan_anon_insert_toko on public.karyawan
  for insert to anon
  with check (
    exists (
      select 1 from public.toko_id t
      where upper(trim(t.id)) = upper(trim(karyawan.toko_id))
        and t.tenant_id = karyawan.tenant_id
    )
  );

grant execute on function public.lookup_member_id_in_tenant(text, uuid)
  to anon, authenticated, service_role;
grant execute on function public.sync_catalog_metadata_from_pusat(text, uuid)
  to authenticated, service_role;

comment on function public.require_member_tenant(uuid) is
  'Fail-closed. Argumen tenant wajib. Null tidak jatuh ke Optik.';
