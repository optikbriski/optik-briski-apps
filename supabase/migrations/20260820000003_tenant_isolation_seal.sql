-- =============================================================================
-- SEAL tenant isolation. Policy lama using(true) OR-bypass sekat 000002.
-- RPC Member security definer harus filter tenant_id (bukan HP global).
-- =============================================================================

create or replace function public.require_member_tenant(p uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p is null then
    return public.default_tenant_id();
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

grant execute on function public.require_member_tenant(uuid)
  to anon, authenticated, service_role;

-- Toko menentukan tenant. Jangan percaya tenant_id dari client.
create or replace function public.trg_set_tenant_from_toko()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v uuid;
  v_toko text;
begin
  v_toko := nullif(upper(trim(coalesce(new.toko_id::text, ''))), '');
  if v_toko is not null then
    select tenant_id into v from public.toko_id where upper(trim(id)) = v_toko;
    if v is null then
      raise exception 'toko_id % tidak dikenal', v_toko;
    end if;
    new.tenant_id := v;
    return new;
  end if;
  new.tenant_id := coalesce(new.tenant_id, public.current_tenant_id());
  if new.tenant_id is null then
    raise exception 'tenant_id wajib';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 1. Buang policy permissive (using true / auth_all) di tabel ber-tenant_id
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select p.schemaname, p.tablename, p.policyname
    from pg_policies p
    join information_schema.columns c
      on c.table_schema = p.schemaname
     and c.table_name = p.tablename
     and c.column_name = 'tenant_id'
    where p.schemaname = 'public'
      and (
        p.qual = 'true'
        or p.with_check = 'true'
        or p.policyname like '%\_auth_all' escape '\'
        or p.policyname like '%\_authenticated_all' escape '\'
        or p.policyname like '%\_anon_all' escape '\'
      )
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end
$$;

drop policy if exists toko_id_anon_select on public.toko_id;
drop policy if exists toko_id_auth_select on public.toko_id;
drop policy if exists toko_id_auth_insert on public.toko_id;
drop policy if exists toko_id_auth_update on public.toko_id;
drop policy if exists profiles_auth_select on public.profiles;
drop policy if exists profiles_auth_insert on public.profiles;
drop policy if exists profiles_auth_update on public.profiles;
drop policy if exists profiles_self_or_tenant on public.profiles;
drop policy if exists profiles_self_update on public.profiles;
drop policy if exists karyawan_anon_select on public.karyawan;
drop policy if exists karyawan_anon_insert on public.karyawan;

-- profiles: diri sendiri, atau staf tenant yang sama, atau Rekasa
create policy profiles_tenant_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and (
        public.current_profile_role() in ('admin_pusat', 'admin_toko', 'super_admin', 'owner', 'platform')
        or public.is_owner_provisioner()
      )
    )
  );

create policy profiles_tenant_update on public.profiles
  for update to authenticated
  using (
    id = auth.uid()
    or public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and (
        public.current_profile_role() in ('admin_pusat', 'super_admin', 'platform')
        or public.is_owner_provisioner()
      )
    )
  )
  with check (
    id = auth.uid()
    or public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and (
        public.current_profile_role() in ('admin_pusat', 'super_admin', 'platform')
        or public.is_owner_provisioner()
      )
    )
  );

-- Anon register karyawan: hanya insert ke toko tenant yang dipilih (lewat toko_id).
create policy karyawan_anon_insert_toko on public.karyawan
  for insert to anon
  with check (
    toko_id is not null
    and exists (
      select 1 from public.toko_id t
      where upper(trim(t.id)) = upper(trim(karyawan.toko_id))
        and t.tenant_id = coalesce(karyawan.tenant_id, t.tenant_id)
    )
  );

-- Sekat authenticated di setiap tabel yang sudah punya tenant_id
do $$
declare
  r record;
begin
  for r in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'tenant_id'
      and c.table_name not in ('tenants')
  loop
    execute format('drop policy if exists %I on public.%I', r.table_name || '_tenant_seal', r.table_name);
    execute format(
      'create policy %I on public.%I for all to authenticated
       using (tenant_id = public.current_tenant_id() or public.is_platform_user())
       with check (tenant_id = public.current_tenant_id() or public.is_platform_user())',
      r.table_name || '_tenant_seal',
      r.table_name
    );
  end loop;
end
$$;

-- sales_items: ikut sales.tenant_id (policy lama OR-bypass)
alter table public.sales_items enable row level security;
drop policy if exists sales_items_auth_all on public.sales_items;
drop policy if exists sales_items_authenticated_all on public.sales_items;
drop policy if exists sales_items_select on public.sales_items;
drop policy if exists sales_items_insert on public.sales_items;
drop policy if exists sales_items_update on public.sales_items;
drop policy if exists sales_items_delete on public.sales_items;
drop policy if exists sales_items_tenant_seal on public.sales_items;
create policy sales_items_tenant_seal on public.sales_items
  for all to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = sales_items.sale_id
        and s.tenant_id = public.current_tenant_id()
        and (
          not public.is_owner_role()
          or public.is_owner_provisioner()
          or public.owner_can_access_toko(s.toko_id)
        )
    )
  )
  with check (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = sales_items.sale_id
        and s.tenant_id = public.current_tenant_id()
        and (
          not public.is_owner_role()
          or public.is_owner_provisioner()
        )
    )
  );

-- member_family: tidak punya tenant_id
alter table public.member_family enable row level security;
drop policy if exists member_family_anon_all on public.member_family;
drop policy if exists member_family_tenant_seal on public.member_family;
create policy member_family_tenant_seal on public.member_family
  for all to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.members m
      where m.id = member_family.member_id
        and m.tenant_id = public.current_tenant_id()
    )
  )
  with check (
    public.is_platform_user()
    or exists (
      select 1 from public.members m
      where m.id = member_family.member_id
        and m.tenant_id = public.current_tenant_id()
    )
  );

-- finance_transactions: AND tenant ke policy owner (jangan OR using-true)
drop policy if exists finance_transactions_select on public.finance_transactions;
drop policy if exists finance_transactions_insert on public.finance_transactions;
drop policy if exists finance_transactions_update on public.finance_transactions;
drop policy if exists finance_transactions_delete on public.finance_transactions;

create policy finance_transactions_select on public.finance_transactions
  for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (
      not public.is_owner_role()
      or public.is_owner_provisioner()
      or public.owner_can_access_toko(toko_id)
    )
  );

create policy finance_transactions_insert on public.finance_transactions
  for insert to authenticated
  with check (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (not public.is_owner_role() or public.is_owner_provisioner())
  );

create policy finance_transactions_update on public.finance_transactions
  for update to authenticated
  using (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (not public.is_owner_role() or public.is_owner_provisioner())
  )
  with check (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (not public.is_owner_role() or public.is_owner_provisioner())
  );

create policy finance_transactions_delete on public.finance_transactions
  for delete to authenticated
  using (
    (tenant_id = public.current_tenant_id() or public.is_platform_user())
    and (not public.is_owner_role() or public.is_owner_provisioner())
  );

-- -----------------------------------------------------------------------------
-- 2. member_order_alerts + tenant
-- -----------------------------------------------------------------------------
alter table public.member_order_alerts
  add column if not exists tenant_id uuid references public.tenants (id);

update public.member_order_alerts a
set tenant_id = s.tenant_id
from public.sales s
where a.tenant_id is null
  and nullif(trim(a.no_invoice), '') is not null
  and s.no_invoice = a.no_invoice;

update public.member_order_alerts
set tenant_id = public.default_tenant_id()
where tenant_id is null;

