-- =============================================================================
-- QR Absensi berputar (layar Admin toko) untuk clock-in karyawan.
-- Payload: OBRATT|v1|<toko_id>|<token>
-- Token short-lived; issue baru menonaktifkan token aktif sebelumnya (anti-replay).
-- =============================================================================

create table if not exists public.attendance_qr_tokens (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null references public.toko_id (id),
  token text not null,
  expires_at timestamptz not null,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  constraint attendance_qr_tokens_token_uniq unique (token)
);

create index if not exists attendance_qr_tokens_toko_expires_idx
  on public.attendance_qr_tokens (toko_id, expires_at desc);

create index if not exists attendance_qr_tokens_token_idx
  on public.attendance_qr_tokens (token);

alter table public.attendance_logs
  add column if not exists qr_token_id uuid references public.attendance_qr_tokens (id);

comment on table public.attendance_qr_tokens is
  'Token QR absensi layar Admin; short-lived per toko.';
comment on column public.attendance_logs.qr_token_id is
  'Token QR yang divalidasi saat clock-in (opsional).';

alter table public.attendance_qr_tokens enable row level security;

-- Tidak ada policy langsung: akses hanya lewat RPC security definer.
revoke all on table public.attendance_qr_tokens from anon, authenticated;
grant select on table public.attendance_qr_tokens to service_role;

-- -----------------------------------------------------------------------------
-- Issue token (Admin / owner)
-- -----------------------------------------------------------------------------
create or replace function public.issue_attendance_qr_token(
  p_toko_id text,
  p_ttl_seconds integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_admin_toko text;
  v_ttl integer;
  v_token text;
  v_expires timestamptz;
  v_id uuid;
  v_payload text;
begin
  if v_uid is null then
    raise exception 'Login diperlukan untuk menampilkan QR absensi.';
  end if;

  if p_toko_id is null or length(trim(p_toko_id)) = 0 then
    raise exception 'toko_id wajib diisi.';
  end if;

  if not exists (select 1 from public.toko_id t where t.id = trim(p_toko_id)) then
    raise exception 'Toko % tidak ditemukan.', trim(p_toko_id);
  end if;

  select p.role, p.toko_id
    into v_role, v_admin_toko
  from public.profiles p
  where p.id = v_uid;

  if v_role is null then
    raise exception 'Hanya Admin yang boleh menampilkan QR absensi.';
  end if;

  -- Cabang hanya boleh issue untuk tokonya; pusat/owner boleh semua.
  if coalesce(v_admin_toko, '') not in ('PUSAT', 'CABANG-PUSAT')
     and coalesce(v_role, '') not in ('owner', 'admin_pusat')
     and coalesce(v_admin_toko, '') <> trim(p_toko_id) then
    raise exception 'QR absensi hanya untuk toko Anda (%).', v_admin_toko;
  end if;

  v_ttl := greatest(5, least(coalesce(p_ttl_seconds, 5), 120));

  -- Nonaktifkan token aktif sebelumnya (anti screenshot lama).
  update public.attendance_qr_tokens
     set expires_at = now()
   where toko_id = trim(p_toko_id)
     and expires_at > now();

  v_token := encode(gen_random_bytes(24), 'hex');
  v_expires := now() + make_interval(secs => v_ttl);

  insert into public.attendance_qr_tokens (toko_id, token, expires_at, created_by)
  values (trim(p_toko_id), v_token, v_expires, v_uid)
  returning id into v_id;

  v_payload := 'OBRATT|v1|' || trim(p_toko_id) || '|' || v_token;

  return jsonb_build_object(
    'id', v_id,
    'toko_id', trim(p_toko_id),
    'token', v_token,
    'payload', v_payload,
    'expires_at', v_expires,
    'ttl_seconds', v_ttl
  );
end;
$$;

revoke all on function public.issue_attendance_qr_token(text, integer) from public;
grant execute on function public.issue_attendance_qr_token(text, integer) to authenticated;

comment on function public.issue_attendance_qr_token(text, integer) is
  'Admin: buat token QR absensi berputar untuk toko.';

-- -----------------------------------------------------------------------------
-- Validate token (Karyawan clock-in)
-- -----------------------------------------------------------------------------
create or replace function public.validate_attendance_qr_token(
  p_payload text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_raw text := trim(coalesce(p_payload, ''));
  v_parts text[];
  v_toko text;
  v_token text;
  v_row public.attendance_qr_tokens%rowtype;
  v_karyawan_toko text;
begin
  if v_uid is null then
    raise exception 'Login karyawan diperlukan untuk scan QR absensi.';
  end if;

  if length(v_raw) = 0 then
    raise exception 'QR kosong / tidak terbaca.';
  end if;

  -- Format: OBRATT|v1|<toko_id>|<token>  ATAU token hex saja
  if position('|' in v_raw) > 0 then
    v_parts := string_to_array(v_raw, '|');
    if array_length(v_parts, 1) < 4
       or v_parts[1] <> 'OBRATT'
       or v_parts[2] <> 'v1' then
      raise exception 'Format QR absensi tidak dikenali. Scan QR di layar Admin toko.';
    end if;
    v_toko := trim(v_parts[3]);
    v_token := trim(v_parts[4]);
  else
    v_token := v_raw;
    v_toko := null;
  end if;

  if v_token is null or length(v_token) < 16 then
    raise exception 'Token QR tidak valid.';
  end if;

  select k.toko_id into v_karyawan_toko
  from public.karyawan k
  where k.id = v_uid
     or (k.email is not null and k.email = (auth.jwt() ->> 'email'))
  order by case when k.id = v_uid then 0 else 1 end
  limit 1;

  if v_karyawan_toko is null or length(trim(v_karyawan_toko)) = 0 then
    raise exception 'Data karyawan tidak ditemukan untuk akun ini.';
  end if;

  select * into v_row
  from public.attendance_qr_tokens t
  where t.token = v_token
  order by t.created_at desc
  limit 1;

  if not found then
    raise exception 'QR tidak dikenali. Pastikan scan QR Absensi di layar Admin.';
  end if;

  if v_row.expires_at <= now() then
    raise exception 'QR sudah kedaluwarsa. Minta Admin tampilkan QR terbaru.';
  end if;

  if v_toko is not null and v_toko <> v_row.toko_id then
    raise exception 'QR tidak cocok dengan toko pada kode.';
  end if;

  if trim(v_karyawan_toko) <> v_row.toko_id then
    raise exception 'QR milik toko % — akun Anda terdaftar di %. Scan QR toko Anda.',
      v_row.toko_id, trim(v_karyawan_toko);
  end if;

  return jsonb_build_object(
    'ok', true,
    'token_id', v_row.id,
    'toko_id', v_row.toko_id,
    'expires_at', v_row.expires_at
  );
end;
$$;

revoke all on function public.validate_attendance_qr_token(text) from public;
grant execute on function public.validate_attendance_qr_token(text) to authenticated;

comment on function public.validate_attendance_qr_token(text) is
  'Karyawan: validasi QR absensi Admin; harus cocok toko_id.';
