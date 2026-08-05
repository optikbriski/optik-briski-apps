-- Seal hold stok: cancel pending bila Midtrans gagal + expire gabungan + cron 1 menit.

-- ---------------------------------------------------------------------------
-- 1) Cancel pending online order → lepas ONLINE_HOLD (via trigger status)
-- ---------------------------------------------------------------------------
create or replace function public.cancel_pending_online_order(
  p_online_order_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.online_orders%rowtype;
begin
  if p_online_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'order_id kosong');
  end if;

  select * into v_row
  from public.online_orders
  where id = p_online_order_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
  end if;

  if v_row.status <> 'pending_payment' then
    return jsonb_build_object(
      'ok', true,
      'already', true,
      'status', v_row.status
    );
  end if;

  update public.online_orders
  set
    status = 'cancelled',
    store_note = case
      when nullif(trim(coalesce(p_reason, '')), '') is null then store_note
      else left(
        trim(coalesce(store_note || E'\n', '') || 'Cancel: ' || trim(p_reason)),
        500
      )
    end,
    updated_at = now()
  where id = v_row.id;

  -- Safety: lepas hold bila trigger belum ada di lingkungan lama.
  begin
    perform public.release_reservation(
      'ONLINE_HOLD', 'online_order', v_row.id::text
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'ok', true,
    'cancelled', true,
    'online_order_id', v_row.id,
    'midtrans_order_id', v_row.midtrans_order_id
  );
end;
$$;

grant execute on function public.cancel_pending_online_order(uuid, text)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Expire gabungan (online + POS hold) — dipanggil UI / cron
-- ---------------------------------------------------------------------------
create or replace function public.expire_all_stale_stock_holds()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  n_online int := 0;
  n_pos int := 0;
begin
  begin
    n_online := public.expire_stale_online_orders();
  exception when undefined_function then
    n_online := 0;
  end;
  begin
    n_pos := public.expire_stale_pos_holds();
  exception when undefined_function then
    n_pos := 0;
  end;
  return jsonb_build_object(
    'ok', true,
    'expired_online_orders', n_online,
    'expired_pos_holds', n_pos
  );
end;
$$;

grant execute on function public.expire_all_stale_stock_holds()
  to anon, authenticated, service_role;

-- get detail Member: expire gabungan dulu
create or replace function public.get_online_order_for_member(
  p_phone text,
  p_online_order_id uuid
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
    and (
      phone_e164 = v_phone
      or phone_e164 = v_alt
      or public.wa_digits(phone_e164) = v_phone
    );

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Tidak ditemukan');
  end if;

  return jsonb_build_object(
    'ok', true,
    'order', to_jsonb(v_row)
  );
end;
$$;

grant execute on function public.get_online_order_for_member(text, uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Cron 1 menit (jika pg_cron tersedia)
-- ---------------------------------------------------------------------------
do $$
begin
  perform cron.unschedule('expire_stale_stock_holds');
exception when others then
  null;
end $$;

do $$
begin
  perform cron.schedule(
    'expire_stale_stock_holds',
    '* * * * *',
    $cron$ select public.expire_all_stale_stock_holds(); $cron$
  );
exception when others then
  -- Project tanpa pg_cron: UI/Edge tetap memanggil expire_all_stale_stock_holds.
  raise notice 'pg_cron tidak tersedia — skip schedule expire_stale_stock_holds';
end $$;
