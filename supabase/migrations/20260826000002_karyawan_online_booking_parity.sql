-- #6 Online + booking parity for Karyawan HP:
-- 1) RLS baca online_orders untuk staf hub / karyawan duty cabang
-- 2) karyawan_antrian_action online: packing|ready|fulfilled + sync sales + alert Member

drop policy if exists online_orders_read_staff on public.online_orders;
create policy online_orders_read_staff on public.online_orders
  for select to authenticated
  using (
    public.is_platform_user()
    or (
      tenant_id is not distinct from public.current_tenant_id()
      and (
        public.current_profile_role() in ('owner', 'admin_pusat', 'super_admin')
        or public.same_store_toko(public.current_profile_toko_id(), toko_id)
        or public.invoice_can_staff_hub(toko_id)
        or (
          public.current_karyawan_id() is not null
          and public.same_store_toko(
            (select k.toko_id from public.karyawan k where k.id = public.current_karyawan_id()),
            toko_id
          )
        )
      )
    )
  );

create or replace function public.karyawan_antrian_action(
  p_kind text,
  p_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_kid uuid;
  v_toko text;
  v_tenant uuid;
  v_aktif text;
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_action text := lower(trim(coalesce(p_action, '')));
  v_row_toko text;
  v_row_tenant uuid;
  v_fulfill text;
  v_status text;
  v_phone text;
  v_invoice text;
  v_title text;
  v_body text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if p_id is null or v_kind = '' or v_action = '' then
    return jsonb_build_object('ok', false, 'error', 'Parameter tidak lengkap');
  end if;

  v_kid := public.current_karyawan_id();
  if v_kid is null then
    return jsonb_build_object('ok', false, 'error', 'Akun karyawan tidak ditemukan');
  end if;

  select k.toko_id, k.tenant_id, lower(coalesce(k.status_approval, ''))
    into v_toko, v_tenant, v_aktif
  from public.karyawan k
  where k.id = v_kid
  limit 1;

  if v_toko is null then
    return jsonb_build_object('ok', false, 'error', 'Akun karyawan tidak ditemukan');
  end if;
  if v_aktif <> '' and v_aktif not in ('aktif', 'active', 'approved') then
    return jsonb_build_object('ok', false, 'error', 'Karyawan tidak aktif');
  end if;

  if not public.pos_duty_ok(v_kid, v_toko) then
    return jsonb_build_object(
      'ok', false,
      'error', 'Absen masuk dulu (shift OPEN) sebelum aksi antrian'
    );
  end if;

  if v_kind = 'booking' then
    if v_action not in ('checked_in', 'done', 'no_show') then
      return jsonb_build_object('ok', false, 'error', 'Aksi booking tidak valid');
    end if;
    select b.toko_id, b.tenant_id into v_row_toko, v_row_tenant
    from public.member_bookings b where b.id = p_id for update;
    if v_row_toko is null then
      return jsonb_build_object('ok', false, 'error', 'Booking tidak ditemukan');
    end if;
    if v_tenant is not null and v_row_tenant is not null and v_tenant <> v_row_tenant then
      return jsonb_build_object('ok', false, 'error', 'Tenant tidak cocok');
    end if;
    if not public.same_store_toko(v_toko, v_row_toko) then
      return jsonb_build_object('ok', false, 'error', 'Beda cabang');
    end if;
    update public.member_bookings set status = v_action where id = p_id;
    return jsonb_build_object('ok', true, 'status', v_action);
  end if;

  if v_kind = 'klaim' then
    if v_action <> 'diproses_toko' then
      return jsonb_build_object('ok', false, 'error', 'Aksi klaim tidak valid');
    end if;
    select r.toko_id, r.tenant_id into v_row_toko, v_row_tenant
    from public.garansi_klaim_request r where r.id = p_id for update;
    if v_row_toko is null then
      return jsonb_build_object('ok', false, 'error', 'Klaim tidak ditemukan');
    end if;
    if v_tenant is not null and v_row_tenant is not null and v_tenant <> v_row_tenant then
      return jsonb_build_object('ok', false, 'error', 'Tenant tidak cocok');
    end if;
    if not public.same_store_toko(v_toko, v_row_toko) then
      return jsonb_build_object('ok', false, 'error', 'Beda cabang');
    end if;
    update public.garansi_klaim_request
      set status = 'diproses_toko'
    where id = p_id;
    return jsonb_build_object('ok', true, 'status', 'diproses_toko');
  end if;

  if v_kind = 'online' then
    if v_action not in ('packing', 'ready', 'fulfilled') then
      return jsonb_build_object('ok', false, 'error', 'Aksi online tidak valid');
    end if;
    select o.toko_id, o.tenant_id, o.fulfillment, o.status, o.phone_e164
      into v_row_toko, v_row_tenant, v_fulfill, v_status, v_phone
    from public.online_orders o
    where o.id = p_id
    for update;
    if v_row_toko is null then
      return jsonb_build_object('ok', false, 'error', 'Order tidak ditemukan');
    end if;
    if v_tenant is not null and v_row_tenant is not null and v_tenant <> v_row_tenant then
      return jsonb_build_object('ok', false, 'error', 'Tenant tidak cocok');
    end if;
    if not public.same_store_toko(v_toko, v_row_toko) then
      return jsonb_build_object('ok', false, 'error', 'Beda cabang');
    end if;
    if lower(coalesce(v_fulfill, '')) <> 'pickup' then
      return jsonb_build_object('ok', false, 'error', 'Hanya order pickup');
    end if;

    if v_action = 'packing' and lower(coalesce(v_status, '')) not in ('paid', 'packing') then
      return jsonb_build_object('ok', false, 'error', 'Status order belum bisa dikemas');
    end if;
    if v_action = 'ready' and lower(coalesce(v_status, '')) not in ('paid', 'packing', 'ready') then
      return jsonb_build_object('ok', false, 'error', 'Status order belum bisa siap diambil');
    end if;
    if v_action = 'fulfilled' and lower(coalesce(v_status, '')) not in ('ready', 'fulfilled') then
      return jsonb_build_object('ok', false, 'error', 'Tandai siap diambil dulu');
    end if;

    update public.online_orders
      set status = v_action,
          updated_at = now()
    where id = p_id
      and status in ('paid', 'packing', 'ready', 'fulfilled');

    if not found then
      return jsonb_build_object('ok', false, 'error', 'Order belum lunas / tidak bisa diupdate');
    end if;

    -- Samakan board sales dengan Admin fulfill.
    update public.sales s
    set
      tracking_status = case v_action
        when 'packing' then 'DIPROSES_DI_CABANG'
        when 'ready' then 'SIAP_DIAMBIL'
        when 'fulfilled' then 'DIAMBIL'
        else tracking_status
      end,
      diambil_at = case
        when v_action = 'fulfilled' then coalesce(s.diambil_at, now())
        else s.diambil_at
      end
    from public.online_orders o
    where o.id = p_id
      and s.id = o.sale_id;

    select s.no_invoice into v_invoice
    from public.online_orders o
    left join public.sales s on s.id = o.sale_id
    where o.id = p_id;

    if v_phone is not null then
      v_title := case v_action
        when 'packing' then 'Pesanan dikemas'
        when 'ready' then 'Pesanan siap diambil'
        when 'fulfilled' then 'Pesanan selesai'
        else 'Update pesanan online'
      end;
      v_body := case v_action
        when 'packing' then 'Cabang sedang menyiapkan pesanan online Anda.'
        when 'ready' then 'Silakan ambil di cabang.'
        when 'fulfilled' then 'Terima kasih sudah belanja.'
        else v_action
      end;
      begin
        perform public.create_member_order_alert(
          coalesce(v_invoice, ''),
          v_phone,
          v_title,
          v_body,
          'status',
          p_id,
          coalesce(v_row_tenant, v_tenant)
        );
      exception when others then
        null;
      end;
    end if;

    return jsonb_build_object(
      'ok', true,
      'status', v_action,
      'order_id', p_id,
      'no_invoice', v_invoice
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'Jenis tidak dikenal');
end;
$$;

revoke all on function public.karyawan_antrian_action(text, uuid, text) from public;
grant execute on function public.karyawan_antrian_action(text, uuid, text) to authenticated;

comment on function public.karyawan_antrian_action(text, uuid, text) is
  'Antrian toko: booking/klaim/online. Online pickup: packing|ready|fulfilled + sync sales + alert.';
