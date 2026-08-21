-- =============================================================================
-- Tagihan Rekasa → UMKM + kontrak online (klik-setuju + nama ketik).
-- Hari H lewat & belum bayar → tenants.status = 'suspend' (data tidak dihapus).
-- Apply setelah 000001–000007. Jangan di-apply dari agent ke live.
-- =============================================================================

alter table public.tenant_plan_catalog
  add column if not exists price_idr bigint not null default 0
    check (price_idr >= 0);

update public.tenant_plan_catalog set price_idr = 250000 where plan_key = 'paket_c' and price_idr = 0;
update public.tenant_plan_catalog set price_idr = 450000 where plan_key = 'paket_b' and price_idr = 0;
update public.tenant_plan_catalog set price_idr = 750000 where plan_key = 'paket_a' and price_idr = 0;

alter table public.tenants
  add column if not exists suspend_reason text,
  add column if not exists billing_notes text;

create sequence if not exists public.tenant_invoice_seq;
create sequence if not exists public.tenant_contract_seq;

create table if not exists public.tenant_invoices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  invoice_no text not null unique,
  period text not null,
  amount_idr bigint not null check (amount_idr >= 0),
  due_at timestamptz not null,
  issued_at timestamptz not null default now(),
  paid_at timestamptz,
  status text not null default 'sent'
    check (status in ('draft', 'sent', 'overdue', 'paid', 'void')),
  notes text,
  paid_method text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists tenant_invoices_tenant_idx
  on public.tenant_invoices (tenant_id, due_at desc);

create unique index if not exists tenant_invoices_period_uidx
  on public.tenant_invoices (tenant_id, period)
  where status <> 'void';

create table if not exists public.tenant_contracts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  contract_no text not null unique,
  public_token text not null unique,
  title text not null,
  body text not null,
  plan_key text,
  amount_idr bigint not null default 0 check (amount_idr >= 0),
  status text not null default 'sent'
    check (status in ('draft', 'sent', 'viewed', 'signed', 'void')),
  sent_at timestamptz not null default now(),
  viewed_at timestamptz,
  signed_at timestamptz,
  signer_name text,
  signer_email text,
  signer_ip text,
  signer_user_agent text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists tenant_contracts_tenant_idx
  on public.tenant_contracts (tenant_id, created_at desc);

alter table public.tenant_invoices enable row level security;
alter table public.tenant_contracts enable row level security;

drop policy if exists tenant_invoices_platform on public.tenant_invoices;
create policy tenant_invoices_platform on public.tenant_invoices
  for all to authenticated
  using (public.is_platform_user())
  with check (public.is_platform_user());

drop policy if exists tenant_contracts_platform on public.tenant_contracts;
create policy tenant_contracts_platform on public.tenant_contracts
  for all to authenticated
  using (public.is_platform_user())
  with check (public.is_platform_user());

-- -----------------------------------------------------------------------------
-- Akses tenant: Rekasa lolos. UMKM suspend = current_tenant_id NULL (sistem down).
-- Data tidak dihapus. RPC tagihan/kontrak baca profiles.tenant_id langsung.
-- -----------------------------------------------------------------------------
create or replace function public.current_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v uuid;
  v_status text;
begin
  if auth.uid() is null then
    return null;
  end if;
  if public.is_platform_user() then
    select p.tenant_id into v from public.profiles p where p.id = auth.uid();
    if v is not null then
      return v;
    end if;
    select k.tenant_id into v from public.karyawan k where k.id = auth.uid() limit 1;
    return v;
  end if;

  select p.tenant_id into v from public.profiles p where p.id = auth.uid();
  if v is null then
    select k.tenant_id into v from public.karyawan k where k.id = auth.uid() limit 1;
  end if;
  if v is null then
    return null;
  end if;
  select t.status into v_status from public.tenants t where t.id = v;
  if v_status is distinct from 'aktif' then
    return null;
  end if;
  return v;
end;
$$;

