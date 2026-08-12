-- =============================================================================
-- Member Rating: phone-scoped list + submit ownership check
-- - list_member_ratings(p_phone): pending + history for that member only
-- - submit_invoice_rating(..., p_phone): reject wrong-member invoice
-- =============================================================================

create or replace function public.list_member_ratings(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
begin
  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;

  v_alt := case
    when v_phone like '62%' then '0' || substr(v_phone, 3)
    else v_phone
  end;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.diambil_at desc nulls last, x.created_at desc)
    from (
      select
        s.id as sale_id,
        s.no_invoice,
        s.toko_id,
        s.nama_pelanggan,
        s.nama_kasir,
        s.nama_pembuat_kacamata,
        s.kasir_karyawan_id,
        s.pembuat_kacamata_id,
        s.tracking_status,
        s.diambil_at,
        s.created_at,
        (
          s.diambil_at is not null
          or upper(trim(coalesce(s.tracking_status, ''))) = 'DIAMBIL'
        ) as bisa_rating,
        (
          select jsonb_build_object(
            'peran', r.peran,
            'skor', r.skor,
            'komentar', r.komentar,
            'nama_karyawan', r.nama_karyawan,
            'created_at', r.created_at
          )
          from public.invoice_rating r
          where r.sale_id = s.id and r.peran = 'kasir'
          limit 1
        ) as rating_kasir,
        (
          select jsonb_build_object(
            'peran', r.peran,
            'skor', r.skor,
            'komentar', r.komentar,
            'nama_karyawan', r.nama_karyawan,
            'created_at', r.created_at
          )
          from public.invoice_rating r
          where r.sale_id = s.id and r.peran = 'pembuat'
          limit 1
        ) as rating_pembuat,
        exists (
          select 1 from public.invoice_rating r
          where r.sale_id = s.id and r.peran = 'kasir'
        ) as has_rating_kasir,
        exists (
          select 1 from public.invoice_rating r
          where r.sale_id = s.id and r.peran = 'pembuat'
        ) as has_rating_pembuat,
        (
          coalesce(nullif(trim(s.nama_kasir), ''), '') <> ''
          or s.kasir_karyawan_id is not null
        ) as kasir_assigned,
        (
          coalesce(nullif(trim(s.nama_pembuat_kacamata), ''), '') <> ''
          or s.pembuat_kacamata_id is not null
        ) as pembuat_assigned
      from public.sales s
      where public.wa_digits(s.no_wa) = v_phone
         or regexp_replace(coalesce(s.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
      order by s.diambil_at desc nulls last, s.created_at desc
      limit 80
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_member_ratings(text) from public;
grant execute on function public.list_member_ratings(text) to anon, authenticated;

comment on function public.list_member_ratings(text) is
  'Daftar nota Member (phone-scoped) + status rating kasir/pembuat untuk APK Member.';

-- Submit: wajib cocok nomor HP bila p_phone diisi (Member selalu mengirim).
create or replace function public.submit_invoice_rating(
  p_no_invoice text,
  p_peran text,
  p_skor int,
  p_komentar text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_kid uuid;
  v_nama text;
  v_row public.invoice_rating%rowtype;
  v_uid uuid := auth.uid();
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_owner boolean := false;
begin
  if v_uid is not null and (
    exists (select 1 from public.profiles p where p.id = v_uid)
    or exists (
      select 1 from public.karyawan k
      where k.id = v_uid and coalesce(k.status_approval, '') = 'Aktif'
    )
  ) then
    raise exception 'Karyawan/admin tidak boleh mengisi rating. Minta pelanggan scan QR dari HP mereka.';
  end if;

  if p_peran not in ('kasir', 'pembuat') then
    raise exception 'Peran tidak valid';
  end if;
  if p_skor is null or p_skor < 1 or p_skor > 5 then
    raise exception 'Skor harus 1–5';
  end if;

  select * into v_sale
  from public.sales
  where no_invoice = trim(p_no_invoice)
  limit 1;

  if not found then
    raise exception 'Invoice tidak ditemukan';
  end if;

  -- Member app: phone wajib cocok dengan pemilik nota.
  if v_phone is not null then
    v_alt := case
      when v_phone like '62%' then '0' || substr(v_phone, 3)
      else v_phone
    end;
    v_owner := (
      public.wa_digits(v_sale.no_wa) = v_phone
      or regexp_replace(coalesce(v_sale.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
    );
    if not v_owner then
      raise exception 'Invoice ini bukan milik nomor HP Anda';
    end if;
  end if;

  if v_sale.diambil_at is null
     and upper(trim(coalesce(v_sale.tracking_status, ''))) <> 'DIAMBIL'
  then
    raise exception 'Rating hanya setelah kacamata diambil customer';
  end if;

  if p_peran = 'kasir' then
    v_kid := v_sale.kasir_karyawan_id;
    v_nama := v_sale.nama_kasir;
  else
    v_kid := v_sale.pembuat_kacamata_id;
    v_nama := v_sale.nama_pembuat_kacamata;
  end if;

  if v_kid is null and (v_nama is null or length(trim(v_nama)) = 0) then
    raise exception 'Karyawan untuk peran ini belum ditetapkan di transaksi';
  end if;

  insert into public.invoice_rating (
    sale_id, no_invoice, peran, karyawan_id, nama_karyawan, skor, komentar
  ) values (
    v_sale.id, v_sale.no_invoice, p_peran, v_kid, v_nama, p_skor,
    nullif(trim(p_komentar), '')
  )
  on conflict (sale_id, peran) do nothing
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Rating untuk peran ini sudah pernah diisi';
  end if;

  return to_jsonb(v_row);
end;
$$;

revoke all on function public.submit_invoice_rating(text, text, int, text, text) from public;
grant execute on function public.submit_invoice_rating(text, text, int, text, text) to anon, authenticated;

-- Keep 4-arg overload for older clients / training stubs.
create or replace function public.submit_invoice_rating(
  p_no_invoice text,
  p_peran text,
  p_skor int,
  p_komentar text default null
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.submit_invoice_rating(p_no_invoice, p_peran, p_skor, p_komentar, null);
$$;

revoke all on function public.submit_invoice_rating(text, text, int, text) from public;
grant execute on function public.submit_invoice_rating(text, text, int, text) to anon, authenticated;

-- Harden RLS: anon tidak select/insert langsung (hanya via RPC security definer).
drop policy if exists invoice_rating_anon_insert on public.invoice_rating;
drop policy if exists invoice_rating_anon_select on public.invoice_rating;

drop policy if exists invoice_rating_auth_all on public.invoice_rating;
create policy invoice_rating_auth_all on public.invoice_rating
  for all to authenticated
  using (true)
  with check (true);