-- -----------------------------------------------------------------------------
-- 3. RPC Member: filter tenant (default Optik = APK lama)
-- -----------------------------------------------------------------------------
drop function if exists public.list_member_garansi(text);
create function public.list_member_garansi(
  p_phone text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_today date := (timezone('Asia/Jakarta', now()))::date;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null then return '[]'::jsonb; end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;

  update public.garansi_kartu g
     set status = 'habis'
   where g.tenant_id = v_tenant
     and coalesce(g.klaim_digunakan, false) = false
     and g.status = 'aktif'
     and (
       public.wa_digits(g.no_wa) = v_phone
       or regexp_replace(coalesce(g.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
     )
     and (
       coalesce(
         g.tanggal_akhir,
         coalesce(
           (timezone('Asia/Jakarta', g.diambil_at))::date,
           g.tanggal_mulai
         ) + 7
       ) < v_today
     );

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.tanggal_akhir desc nulls last)
    from (
      select g.*
      from public.garansi_kartu g
      where g.tenant_id = v_tenant
        and (
          public.wa_digits(g.no_wa) = v_phone
          or regexp_replace(coalesce(g.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
        )
      order by g.tanggal_akhir desc nulls last
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_member_garansi(text, uuid) to anon, authenticated;

drop function if exists public.list_member_ratings(text);
create function public.list_member_ratings(
  p_phone text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
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
  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.diambil_at desc nulls last, x.created_at desc)
    from (
      select
        s.id as sale_id,
        s.no_invoice,
        s.toko_id,
        s.nama_pelanggan,
        s.nama_kasir,
        s.nama_pembuat_kacamata,
        s.kasir_karyawan_id,
        s.pembuat_kacamata_id,
        s.tracking_status,
        s.diambil_at,
        s.created_at,
        (
          s.diambil_at is not null
          or upper(trim(coalesce(s.tracking_status, ''))) = 'DIAMBIL'
        ) as bisa_rating,
        (
          select jsonb_build_object(
            'peran', r.peran, 'skor', r.skor, 'komentar', r.komentar,
            'nama_karyawan', r.nama_karyawan, 'created_at', r.created_at
          )
          from public.invoice_rating r
          where r.sale_id = s.id and r.peran = 'kasir'
          limit 1
        ) as rating_kasir,
        (
          select jsonb_build_object(
            'peran', r.peran, 'skor', r.skor, 'komentar', r.komentar,
            'nama_karyawan', r.nama_karyawan, 'created_at', r.created_at
          )
          from public.invoice_rating r
          where r.sale_id = s.id and r.peran = 'pembuat'
          limit 1
        ) as rating_pembuat,
        exists (
          select 1 from public.invoice_rating r
          where r.sale_id = s.id and r.peran = 'kasir'
        ) as has_rating_kasir,
        exists (
          select 1 from public.invoice_rating r
          where r.sale_id = s.id and r.peran = 'pembuat'
        ) as has_rating_pembuat,
        (
          coalesce(nullif(trim(s.nama_kasir), ''), '') <> ''
          or s.kasir_karyawan_id is not null
        ) as kasir_assigned,
        (
          coalesce(nullif(trim(s.nama_pembuat_kacamata), ''), '') <> ''
          or s.pembuat_kacamata_id is not null
        ) as pembuat_assigned
      from public.sales s
      where s.tenant_id = v_tenant
        and (
          public.wa_digits(s.no_wa) = v_phone
          or regexp_replace(coalesce(s.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
        )
      order by s.diambil_at desc nulls last, s.created_at desc
      limit 80
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_member_ratings(text, uuid) to anon, authenticated;

drop function if exists public.list_member_resep(text);
create function public.list_member_resep(
  p_phone text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
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
  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc, x.nama_produk)
    from (
      select
        si.id as item_id,
        s.id as sale_id,
        s.no_invoice,
        s.toko_id,
        s.created_at,
        s.foto_hasil_url,
        si.nama_produk,
        si.tipe_produk,
        si.qty,
        si.detail_resep
      from public.sales s
      join public.sales_items si on si.sale_id = s.id
      where s.tenant_id = v_tenant
        and (
          public.wa_digits(s.no_wa) = v_phone
          or regexp_replace(coalesce(s.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
        )
        and nullif(trim(coalesce(si.detail_resep, '')), '') is not null
        and lower(trim(si.detail_resep)) <> 'normal'
      order by s.created_at desc, si.nama_produk
      limit 120
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_member_resep(text, uuid) to anon, authenticated;

drop function if exists public.list_member_claim_requests(text);
create function public.list_member_claim_requests(
  p_phone text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select r.*
      from public.garansi_klaim_request r
      where public.wa_digits(r.phone_e164) = v_phone
        and (
          r.tenant_id = v_tenant
          or exists (
            select 1 from public.garansi_kartu g
            where g.id = r.kartu_id and g.tenant_id = v_tenant
          )
          or exists (
            select 1 from public.toko_id t
            where upper(trim(t.id)) = upper(trim(r.toko_id))
              and t.tenant_id = v_tenant
          )
        )
      order by r.created_at desc
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_member_claim_requests(text, uuid)
  to anon, authenticated;

drop function if exists public.list_member_online_orders(text);
create function public.list_member_online_orders(
  p_phone text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
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
  begin
    perform public.expire_all_stale_stock_holds();
  exception when undefined_function then
    begin
      perform public.expire_stale_online_orders();
    exception when undefined_function then
      null;
    end;
  end;

  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;
  v_alt := case
    when v_phone like '62%' then '0' || substr(v_phone, 3)
    when v_phone like '0%' then '62' || substr(v_phone, 2)
    else v_phone
  end;

  return coalesce((
    select jsonb_agg(to_jsonb(o) order by o.created_at desc)
    from (
      select *
      from public.online_orders
      where tenant_id = v_tenant
        and (
          phone_e164 = v_phone
          or phone_e164 = v_alt
          or public.wa_digits(phone_e164) = v_phone
        )
      order by created_at desc
      limit 40
    ) o
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_member_online_orders(text, uuid)
  to anon, authenticated;

drop function if exists public.list_member_order_alerts(text);
drop function if exists public.list_member_order_alerts(text, timestamptz);
create function public.list_member_order_alerts(
  p_phone text,
  p_after timestamptz default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text;
  v_alt text;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  v_digits := public.wa_digits(p_phone);
  if v_digits is null or length(v_digits) < 8 then
    return '[]'::jsonb;
  end if;
  v_alt := case
    when v_digits like '62%' then '0' || substr(v_digits, 3)
    when v_digits like '0%' and length(v_digits) >= 9
      then '62' || substr(v_digits, 2)
    else v_digits
  end;

  return coalesce((
    select jsonb_agg(x.obj order by x.created_at desc)
    from (
      select jsonb_build_object(
        'id', a.id,
        'no_invoice', a.no_invoice,
        'online_order_id', a.online_order_id,
        'title', a.title,
        'body', a.body,
        'kind', a.kind,
        'created_at', a.created_at
      ) as obj,
      a.created_at
      from public.member_order_alerts a
      where a.tenant_id = v_tenant
        and a.phone_digits in (v_digits, v_alt)
        and (p_after is null or a.created_at > p_after)
      order by a.created_at desc
      limit 40
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_member_order_alerts(text, timestamptz, uuid)
  to anon, authenticated, service_role;

drop function if exists public.list_online_selling_stores();
create function public.list_online_selling_stores(
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
  v_pusat text := public.tenant_pusat_toko_id(v_tenant);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.label)
    from (
      select
        t.id as toko_id,
        coalesce(nullif(trim(t.toko_id), ''), t.id) as label,
        t.latitude,
        t.longitude,
        coalesce(s.online_selling_enabled, true) as online_selling_enabled,
        coalesce(s.pickup_enabled, true) as pickup_enabled,
        coalesce(s.online_selling_enabled, true) as delivery_enabled,
        coalesce(s.fee_grab, 15000) as fee_grab,
        coalesce(s.fee_gojek, 15000) as fee_gojek,
        coalesce(s.fee_other, 20000) as fee_other,
        coalesce(s.obr_instant_enabled, true) as obr_instant_enabled,
        coalesce(s.obr_sameday_enabled, true) as obr_sameday_enabled,
        coalesce(s.obr_nextday_enabled, true) as obr_nextday_enabled
      from public.toko_id t
      left join public.toko_delivery_settings s on s.toko_id = t.id
      where t.tenant_id = v_tenant
        and coalesce(t.is_pusat, false) = false
        and upper(trim(t.id)) not in ('PUSAT', 'CABANG-PUSAT')
        and upper(trim(t.id)) is distinct from upper(trim(coalesce(v_pusat, '')))
        and coalesce(s.online_selling_enabled, true) = true
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_online_selling_stores(uuid)
  to anon, authenticated;

-- Finalize register: jangan jatuh ke Optik jika tenant dikirim
drop function if exists public.member_finalize_register(text);
create function public.member_finalize_register(
  p_phone text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_pend public.member_register_pending%rowtype;
  v_member public.members%rowtype;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null then
    return jsonb_build_object('ok', false, 'error', 'Nomor tidak valid');
  end if;

  select * into v_pend
  from public.member_register_pending
  where phone_e164 = v_phone
    and coalesce(tenant_id, public.default_tenant_id()) = v_tenant;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Data daftar tidak ditemukan');
  end if;
  if not coalesce(v_pend.wa_verified, false) then
    return jsonb_build_object('ok', false, 'error', 'Verifikasi WhatsApp dulu');
  end if;
  if not coalesce(v_pend.email_verified, false) then
    return jsonb_build_object('ok', false, 'error', 'Verifikasi email dulu');
  end if;
  if nullif(trim(coalesce(v_pend.nama, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Isi nama lengkap dulu');
  end if;
  if v_pend.email is null then
    return jsonb_build_object('ok', false, 'error', 'Isi email dulu');
  end if;
  if v_pend.tanggal_lahir is null then
    return jsonb_build_object('ok', false, 'error', 'Pilih tanggal lahir dulu');
  end if;
  if v_pend.password_hash is null then
    return jsonb_build_object('ok', false, 'error', 'Isi password dulu');
  end if;
  if exists (
    select 1 from public.members m
    where m.tenant_id = v_tenant and m.phone_e164 = v_phone
  ) then
    delete from public.member_register_pending
    where phone_e164 = v_phone and coalesce(tenant_id, public.default_tenant_id()) = v_tenant;
    return jsonb_build_object('ok', false, 'error', 'Nomor sudah terdaftar. Silakan masuk.');
  end if;

  insert into public.members (
    tenant_id, phone_e164, phone_raw, nama, email, tanggal_lahir, password_hash
  ) values (
    v_tenant, v_pend.phone_e164, v_pend.phone_raw, v_pend.nama, v_pend.email,
    v_pend.tanggal_lahir, v_pend.password_hash
  )
  returning * into v_member;

  delete from public.member_register_pending
  where phone_e164 = v_phone and coalesce(tenant_id, public.default_tenant_id()) = v_tenant;

  return jsonb_build_object(
    'ok', true,
    'member', public.member_public_row(v_member),
    'message', 'Akun siap. Silakan masuk.'
  );
end;
$$;
grant execute on function public.member_finalize_register(text, uuid)
  to anon, authenticated;

-- Password reset: hanya akun di tenant itu
drop function if exists public.member_request_password_reset(text);
create function public.member_request_password_reset(
  p_identifier text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id text := trim(coalesce(p_identifier, ''));
  v_phone text;
  v_key text;
  v_member public.members%rowtype;
  v_code text := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_id = '' then
    return jsonb_build_object('ok', false, 'error', 'Isi email atau nomor HP');
  end if;

  if position('@' in v_id) > 0 then
    select * into v_member from public.members m
    where m.tenant_id = v_tenant and lower(trim(m.email)) = lower(v_id)
    limit 1;
    v_key := v_tenant::text || ':email:' || lower(v_id);
  else
    v_phone := public.wa_digits(v_id);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
    end if;
    select * into v_member from public.members m
    where m.tenant_id = v_tenant and m.phone_e164 = v_phone
    limit 1;
    v_key := v_tenant::text || ':phone:' || v_phone;
  end if;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun tidak ditemukan');
  end if;

  insert into public.member_password_resets(identifier, code_hash, expires_at, attempts, tenant_id)
  values (v_key, crypt(v_code, gen_salt('bf')), now() + interval '15 minutes', 0, v_tenant)
  on conflict (identifier) do update
  set code_hash = excluded.code_hash,
      expires_at = excluded.expires_at,
      attempts = 0,
      created_at = now(),
      tenant_id = excluded.tenant_id;

  return jsonb_build_object(
    'ok', true,
    'message', 'Kode reset dibuat.',
    'debug_code', v_code
  );
end;
$$;
grant execute on function public.member_request_password_reset(text, uuid)
  to anon, authenticated;

comment on function public.require_member_tenant(uuid) is
  'RPC Member wajib tenant aktif. Jangan fallback diam-diam ke Optik untuk slug asing.';

-- =============================================================================
-- 4+. Seal lanjutan: RLS OR-bypass, kunci OTP, RPC Member sisa.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 4. Policy authenticated tanpa tenant_id = OR-bypass. Buang.
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select p.tablename, p.policyname
    from pg_policies p
    join information_schema.columns c
      on c.table_schema = p.schemaname
     and c.table_name = p.tablename
     and c.column_name = 'tenant_id'
    where p.schemaname = 'public'
      and p.tablename not in ('tenants')
      and coalesce(p.qual, '') not like '%current_tenant_id%'
      and coalesce(p.qual, '') not like '%is_platform_user%'
      and coalesce(p.with_check, '') not like '%current_tenant_id%'
      and coalesce(p.with_check, '') not like '%is_platform_user%'
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end
$$;

-- Recreate tenant_seal after the sweep
do $$
declare
  r record;
begin
  for r in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'tenant_id'
      and c.table_name not in ('tenants')
  loop
    execute format('drop policy if exists %I on public.%I', r.table_name || '_tenant_seal', r.table_name);
    execute format(
      'create policy %I on public.%I for all to authenticated
       using (tenant_id = public.current_tenant_id() or public.is_platform_user())
       with check (tenant_id = public.current_tenant_id() or public.is_platform_user())',
      r.table_name || '_tenant_seal',
      r.table_name
    );
  end loop;
end
$$;

drop policy if exists karyawan_anon_insert_toko on public.karyawan;
create policy karyawan_anon_insert_toko on public.karyawan
  for insert to anon
  with check (
    toko_id is not null
    and exists (
      select 1 from public.toko_id t
      where upper(trim(t.id)) = upper(trim(karyawan.toko_id))
        and t.tenant_id = coalesce(karyawan.tenant_id, t.tenant_id)
    )
  );

-- invoice_rating / member_survey: tidak selalu punya tenant_id
alter table public.invoice_rating enable row level security;
drop policy if exists invoice_rating_auth_all on public.invoice_rating;
drop policy if exists invoice_rating_tenant_seal on public.invoice_rating;
create policy invoice_rating_tenant_seal on public.invoice_rating
  for all to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = invoice_rating.sale_id
        and s.tenant_id = public.current_tenant_id()
    )
  )
  with check (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = invoice_rating.sale_id
        and s.tenant_id = public.current_tenant_id()
    )
  );

alter table public.member_survey enable row level security;
drop policy if exists member_survey_anon_all on public.member_survey;
drop policy if exists member_survey_tenant_seal on public.member_survey;
create policy member_survey_tenant_seal on public.member_survey
  for all to authenticated
  using (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = member_survey.sale_id
        and s.tenant_id = public.current_tenant_id()
    )
  )
  with check (
    public.is_platform_user()
    or exists (
      select 1 from public.sales s
      where s.id = member_survey.sale_id
        and s.tenant_id = public.current_tenant_id()
    )
  );

-- -----------------------------------------------------------------------------
-- 5. OTP / pending / password-reset: kunci per tenant (bukan HP global)
-- -----------------------------------------------------------------------------
alter table public.member_otp
  add column if not exists tenant_id uuid references public.tenants (id);
update public.member_otp
set tenant_id = public.default_tenant_id()
where tenant_id is null;
alter table public.member_otp
  alter column tenant_id set default public.default_tenant_id();
alter table public.member_otp
  alter column tenant_id set not null;
alter table public.member_otp drop constraint if exists member_otp_pkey;
alter table public.member_otp
  add constraint member_otp_pkey primary key (tenant_id, phone_e164);

alter table public.member_register_pending
  add column if not exists tenant_id uuid references public.tenants (id);
update public.member_register_pending
set tenant_id = public.default_tenant_id()
where tenant_id is null;
alter table public.member_register_pending
  alter column tenant_id set default public.default_tenant_id();
alter table public.member_register_pending
  alter column tenant_id set not null;
alter table public.member_register_pending drop constraint if exists member_register_pending_pkey;
alter table public.member_register_pending
  add constraint member_register_pending_pkey primary key (tenant_id, phone_e164);

create unique index if not exists member_promos_tenant_code_uidx
  on public.member_promos (tenant_id, upper(trim(voucher_code)))
  where nullif(trim(voucher_code), '') is not null;

-- Jangan diam-diam masukkan member UMKM ke Optik
create or replace function public.trg_members_tenant_default()
returns trigger
language plpgsql
as $$
begin
  new.tenant_id := coalesce(new.tenant_id, public.current_tenant_id());
  if new.tenant_id is null then
    raise exception 'tenant_id wajib — registrasi Member tidak boleh jatuh ke tenant lain';
  end if;
  return new;
end;
$$;

create or replace function public.trg_owners_tenant_default()
returns trigger
language plpgsql
as $$
begin
  new.tenant_id := coalesce(new.tenant_id, public.current_tenant_id());
  if new.tenant_id is null then
    raise exception 'tenant_id wajib';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. RPC Member sisa: OTP, daftar, reset, promo, order, rating, klaim
-- -----------------------------------------------------------------------------
drop function if exists public.member_request_otp(text);
create function public.member_request_otp(
  p_phone text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_code text;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null or length(v_phone) < 10 then
    raise exception 'Nomor HP tidak valid';
  end if;
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into public.member_otp(tenant_id, phone_e164, code_hash, expires_at, attempts)
  values (v_tenant, v_phone, crypt(v_code, gen_salt('bf')), now() + interval '10 minutes', 0)
  on conflict (tenant_id, phone_e164) do update
    set code_hash = excluded.code_hash,
        expires_at = excluded.expires_at,
        attempts = 0,
        created_at = now();

  insert into public.members(tenant_id, phone_e164, phone_raw)
  values (v_tenant, v_phone, trim(p_phone))
  on conflict (tenant_id, phone_e164) do update
    set phone_raw = excluded.phone_raw, updated_at = now();

  return jsonb_build_object('ok', true, 'phone_e164', v_phone, 'otp', v_code, 'ttl_seconds', 600);
end;
$$;
grant execute on function public.member_request_otp(text, uuid) to anon, authenticated;

drop function if exists public.member_verify_otp(text, text);
create function public.member_verify_otp(
  p_phone text,
  p_code text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_row public.member_otp%rowtype;
  v_member public.members%rowtype;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null then
    raise exception 'Nomor HP tidak valid';
  end if;
  select * into v_row from public.member_otp
  where phone_e164 = v_phone and tenant_id = v_tenant;
  if not found then
    raise exception 'OTP belum diminta';
  end if;
  if v_row.expires_at < now() then
    raise exception 'OTP kedaluwarsa';
  end if;
  if v_row.attempts >= 5 then
    raise exception 'Terlalu banyak percobaan';
  end if;
  if v_row.code_hash <> crypt(trim(p_code), v_row.code_hash) then
    update public.member_otp set attempts = attempts + 1
    where phone_e164 = v_phone and tenant_id = v_tenant;
    raise exception 'OTP salah';
  end if;
  delete from public.member_otp where phone_e164 = v_phone and tenant_id = v_tenant;
  select * into v_member from public.members
  where phone_e164 = v_phone and tenant_id = v_tenant;
  return jsonb_build_object(
    'ok', true,
    'member', jsonb_build_object(
      'id', v_member.id,
      'tenant_id', v_member.tenant_id,
      'phone_e164', v_member.phone_e164,
      'phone_raw', v_member.phone_raw,
      'nama', v_member.nama,
      'email', v_member.email,
      'alamat', v_member.alamat,
      'font_scale', v_member.font_scale,
      'locale', v_member.locale
    )
  );
end;
$$;
grant execute on function public.member_verify_otp(text, text, uuid) to anon, authenticated;

drop function if exists public.member_save_register_draft(text, text, text, text, date);
create function public.member_save_register_draft(
  p_phone text,
  p_password text default null,
  p_nama text default null,
  p_email text default null,
  p_tanggal_lahir date default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_pass text := coalesce(p_password, '');
  v_existing public.member_register_pending%rowtype;
  v_hash text;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null or length(v_phone) < 10 then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP / WhatsApp tidak valid');
  end if;
  if exists (
    select 1 from public.members m
    where m.tenant_id = v_tenant and m.phone_e164 = v_phone
  ) then
    return jsonb_build_object('ok', false, 'error', 'Nomor HP sudah terdaftar');
  end if;
  if v_email is not null
     and exists (
       select 1 from public.members m
       where m.tenant_id = v_tenant and lower(trim(m.email)) = v_email
     ) then
    return jsonb_build_object('ok', false, 'error', 'Email sudah terdaftar');
  end if;
  if p_tanggal_lahir is not null
     and p_tanggal_lahir > (current_date - interval '10 years') then
    return jsonb_build_object('ok', false, 'error', 'Usia minimal 10 tahun');
  end if;
  if length(v_pass) > 0 and length(v_pass) < 6 then
    return jsonb_build_object('ok', false, 'error', 'Password minimal 6 karakter');
  end if;

  select * into v_existing
  from public.member_register_pending
  where phone_e164 = v_phone and tenant_id = v_tenant;

  v_hash := case
    when length(v_pass) >= 6 then crypt(v_pass, gen_salt('bf'))
    else coalesce(v_existing.password_hash, null)
  end;

  if found then
    update public.member_register_pending set
      phone_raw = trim(p_phone),
      nama = coalesce(nullif(trim(coalesce(p_nama, '')), ''), nama),
      tanggal_lahir = coalesce(p_tanggal_lahir, tanggal_lahir),
      password_hash = coalesce(v_hash, password_hash),
      email = coalesce(v_email, email),
      wa_verified = case
        when phone_raw is not distinct from trim(p_phone) then wa_verified
        else false
      end,
      email_verified = case
        when v_email is null or email is not distinct from v_email then email_verified
        else false
      end,
      created_at = now()
    where phone_e164 = v_phone and tenant_id = v_tenant;
  else
    insert into public.member_register_pending (
      tenant_id, phone_e164, phone_raw, nama, email, tanggal_lahir, password_hash
    ) values (
      v_tenant, v_phone, trim(p_phone),
      nullif(trim(coalesce(p_nama, '')), ''),
      v_email, p_tanggal_lahir, v_hash
    );
  end if;

  select * into v_existing
  from public.member_register_pending
  where phone_e164 = v_phone and tenant_id = v_tenant;

  return jsonb_build_object(
    'ok', true,
    'phone_e164', v_phone,
    'email', v_existing.email,
    'wa_verified', coalesce(v_existing.wa_verified, false),
    'email_verified', coalesce(v_existing.email_verified, false)
  );
end;
$$;
grant execute on function public.member_save_register_draft(text, text, text, text, date, uuid)
  to anon, authenticated, service_role;

drop function if exists public.member_issue_register_otp(text, text);
create function public.member_issue_register_otp(
  p_phone text,
  p_channel text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_ch text := lower(trim(coalesce(p_channel, '')));
  v_code text := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_email text;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null then
    return jsonb_build_object('ok', false, 'error', 'Nomor tidak valid');
  end if;
  if v_ch not in ('wa', 'email') then
    return jsonb_build_object('ok', false, 'error', 'Channel harus wa atau email');
  end if;
  if not exists (
    select 1 from public.member_register_pending
    where phone_e164 = v_phone and tenant_id = v_tenant
  ) then
    return jsonb_build_object('ok', false, 'error', 'Isi nomor WhatsApp dulu');
  end if;

  select email into v_email
  from public.member_register_pending
  where phone_e164 = v_phone and tenant_id = v_tenant;

  if v_ch = 'email' and v_email is null then
    return jsonb_build_object('ok', false, 'error', 'Isi email dulu');
  end if;

  if v_ch = 'wa' then
    update public.member_register_pending set
      wa_code_hash = crypt(v_code, gen_salt('bf')),
      wa_expires_at = now() + interval '15 minutes',
      wa_attempts = 0,
      wa_verified = false
    where phone_e164 = v_phone and tenant_id = v_tenant;
  else
    update public.member_register_pending set
      email_code_hash = crypt(v_code, gen_salt('bf')),
      email_expires_at = now() + interval '15 minutes',
      email_attempts = 0,
      email_verified = false
    where phone_e164 = v_phone and tenant_id = v_tenant;
  end if;

  return jsonb_build_object(
    'ok', true,
    'channel', v_ch,
    'phone_e164', v_phone,
    'email', v_email,
    'otp', v_code,
    'ttl_seconds', 900
  );
end;
$$;
grant execute on function public.member_issue_register_otp(text, text, uuid)
  to anon, authenticated, service_role;

drop function if exists public.member_check_register_otp(text, text, text);
create function public.member_check_register_otp(
  p_phone text,
  p_channel text,
  p_code text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_ch text := lower(trim(coalesce(p_channel, '')));
  v_code text := trim(coalesce(p_code, ''));
  v_row public.member_register_pending%rowtype;
  v_hash text;
  v_exp timestamptz;
  v_att int;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null or v_code = '' then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Data kurang');
  end if;

  select * into v_row
  from public.member_register_pending
  where phone_e164 = v_phone and tenant_id = v_tenant;
  if not found then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Draft tidak ada');
  end if;

  if v_ch = 'wa' then
    v_hash := v_row.wa_code_hash; v_exp := v_row.wa_expires_at; v_att := v_row.wa_attempts;
  elsif v_ch = 'email' then
    v_hash := v_row.email_code_hash; v_exp := v_row.email_expires_at; v_att := v_row.email_attempts;
  else
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Channel invalid');
  end if;

  if v_hash is null then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Belum kirim OTP');
  end if;
  if v_exp is null or v_exp < now() then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'OTP kedaluwarsa');
  end if;
  if v_att >= 8 then
    return jsonb_build_object('ok', false, 'verified', false, 'error', 'Terlalu banyak percobaan');
  end if;

  if crypt(v_code, v_hash) <> v_hash then
    if v_ch = 'wa' then
      update public.member_register_pending set wa_attempts = wa_attempts + 1
      where phone_e164 = v_phone and tenant_id = v_tenant;
    else
      update public.member_register_pending set email_attempts = email_attempts + 1
      where phone_e164 = v_phone and tenant_id = v_tenant;
    end if;
    return jsonb_build_object('ok', true, 'verified', false, 'error', 'Kode salah');
  end if;

  if v_ch = 'wa' then
    update public.member_register_pending set wa_verified = true
    where phone_e164 = v_phone and tenant_id = v_tenant;
  else
    update public.member_register_pending set email_verified = true
    where phone_e164 = v_phone and tenant_id = v_tenant;
  end if;

  return jsonb_build_object('ok', true, 'verified', true, 'channel', v_ch);
end;
$$;
grant execute on function public.member_check_register_otp(text, text, text, uuid)
  to anon, authenticated;

drop function if exists public.member_finalize_register_with_profile(text, text, text, text, date);
create function public.member_finalize_register_with_profile(
  p_phone text,
  p_password text default null,
  p_nama text default null,
  p_email text default null,
  p_tanggal_lahir date default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_draft jsonb;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  v_draft := public.member_save_register_draft(
    p_phone, p_password, p_nama, p_email, p_tanggal_lahir, v_tenant
  );
  if coalesce((v_draft->>'ok')::boolean, false) is not true then
    return v_draft;
  end if;
  return public.member_finalize_register(p_phone, v_tenant);
end;
$$;
grant execute on function public.member_finalize_register_with_profile(text, text, text, text, date, uuid)
  to anon, authenticated;

drop function if exists public.member_reset_password(text, text, text);
create function public.member_reset_password(
  p_identifier text,
  p_code text,
  p_new_password text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id text := trim(coalesce(p_identifier, ''));
  v_code text := trim(coalesce(p_code, ''));
  v_pass text := coalesce(p_new_password, '');
  v_phone text;
  v_key text;
  v_row public.member_password_resets%rowtype;
  v_member public.members%rowtype;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if length(v_pass) < 6 then
    return jsonb_build_object('ok', false, 'error', 'Password baru minimal 6 karakter');
  end if;
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Isi kode reset');
  end if;

  if position('@' in v_id) > 0 then
    v_key := v_tenant::text || ':email:' || lower(v_id);
  else
    v_phone := public.wa_digits(v_id);
    if v_phone is null then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak valid');
    end if;
    v_key := v_tenant::text || ':phone:' || v_phone;
  end if;

  select * into v_row from public.member_password_resets
  where identifier = v_key and coalesce(tenant_id, v_tenant) = v_tenant;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Minta kode reset dulu');
  end if;
  if v_row.expires_at < now() then
    return jsonb_build_object('ok', false, 'error', 'Kode kedaluwarsa. Minta ulang.');
  end if;
  if v_row.attempts >= 5 then
    return jsonb_build_object('ok', false, 'error', 'Terlalu banyak percobaan.');
  end if;
  if crypt(v_code, v_row.code_hash) <> v_row.code_hash then
    update public.member_password_resets set attempts = attempts + 1 where identifier = v_key;
    return jsonb_build_object('ok', false, 'error', 'Kode salah');
  end if;

  if position('@' in v_id) > 0 then
    update public.members
    set password_hash = crypt(v_pass, gen_salt('bf')), updated_at = now()
    where tenant_id = v_tenant and lower(trim(email)) = lower(v_id)
    returning * into v_member;
  else
    update public.members
    set password_hash = crypt(v_pass, gen_salt('bf')), updated_at = now()
    where tenant_id = v_tenant and phone_e164 = public.wa_digits(v_id)
    returning * into v_member;
  end if;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun tidak ditemukan');
  end if;

  delete from public.member_password_resets where identifier = v_key;
  return jsonb_build_object('ok', true, 'member', public.member_public_row(v_member));
end;
$$;
grant execute on function public.member_reset_password(text, text, text, uuid)
  to anon, authenticated;

drop function if exists public.lookup_member_promo(text);
drop function if exists public.lookup_member_promo(text, text);
create function public.lookup_member_promo(
  p_code text,
  p_channel text default 'pos',
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.member_promos%rowtype;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_ch text := lower(trim(coalesce(p_channel, 'pos')));
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
begin
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Kode kosong');
  end if;
  if v_ch not in ('pos', 'online', 'member', 'any') then
    v_ch := 'pos';
  end if;

  select * into v_row
  from public.member_promos
  where tenant_id = v_tenant
    and upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and (
      (v_ch = 'pos' and coalesce(show_on_pos, true) = true)
      or (v_ch in ('online', 'member') and coalesce(show_on_member, true) = true)
      or (
        v_ch = 'any'
        and (coalesce(show_on_pos, true) = true or coalesce(show_on_member, true) = true)
      )
    )
  order by sort_order nulls last, created_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error',
      case
        when v_ch in ('online', 'member')
          then 'Voucher tidak ditemukan / tidak aktif di Member'
        else 'Voucher tidak ditemukan / tidak aktif di POS'
      end
    );
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
    'terms', v_row.terms,
    'channel', v_ch
  );
end;
$$;
grant execute on function public.lookup_member_promo(text, text, uuid)
  to anon, authenticated, service_role;

drop function if exists public.list_member_promos();
drop function if exists public.list_member_promos(boolean);
create function public.list_member_promos(
  p_for_member boolean default true,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p) order by p.sort_order nulls last, p.created_at)
    from public.member_promos p
    where p.tenant_id = v_tenant
      and p.active = true
      and (p_for_member is not true or coalesce(p.show_on_member, true) = true)
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_member_promos(boolean, uuid)
  to anon, authenticated;

drop function if exists public.get_member_home_content();
create function public.get_member_home_content(
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
  v jsonb;
begin
  select to_jsonb(x) into v
  from (
    select brand_label, slides, greeting_guest, greeting_subtitle_guest,
           promo_title, promo_subtitle, sections, feature_flags
    from public.member_home_content
    where tenant_id = v_tenant
    limit 1
  ) x;
  return v;
end;
$$;
grant execute on function public.get_member_home_content(uuid) to anon, authenticated;

drop function if exists public.list_branch_sellable(text, text[]);
create function public.list_branch_sellable(
  p_toko_id text,
  p_skus text[] default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
  v_pusat text;
begin
  if v_toko = '' then
    return '[]'::jsonb;
  end if;
  if not exists (
    select 1 from public.toko_id t
    where upper(trim(t.id)) = v_toko and t.tenant_id = v_tenant
  ) then
    return '[]'::jsonb;
  end if;
  v_pusat := public.tenant_pusat_toko_id(v_tenant);
  if v_pusat is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.sku)
    from (
      select
        pp.sku,
        pp.id as pusat_product_id,
        pb.id as branch_product_id,
        coalesce(nullif(trim(pb.nama), ''), pp.nama) as nama,
        pp.kategori,
        coalesce(pb.harga_jual, pb.harga, pp.harga_jual, pp.harga, 0)::bigint as harga,
        greatest(
          0,
          coalesce(pb.stock, 0) - coalesce(pb.reserved_qty, 0)
        )::int as available_qty,
        coalesce(nullif(trim(pp.image_url), ''), nullif(trim(pp.foto_url), '')) as image_url
      from public.products pp
      left join public.products pb
        on pb.tenant_id = v_tenant
       and upper(trim(pb.toko_id)) = v_toko
       and upper(trim(pb.sku)) = upper(trim(pp.sku))
      where pp.tenant_id = v_tenant
        and upper(trim(pp.toko_id)) = upper(trim(v_pusat))
        and nullif(trim(pp.sku), '') is not null
        and (
          p_skus is null
          or upper(trim(pp.sku)) = any (
            select upper(trim(s)) from unnest(p_skus) s
          )
        )
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_branch_sellable(text, text[], uuid) to anon, authenticated;

drop function if exists public.get_online_order_for_member(text, uuid);
create function public.get_online_order_for_member(
  p_phone text,
  p_online_order_id uuid,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_row public.online_orders%rowtype;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  perform public.expire_all_stale_stock_holds();

  if v_phone is null then
    return jsonb_build_object('ok', false, 'error', 'Nomor tidak valid');
  end if;
  v_alt := case
    when v_phone like '62%' then '0' || substr(v_phone, 3)
    when v_phone like '0%' then '62' || substr(v_phone, 2)
    else v_phone
  end;

  select * into v_row
  from public.online_orders
  where id = p_online_order_id
    and tenant_id = v_tenant
    and (
      phone_e164 = v_phone
      or phone_e164 = v_alt
      or public.wa_digits(phone_e164) = v_phone
    );

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Tidak ditemukan');
  end if;

  return jsonb_build_object('ok', true, 'order', to_jsonb(v_row));
end;
$$;
grant execute on function public.get_online_order_for_member(text, uuid, uuid)
  to anon, authenticated;

drop function if exists public.cancel_pending_online_order_for_member(text, uuid, text);
create function public.cancel_pending_online_order_for_member(
  p_phone text,
  p_online_order_id uuid,
  p_reason text default 'member_cancel',
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_row public.online_orders%rowtype;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null or p_online_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'Argumen tidak valid');
  end if;
  v_alt := case
    when v_phone like '62%' then '0' || substr(v_phone, 3)
    when v_phone like '0%' then '62' || substr(v_phone, 2)
    else v_phone
  end;

  select * into v_row
  from public.online_orders
  where id = p_online_order_id
    and tenant_id = v_tenant
    and (
      phone_e164 = v_phone
      or phone_e164 = v_alt
      or public.wa_digits(phone_e164) = v_phone
    )
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
  end if;

  if v_row.status <> 'pending_payment' then
    return jsonb_build_object(
      'ok', true, 'already', true, 'status', v_row.status
    );
  end if;

  return public.cancel_pending_online_order(
    p_online_order_id,
    coalesce(nullif(trim(p_reason), ''), 'member_cancel')
  );
end;
$$;
grant execute on function public.cancel_pending_online_order_for_member(text, uuid, text, uuid)
  to anon, authenticated;

drop function if exists public.create_member_order_alert(text, text, text, text, text, uuid);
create function public.create_member_order_alert(
  p_no_invoice text,
  p_phone text,
  p_title text,
  p_body text,
  p_kind text default 'status',
  p_online_order_id uuid default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text;
  v_id uuid;
  v_inv text := trim(coalesce(p_no_invoice, ''));
  v_tenant uuid;
begin
  v_tenant := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
  v_digits := public.wa_digits(p_phone);
  if v_digits is null or length(v_digits) < 8 then
    raise exception 'phone tidak valid';
  end if;
  if v_inv = '' and p_online_order_id is null then
    raise exception 'invoice atau online_order_id wajib';
  end if;

  if p_online_order_id is not null
     and (
       v_inv = ''
       or upper(v_inv) = 'ONLINE'
       or v_inv = p_online_order_id::text
     ) then
    v_inv := '';
  end if;

  if v_inv <> '' then
    if not exists (
      select 1 from public.sales s
      where s.no_invoice = v_inv and s.tenant_id = v_tenant
    ) then
      raise exception 'Nota bukan milik usaha ini';
    end if;
  end if;
  if p_online_order_id is not null then
    if not exists (
      select 1 from public.online_orders o
      where o.id = p_online_order_id and o.tenant_id = v_tenant
    ) then
      raise exception 'Pesanan bukan milik usaha ini';
    end if;
  end if;

  insert into public.member_order_alerts (
    tenant_id, no_invoice, phone_digits, title, body, kind, online_order_id
  ) values (
    v_tenant,
    v_inv,
    v_digits,
    coalesce(nullif(trim(p_title), ''), 'Update pesanan'),
    coalesce(nullif(trim(p_body), ''), ''),
    coalesce(nullif(trim(p_kind), ''), 'status'),
    p_online_order_id
  )
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.create_member_order_alert(text, text, text, text, text, uuid, uuid)
  to anon, authenticated, service_role;

drop function if exists public.submit_invoice_rating(text, text, int, text, text);
drop function if exists public.submit_invoice_rating(text, text, int, text);
create function public.submit_invoice_rating(
  p_no_invoice text,
  p_peran text,
  p_skor int,
  p_komentar text default null,
  p_phone text default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_kid uuid;
  v_nama text;
  v_row public.invoice_rating%rowtype;
  v_uid uuid := auth.uid();
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_owner boolean := false;
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
begin
  if v_uid is not null and (
    exists (select 1 from public.profiles p where p.id = v_uid)
    or exists (
      select 1 from public.karyawan k
      where k.id = v_uid and coalesce(k.status_approval, '') = 'Aktif'
    )
  ) then
    raise exception 'Karyawan/admin tidak boleh mengisi rating. Minta pelanggan scan QR dari HP mereka.';
  end if;

  if p_peran not in ('kasir', 'pembuat') then
    raise exception 'Peran tidak valid';
  end if;
  if p_skor is null or p_skor < 1 or p_skor > 5 then
    raise exception 'Skor harus 1–5';
  end if;

  select * into v_sale
  from public.sales
  where no_invoice = trim(p_no_invoice)
    and tenant_id = v_tenant
  limit 1;

  if not found then
    raise exception 'Invoice tidak ditemukan';
  end if;

  if v_phone is not null then
    v_alt := case
      when v_phone like '62%' then '0' || substr(v_phone, 3)
      else v_phone
    end;
    v_owner := (
      public.wa_digits(v_sale.no_wa) = v_phone
      or regexp_replace(coalesce(v_sale.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
    );
    if not v_owner then
      raise exception 'Invoice ini bukan milik nomor HP Anda';
    end if;
  end if;

  if v_sale.diambil_at is null
     and upper(trim(coalesce(v_sale.tracking_status, ''))) <> 'DIAMBIL'
  then
    raise exception 'Rating hanya setelah kacamata diambil customer';
  end if;

  if p_peran = 'kasir' then
    v_kid := v_sale.kasir_karyawan_id;
    v_nama := v_sale.nama_kasir;
  else
    v_kid := v_sale.pembuat_kacamata_id;
    v_nama := v_sale.nama_pembuat_kacamata;
  end if;

  if v_kid is null and (v_nama is null or length(trim(v_nama)) = 0) then
    raise exception 'Karyawan untuk peran ini belum ditetapkan di transaksi';
  end if;

  insert into public.invoice_rating (
    sale_id, no_invoice, peran, karyawan_id, nama_karyawan, skor, komentar
  ) values (
    v_sale.id, v_sale.no_invoice, p_peran, v_kid, v_nama, p_skor,
    nullif(trim(p_komentar), '')
  )
  on conflict (sale_id, peran) do nothing
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Rating untuk peran ini sudah pernah diisi';
  end if;

  return to_jsonb(v_row);
end;
$$;
grant execute on function public.submit_invoice_rating(text, text, int, text, text, uuid)
  to anon, authenticated;

create function public.submit_invoice_rating(
  p_no_invoice text,
  p_peran text,
  p_skor int,
  p_komentar text default null
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.submit_invoice_rating(p_no_invoice, p_peran, p_skor, p_komentar, null, public.default_tenant_id());
$$;
grant execute on function public.submit_invoice_rating(text, text, int, text) to anon, authenticated;

drop function if exists public.submit_member_garansi_klaim(text, uuid, text, text, timestamptz, uuid, uuid, text);

create function public.submit_member_garansi_klaim(
  p_phone text,
  p_kartu_id uuid,
  p_toko_id text,
  p_alasan text,
  p_jadwal_kunjungan timestamptz,
  p_sale_id uuid default null,
  p_member_id uuid default null,
  p_foto_url text default null
,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_kartu public.garansi_kartu%rowtype;
  v_alasan text := trim(coalesce(p_alasan, ''));
  v_toko text := trim(coalesce(p_toko_id, ''));
  v_row public.garansi_klaim_request%rowtype;
  v_today date := (timezone('Asia/Jakarta', now()))::date;
  v_start date;
  v_end date;
  v_tenant uuid;
begin
  v_tenant := public.require_member_tenant(p_tenant_id);

  if v_phone is null or length(v_phone) < 8 then
    raise exception 'Nomor HP tidak valid';
  end if;
  if p_kartu_id is null then
    raise exception 'Kartu garansi wajib dipilih';
  end if;
  if v_toko = '' then
    raise exception 'Cabang kunjungan wajib dipilih';
  end if;
  if not exists (
    select 1 from public.toko_id t
    where upper(trim(t.id)) = upper(trim(v_toko))
      and t.tenant_id = v_tenant
  ) then
    raise exception 'Cabang bukan milik usaha ini';
  end if;
  if v_alasan = '' then
    raise exception 'Alasan / keluhan wajib diisi';
  end if;
  if p_jadwal_kunjungan is null then
    raise exception 'Jadwal kunjungan wajib diisi';
  end if;
  if coalesce(trim(p_foto_url), '') = '' then
    raise exception 'Foto kondisi barang wajib diunggah';
  end if;

  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;

  select * into v_kartu
  from public.garansi_kartu g
  where g.id = p_kartu_id
    and g.tenant_id = v_tenant
  limit 1;
  if not found then
    raise exception 'Kartu garansi tidak ditemukan';
  end if;

  if not (
    public.wa_digits(v_kartu.no_wa) = v_phone
    or regexp_replace(coalesce(v_kartu.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
  ) then
    raise exception 'Kartu garansi tidak milik nomor ini';
  end if;

  if coalesce(v_kartu.status, '') = 'menunggu_ambil' then
    raise exception 'Garansi belum aktif — ambil barang di toko dulu';
  end if;
  if coalesce(v_kartu.klaim_digunakan, false)
     or coalesce(v_kartu.status, '') = 'diklaim' then
    raise exception 'Klaim untuk transaksi ini sudah dipakai (maks. 1×)';
  end if;
  if coalesce(v_kartu.status, '') = 'batal' then
    raise exception 'Garansi dibatalkan — tidak bisa klaim';
  end if;
  if coalesce(v_kartu.status, '') = 'habis' then
    raise exception 'Garansi mati — lebih dari 7 hari sejak diambil';
  end if;
  if coalesce(v_kartu.status, '') <> 'aktif' then
    raise exception 'Garansi tidak aktif — ambil barang di toko dulu atau masa sudah habis';
  end if;

  -- Clock: hari kalender diambil (Jakarta). Window inklusif hari 0..7.
  v_start := coalesce(
    (timezone('Asia/Jakarta', v_kartu.diambil_at))::date,
    v_kartu.tanggal_mulai
  );
  if v_start is null then
    raise exception 'Garansi belum aktif — ambil barang di toko dulu';
  end if;

  v_end := coalesce(v_kartu.tanggal_akhir, v_start + 7);
  if v_end > (v_start + 7) then
    v_end := v_start + 7;
  end if;

  if v_today > v_end then
    update public.garansi_kartu
       set status = 'habis'
     where id = v_kartu.id
       and status = 'aktif'
       and coalesce(klaim_digunakan, false) = false;
    raise exception 'Garansi mati — lebih dari 7 hari sejak diambil';
  end if;

  -- Jadwal kunjungan: tanggal Jakarta tidak boleh lewat akhir window.
  if (timezone('Asia/Jakarta', p_jadwal_kunjungan))::date > v_end then
    raise exception 'Jadwal kunjungan di luar masa garansi (maks. 7 hari sejak diambil)';
  end if;

  if exists (
    select 1
    from public.garansi_klaim_request r
    where r.kartu_id = p_kartu_id
      and r.status in ('diajukan', 'diproses_toko')
  ) then
    raise exception 'Pengajuan untuk kartu ini masih terbuka';
  end if;

  insert into public.garansi_klaim_request (
    phone_e164,
    member_id,
    kartu_id,
    sale_id,
    toko_id,
    alasan,
    foto_url,
    jadwal_kunjungan,
    status
  ) values (
    v_phone,
    p_member_id,
    p_kartu_id,
    coalesce(p_sale_id, v_kartu.sale_id),
    v_toko,
    v_alasan,
    trim(p_foto_url),
    p_jadwal_kunjungan,
    'diajukan'
  )
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

grant execute on function public.submit_member_garansi_klaim(text, uuid, text, text, timestamptz, uuid, uuid, text, uuid)
  to anon, authenticated;

drop function if exists public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision,
  jsonb, bigint, text, text, text, text, boolean, bigint, text, bigint
);
create function public.create_online_order(
  p_phone text,
  p_member_id uuid,
  p_customer_name text,
  p_toko_id text,
  p_fulfillment text,
  p_courier text,
  p_address_text text,
  p_address_lat double precision,
  p_address_lng double precision,
  p_items jsonb,
  p_shipping_fee bigint default null,
  p_courier_company text default null,
  p_courier_service_code text default null,
  p_courier_service_name text default null,
  p_shipping_category text default null,
  p_is_obr boolean default false,
  p_shipping_voucher_discount bigint default 0,
  p_product_promo_code text default null,
  p_product_promo_discount bigint default 0
,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_fulfill text := lower(trim(coalesce(p_fulfillment, '')));
  v_courier text := nullif(lower(trim(coalesce(p_courier, ''))), '');
  v_phone text := coalesce(
    public.wa_digits(p_phone),
    nullif(trim(coalesce(p_phone, '')), '')
  );
  v_settings public.toko_delivery_settings%rowtype;
  v_item jsonb;
  v_sku text;
  v_qty int;
  v_kat text;
  v_sell jsonb;
  v_harga bigint;
  v_avail int;
  v_nama text;
  v_branch_pid uuid;
  v_pusat_pid uuid;
  v_stock_qty int;
  v_preorder_qty int;
  v_subtotal bigint := 0;
  v_ship bigint := 0;
  v_ship_disc bigint := 0;
  v_prod_disc bigint := 0;
  v_prod_disc_server bigint := 0;
  v_total bigint := 0;
  v_lines jsonb := '[]'::jsonb;
  v_id uuid;
  v_mid text;
  v_has_preorder boolean := false;
  v_promo_code text := nullif(upper(trim(coalesce(p_product_promo_code, ''))), '');
  v_promo public.member_promos%rowtype;
  v_dtype text;
  v_dval bigint;
  v_redeem jsonb;
  v_client_disc bigint := greatest(0, coalesce(p_product_promo_discount, 0));
  v_ship_cat text;
  v_origin_lat double precision;
  v_origin_lng double precision;
  v_dist_m double precision;
  v_obr_max_m double precision;
  v_goods bigint;
  v_tenant uuid;
  v_pusat_toko text;
begin
  if v_phone is null or v_phone = '' then
    return jsonb_build_object('ok', false, 'error', 'Login / nomor WA wajib');
  end if;
  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'Pilih cabang');
  end if;
  v_tenant := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
  v_pusat_toko := public.tenant_pusat_toko_id(v_tenant);
  if not exists (
    select 1 from public.toko_id t
    where upper(trim(t.id)) = v_toko
      and t.tenant_id = v_tenant
  ) then
    return jsonb_build_object('ok', false, 'error', 'Cabang bukan milik usaha ini');
  end if;
  if v_fulfill not in ('pickup', 'delivery') then
    return jsonb_build_object('ok', false, 'error', 'Metode ambil tidak valid');
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Keranjang kosong');
  end if;
  -- Alamat wajib hanya untuk pengiriman; pickup cukup pilih cabang.
  if v_fulfill = 'delivery'
     and nullif(trim(coalesce(p_address_text, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Alamat pengiriman wajib diisi');
  end if;

  -- Diskon tanpa kode = ditolak (anti bypass redeem)
  if v_client_disc > 0 and v_promo_code is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Diskon produk wajib pakai kode voucher yang valid'
    );
  end if;

  select * into v_settings from public.toko_delivery_settings where toko_id = v_toko;
  if not found then
    insert into public.toko_delivery_settings (toko_id) values (v_toko)
    returning * into v_settings;
  end if;

  if not coalesce(v_settings.online_selling_enabled, true) then
    return jsonb_build_object('ok', false, 'error', 'Cabang belum aktif jual online');
  end if;
  if v_fulfill = 'pickup' and not coalesce(v_settings.pickup_enabled, true) then
    return jsonb_build_object('ok', false, 'error', 'Cabang tidak menerima ambil di toko');
  end if;
  if v_fulfill = 'delivery' then
    -- Biteship selalu boleh selama toko jual online (abaikan delivery_enabled).
    if v_courier is null or v_courier not in ('grab', 'gojek', 'other', 'obr') then
      return jsonb_build_object('ok', false, 'error', 'Pilih kurir');
    end if;
    -- OBR hanya bila toggle kategori cabang aktif.
    if coalesce(p_is_obr, false) or v_courier = 'obr' then
      v_ship_cat := lower(trim(coalesce(p_shipping_category, '')));
      if v_ship_cat in ('same_day') then v_ship_cat := 'sameday'; end if;
      if v_ship_cat in ('next_day') then v_ship_cat := 'nextday'; end if;
      if v_ship_cat = 'instant' and not coalesce(v_settings.obr_instant_enabled, true) then
        return jsonb_build_object('ok', false, 'error', 'OBR Instant tidak aktif di cabang ini');
      elsif v_ship_cat = 'sameday' and not coalesce(v_settings.obr_sameday_enabled, true) then
        return jsonb_build_object('ok', false, 'error', 'OBR Same Day tidak aktif di cabang ini');
      elsif v_ship_cat = 'nextday' and not coalesce(v_settings.obr_nextday_enabled, true) then
        return jsonb_build_object('ok', false, 'error', 'OBR Next Day tidak aktif di cabang ini');
      elsif v_ship_cat not in ('instant', 'sameday', 'nextday') then
        return jsonb_build_object('ok', false, 'error', 'Kategori OBR tidak valid');
      end if;
    end if;

    -- Ongkir wajib dari quote Member (Biteship/OBR). Jangan terima null.
    if p_shipping_fee is null then
      return jsonb_build_object('ok', false, 'error', 'Ongkir wajib dari pilihan kurir');
    end if;
    if p_shipping_fee < 0 or p_shipping_fee > 500000 then
      return jsonb_build_object('ok', false, 'error', 'Ongkir tidak valid');
    end if;
    v_ship := p_shipping_fee;
  else
    v_courier := null;
    v_ship := 0;
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_qty := greatest(1, coalesce((v_item->>'qty')::int, 1));
    if v_sku = '' then
      return jsonb_build_object('ok', false, 'error', 'Item tanpa SKU');
    end if;

    select
      pp.kategori,
      pp.id,
      coalesce(pp.harga_jual, pp.harga, 0)::bigint,
      coalesce(nullif(trim(pp.nama), ''), v_sku)
    into v_kat, v_pusat_pid, v_harga, v_nama
    from public.products pp
    where pp.tenant_id = v_tenant
      and upper(trim(pp.toko_id)) = upper(trim(coalesce(v_pusat_toko, 'PUSAT')))
      and upper(trim(pp.sku)) = v_sku
    limit 1;

    if v_kat is null then
      return jsonb_build_object('ok', false, 'error', 'Produk tidak ada di katalog: ' || v_sku);
    end if;
    if lower(trim(v_kat)) = 'lensa' then
      return jsonb_build_object(
        'ok', false,
        'error',
        'Lensa custom tidak dijual online. Silakan lewat cabang / booking.'
      );
    end if;

    select elem into v_sell
    from jsonb_array_elements(
      public.list_branch_sellable(v_toko, array[v_sku], v_tenant)
    ) as elem
    limit 1;

    if v_sell is not null then
      v_avail := coalesce((v_sell->>'available_qty')::int, 0);
      v_harga := coalesce((v_sell->>'harga')::bigint, v_harga);
      v_nama := coalesce(nullif(trim(v_sell->>'nama'), ''), v_nama);
      v_branch_pid := nullif(v_sell->>'branch_product_id', '')::uuid;
      v_pusat_pid := coalesce(
        nullif(v_sell->>'pusat_product_id', '')::uuid,
        v_pusat_pid
      );
    else
      v_avail := 0;
      v_branch_pid := null;
    end if;

    if v_harga <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Harga tidak valid: ' || v_nama);
    end if;

    v_stock_qty := least(v_avail, v_qty);
    v_preorder_qty := greatest(0, v_qty - v_stock_qty);
    if v_preorder_qty > 0 then
      v_has_preorder := true;
    end if;

    v_subtotal := v_subtotal + (v_harga * v_qty);
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'sku', v_sku,
      'qty', v_qty,
      'stock_qty', v_stock_qty,
      'preorder_qty', v_preorder_qty,
      'pre_order', v_preorder_qty > 0,
      'harga', v_harga,
      'nama', v_nama,
      'kategori', v_kat,
      'subtotal', v_harga * v_qty,
      'branch_product_id', v_branch_pid,
      'pusat_product_id', v_pusat_pid,
      'image_url', case
        when v_sell is not null then v_sell->>'image_url'
        else null
      end
    ));
  end loop;

  -- Voucher produk: hitung ulang di server (jangan percaya client)
  if v_promo_code is not null then
    select * into v_promo
    from public.member_promos
    where tenant_id = v_tenant
      and upper(trim(coalesce(voucher_code, ''))) = v_promo_code
      and active = true
      and coalesce(show_on_member, true) = true
    order by sort_order nulls last, created_at desc
    limit 1;

    if not found then
      return jsonb_build_object('ok', false, 'error', 'Voucher produk tidak valid untuk Member');
    end if;
    if v_promo.valid_until is not null and v_promo.valid_until < current_date then
      return jsonb_build_object('ok', false, 'error', 'Voucher produk kedaluwarsa');
    end if;
    if v_promo.quantity_remaining is not null and v_promo.quantity_remaining <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Kuota voucher produk habis');
    end if;

    v_dtype := lower(trim(coalesce(v_promo.discount_type, 'nominal')));
    v_dval := greatest(0, coalesce(v_promo.discount_value, 0));

    if v_dtype = 'info' then
      -- Info saja: tidak ada potongan & tidak redeem
      v_promo_code := null;
      v_prod_disc := 0;
    else
      if v_dtype = 'percent' then
        v_prod_disc_server := floor(v_subtotal * least(v_dval, 100) / 100.0)::bigint;
      else
        v_prod_disc_server := v_dval;
      end if;
      if v_prod_disc_server > v_subtotal then
        v_prod_disc_server := v_subtotal;
      end if;
      -- Anti cheat: nilai diskon selalu dari server (abaikan nominal client).
      v_prod_disc := v_prod_disc_server;
    end if;
  else
    v_prod_disc := 0;
  end if;

  if v_fulfill = 'delivery' then
    v_ship_disc := greatest(0, coalesce(p_shipping_voucher_discount, 0));
    if v_ship_disc > 0 then
      if not (coalesce(p_is_obr, false) or v_courier = 'obr') then
        return jsonb_build_object('ok', false, 'error', 'Voucher ongkir hanya untuk OBR Delivery');
      end if;
      v_ship_cat := lower(trim(coalesce(p_shipping_category, '')));
      if v_ship_cat in ('same_day') then v_ship_cat := 'sameday'; end if;
      if v_ship_cat in ('next_day') then v_ship_cat := 'nextday'; end if;
      v_ship_disc := least(
        v_ship_disc,
        v_ship,
        public.obr_shipping_voucher_max(v_subtotal, v_ship_cat)
      );
      if v_ship_disc <= 0 and coalesce(p_shipping_voucher_discount, 0) > 0 then
        return jsonb_build_object(
          'ok', false,
          'error', 'Voucher ongkir tidak berlaku untuk kategori/subtotal ini'
        );
      end if;
    end if;
  else
    v_ship_disc := 0;
  end if;

  -- OBR: jangkauan server-side (≤10 km; ≤15 km bila belanja > 1jt)
  if v_fulfill = 'delivery' and (coalesce(p_is_obr, false) or v_courier = 'obr') then
    if p_address_lat is null or p_address_lng is null then
      return jsonb_build_object('ok', false, 'error', 'Koordinat alamat wajib untuk OBR');
    end if;
    select t.latitude, t.longitude
      into v_origin_lat, v_origin_lng
    from public.toko_id t
    where upper(trim(t.id)) = v_toko
    limit 1;
    if v_origin_lat is null or v_origin_lng is null
       or (v_origin_lat = 0 and v_origin_lng = 0) then
      return jsonb_build_object('ok', false, 'error', 'Koordinat cabang belum ada untuk OBR');
    end if;
    v_dist_m := public.haversine_meters(
      v_origin_lat, v_origin_lng, p_address_lat, p_address_lng
    );
    v_goods := greatest(0, v_subtotal - coalesce(v_prod_disc, 0));
    v_obr_max_m := case when v_goods > 1000000 then 15000.0 else 10000.0 end;
    if v_dist_m is null or v_dist_m > (v_obr_max_m + 0.5) then
      return jsonb_build_object(
        'ok', false,
        'error',
        'OBR di luar jangkauan ('
          || to_char(round((coalesce(v_dist_m, 0) / 1000.0)::numeric, 1), 'FM999990.0')
          || ' km). Pilih kurir Biteship.'
      );
    end if;
  end if;

  v_total := (v_subtotal - v_prod_disc) + (v_ship - v_ship_disc);
  if v_total < 0 then
    v_total := 0;
  end if;

  v_mid := 'OBR-ON-' || to_char(timezone('utc', now()), 'YYYYMMDDHH24MISS')
        || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into public.online_orders (
    member_id, phone_e164, customer_name, toko_id, fulfillment, courier,
    address_text, address_lat, address_lng, shipping_fee, items,
    subtotal, total, status, midtrans_order_id,
    store_note,
    courier_company, courier_service_code, courier_service_name,
    shipping_category, is_obr,
    shipping_voucher_discount, product_promo_code, product_promo_discount,
    expires_at
  ) values (
    p_member_id, v_phone, nullif(trim(coalesce(p_customer_name, '')), ''),
    v_toko, v_fulfill, v_courier,
    nullif(trim(coalesce(p_address_text, '')), ''),
    p_address_lat, p_address_lng, v_ship, v_lines,
    v_subtotal, v_total, 'pending_payment', v_mid,
    case when v_has_preorder
      then 'Ada item pre-order → RO cabang saat lunas'
      else null
    end,
    nullif(trim(coalesce(p_courier_company, '')), ''),
    nullif(trim(coalesce(p_courier_service_code, '')), ''),
    nullif(trim(coalesce(p_courier_service_name, '')), ''),
    nullif(lower(trim(coalesce(p_shipping_category, ''))), ''),
    coalesce(p_is_obr, false),
    v_ship_disc,
    v_promo_code,
    v_prod_disc,
    now() + interval '15 minutes'
  )
  returning id into v_id;

  -- Hold stok (stock_qty) → reserved_qty; Member lain lihat sisa available
  for v_item in select * from jsonb_array_elements(v_lines)
  loop
    v_sku := upper(trim(coalesce(v_item->>'sku', '')));
    v_stock_qty := greatest(0, coalesce((v_item->>'stock_qty')::int, 0));
    if v_sku = '' or v_stock_qty <= 0 then
      continue;
    end if;
    begin
      perform public.reserve_stock(
        v_toko,
        v_sku,
        v_stock_qty,
        'ONLINE_HOLD',
        'online_order',
        v_id::text,
        jsonb_build_object(
          'midtrans_order_id', v_mid,
          'channel', 'member_online',
          'hold_minutes', 15
        )
      );
    exception when others then
      raise exception 'Gagal hold stok % ×%: %', v_sku, v_stock_qty, SQLERRM;
    end;
  end loop;

  -- Redeem wajib bila ada kode produk (bukan info)
  if v_promo_code is not null then
    v_redeem := public.redeem_member_promo(
      v_promo_code,
      null,                 -- sale_id
      v_phone,
      v_prod_disc,
      v_id,                 -- online_order_id
      'online'
    );
    if coalesce((v_redeem->>'ok')::boolean, false) is not true then
      raise exception '%', coalesce(v_redeem->>'error', 'Redeem voucher online gagal');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'online_order_id', v_id,
    'midtrans_order_id', v_mid,
    'subtotal', v_subtotal,
    'shipping_fee', v_ship,
    'shipping_voucher_discount', v_ship_disc,
    'product_promo_code', v_promo_code,
    'product_promo_discount', v_prod_disc,
    'total', v_total,
    'toko_id', v_toko,
    'items', v_lines,
    'has_preorder', v_has_preorder,
    'expires_at', (select o.expires_at from public.online_orders o where o.id = v_id),
    'hold_minutes', 15
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

grant execute on function public.create_online_order(
  text, uuid, text, text, text, text, text, double precision, double precision,
  jsonb, bigint, text, text, text, text, boolean, bigint, text, bigint, uuid
) to anon, authenticated, service_role;
drop function if exists public.get_invoice_hub(text, text);
drop function if exists public.get_invoice_hub(text);
create function public.get_invoice_hub(
  p_no_invoice text,
  p_phone text default null,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sale public.sales%rowtype;
  v_items jsonb;
  v_garansi jsonb;
  v_ratings jsonb;
  v_is_staff boolean := false;
  v_uid uuid := auth.uid();
  v_claimable boolean := false;
  v_review text;
  v_bisa_rating boolean := false;
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_owner boolean := false;
  v_is_dp boolean := false;
  v_diambil boolean := false;
  v_phase text;
  v_token text;
  v_payload text;
  v_token_col text;
  v_channel text;
  v_tenant uuid;
begin
  if p_no_invoice is null or length(trim(p_no_invoice)) = 0 then
    return null;
  end if;

  if public.is_platform_user() then
    v_tenant := null;
  else
    v_tenant := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
  end if;

  select * into v_sale
  from public.sales
  where no_invoice = trim(p_no_invoice)
    and (v_tenant is null or tenant_id = v_tenant)
  limit 1;
  if not found then return null; end if;

  if v_uid is not null then
    v_is_staff := exists (
      select 1 from public.profiles p where p.id = v_uid
    ) or exists (
      select 1 from public.karyawan k
      where k.id = v_uid and coalesce(k.status_approval, '') = 'Aktif'
    );
  end if;

  if v_phone is not null then
    v_alt := case
      when v_phone like '62%' then '0' || substr(v_phone, 3)
      else v_phone
    end;
    v_owner := (
      public.wa_digits(v_sale.no_wa) = v_phone
      or regexp_replace(coalesce(v_sale.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
    );
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', si.id,
    'nama_produk', si.nama_produk,
    'tipe_produk', si.tipe_produk,
    'qty', si.qty,
    'subtotal', si.subtotal,
    'detail_resep', si.detail_resep,
    'needs_fulfillment', coalesce(si.needs_fulfillment, false),
    'fulfillment_status', coalesce(si.fulfillment_status, 'READY'),
    'diambil_at', si.diambil_at
  ) order by si.nama_produk), '[]'::jsonb)
  into v_items
  from public.sales_items si
  where si.sale_id = v_sale.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', g.id,
    'jenis_garansi', g.jenis_garansi,
    'nama_produk', g.nama_produk,
    'status', g.status,
    'tanggal_mulai', g.tanggal_mulai,
    'tanggal_akhir', g.tanggal_akhir,
    'klaim_digunakan', g.klaim_digunakan,
    'spesifikasi_produk', g.spesifikasi_produk,
    'no_invoice', g.no_invoice,
    'sale_id', g.sale_id,
    'toko_id', g.toko_id
  )), '[]'::jsonb)
  into v_garansi
  from public.garansi_kartu g
  where g.sale_id = v_sale.id;

  select exists (
    select 1 from public.garansi_kartu g
    where g.sale_id = v_sale.id
      and g.status = 'aktif'
      and coalesce(g.klaim_digunakan, false) = false
      and g.tanggal_akhir is not null
      and g.tanggal_akhir::date >= (timezone('Asia/Jakarta', now()))::date
  ) into v_claimable;

  select coalesce(i.google_review_url, p.google_review_url)
  into v_review
  from (select 1) _
  left join public.invoice_settings i on upper(trim(i.toko_id)) = upper(trim(v_sale.toko_id))
  left join public.invoice_settings p on upper(trim(p.toko_id)) = 'PUSAT';

  v_bisa_rating := (
    v_sale.diambil_at is not null
    or upper(trim(coalesce(v_sale.tracking_status, ''))) = 'DIAMBIL'
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'peran', r.peran,
    'skor', r.skor,
    'komentar', r.komentar,
    'created_at', r.created_at
  )), '[]'::jsonb)
  into v_ratings
  from public.invoice_rating r
  where r.sale_id = v_sale.id;

  v_is_dp := (
    upper(trim(coalesce(v_sale.status_pembayaran, ''))) = 'DP'
    or coalesce(v_sale.sisa_tagihan, 0) > 0
  );
  v_diambil := (
    v_sale.diambil_at is not null
    or upper(trim(coalesce(v_sale.tracking_status, ''))) = 'DIAMBIL'
  );
  v_channel := case
    when lower(trim(coalesce(v_sale.channel, ''))) = 'online' then 'ONLINE'
    else 'OFFLINE'
  end;

  if v_is_dp then
    -- QR DP HANYA setelah admin Barang Ready (SIAP_PELUNASAN).
    if v_sale.qr_dp_used_at is null
       and upper(trim(coalesce(v_sale.tracking_status, ''))) = 'SIAP_PELUNASAN'
    then
      v_phase := 'DP';
      v_token := nullif(trim(coalesce(v_sale.qr_dp_token, '')), '');
      v_token_col := 'qr_dp_token';
    else
      v_phase := null;
      v_token := null;
      v_token_col := null;
    end if;
  elsif not v_diambil then
    if upper(trim(coalesce(v_sale.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR') then
      v_phase := 'LUNAS';
      v_token := nullif(trim(coalesce(v_sale.qr_lunas_token, '')), '');
      v_token_col := 'qr_lunas_token';
      if v_sale.qr_lunas_used_at is not null then
        v_phase := null;
        v_token := null;
        v_token_col := null;
      end if;
    else
      -- Lunas PENDING: belum Barang Ready → tanpa QR pengambilan.
      v_phase := null;
      v_token := null;
      v_token_col := null;
    end if;
  else
    v_phase := 'CLAIM';
    v_token := nullif(trim(coalesce(v_sale.qr_claim_token, '')), '');
    v_token_col := 'qr_claim_token';
    if v_sale.qr_claim_used_at is not null then
      v_phase := null;
      v_token := null;
      v_token_col := null;
    end if;
  end if;

  if v_phase is null
     and v_sale.qr_claim_used_at is null
     and length(trim(coalesce(v_sale.qr_claim_token, ''))) >= 8
  then
    v_phase := 'CLAIM';
    v_token := nullif(trim(coalesce(v_sale.qr_claim_token, '')), '');
    v_token_col := 'qr_claim_token';
  end if;

  if (v_owner or v_is_staff)
     and v_phase is not null
     and v_token_col is not null
     and (v_token is null or length(v_token) < 8)
  then
    v_token := encode(extensions.gen_random_bytes(16), 'hex');
    if v_token_col = 'qr_dp_token' then
      update public.sales set qr_dp_token = v_token where id = v_sale.id;
    elsif v_token_col = 'qr_lunas_token' then
      update public.sales set qr_lunas_token = v_token where id = v_sale.id;
    else
      update public.sales set qr_claim_token = v_token where id = v_sale.id;
    end if;
  end if;

  if (v_owner or v_is_staff)
     and v_phase is not null
     and v_token is not null
     and length(v_token) >= 8
  then
    v_payload := 'OBRINV|v1|' || trim(v_sale.no_invoice) || '|' || v_phase
      || '|' || v_token || '|' || v_channel;
  else
    v_payload := null;
    if not (v_owner or v_is_staff) then
      v_phase := case
        when v_is_dp
          and v_sale.qr_dp_used_at is null
          and upper(trim(coalesce(v_sale.tracking_status, ''))) = 'SIAP_PELUNASAN'
          then 'DP'
        when not v_diambil
          and upper(trim(coalesce(v_sale.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR')
          and v_sale.qr_lunas_used_at is null then 'LUNAS'
        when v_diambil and v_sale.qr_claim_used_at is null then 'CLAIM'
        else null
      end;
    end if;
  end if;

  return jsonb_build_object(
    'role_view', case when v_is_staff then 'staff' else 'customer' end,
    'sale_id', v_sale.id,
    'no_invoice', v_sale.no_invoice,
    'toko_id', v_sale.toko_id,
    'nama_pelanggan', v_sale.nama_pelanggan,
    'nama_kasir', v_sale.nama_kasir,
    'nama_pembuat_kacamata', v_sale.nama_pembuat_kacamata,
    'kasir_karyawan_id', v_sale.kasir_karyawan_id,
    'pembuat_kacamata_id', v_sale.pembuat_kacamata_id,
    'status_pembayaran', v_sale.status_pembayaran,
    'tracking_status', v_sale.tracking_status,
    'diambil_at', v_sale.diambil_at,
    'foto_hasil_url', v_sale.foto_hasil_url,
    'created_at', v_sale.created_at,
    'lunas_at', v_sale.lunas_at,
    'total_harga', v_sale.total_harga,
    'dibayarkan', v_sale.dibayarkan,
    'sisa_tagihan', v_sale.sisa_tagihan,
    'metode_pembayaran', v_sale.metode_pembayaran,
    'channel', v_sale.channel,
    'fulfillment', v_sale.fulfillment,
    'courier', v_sale.courier,
    'online_order_id', v_sale.online_order_id,
    'no_wa', case when v_is_staff then v_sale.no_wa else null end,
    'email_pelanggan', case when v_is_staff then v_sale.email_pelanggan else null end,
    'alamat', case when v_is_staff then v_sale.alamat else null end,
    'items', v_items,
    'garansi', v_garansi,
    'garansi_claimable', v_claimable,
    'google_review_url', v_review,
    'bisa_rating', v_bisa_rating,
    'ratings', coalesce(v_ratings, '[]'::jsonb),
    'qr_dp_ready',
      upper(trim(coalesce(v_sale.tracking_status, ''))) = 'SIAP_PELUNASAN'
      and v_sale.qr_dp_token is not null
      and v_sale.qr_dp_used_at is null,
    'qr_lunas_ready',
      upper(trim(coalesce(v_sale.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR')
      and v_sale.qr_lunas_token is not null
      and v_sale.qr_lunas_used_at is null,
    'qr_claim_ready', (v_sale.qr_claim_token is not null and v_sale.qr_claim_used_at is null)
      or (v_phase = 'CLAIM' and v_payload is not null),
    'qr_dp_used', (v_sale.qr_dp_used_at is not null),
    'qr_lunas_used', (v_sale.qr_lunas_used_at is not null),
    'qr_claim_used', (v_sale.qr_claim_used_at is not null),
    'qr_phase', v_phase,
    'qr_payload', v_payload,
    'qr_owner_verified', v_owner
  );
end;
$$;

grant execute on function public.get_invoice_hub(text, text, uuid) to anon, authenticated;

create function public.get_invoice_hub(p_no_invoice text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.get_invoice_hub(p_no_invoice, null, public.default_tenant_id());
$$;
grant execute on function public.get_invoice_hub(text) to anon, authenticated;

drop function if exists public.redeem_member_promo(text, uuid, text, bigint, uuid, text);
create function public.redeem_member_promo(
  p_code text,
  p_sale_id uuid default null,
  p_phone text default null,
  p_discount_applied bigint default 0,
  p_online_order_id uuid default null,
  p_channel text default 'pos'
,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
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
  v_digits text;
  v_alt text;
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
    return jsonb_build_object(
      'ok', false,
      'error', 'Harus ada tepat satu: sale_id atau online_order_id'
    );
  end if;

  v_tenant := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));

  if v_ch not in ('pos', 'online', 'member', 'any') then
    v_ch := case when p_online_order_id is not null then 'online' else 'pos' end;
  end if;

  if p_sale_id is not null then
    select * into v_sale from public.sales where id = p_sale_id and tenant_id = v_tenant limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Nota penjualan tidak ditemukan');
    end if;
    v_ref_label := coalesce(v_sale.no_invoice, p_sale_id::text);
    select id into v_existing
    from public.member_promo_redemptions
    where sale_id = p_sale_id
    limit 1;
  else
    select * into v_online from public.online_orders where id = p_online_order_id and tenant_id = v_tenant limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Pesanan online tidak ditemukan');
    end if;
    v_ref_label := coalesce(v_online.midtrans_order_id, p_online_order_id::text);
    select id into v_existing
    from public.member_promo_redemptions
    where online_order_id = p_online_order_id
    limit 1;
  end if;

  if v_existing is not null then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_redeemed',
      'redemption_id', v_existing
    );
  end if;

  select * into v_row
  from public.member_promos
  where tenant_id = v_tenant
    and upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and (
      (v_ch = 'pos' and coalesce(show_on_pos, true) = true)
      or (v_ch in ('online', 'member') and coalesce(show_on_member, true) = true)
      or (
        v_ch = 'any'
        and (coalesce(show_on_pos, true) = true or coalesce(show_on_member, true) = true)
      )
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

  v_digits := public.wa_digits(v_phone);
  if v_digits is not null and length(v_digits) >= 8 then
    v_alt := case
      when v_digits like '62%' then '0' || substr(v_digits, 3)
      when v_digits like '0%' then '62' || substr(v_digits, 2)
      else v_digits
    end;
    select m.id into v_member_id
    from public.members m
    where public.wa_digits(m.phone_e164) in (v_digits, v_alt)
       or regexp_replace(coalesce(m.phone_e164, ''), '\D', '', 'g') in (v_digits, v_alt)
       or regexp_replace(coalesce(m.phone_raw, ''), '\D', '', 'g') in (v_digits, v_alt)
    order by m.created_at
    limit 1;
  end if;

  if v_points > 0 then
    if v_member_id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'Voucher butuh ' || v_points || ' poin — nomor WA harus terdaftar member'
      );
    end if;
    select coalesce(sum(delta), 0)::int into v_balance
    from public.member_points_ledger
    where member_id = v_member_id;
    if v_balance < v_points then
      return jsonb_build_object(
        'ok', false,
        'error',
        'Poin member tidak cukup (saldo ' || v_balance || ', butuh ' || v_points || ')'
      );
    end if;
  end if;

  if v_row.quantity_remaining is not null then
    update public.member_promos
    set quantity_remaining = quantity_remaining - 1
    where id = v_row.id
      and quantity_remaining is not null
      and quantity_remaining > 0;
    get diagnostics v_updated = row_count;
    if v_updated = 0 then
      return jsonb_build_object('ok', false, 'error', 'Kuota voucher habis');
    end if;
  end if;

  if v_points > 0 and v_member_id is not null then
    insert into public.member_points_ledger (
      member_id, delta, reason, sale_id, meta
    ) values (
      v_member_id,
      -v_points,
      'voucher_redeem',
      p_sale_id,
      jsonb_build_object(
        'voucher_code', v_code,
        'promo_id', v_row.id,
        'ref', v_ref_label,
        'channel', v_ch,
        'online_order_id', p_online_order_id,
        'discount_applied', v_disc
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
    set
      voucher_code = v_code,
      voucher_discount = case
        when coalesce(voucher_discount, 0) > 0 then voucher_discount
        else v_disc
      end
    where id = p_sale_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'promo_id', v_row.id,
    'voucher_code', v_code,
    'points_spent', v_points,
    'member_id', v_member_id,
    'channel', v_ch,
    'quantity_remaining', (
      select quantity_remaining from public.member_promos where id = v_row.id
    )
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_redeemed_race'
    );
end;
$$;

grant execute on function public.redeem_member_promo(text, uuid, text, bigint, uuid, text, uuid)
  to anon, authenticated, service_role;

-- Help-bot stok: jangan baca katalog PUSAT Optik untuk tenant lain
drop function if exists public.search_member_toko_stock(text, text, int);
create function public.search_member_toko_stock(
  p_toko_id text,
  p_q text default null,
  p_limit int default 8,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_q text := nullif(trim(coalesce(p_q, '')), '');
  v_limit int := greatest(1, least(coalesce(p_limit, 8), 30));
  v_exists boolean := false;
  v_summary json;
  v_matches json;
  v_skus_in_stock int := 0;
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
  v_pusat text := public.tenant_pusat_toko_id(v_tenant);
begin
  if v_toko = '' then
    return json_build_object(
      'toko_id', null, 'ok', false, 'error', 'toko_id_required',
      'mode', 'summary', 'query', null, 'skus_in_stock', 0,
      'by_kategori', '[]'::json, 'matches', '[]'::json
    );
  end if;

  if not exists (
    select 1 from public.toko_id t
    where upper(trim(t.id)) = v_toko and t.tenant_id = v_tenant
  ) then
    return json_build_object(
      'toko_id', v_toko, 'ok', false, 'error', 'toko_not_found',
      'mode', 'summary', 'query', v_q, 'skus_in_stock', 0,
      'by_kategori', '[]'::json, 'matches', '[]'::json
    );
  end if;

  if v_pusat is not null and upper(trim(v_pusat)) = v_toko then
    return json_build_object(
      'toko_id', v_toko, 'ok', false, 'error', 'toko_not_branch',
      'mode', 'summary', 'query', v_q, 'skus_in_stock', 0,
      'by_kategori', '[]'::json, 'matches', '[]'::json
    );
  end if;

  select exists(
    select 1 from public.toko_id t
    where upper(trim(t.id)) = v_toko and t.tenant_id = v_tenant
  ) into v_exists;
  if not v_exists then
    return json_build_object(
      'toko_id', v_toko, 'ok', false, 'error', 'toko_not_found',
      'mode', 'summary', 'query', v_q, 'skus_in_stock', 0,
      'by_kategori', '[]'::json, 'matches', '[]'::json
    );
  end if;

  select coalesce(json_agg(row_to_json(x) order by x.kategori), '[]'::json),
         coalesce(sum(x.skus_in_stock), 0)::int
  into v_summary, v_skus_in_stock
  from (
    select
      coalesce(nullif(trim(p.kategori), ''), 'Lainnya') as kategori,
      count(*) filter (
        where public.product_available_qty(
          coalesce(b.stock, 0), coalesce(b.reserved_qty, 0)
        ) > 0
      )::int as skus_in_stock,
      coalesce(sum(public.product_available_qty(
        coalesce(b.stock, 0), coalesce(b.reserved_qty, 0)
      )), 0)::int as total_available
    from public.products p
    left join public.products b
      on b.tenant_id = v_tenant
     and upper(trim(b.toko_id)) = v_toko
     and upper(trim(b.sku)) = upper(trim(p.sku))
    where p.tenant_id = v_tenant
      and upper(trim(p.toko_id)) = upper(trim(coalesce(v_pusat, '')))
      and nullif(trim(p.sku), '') is not null
    group by 1
  ) x;

  if v_q is null or char_length(v_q) < 2 then
    select coalesce(json_agg(json_build_object(
      'sku', m.sku, 'nama', m.nama, 'kategori', m.kategori,
      'warna', m.warna, 'available_qty', m.available_qty, 'in_stock', m.in_stock
    ) order by m.kategori, m.nama), '[]'::json)
    into v_matches
    from (
      select p.sku, p.nama,
        coalesce(nullif(trim(p.kategori), ''), 'Lainnya') as kategori,
        p.warna,
        public.product_available_qty(coalesce(b.stock, 0), coalesce(b.reserved_qty, 0)) as available_qty,
        true as in_stock
      from public.products p
      join public.products b
        on b.tenant_id = v_tenant
       and upper(trim(b.toko_id)) = v_toko
       and upper(trim(b.sku)) = upper(trim(p.sku))
      where p.tenant_id = v_tenant
        and upper(trim(p.toko_id)) = upper(trim(coalesce(v_pusat, '')))
        and nullif(trim(p.sku), '') is not null
        and public.product_available_qty(coalesce(b.stock, 0), coalesce(b.reserved_qty, 0)) > 0
      order by 3, p.nama
      limit v_limit
    ) m;

    return json_build_object(
      'toko_id', v_toko, 'ok', true, 'mode', 'summary', 'query', v_q,
      'skus_in_stock', v_skus_in_stock, 'by_kategori', v_summary, 'matches', v_matches
    );
  end if;

  select coalesce(json_agg(json_build_object(
    'sku', m.sku, 'nama', m.nama, 'kategori', m.kategori,
    'warna', m.warna, 'available_qty', m.available_qty, 'in_stock', m.in_stock
  ) order by m.rank_score desc, m.nama), '[]'::json)
  into v_matches
  from (
    with tokens as (
      select distinct lower(tok) as tok
      from unnest(regexp_split_to_array(lower(v_q), '[\s,/;]+')) as tok
      where length(tok) >= 2
        and tok not in (
          'di', 'ke', 'dari', 'untuk', 'yang', 'dan', 'atau',
          'cabang', 'toko', 'stok', 'stock', 'ada', 'cek'
        )
    )
    select p.sku, p.nama, p.kategori, p.warna,
      public.product_available_qty(coalesce(b.stock, 0), coalesce(b.reserved_qty, 0)) as available_qty,
      (public.product_available_qty(coalesce(b.stock, 0), coalesce(b.reserved_qty, 0)) > 0) as in_stock,
      (
        case when upper(trim(p.sku)) = upper(v_q) then 100 else 0 end
        + case when coalesce(p.barcode, '') ilike v_q then 90 else 0 end
        + case when p.nama ilike v_q then 80 else 0 end
        + case when p.nama ilike '%' || v_q || '%' then 40 else 0 end
        + case when p.sku ilike '%' || v_q || '%' then 35 else 0 end
        + (
          select coalesce(sum(
            case
              when p.nama ilike '%' || t.tok || '%' then 20
              when p.sku ilike '%' || t.tok || '%' then 18
              when coalesce(p.warna, '') ilike '%' || t.tok || '%' then 14
              when coalesce(p.kategori, '') ilike '%' || t.tok || '%' then 10
              when coalesce(p.sub_kategori, '') ilike '%' || t.tok || '%' then 8
              when coalesce(p.barcode, '') ilike '%' || t.tok || '%' then 16
              else 0
            end
          ), 0) from tokens t
        )
        + case when public.product_available_qty(
            coalesce(b.stock, 0), coalesce(b.reserved_qty, 0)
          ) > 0 then 10 else 0 end
      ) as rank_score
    from public.products p
    left join public.products b
      on b.tenant_id = v_tenant
     and upper(trim(b.toko_id)) = v_toko
     and upper(trim(b.sku)) = upper(trim(p.sku))
    where p.tenant_id = v_tenant
      and upper(trim(p.toko_id)) = upper(trim(coalesce(v_pusat, '')))
      and nullif(trim(p.sku), '') is not null
      and (
        p.nama ilike '%' || v_q || '%'
        or p.sku ilike '%' || v_q || '%'
        or coalesce(p.barcode, '') ilike '%' || v_q || '%'
        or coalesce(p.warna, '') ilike '%' || v_q || '%'
        or coalesce(p.kategori, '') ilike '%' || v_q || '%'
        or coalesce(p.sub_kategori, '') ilike '%' || v_q || '%'
        or exists (
          select 1 from tokens t
          where p.nama ilike '%' || t.tok || '%'
             or p.sku ilike '%' || t.tok || '%'
             or coalesce(p.barcode, '') ilike '%' || t.tok || '%'
             or coalesce(p.warna, '') ilike '%' || t.tok || '%'
             or coalesce(p.kategori, '') ilike '%' || t.tok || '%'
             or coalesce(p.sub_kategori, '') ilike '%' || t.tok || '%'
        )
      )
    order by rank_score desc, p.nama
    limit v_limit
  ) m;

  return json_build_object(
    'toko_id', v_toko, 'ok', true, 'mode', 'search', 'query', v_q,
    'skus_in_stock', v_skus_in_stock, 'by_kategori', v_summary, 'matches', v_matches
  );
end;
$$;
grant execute on function public.search_member_toko_stock(text, text, int, uuid)
  to anon, authenticated, service_role;

drop function if exists public.get_toko_lab_queue_counts(text);
create function public.get_toko_lab_queue_counts(
  p_toko_id text,
  p_tenant_id uuid default '00000000-0000-0000-0000-000000000001'
)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_waiting int := 0;
  v_in_progress int := 0;
  v_ready int := 0;
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
begin
  if v_toko = '' then
    return json_build_object('toko_id', null, 'waiting', 0, 'in_progress', 0, 'ready', 0, 'ok', false, 'error', 'toko_id_required');
  end if;
  if not exists (
    select 1 from public.toko_id t
    where upper(trim(t.id)) = v_toko and t.tenant_id = v_tenant
  ) then
    return json_build_object('toko_id', v_toko, 'waiting', 0, 'in_progress', 0, 'ready', 0, 'ok', false, 'error', 'toko_not_found');
  end if;

  select count(*)::int into v_waiting
  from public.lab_jobs j
  where j.tenant_id = v_tenant
    and upper(trim(coalesce(j.toko_id, ''))) = v_toko
    and upper(trim(j.status)) = 'OPEN';

  select count(*)::int into v_in_progress
  from public.lab_jobs j
  where j.tenant_id = v_tenant
    and upper(trim(coalesce(j.toko_id, ''))) = v_toko
    and upper(trim(j.status)) = 'CLAIMED';

  select count(*)::int into v_ready
  from public.sales s
  where s.tenant_id = v_tenant
    and upper(trim(coalesce(s.toko_id, ''))) = v_toko
    and upper(trim(coalesce(s.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR')
    and s.diambil_at is null;

  return json_build_object(
    'toko_id', v_toko, 'waiting', v_waiting, 'in_progress', v_in_progress,
    'ready', v_ready, 'ok', true
  );
end;
$$;
grant execute on function public.get_toko_lab_queue_counts(text, uuid)
  to anon, authenticated, service_role;

comment on function public.require_member_tenant(uuid) is
  'RPC Member wajib tenant aktif. Client yang gagal resolve slug HARUS gagal, bukan jatuh ke Optik.';

