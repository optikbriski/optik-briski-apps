-- Isolasi cabang: order cabang A tidak boleh ke cabang B / Pusat.

-- 1) Paksa toko_id uppercase + tolak PUSAT sebagai cabang pemenuhan online
create or replace function public.trg_online_orders_branch_guard()
returns trigger
language plpgsql
as $$
declare
  v_toko text := upper(trim(coalesce(NEW.toko_id, '')));
begin
  if v_toko = '' then
    raise exception 'toko_id pesanan online wajib';
  end if;
  if v_toko in ('PUSAT', 'CABANG-PUSAT') then
    raise exception 'Pesanan online tidak boleh ke Pusat — pilih cabang';
  end if;
  if not exists (
    select 1 from public.toko_id t where upper(trim(t.id)) = v_toko
  ) then
    raise exception 'Cabang pemenuhan tidak valid: %', v_toko;
  end if;
  NEW.toko_id := v_toko;
  return NEW;
end;
$$;

drop trigger if exists trg_online_orders_branch_guard on public.online_orders;
create trigger trg_online_orders_branch_guard
  before insert or update of toko_id on public.online_orders
  for each row
  execute function public.trg_online_orders_branch_guard();

-- 2) update fulfillment: wajib auth + hanya cabang sendiri / role pusat
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
  v_status text := lower(trim(coalesce(p_status, '')));
  v_toko text;
  v_allowed boolean;
  v_phone text;
  v_invoice text;
  v_fulfill text;
  v_title text;
  v_body text;
  v_uid uuid := auth.uid();
  v_role text;
  v_staff_toko text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Login staf wajib');
  end if;

  if v_status not in ('packing', 'ready', 'shipped', 'fulfilled', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'Status tidak valid');
  end if;

  select toko_id, phone_e164, fulfillment
    into v_toko, v_phone, v_fulfill
  from public.online_orders
  where id = p_order_id;
  if v_toko is null then
    return jsonb_build_object('ok', false, 'error', 'Order tidak ada');
  end if;

  select lower(coalesce(p.role, '')), upper(trim(coalesce(p.toko_id, '')))
    into v_role, v_staff_toko
  from public.profiles p
  where p.id = v_uid;

  if v_role is null then
    return jsonb_build_object('ok', false, 'error', 'Profil staf tidak ditemukan');
  end if;

  -- Hanya role pusat yang boleh proses order cabang lain.
  v_allowed := v_role in ('owner', 'admin_pusat', 'super_admin')
    or v_staff_toko = upper(trim(v_toko));

  if not coalesce(v_allowed, false) then
    return jsonb_build_object(
      'ok', false,
      'error',
      'Tidak berwenang: order milik ' || v_toko || ', staf ' || coalesce(v_staff_toko, '-')
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
      (v_status = 'cancelled' and status in ('pending_payment', 'paid', 'packing', 'ready'))
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

  if v_invoice is not null and v_phone is not null and v_status <> 'cancelled' then
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
        v_invoice, v_phone, v_title, v_body, 'status'
      );
    exception when others then
      null;
    end;
  end if;

  return jsonb_build_object('ok', true, 'status', v_status, 'toko_id', v_toko);
end;
$$;

grant execute on function public.update_online_order_fulfillment(uuid, text, text, text)
  to authenticated;

-- 3) RLS baca/tulis: role pusat ATAU toko sama (sudah ada — perketat komentar via recreate)
drop policy if exists online_orders_read_staff on public.online_orders;
create policy online_orders_read_staff on public.online_orders
  for select to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
          or upper(trim(p.toko_id)) = upper(trim(online_orders.toko_id))
        )
    )
  );

drop policy if exists online_orders_write_staff on public.online_orders;
create policy online_orders_write_staff on public.online_orders
  for update to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
          or upper(trim(p.toko_id)) = upper(trim(online_orders.toko_id))
        )
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (
          lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
          or upper(trim(p.toko_id)) = upper(trim(online_orders.toko_id))
        )
    )
  );
