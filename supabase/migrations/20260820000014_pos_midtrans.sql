-- =============================================================================
-- Midtrans Snap untuk POS (kasir + pelunasan). Bukan tagihan etalase Rekasa.
-- Apply setelah 000013. Jangan dari agent ke live. Tanpa service_role di APK.
-- =============================================================================

create table if not exists public.pos_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  toko_id text,
  sale_id uuid,
  purpose text not null check (purpose in ('sale', 'pelunasan')),
  amount_idr bigint not null check (amount_idr > 0 and amount_idr < 100000000000),
  midtrans_order_id text not null unique,
  midtrans_snap_token text,
  midtrans_redirect_url text,
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'expired', 'cancelled')),
  payment_type text,
  invoice_no text,
  customer_name text,
  customer_phone text,
  created_by uuid,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists pos_payments_tenant_idx
  on public.pos_payments (tenant_id, created_at desc);

alter table public.pos_payments enable row level security;

drop policy if exists pos_payments_select on public.pos_payments;
create policy pos_payments_select on public.pos_payments
  for select using (
    tenant_id = public.current_tenant_id()
    or public.is_platform_user()
  );

create or replace function public.create_pos_payment(
  p_amount_idr bigint,
  p_purpose text,
  p_toko_id text default null,
  p_sale_id uuid default null,
  p_invoice_no text default null,
  p_customer_name text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tid uuid := public.current_tenant_id();
  v_uid uuid := auth.uid();
  v_purpose text := lower(trim(coalesce(p_purpose, 'sale')));
  v_mid text;
  v_id uuid := gen_random_uuid();
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Login kasir dulu');
  end if;
  if v_tid is null then
    return jsonb_build_object('ok', false, 'error', 'Kode usaha belum terikat');
  end if;
  if public.is_platform_user() then
    return jsonb_build_object('ok', false, 'error', 'Etalase Rekasa bukan kasir');
  end if;
  if v_purpose not in ('sale', 'pelunasan') then
    return jsonb_build_object('ok', false, 'error', 'Tujuan bayar tidak valid');
  end if;
  if coalesce(p_amount_idr, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Nominal Midtrans harus > 0');
  end if;
  if v_purpose = 'pelunasan' and p_sale_id is null then
    return jsonb_build_object('ok', false, 'error', 'Pelunasan butuh nota');
  end if;

  v_mid := 'POS-' || replace(v_id::text, '-', '');

  insert into public.pos_payments (
    id, tenant_id, toko_id, sale_id, purpose, amount_idr,
    midtrans_order_id, invoice_no, customer_name, customer_phone, created_by
  ) values (
    v_id, v_tid, nullif(trim(coalesce(p_toko_id, '')), ''),
    p_sale_id, v_purpose, p_amount_idr, v_mid,
    nullif(trim(coalesce(p_invoice_no, '')), ''),
    nullif(trim(coalesce(p_customer_name, '')), ''),
    nullif(trim(coalesce(p_phone, '')), ''),
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'midtrans_order_id', v_mid,
    'amount_idr', p_amount_idr,
    'purpose', v_purpose,
    'status', 'pending'
  );
end;
$$;

create or replace function public.attach_pos_payment_snap(
  p_midtrans_order_id text,
  p_snap_token text,
  p_redirect_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tid uuid := public.current_tenant_id();
begin
  if auth.uid() is not null then
    if v_tid is null then
      return jsonb_build_object('ok', false, 'error', 'Kode usaha belum terikat');
    end if;
    update public.pos_payments
       set midtrans_snap_token = p_snap_token,
           midtrans_redirect_url = p_redirect_url,
           updated_at = now()
     where midtrans_order_id = trim(p_midtrans_order_id)
       and status = 'pending'
       and tenant_id = v_tid;
  else
    update public.pos_payments
       set midtrans_snap_token = p_snap_token,
           midtrans_redirect_url = p_redirect_url,
           updated_at = now()
     where midtrans_order_id = trim(p_midtrans_order_id)
       and status = 'pending';
  end if;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Pembayaran POS tidak ditemukan');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.get_pos_payment(p_midtrans_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.pos_payments;
  v_tid uuid := public.current_tenant_id();
begin
  select * into v_row
  from public.pos_payments
  where midtrans_order_id = trim(p_midtrans_order_id);
  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'Tidak ada');
  end if;
  if v_tid is distinct from v_row.tenant_id and not public.is_platform_user() then
    return jsonb_build_object('ok', false, 'error', 'Bukan usaha Anda');
  end if;
  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'status', v_row.status,
    'amount_idr', v_row.amount_idr,
    'payment_type', v_row.payment_type,
    'midtrans_order_id', v_row.midtrans_order_id,
    'sale_id', v_row.sale_id,
    'purpose', v_row.purpose
  );
end;
$$;

create or replace function public.link_pos_payment_sale(
  p_midtrans_order_id text,
  p_sale_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Login kasir dulu');
  end if;
  update public.pos_payments
     set sale_id = p_sale_id, updated_at = now()
   where midtrans_order_id = trim(p_midtrans_order_id)
     and tenant_id = public.current_tenant_id()
     and status = 'paid';
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Pembayaran belum lunas / bukan usaha ini');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.fulfill_pos_payment(
  p_midtrans_order_id text,
  p_payment_type text default 'Midtrans',
  p_gross_amount bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.pos_payments;
  v_mid text := trim(coalesce(p_midtrans_order_id, ''));
begin
  if v_mid = '' or v_mid not like 'POS-%' then
    return jsonb_build_object('ok', false, 'error', 'order_id POS tidak valid');
  end if;

  select * into v_row from public.pos_payments where midtrans_order_id = v_mid;
  if v_row.id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found', 'error', 'POS payment tidak ada');
  end if;
  if v_row.status = 'paid' then
    return jsonb_build_object(
      'ok', true,
      'already', true,
      'id', v_row.id,
      'status', 'paid',
      'payment_type', v_row.payment_type
    );
  end if;
  if v_row.status <> 'pending' then
    return jsonb_build_object('ok', false, 'error', 'Status ' || v_row.status);
  end if;
  if p_gross_amount is not null and p_gross_amount <> v_row.amount_idr then
    return jsonb_build_object('ok', false, 'error', 'Nominal Midtrans tidak cocok');
  end if;

  update public.pos_payments
     set status = 'paid',
         payment_type = coalesce(nullif(trim(coalesce(p_payment_type, '')), ''), 'Midtrans'),
         paid_at = now(),
         updated_at = now()
   where id = v_row.id
     and status = 'pending';

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'status', 'paid',
    'payment_type', coalesce(nullif(trim(coalesce(p_payment_type, '')), ''), 'Midtrans'),
    'amount_idr', v_row.amount_idr,
    'purpose', v_row.purpose
  );
end;
$$;

create or replace function public.dev_fulfill_pos_payment(p_midtrans_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Login kasir dulu');
  end if;
  select midtrans_snap_token into v_token
  from public.pos_payments
  where midtrans_order_id = trim(p_midtrans_order_id)
    and tenant_id = public.current_tenant_id();
  if v_token is null or v_token not like 'DEV_%' then
    return jsonb_build_object(
      'ok', false,
      'error', 'Bayar uji POS hanya jika Midtrans belum di-set (token DEV_*)'
    );
  end if;
  return public.fulfill_pos_payment(trim(p_midtrans_order_id), 'DEV_MOCK', null);
end;
$$;

grant execute on function public.create_pos_payment(bigint, text, text, uuid, text, text, text)
  to authenticated;
grant execute on function public.attach_pos_payment_snap(text, text, text)
  to authenticated, service_role;
grant execute on function public.get_pos_payment(text) to authenticated;
grant execute on function public.link_pos_payment_sale(text, uuid) to authenticated;
grant execute on function public.dev_fulfill_pos_payment(text) to authenticated;
grant execute on function public.fulfill_pos_payment(text, text, bigint) to service_role;

comment on table public.pos_payments is
  'Snap Midtrans kasir / pelunasan. Bukan invoice Rekasa ke UMKM.';
