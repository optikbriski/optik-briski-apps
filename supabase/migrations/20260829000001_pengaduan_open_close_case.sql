-- Open case = IN_PROGRESS without a reply.
-- Close case = DONE and requires a tanggapan.

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
  v_judul text;
  v_isi text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if p_id is null then
    return jsonb_build_object('ok', false, 'error', 'Pengaduan tidak ditemukan');
  end if;
  if v_status not in ('OPEN', 'IN_PROGRESS', 'DONE') then
    v_status := 'DONE';
  end if;
  if v_status = 'DONE' and v_body = '' then
    return jsonb_build_object('ok', false, 'error', 'Balasan wajib diisi');
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

  if v_status = 'IN_PROGRESS' then
    update public.pengaduan
    set
      status = 'IN_PROGRESS',
      balasan = case when v_body = '' then balasan else v_body end,
      dibalas_at = case when v_body = '' then dibalas_at else now() end,
      dibalas_oleh = case when v_body = '' then dibalas_oleh else v_nama end,
      dibalas_oleh_user_id = case
        when v_body = '' then dibalas_oleh_user_id
        else v_uid
      end
    where id = p_id;
    v_judul := 'Pengaduan sedang diusut';
    v_isi := case
      when v_body = '' then 'Pusat sedang menindaklanjuti laporan Anda.'
      else left('Status IN_PROGRESS: ' || v_body, 280)
    end;
  else
    update public.pengaduan
    set
      balasan = v_body,
      status = v_status,
      dibalas_at = now(),
      dibalas_oleh = v_nama,
      dibalas_oleh_user_id = v_uid
    where id = p_id;
    v_judul := 'Balasan pengaduan';
    v_isi := left('Status ' || v_status || ': ' || v_body, 280);
  end if;

  v_kary_uid := v_row.karyawan_id;
  if v_kary_uid is not null then
    begin
      insert into public.notifikasi (user_id, judul, isi, tipe)
      values (v_kary_uid, v_judul, v_isi, 'PENGADUAN');
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

comment on function public.reply_pengaduan(uuid, text, text) is
  'Admin: IN_PROGRESS = buka kasus (balasan opsional); DONE = tutup kasus (balasan wajib).';