create or replace function public.require_member_tenant(p uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if p is null then
    raise exception 'tenant wajib — jangan memakai data usaha lain';
  end if;
  select t.status into v_status from public.tenants t where t.id = p;
  if v_status = 'aktif' then
    return p;
  end if;
  if v_status = 'suspend' then
    raise exception 'Langganan ditangguhkan. Tagihan belum dibayar — sistem dimatikan sampai lunas. Data toko tidak dihapus.';
  end if;
  if v_status = 'trial' then
    raise exception 'Usaha masih uji coba / belum aktif. Tandatangani kontrak atau hubungi Rekasa.';
  end if;
  raise exception 'Kode usaha / tenant tidak valid';
end;
$$;

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
    return jsonb_build_object('ok', false, 'reason', 'empty', 'error', 'Kode usaha wajib');
  end if;
  select * into v from public.tenants where slug = v_slug;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found', 'error', 'Kode usaha tidak ditemukan');
  end if;
  select * into v_brand from public.app_brand where tenant_id = v.id;
  if v.status is distinct from 'aktif' then
    return jsonb_build_object(
      'ok', false,
      'reason', v.status,
      'status', v.status,
      'id', v.id,
      'slug', v.slug,
      'display_name', coalesce(v_brand.display_name, v.legal_name),
      'error', case v.status
        when 'suspend' then
          'Langganan ditangguhkan. Tagihan belum dibayar pada hari H — sistem dimatikan sampai lunas. Data tidak dihapus. Hubungi Rekasa.'
        when 'trial' then
          'Usaha belum aktif. Tandatangani kontrak online dulu, atau hubungi Rekasa.'
        else
          'Kode usaha tidak aktif.'
      end
    );
  end if;
  return jsonb_build_object(
    'ok', true,
    'id', v.id,
    'slug', v.slug,
    'legal_name', v.legal_name,
    'pusat_toko_id', v.pusat_toko_id,
    'display_name', coalesce(v_brand.display_name, v.legal_name),
    'short_name', v_brand.short_name,
    'assistant_name', v_brand.assistant_name,
    'status', v.status
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Template kontrak (SaaS berlanjut, bukan fork per UMKM).
-- -----------------------------------------------------------------------------
create or replace function public.rekasa_contract_template(
  p_display_name text,
  p_legal_name text,
  p_slug text,
  p_plan_label text,
  p_amount_idr bigint
)
returns text
language plpgsql
stable
as $$
begin
  return
    'PERJANJIAN LANGGANAN PERANGKAT LUNAK' || E'\n'
    || 'Nomor akan diisi otomatis saat kontrak dikirim.' || E'\n\n'
    || 'Pihak Pertama (Penyedia):' || E'\n'
    || 'REKASA KARYA INDONESIA, Perseroan Perorangan, Wajib Pajak dengan PPh Final 0,5%.' || E'\n'
    || 'Produk: satu codebase (aplikasi kasir / member / admin) yang disewakan per usaha.' || E'\n\n'
    || 'Pihak Kedua (Pelanggan):' || E'\n'
    || coalesce(nullif(trim(p_legal_name), ''), nullif(trim(p_display_name), ''), 'UMKM') || E'\n'
    || 'Nama merek di aplikasi: ' || coalesce(nullif(trim(p_display_name), ''), '-') || E'\n'
    || 'Kode usaha: ' || coalesce(nullif(trim(p_slug), ''), '-') || E'\n\n'
    || '1. Objek. Rekasa menyediakan hak pakai perangkat lunak sesuai paket '
    || coalesce(nullif(trim(p_plan_label), ''), 'yang disepakati')
    || '. Bukan jual putus source code, bukan cabang Optik B. Riski, bukan pengalihan badan hukum.' || E'\n\n'
    || '2. Biaya. Biaya langganan Rp '
    || to_char(coalesce(p_amount_idr, 0), 'FM999,999,999,999')
    || ' per periode tagihan, ditagih di muka. Perubahan paket = perubahan modul, bukan ganti aplikasi.' || E'\n\n'
    || '3. Jangka waktu. Berlaku sejak ditandatangani dan berlanjut (perpanjang otomatis) sampai diakhiri tertulis oleh salah satu pihak dengan pemberitahuan wajar.' || E'\n\n'
    || '4. Hari H. Jika tagihan tidak dilunasi pada atau sebelum jatuh tempo, Rekasa berhak menonaktifkan akses (sistem down / status suspend) tanpa menghapus data toko, nota, stok, atau member. Akses dinyalakan kembali setelah pelunasan dicatat Rekasa.' || E'\n\n'
    || '5. Data. Data pelanggan tetap milik Pihak Kedua. Rekasa tidak memindahkan data merek ini ke usaha lain.' || E'\n\n'
    || '6. Pajak. Rekasa adalah Perseroan Perorangan (bukan PT Biasa). Perlakuan pajak mengikuti ketentuan yang berlaku bagi perseroan perorangan, termasuk PPh Final 0,5% sepanjang masih memenuhi syarat.' || E'\n\n'
    || '7. Tanda tangan. Persetujuan elektronik (centang + ketik nama + stempel waktu) mengikat seperti tanda tangan basah. Salinan kontrak dapat diunduh / disalin dari tautan yang sama.' || E'\n\n'
    || 'Dengan menandatangani, Pihak Kedua menyatakan telah membaca dan menyetujui seluruh pasal di atas.';
end;
$$;

grant execute on function public.rekasa_contract_template(text, text, text, text, bigint)
  to authenticated;

create or replace function public.list_tenant_plans()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'plan_key', c.plan_key,
    'label', c.label,
    'white_label', c.white_label,
    'price_idr', c.price_idr,
    'shell', case
      when c.white_label then 'APK & web merek sendiri (nama + ikon)'
      else 'Kulit Rekasa + kode usaha di login'
    end
  ) order by c.sort_order), '[]'::jsonb)
  from public.tenant_plan_catalog c;
