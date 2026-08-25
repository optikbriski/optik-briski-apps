-- #7: pengaduan reply loop + helpers for contribution/ops hygiene

alter table public.pengaduan
  add column if not exists balasan text,
  add column if not exists dibalas_at timestamptz,
  add column if not exists dibalas_oleh text,
  add column if not exists dibalas_oleh_user_id uuid;

comment on column public.pengaduan.balasan is
  'Balasan Admin/Owner ke karyawan; null = belum ditindak.';

-- Status: OPEN | IN_PROGRESS | DONE (teks bebas tetap ditoleransi)
create or replace function public.reply_pengaduan(
  p_id uuid,
  p_balasan text,
  p_status text default 'DONE'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := lower(coalesce(public.current_profile_role(), ''));
  v_toko text := public.current_profile_toko_id();
  v_row public.pengaduan%rowtype;
  v_status text := upper(trim(coalesce(p_status, 'DONE')));
  v_body text := trim(coalesce(p_balasan, ''));
  v_nama text;
  v_kary_uid uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if p_id is null or v_body = '' then
    return jsonb_build_object('ok', false, 'error', 'Balasan wajib diisi');
  end if;
  if v_status not in ('OPEN', 'IN_PROGRESS', 'DONE') then
    v_status := 'DONE';
  end if;

  if not (
    public.is_platform_user()
    or v_role in ('owner', 'admin_pusat', 'super_admin', 'admin_toko', 'kasir')
  ) then
    return jsonb_build_object('ok', false, 'error', 'Hanya staf Admin yang boleh membalas');
  end if;

  select * into v_row from public.pengaduan where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Pengaduan tidak ditemukan');
  end if;

  if v_row.tenant_id is not null
     and public.current_tenant_id() is not null
     and v_row.tenant_id is distinct from public.current_tenant_id() then
    return jsonb_build_object('ok', false, 'error', 'Tenant tidak cocok');
  end if;

  -- admin_toko / kasir: hanya cabang sendiri (PUSAT boleh semua)
  if v_role in ('admin_toko', 'kasir')
     and not public.is_platform_user()
     and v_role not in ('owner', 'admin_pusat', 'super_admin') then
    if v_toko is null
       or not public.same_store_toko(v_toko, coalesce(v_row.toko_id, '')) then
      return jsonb_build_object('ok', false, 'error', 'Beda cabang');
    end if;
  end if;

  select coalesce(nullif(trim(p.email), ''), 'Admin')
    into v_nama
  from public.profiles p
  where p.id = v_uid
  limit 1;
  v_nama := coalesce(v_nama, 'Admin');

  update public.pengaduan
  set
    balasan = v_body,
    status = v_status,
    dibalas_at = now(),
    dibalas_oleh = v_nama,
    dibalas_oleh_user_id = v_uid
  where id = p_id;

  -- Notifikasi in-app ke karyawan (id karyawan = auth.users.id)
  v_kary_uid := v_row.karyawan_id;
  if v_kary_uid is not null then
    begin
      insert into public.notifikasi (user_id, judul, isi, tipe)
      values (
        v_kary_uid,
        'Balasan pengaduan',
        left('Status ' || v_status || ': ' || v_body, 280),
        'ADMIN'
      );
    exception when others then
      null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', p_id,
    'status', v_status,
    'dibalas_oleh', v_nama
  );
end;
$$;

revoke all on function public.reply_pengaduan(uuid, text, text) from public;
grant execute on function public.reply_pengaduan(uuid, text, text) to authenticated;

comment on function public.reply_pengaduan(uuid, text, text) is
  'Admin membalas pengaduan karyawan + tulis notifikasi in-app.';
