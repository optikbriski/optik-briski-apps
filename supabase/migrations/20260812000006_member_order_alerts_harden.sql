-- Harden member_order_alerts: phone-scoped RPC only, optional online_order_id.

alter table public.member_order_alerts
  add column if not exists online_order_id uuid
    references public.online_orders (id) on delete set null;

create index if not exists member_order_alerts_online_order_idx
  on public.member_order_alerts (online_order_id)
  where online_order_id is not null;

-- Direct table access: RLS on, no policies → deny for anon/authenticated.
alter table public.member_order_alerts enable row level security;
revoke all on table public.member_order_alerts from anon, authenticated;
grant select, insert on table public.member_order_alerts to service_role;

-- Drop 5-arg overload so 6-arg (dengan default) jadi satu pintu masuk.
drop function if exists public.create_member_order_alert(text, text, text, text, text);
drop function if exists public.create_member_order_alert(text, text, text, text, text, uuid);

create or replace function public.create_member_order_alert(
  p_no_invoice text,
  p_phone text,
  p_title text,
  p_body text,
  p_kind text default 'status',
  p_online_order_id uuid default null
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
begin
  v_digits := public.wa_digits(p_phone);
  if v_digits is null or length(v_digits) < 8 then
    raise exception 'phone tidak valid';
  end if;
  if v_inv = '' and p_online_order_id is null then
    raise exception 'invoice atau online_order_id wajib';
  end if;

  insert into public.member_order_alerts (
    no_invoice, phone_digits, title, body, kind, online_order_id
  ) values (
    coalesce(nullif(v_inv, ''), coalesce(p_online_order_id::text, 'ONLINE')),
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

revoke all on function public.create_member_order_alert(text, text, text, text, text, uuid)
  from public;
grant execute on function public.create_member_order_alert(text, text, text, text, text, uuid)
  to anon, authenticated, service_role;

create or replace function public.list_member_order_alerts(
  p_phone text,
  p_after timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text;
  v_alt text;
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
      where a.phone_digits in (v_digits, v_alt)
        and (p_after is null or a.created_at > p_after)
      order by a.created_at desc
      limit 40
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_member_order_alerts(text, timestamptz) from public;
grant execute on function public.list_member_order_alerts(text, timestamptz)
  to anon, authenticated, service_role;

create or replace function public.list_member_order_alerts(p_phone text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.list_member_order_alerts(p_phone, null);
$$;

revoke all on function public.list_member_order_alerts(text) from public;
grant execute on function public.list_member_order_alerts(text)
  to anon, authenticated, service_role;

-- Online fulfillment: sertakan online_order_id di alert (deep link Member).
create or replace function public.update_online_order_fulfillment(
  p_order_id uuid,
  p_status text,
  p_courier_tracking text default null,
  p_store_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_staff_toko text;
  v_toko text;
  v_phone text;
  v_fulfill text;
  v_cur text;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_allowed boolean := false;
  v_invoice text;
  v_title text;
  v_body text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if p_order_id is null or v_status = '' then
    return jsonb_build_object('ok', false, 'error', 'Parameter tidak lengkap');
  end if;
  if v_status not in ('packing', 'ready', 'shipped', 'fulfilled', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'Status tidak valid');
  end if;

  select o.toko_id, o.phone_e164, o.fulfillment, o.status
    into v_toko, v_phone, v_fulfill, v_cur
  from public.online_orders o
  where o.id = p_order_id
  for update;

  if v_toko is null then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
  end if;

  select p.role, p.toko_id into v_role, v_staff_toko
  from public.profiles p
  where p.id = v_uid;

  if v_role is null then
    return jsonb_build_object('ok', false, 'error', 'Profil staf tidak ditemukan');
  end if;

  v_allowed := v_role in ('owner', 'admin_pusat', 'super_admin')
    or v_staff_toko = upper(trim(v_toko));

  if not coalesce(v_allowed, false) then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Tidak berwenang: order milik ' || v_toko || ', staf ' || coalesce(v_staff_toko, '-')
    );
  end if;

  if v_status = 'cancelled' and v_cur <> 'pending_payment' then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Batalkan hanya untuk pending bayar. Order lunas: proses refund/retur stok terpisah.'
    );
  end if;

  update public.online_orders
  set
    status = v_status,
    courier_tracking = coalesce(nullif(trim(p_courier_tracking), ''), courier_tracking),
    store_note = coalesce(nullif(trim(p_store_note), ''), store_note),
    updated_at = now()
  where id = p_order_id
    and (
      (v_status = 'cancelled' and status = 'pending_payment')
      or (v_status <> 'cancelled' and status in ('paid', 'packing', 'ready', 'shipped', 'fulfilled'))
    );

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Order belum lunas / tidak bisa diupdate');
  end if;

  update public.sales s
  set
    tracking_status = case v_status
      when 'ready' then 'SIAP_DIAMBIL'
      when 'shipped' then 'DIKIRIM'
      when 'fulfilled' then 'DIAMBIL'
      when 'packing' then 'DIPROSES_DI_CABANG'
      when 'cancelled' then tracking_status
      else tracking_status
    end,
    diambil_at = case
      when v_status = 'fulfilled' then coalesce(s.diambil_at, now())
      else s.diambil_at
    end
  from public.online_orders o
  where o.id = p_order_id
    and s.id = o.sale_id;

  select s.no_invoice into v_invoice
  from public.online_orders o
  left join public.sales s on s.id = o.sale_id
  where o.id = p_order_id;

  if v_phone is not null and v_status <> 'cancelled' then
    v_title := case v_status
      when 'packing' then 'Pesanan dikemas'
      when 'ready' then case when v_fulfill = 'delivery'
        then 'Pesanan siap dikirim' else 'Pesanan siap diambil' end
      when 'shipped' then 'Pesanan dalam pengiriman'
      when 'fulfilled' then 'Pesanan selesai'
      else 'Update pesanan online'
    end;
    v_body := case v_status
      when 'packing' then 'Cabang sedang menyiapkan pesanan online Anda.'
      when 'ready' then case when v_fulfill = 'delivery'
        then 'Barang siap — menunggu kurir / resi.'
        else 'Silakan ambil di cabang.' end
      when 'shipped' then coalesce(
        nullif(trim(p_courier_tracking), ''),
        'Kurir sudah membawa pesanan Anda.'
      )
      when 'fulfilled' then 'Terima kasih sudah belanja di Optik B. Riski.'
      else v_status
    end;
    begin
      perform public.create_member_order_alert(
        coalesce(v_invoice, ''),
        v_phone,
        v_title,
        v_body,
        'status',
        p_order_id
      );
    exception when others then
      null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', v_status,
    'toko_id', v_toko,
    'order_id', p_order_id,
    'no_invoice', v_invoice
  );
end;
$$;

grant execute on function public.update_online_order_fulfillment(uuid, text, text, text)
  to authenticated;
