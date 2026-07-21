-- Admin pusat hanya boleh issue QR untuk PUSAT / CABANG-PUSAT (bukan cabang lain).
create or replace function public.issue_attendance_qr_token(
  p_toko_id text,
  p_ttl_seconds integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
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
  v_is_pusat boolean;
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

  v_is_pusat := coalesce(v_admin_toko, '') in ('PUSAT', 'CABANG-PUSAT')
    or coalesce(v_role, '') in ('owner', 'admin_pusat');

  if v_is_pusat then
    if trim(p_toko_id) not in ('PUSAT', 'CABANG-PUSAT') then
      raise exception 'Admin pusat hanya menampilkan QR Absensi Pusat, bukan cabang.';
    end if;
  elsif coalesce(v_admin_toko, '') <> trim(p_toko_id) then
    raise exception 'QR absensi hanya untuk toko Anda (%).', v_admin_toko;
  end if;

  v_ttl := greatest(5, least(coalesce(p_ttl_seconds, 5), 120));

  update public.attendance_qr_tokens
     set expires_at = now()
   where toko_id = trim(p_toko_id)
     and expires_at > now();

  v_token := encode(extensions.gen_random_bytes(24), 'hex');
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