$$;

create or replace function public.platform_set_plan_price(p_plan_key text, p_price_idr bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text := lower(trim(coalesce(p_plan_key, '')));
  v_price bigint := greatest(coalesce(p_price_idr, 0), 0);
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  if not exists (select 1 from public.tenant_plan_catalog c where c.plan_key = v_plan) then
    raise exception 'Paket tidak dikenal';
  end if;
  update public.tenant_plan_catalog set price_idr = v_price where plan_key = v_plan;
  return jsonb_build_object('ok', true, 'plan_key', v_plan, 'price_idr', v_price);
end;
$$;

grant execute on function public.platform_set_plan_price(text, bigint) to authenticated;

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
      'created_at', t.created_at,
      'open_invoices', (
        select count(*) from public.tenant_invoices i
        where i.tenant_id = t.id and i.status in ('sent', 'overdue')
      ),
      'overdue_invoices', (
        select count(*) from public.tenant_invoices i
        where i.tenant_id = t.id and i.status = 'overdue'
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
  ), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- Tagihan
-- -----------------------------------------------------------------------------
create or replace function public.enforce_tenant_billing()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_overdue int := 0;
  v_suspend int := 0;
begin
  if auth.uid() is not null and not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  update public.tenant_invoices
  set status = 'overdue', updated_at = now()
  where status in ('draft', 'sent')
    and paid_at is null
    and due_at < now();
  get diagnostics v_overdue = row_count;

  update public.tenants t
  set status = 'suspend',
      suspend_reason = 'tagihan_jatuh_tempo',
      updated_at = now()
  where t.status = 'aktif'
    and exists (
      select 1 from public.tenant_invoices i
      where i.tenant_id = t.id
        and i.status = 'overdue'
        and i.paid_at is null
    );
  get diagnostics v_suspend = row_count;

  return jsonb_build_object(
    'ok', true,
    'marked_overdue', v_overdue,
    'suspended', v_suspend
  );
end;
$$;

grant execute on function public.enforce_tenant_billing() to authenticated, service_role;

create or replace function public.platform_create_invoice(
  p_tenant_id uuid,
  p_period text,
  p_amount_idr bigint default null,
  p_due_at timestamptz default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period text := nullif(trim(coalesce(p_period, '')), '');
  v_amount bigint;
  v_due timestamptz;
  v_no text;
  v_id uuid := gen_random_uuid();
  v_plan text;
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  if p_tenant_id is null or not exists (select 1 from public.tenants t where t.id = p_tenant_id) then
    raise exception 'Tenant tidak ada';
  end if;
  if v_period is null then
    v_period := to_char(now(), 'YYYY-MM');
  end if;
  if exists (
    select 1 from public.tenant_invoices i
    where i.tenant_id = p_tenant_id and i.period = v_period and i.status <> 'void'
  ) then
    raise exception 'Tagihan periode % sudah ada', v_period;
  end if;

  select t.plan_key, c.price_idr
    into v_plan, v_amount
  from public.tenants t
  left join public.tenant_plan_catalog c on c.plan_key = t.plan_key
  where t.id = p_tenant_id;

  v_amount := coalesce(p_amount_idr, v_amount, 0);
  if v_amount < 0 then
    raise exception 'Nominal tidak valid';
  end if;
  v_due := coalesce(p_due_at, date_trunc('month', now()) + interval '1 month');

  v_no := 'RK-INV-' || to_char(now(), 'YYYYMM') || '-'
    || lpad(nextval('public.tenant_invoice_seq')::text, 4, '0');

  insert into public.tenant_invoices (
    id, tenant_id, invoice_no, period, amount_idr, due_at, status, notes, created_by
  ) values (
    v_id, p_tenant_id, v_no, v_period, v_amount, v_due, 'sent',
    nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  );

  perform public.enforce_tenant_billing();

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'invoice_no', v_no,
    'period', v_period,
    'amount_idr', v_amount,
    'due_at', v_due,
    'plan_key', v_plan
  );
end;
$$;

grant execute on function public.platform_create_invoice(uuid, text, bigint, timestamptz, text)
  to authenticated;

create or replace function public.platform_void_invoice(p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  update public.tenant_invoices
  set status = 'void', updated_at = now()
  where id = p_invoice_id and status <> 'paid';
  if not found then
    raise exception 'Tagihan tidak bisa dibatalkan';
  end if;
  return jsonb_build_object('ok', true, 'id', p_invoice_id);
end;
$$;

grant execute on function public.platform_void_invoice(uuid) to authenticated;

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
      and status = 'suspend'
      and coalesce(suspend_reason, 'tagihan_jatuh_tempo') = 'tagihan_jatuh_tempo';
  end if;

  return jsonb_build_object('ok', true, 'id', p_invoice_id, 'tenant_id', v_tenant, 'reactivated', v_left = 0);
end;
$$;

grant execute on function public.platform_mark_invoice_paid(uuid, text) to authenticated;

create or replace function public.platform_set_tenant_status(
  p_tenant_id uuid,
  p_status text,
  p_reason text default null,
  p_force boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
  v_left int := 0;
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  if v_status not in ('aktif', 'suspend', 'trial') then
    raise exception 'Status tidak dikenal';
  end if;
  if p_tenant_id is null or not exists (select 1 from public.tenants t where t.id = p_tenant_id) then
    raise exception 'Tenant tidak ada';
  end if;
  if v_status = 'aktif' and coalesce(p_force, false) is not true then
    select count(*) into v_left
    from public.tenant_invoices i
    where i.tenant_id = p_tenant_id and i.status = 'overdue' and i.paid_at is null;
    if v_left > 0 then
      raise exception 'Masih ada % tagihan jatuh tempo. Lunasi dulu atau pakai force.', v_left;
    end if;
  end if;
  update public.tenants
  set status = v_status,
      suspend_reason = case
        when v_status = 'suspend' then coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'manual')
        else null
      end,
      updated_at = now()
  where id = p_tenant_id;
  return jsonb_build_object('ok', true, 'tenant_id', p_tenant_id, 'status', v_status);
end;
$$;

grant execute on function public.platform_set_tenant_status(uuid, text, text, boolean)
  to authenticated;

create or replace function public.platform_list_invoices(p_tenant_id uuid default null)
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
      'id', i.id,
      'tenant_id', i.tenant_id,
      'slug', t.slug,
      'display_name', coalesce(b.display_name, t.legal_name),
      'invoice_no', i.invoice_no,
      'period', i.period,
      'amount_idr', i.amount_idr,
      'due_at', i.due_at,
      'issued_at', i.issued_at,
      'paid_at', i.paid_at,
      'status', i.status,
      'notes', i.notes,
      'paid_method', i.paid_method
    ) order by i.due_at desc, i.created_at desc)
    from public.tenant_invoices i
    join public.tenants t on t.id = i.tenant_id
    left join public.app_brand b on b.tenant_id = t.id
    where p_tenant_id is null or i.tenant_id = p_tenant_id
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.platform_list_invoices(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Kontrak online
-- -----------------------------------------------------------------------------
create or replace function public.platform_create_contract(
  p_tenant_id uuid,
  p_title text default null,
  p_body text default null,
  p_amount_idr bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_no text;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_title text;
  v_body text;
  v_amount bigint;
  v_plan text;
  v_plan_label text;
  v_name text;
  v_legal text;
  v_slug text;
begin
  if not public.is_platform_user() then
    raise exception 'Hanya akun Rekasa';
  end if;
  if p_tenant_id is null then
    raise exception 'Tenant wajib';
  end if;

  select t.plan_key, t.legal_name, t.slug, c.label, c.price_idr, b.display_name
    into v_plan, v_legal, v_slug, v_plan_label, v_amount, v_name
  from public.tenants t
  left join public.tenant_plan_catalog c on c.plan_key = t.plan_key
  left join public.app_brand b on b.tenant_id = t.id
  where t.id = p_tenant_id;
  if v_slug is null then
    raise exception 'Tenant tidak ada';
  end if;

  v_amount := coalesce(p_amount_idr, v_amount, 0);
  v_title := coalesce(
    nullif(trim(coalesce(p_title, '')), ''),
    'Perjanjian langganan Rekasa — ' || coalesce(v_name, v_legal, v_slug)
  );
  v_body := coalesce(
    nullif(trim(coalesce(p_body, '')), ''),
    public.rekasa_contract_template(v_name, v_legal, v_slug, v_plan_label, v_amount)
  );
  v_no := 'RK-KTR-' || to_char(now(), 'YYYY') || '-'
    || lpad(nextval('public.tenant_contract_seq')::text, 4, '0');

  insert into public.tenant_contracts (
    id, tenant_id, contract_no, public_token, title, body,
    plan_key, amount_idr, status, created_by
  ) values (
    v_id, p_tenant_id, v_no, v_token, v_title, v_body,
    v_plan, v_amount, 'sent', auth.uid()
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'contract_no', v_no,
    'public_token', v_token,
    'title', v_title,
    'amount_idr', v_amount
  );
end;
$$;

grant execute on function public.platform_create_contract(uuid, text, text, bigint)
  to authenticated;

create or replace function public.platform_list_contracts(p_tenant_id uuid default null)
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
      'id', c.id,
      'tenant_id', c.tenant_id,
      'slug', t.slug,
      'display_name', coalesce(b.display_name, t.legal_name),
      'contract_no', c.contract_no,
      'public_token', c.public_token,
      'title', c.title,
      'plan_key', c.plan_key,
      'amount_idr', c.amount_idr,
      'status', c.status,
      'sent_at', c.sent_at,
      'viewed_at', c.viewed_at,
      'signed_at', c.signed_at,
      'signer_name', c.signer_name
    ) order by c.created_at desc)
    from public.tenant_contracts c
    join public.tenants t on t.id = c.tenant_id
    left join public.app_brand b on b.tenant_id = t.id
    where p_tenant_id is null or c.tenant_id = p_tenant_id
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.platform_list_contracts(uuid) to authenticated;

