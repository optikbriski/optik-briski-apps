-- #3 jadwal decide → notifikasi
-- #1 fondasi: token push + broadcast notifikasi ke staf cabang

alter table public.pengaduan
  add column if not exists balasan text; -- no-op if already from 00003

create table if not exists public.karyawan_push_tokens (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null,
  platform text not null default 'unknown',
  updated_at timestamptz not null default now(),
  tenant_id uuid,
  unique (karyawan_id, token)
);

create index if not exists karyawan_push_tokens_user_idx
  on public.karyawan_push_tokens (user_id);

alter table public.karyawan_push_tokens enable row level security;

drop policy if exists karyawan_push_tokens_own on public.karyawan_push_tokens;
create policy karyawan_push_tokens_own on public.karyawan_push_tokens
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace function public.upsert_karyawan_push_token(
  p_token text,
  p_platform text default 'unknown'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_kid uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if nullif(trim(p_token), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Token kosong');
  end if;

  v_kid := public.current_karyawan_id();
  if v_kid is null then
    return jsonb_build_object('ok', false, 'error', 'Bukan akun karyawan');
  end if;

  insert into public.karyawan_push_tokens (
    karyawan_id, user_id, token, platform, updated_at, tenant_id
  )
  values (
    v_kid,
    v_uid,
    trim(p_token),
    coalesce(nullif(trim(p_platform), ''), 'unknown'),
    now(),
    public.current_tenant_id()
  )
  on conflict (karyawan_id, token) do update
    set platform = excluded.platform,
        updated_at = now(),
        user_id = excluded.user_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.upsert_karyawan_push_token(text, text) from public;
grant execute on function public.upsert_karyawan_push_token(text, text) to authenticated;

-- Notifikasi in-app ke semua karyawan aktif cabang (fondasi push / pengingat).
create or replace function public.notify_toko_karyawan(
  p_toko text,
  p_judul text,
  p_isi text,
  p_tipe text default 'INFO'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int := 0;
begin
  if nullif(trim(p_toko), '') is null then
    return 0;
  end if;
  insert into public.notifikasi (user_id, judul, isi, tipe)
  select k.id, left(coalesce(p_judul, 'Update toko'), 120),
         left(coalesce(p_isi, ''), 400),
         coalesce(nullif(trim(p_tipe), ''), 'INFO')
  from public.karyawan k
  where public.same_store_toko(k.toko_id, p_toko)
    and lower(coalesce(k.status_approval, '')) in ('aktif', 'active', 'approved')
    and exists (select 1 from auth.users u where u.id = k.id);
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.notify_toko_karyawan(text, text, text, text) from public;
grant execute on function public.notify_toko_karyawan(text, text, text, text)
  to authenticated, service_role;

-- Patch decide_jadwal_pengajuan: kirim notifikasi ke pemohon
create or replace function public.decide_jadwal_pengajuan(
  p_pengajuan_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.jadwal_pengajuan%rowtype;
  v_status text;
  v_title text;
  v_body text;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  select * into v_j
  from public.jadwal_pengajuan
  where id = p_pengajuan_id
    and status = 'PENDING';
  if v_j.id is null then
    raise exception 'Pengajuan tidak ditemukan / sudah diproses.';
  end if;

  if public.jadwal_is_self_karyawan(v_j.karyawan_id)
     and not public.is_platform_user() then
    raise exception 'Tidak boleh menyetujui atau menolak pengajuan sendiri.'
      using errcode = '42501';
  end if;

  if not public.jadwal_pengajuan_case_ok(v_j.toko_id, v_j.karyawan_id) then
    raise exception 'Hanya admin toko/cabang yang berhak memutus pengajuan.'
      using errcode = '42501';
  end if;

  v_status := case when p_approve then 'APPROVED' else 'REJECTED' end;

  update public.jadwal_pengajuan set
    status = v_status,
    reviewer_note = p_note,
    reviewed_at = now()
  where id = p_pengajuan_id
    and status = 'PENDING';

  if not found then
    raise exception 'Pengajuan tidak ditemukan / sudah diproses.';
  end if;

  v_title := case when p_approve
    then 'Pengajuan disetujui'
    else 'Pengajuan ditolak' end;
  v_body := trim(both from concat_ws(
    ' · ',
    coalesce(v_j.tipe, 'JADWAL'),
    coalesce(v_j.tanggal::text, ''),
    nullif(trim(coalesce(p_note, '')), '')
  ));

  begin
    insert into public.notifikasi (user_id, judul, isi, tipe)
    values (
      v_j.karyawan_id,
      v_title,
      left(v_body, 280),
      'SHIFT'
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'ok', true,
    'id', p_pengajuan_id,
    'status', v_status,
    'tipe', v_j.tipe
  );
end;
$$;

comment on function public.decide_jadwal_pengajuan(uuid, boolean, text) is
  'Admin memutus ijin + notifikasi in-app ke pemohon.';

-- Balasan pengaduan: tipe PENGADUAN agar deep-link jelas
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

  v_kary_uid := v_row.karyawan_id;
  if v_kary_uid is not null then
    begin
      insert into public.notifikasi (user_id, judul, isi, tipe)
      values (
        v_kary_uid,
        'Balasan pengaduan',
        left('Status ' || v_status || ': ' || v_body, 280),
        'PENGADUAN'
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
