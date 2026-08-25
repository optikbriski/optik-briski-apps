-- Karyawan lantai toko: aksi antrian (booking / klaim / online pickup)
-- tanpa butuh baris profiles Admin.

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
  v_toko text;
  v_tenant uuid;
  v_aktif text;
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_action text := lower(trim(coalesce(p_action, '')));
  v_row_toko text;
  v_row_tenant uuid;
  v_fulfill text;
  v_status text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if p_id is null or v_kind = '' or v_action = '' then
    return jsonb_build_object('ok', false, 'error', 'Parameter tidak lengkap');
  end if;

  select k.toko_id, k.tenant_id, lower(coalesce(k.status_approval, ''))
    into v_toko, v_tenant, v_aktif
  from public.karyawan k
  where k.id = v_uid
  limit 1;

  if v_toko is null then
    return jsonb_build_object('ok', false, 'error', 'Akun karyawan tidak ditemukan');
  end if;
  if v_aktif <> '' and v_aktif not in ('aktif', 'active') then
    return jsonb_build_object('ok', false, 'error', 'Karyawan tidak aktif');
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
    if v_action not in ('ready', 'fulfilled') then
      return jsonb_build_object('ok', false, 'error', 'Aksi online tidak valid');
    end if;
    select o.toko_id, o.tenant_id, o.fulfillment, o.status
      into v_row_toko, v_row_tenant, v_fulfill, v_status
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
    if v_action = 'ready' and lower(coalesce(v_status, '')) not in ('paid', 'packing', 'ready') then
      return jsonb_build_object('ok', false, 'error', 'Status order belum bisa siap diambil');
    end if;
    if v_action = 'fulfilled' and lower(coalesce(v_status, '')) not in ('ready', 'fulfilled') then
      return jsonb_build_object('ok', false, 'error', 'Tandai siap diambil dulu');
    end if;
    update public.online_orders
      set status = v_action,
          updated_at = now()
    where id = p_id;
    return jsonb_build_object('ok', true, 'status', v_action);
  end if;

  return jsonb_build_object('ok', false, 'error', 'Jenis tidak dikenal');
end;
$$;

revoke all on function public.karyawan_antrian_action(text, uuid, text) from public;
grant execute on function public.karyawan_antrian_action(text, uuid, text) to authenticated;

comment on function public.karyawan_antrian_action(text, uuid, text) is
  'Aksi inbox lantai toko Karyawan: booking / klaim / online pickup (same toko).';