create or replace function public.get_contract_by_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.tenant_contracts%rowtype;
  v_name text;
  v_slug text;
  v_legal text;
begin
  if nullif(trim(coalesce(p_token, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Tautan kontrak tidak valid');
  end if;
  select * into v from public.tenant_contracts
  where public_token = trim(p_token) and status <> 'void';
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Kontrak tidak ditemukan atau sudah dibatalkan');
  end if;
  if v.status = 'sent' then
    update public.tenant_contracts
    set status = 'viewed', viewed_at = now(), updated_at = now()
    where id = v.id;
    v.status := 'viewed';
    v.viewed_at := now();
  end if;
  select t.slug, t.legal_name, b.display_name
    into v_slug, v_legal, v_name
  from public.tenants t
  left join public.app_brand b on b.tenant_id = t.id
  where t.id = v.tenant_id;

  return jsonb_build_object(
    'ok', true,
    'id', v.id,
    'contract_no', v.contract_no,
    'title', v.title,
    'body', v.body,
    'status', v.status,
    'plan_key', v.plan_key,
    'amount_idr', v.amount_idr,
    'sent_at', v.sent_at,
    'viewed_at', v.viewed_at,
    'signed_at', v.signed_at,
    'signer_name', v.signer_name,
    'display_name', coalesce(v_name, v_legal),
    'legal_name', v_legal,
    'slug', v_slug,
    'provider', 'REKASA KARYA INDONESIA'
  );
end;
$$;

grant execute on function public.get_contract_by_token(text)
  to anon, authenticated, service_role;

create or replace function public.sign_tenant_contract(
  p_token text,
  p_signer_name text,
  p_agree boolean,
  p_signer_email text default null,
  p_ip text default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(coalesce(p_signer_name, '')), '');
  v_id uuid;
  v_no text;
begin
  if coalesce(p_agree, false) is not true then
    raise exception 'Centang persetujuan dulu';
  end if;
  if v_name is null or length(v_name) < 3 then
    raise exception 'Ketik nama lengkap (minimal 3 huruf)';
  end if;
  update public.tenant_contracts
  set status = 'signed',
      signed_at = now(),
      signer_name = v_name,
      signer_email = nullif(trim(coalesce(p_signer_email, '')), ''),
      signer_ip = nullif(trim(coalesce(p_ip, '')), ''),
      signer_user_agent = nullif(left(trim(coalesce(p_user_agent, '')), 400), ''),
      updated_at = now()
  where public_token = trim(coalesce(p_token, ''))
    and status in ('sent', 'viewed')
  returning id, contract_no into v_id, v_no;
  if v_id is null then
    raise exception 'Kontrak tidak bisa ditandatangani (sudah ditandatangani, batal, atau tautan salah)';
  end if;
  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'contract_no', v_no,
    'signed_at', now(),
    'signer_name', v_name
  );
end;
$$;

grant execute on function public.sign_tenant_contract(text, text, boolean, text, text, text)
  to anon, authenticated, service_role;

-- Akses lock-screen: baca tenant dari profil, bukan current_tenant_id (bisa NULL saat suspend).
create or replace function public.my_tenant_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tid uuid;
  v_status text;
  v_reason text;
  v_name text;
  v_slug text;
begin
  if public.is_platform_user() then
    return jsonb_build_object('ok', true, 'platform', true, 'reason', 'platform');
  end if;
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'anon', 'error', 'Belum login');
  end if;
  select p.tenant_id into v_tid from public.profiles p where p.id = auth.uid();
  if v_tid is null then
    select k.tenant_id into v_tid from public.karyawan k where k.id = auth.uid() limit 1;
  end if;
  if v_tid is null then
    return jsonb_build_object('ok', true, 'reason', 'no_tenant');
  end if;
  select t.status, t.suspend_reason, t.slug, coalesce(b.display_name, t.legal_name)
    into v_status, v_reason, v_slug, v_name
  from public.tenants t
  left join public.app_brand b on b.tenant_id = t.id
  where t.id = v_tid;
  if v_status is distinct from 'aktif' then
    return jsonb_build_object(
      'ok', false,
      'reason', v_status,
      'status', v_status,
      'suspend_reason', v_reason,
      'tenant_id', v_tid,
      'slug', v_slug,
      'display_name', v_name,
      'error', case v_status
        when 'suspend' then
          'Langganan ditangguhkan. Tagihan belum dibayar — sistem dimatikan sampai lunas. Data tidak dihapus.'
        else
          'Usaha belum aktif. Tandatangani kontrak atau hubungi Rekasa.'
      end,
      'invoices', coalesce((
        select jsonb_agg(jsonb_build_object(
          'invoice_no', i.invoice_no,
          'period', i.period,
          'amount_idr', i.amount_idr,
          'due_at', i.due_at,
          'status', i.status
        ) order by i.due_at desc)
        from public.tenant_invoices i
        where i.tenant_id = v_tid and i.status in ('sent', 'overdue')
      ), '[]'::jsonb),
      'unsigned_contract_token', (
        select c.public_token from public.tenant_contracts c
        where c.tenant_id = v_tid and c.status in ('sent', 'viewed')
        order by c.created_at desc limit 1
      )
    );
  end if;
  return jsonb_build_object(
    'ok', true,
    'status', 'aktif',
    'tenant_id', v_tid,
    'slug', v_slug,
    'display_name', v_name
  );
end;
$$;

grant execute on function public.my_tenant_access() to authenticated;

comment on function public.enforce_tenant_billing() is
  'Tandai tagihan lewat hari H sebagai overdue, lalu suspend tenant. Data tidak dihapus.';

-- Jadwal harian jika pg_cron ada (Pro). Kalau tidak, Rekasa tap "Tegakkan tagihan".
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('rekasa-enforce-billing');
  end if;
exception when others then
  null;
end
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'rekasa-enforce-billing',
      '20 0 * * *',
      'select public.enforce_tenant_billing()'
    );
  end if;
exception when others then
  null;
end
$$;
