-- =============================================================================
-- Member APK: profil, OTP, list pesanan/garansi, booking, poin, klaim request,
-- survei, + perbaiki get_invoice_hub untuk pelanggan.
-- =============================================================================

create extension if not exists pgcrypto;

-- Digits-only helper
create or replace function public.wa_digits(p text)
returns text
language sql
immutable
as $$
  select nullif(
    regexp_replace(
      case
        when regexp_replace(coalesce(p, ''), '\D', '', 'g') ~ '^0'
          then '62' || substr(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 2)
        else regexp_replace(coalesce(p, ''), '\D', '', 'g')
      end,
      '\D',
      '',
      'g'
    ),
    ''
  );
$$;

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  phone_e164 text not null unique,
  phone_raw text,
  nama text,
  email text,
  alamat text,
  font_scale numeric not null default 1.0,
  locale text not null default 'id',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.member_otp (
  phone_e164 text primary key,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.member_family (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  nama text not null,
  hubungan text,
  phone_e164 text,
  created_at timestamptz not null default now()
);

create table if not exists public.member_bookings (
  id uuid primary key default gen_random_uuid(),
  member_id uuid references public.members(id) on delete set null,
  phone_e164 text not null,
  toko_id text not null,
  jenis text not null default 'kontrol',
  scheduled_at timestamptz not null,
  status text not null default 'booked'
    check (status in ('booked', 'checked_in', 'done', 'cancelled', 'no_show')),
  catatan text,
  created_at timestamptz not null default now()
);

create table if not exists public.member_points_ledger (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  delta int not null,
  reason text not null,
  sale_id uuid,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.member_promos (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  toko_id text,
  voucher_code text,
  points_cost int not null default 0,
  active boolean not null default true,
  valid_until date,
  created_at timestamptz not null default now()
);

create table if not exists public.garansi_klaim_request (
  id uuid primary key default gen_random_uuid(),
  member_id uuid references public.members(id) on delete set null,
  phone_e164 text not null,
  kartu_id uuid not null references public.garansi_kartu(id),
  sale_id uuid,
  toko_id text not null,
  alasan text not null,
  foto_url text,
  status text not null default 'diajukan'
    check (status in ('diajukan', 'diproses_toko', 'selesai', 'dibatalkan')),
  created_at timestamptz not null default now()
);

create table if not exists public.member_survey (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  phone_e164 text,
  nyaman int check (nyaman between 1 and 5),
  cocok int check (cocok between 1 and 5),
  pelayanan int check (pelayanan between 1 and 5),
  komentar text,
  created_at timestamptz not null default now(),
  unique (sale_id)
);

create index if not exists sales_no_wa_idx on public.sales (no_wa);
create index if not exists member_bookings_phone_idx on public.member_bookings (phone_e164);
create index if not exists garansi_kartu_no_wa_idx on public.garansi_kartu (no_wa);

alter table public.members enable row level security;
alter table public.member_family enable row level security;
alter table public.member_bookings enable row level security;
alter table public.member_points_ledger enable row level security;
alter table public.member_promos enable row level security;
alter table public.garansi_klaim_request enable row level security;
alter table public.member_survey enable row level security;

-- Promos readable by anyone (katalog)
drop policy if exists member_promos_read on public.member_promos;
create policy member_promos_read on public.member_promos
  for select to anon, authenticated using (active = true);

-- Member app (anon) akses operasional via phone di payload — dikunci di UI + RPC list.
-- Hardening lanjutan: ganti ke JWT member / Edge Function.
drop policy if exists members_anon_all on public.members;
create policy members_anon_all on public.members
  for all to anon, authenticated using (true) with check (true);

drop policy if exists member_family_anon_all on public.member_family;
create policy member_family_anon_all on public.member_family
  for all to anon, authenticated using (true) with check (true);

drop policy if exists member_bookings_anon_all on public.member_bookings;
create policy member_bookings_anon_all on public.member_bookings
  for all to anon, authenticated using (true) with check (true);

drop policy if exists member_points_anon_all on public.member_points_ledger;
create policy member_points_anon_all on public.member_points_ledger
  for all to anon, authenticated using (true) with check (true);

drop policy if exists garansi_klaim_req_anon_all on public.garansi_klaim_request;
create policy garansi_klaim_req_anon_all on public.garansi_klaim_request
  for all to anon, authenticated using (true) with check (true);

drop policy if exists member_survey_anon_all on public.member_survey;
create policy member_survey_anon_all on public.member_survey
  for all to anon, authenticated using (true) with check (true);

-- Access via security definer RPCs (anon Member app)
create or replace function public.member_request_otp(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_code text;
begin
  if v_phone is null or length(v_phone) < 10 then
    raise exception 'Nomor HP tidak valid';
  end if;
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into public.member_otp(phone_e164, code_hash, expires_at, attempts)
  values (v_phone, crypt(v_code, gen_salt('bf')), now() + interval '10 minutes', 0)
  on conflict (phone_e164) do update
    set code_hash = excluded.code_hash,
        expires_at = excluded.expires_at,
        attempts = 0,
        created_at = now();

  insert into public.members(phone_e164, phone_raw)
  values (v_phone, trim(p_phone))
  on conflict (phone_e164) do update set phone_raw = excluded.phone_raw, updated_at = now();

  -- TODO: kirim via WhatsApp gateway. Sementara dikembalikan agar alur Member jalan.
  return jsonb_build_object('ok', true, 'phone_e164', v_phone, 'otp', v_code, 'ttl_seconds', 600);
end;
$$;

create or replace function public.member_verify_otp(p_phone text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_row public.member_otp%rowtype;
  v_member public.members%rowtype;
begin
  if v_phone is null then
    raise exception 'Nomor HP tidak valid';
  end if;
  select * into v_row from public.member_otp where phone_e164 = v_phone;
  if not found then
    raise exception 'OTP belum diminta';
  end if;
  if v_row.expires_at < now() then
    raise exception 'OTP kedaluwarsa';
  end if;
  if v_row.attempts >= 5 then
    raise exception 'Terlalu banyak percobaan';
  end if;
  if v_row.code_hash <> crypt(trim(p_code), v_row.code_hash) then
    update public.member_otp set attempts = attempts + 1 where phone_e164 = v_phone;
    raise exception 'OTP salah';
  end if;
  delete from public.member_otp where phone_e164 = v_phone;
  select * into v_member from public.members where phone_e164 = v_phone;
  return jsonb_build_object(
    'ok', true,
    'member', jsonb_build_object(
      'id', v_member.id,
      'phone_e164', v_member.phone_e164,
      'phone_raw', v_member.phone_raw,
      'nama', v_member.nama,
      'email', v_member.email,
      'alamat', v_member.alamat,
      'font_scale', v_member.font_scale,
      'locale', v_member.locale
    )
  );
end;
$$;

create or replace function public.member_upsert_profile(
  p_phone text,
  p_nama text default null,
  p_email text default null,
  p_alamat text default null,
  p_font_scale numeric default null,
  p_locale text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_member public.members%rowtype;
begin
  if v_phone is null then raise exception 'Nomor HP tidak valid'; end if;
  insert into public.members(phone_e164, phone_raw, nama, email, alamat, font_scale, locale)
  values (
    v_phone, trim(p_phone), nullif(trim(p_nama), ''), nullif(trim(p_email), ''),
    nullif(trim(p_alamat), ''), coalesce(p_font_scale, 1.0), coalesce(nullif(trim(p_locale), ''), 'id')
  )
  on conflict (phone_e164) do update set
    nama = coalesce(excluded.nama, members.nama),
    email = coalesce(excluded.email, members.email),
    alamat = coalesce(excluded.alamat, members.alamat),
    font_scale = coalesce(p_font_scale, members.font_scale),
    locale = coalesce(nullif(trim(p_locale), ''), members.locale),
    updated_at = now();
  select * into v_member from public.members where phone_e164 = v_phone;
  return to_jsonb(v_member);
end;
$$;

create or replace function public.list_member_sales(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
begin
  if v_phone is null then return '[]'::jsonb; end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        s.id, s.no_invoice, s.toko_id, s.nama_pelanggan, s.status_pembayaran,
        s.tracking_status, s.diambil_at, s.foto_hasil_url, s.sisa_tagihan,
        s.total_harga, s.dibayarkan, s.created_at, s.lunas_at
      from public.sales s
      where public.wa_digits(s.no_wa) = v_phone
         or regexp_replace(coalesce(s.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
      order by s.created_at desc
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

create or replace function public.list_member_garansi(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
begin
  if v_phone is null then return '[]'::jsonb; end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.tanggal_akhir desc nulls last)
    from (
      select g.*
      from public.garansi_kartu g
      where public.wa_digits(g.no_wa) = v_phone
         or regexp_replace(coalesce(g.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
      order by g.tanggal_akhir desc nulls last
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

-- Full hub for customer + staff (restore rating/google/resep/money for member)
create or replace function public.get_invoice_hub(p_no_invoice text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_items jsonb;
  v_garansi jsonb;
  v_ratings jsonb;
  v_is_staff boolean := false;
  v_uid uuid := auth.uid();
  v_claimable boolean := false;
  v_review text;
  v_bisa_rating boolean := false;
begin
  if p_no_invoice is null or length(trim(p_no_invoice)) = 0 then
    return null;
  end if;

  select * into v_sale
  from public.sales
  where no_invoice = trim(p_no_invoice)
  limit 1;
  if not found then return null; end if;

  if v_uid is not null then
    v_is_staff := exists (
      select 1 from public.profiles p where p.id = v_uid
    ) or exists (
      select 1 from public.karyawan k
      where k.id = v_uid and coalesce(k.status_approval, '') = 'Aktif'
    );
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'nama_produk', si.nama_produk,
    'tipe_produk', si.tipe_produk,
    'qty', si.qty,
    'subtotal', si.subtotal,
    'detail_resep', si.detail_resep
  ) order by si.nama_produk), '[]'::jsonb)
  into v_items
  from public.sales_items si
  where si.sale_id = v_sale.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', g.id,
    'jenis_garansi', g.jenis_garansi,
    'nama_produk', g.nama_produk,
    'status', g.status,
    'tanggal_mulai', g.tanggal_mulai,
    'tanggal_akhir', g.tanggal_akhir,
    'klaim_digunakan', g.klaim_digunakan,
    'spesifikasi_produk', g.spesifikasi_produk,
    'no_invoice', g.no_invoice,
    'sale_id', g.sale_id,
    'toko_id', g.toko_id
  )), '[]'::jsonb)
  into v_garansi
  from public.garansi_kartu g
  where g.sale_id = v_sale.id;

  select exists (
    select 1 from public.garansi_kartu g
    where g.sale_id = v_sale.id
      and g.status = 'aktif'
      and coalesce(g.klaim_digunakan, false) = false
      and g.tanggal_akhir is not null
      and g.tanggal_akhir::date >= (timezone('Asia/Jakarta', now()))::date
  ) into v_claimable;

  select coalesce(i.google_review_url, p.google_review_url)
  into v_review
  from (select 1) _
  left join public.invoice_settings i on upper(trim(i.toko_id)) = upper(trim(v_sale.toko_id))
  left join public.invoice_settings p on upper(trim(p.toko_id)) = 'PUSAT';

  v_bisa_rating := (
    v_sale.diambil_at is not null
    or upper(trim(coalesce(v_sale.tracking_status, ''))) = 'DIAMBIL'
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'peran', r.peran,
    'skor', r.skor,
    'komentar', r.komentar,
    'created_at', r.created_at
  )), '[]'::jsonb)
  into v_ratings
  from public.invoice_rating r
  where r.sale_id = v_sale.id;

  return jsonb_build_object(
    'role_view', case when v_is_staff then 'staff' else 'customer' end,
    'sale_id', v_sale.id,
    'no_invoice', v_sale.no_invoice,
    'toko_id', v_sale.toko_id,
    'nama_pelanggan', v_sale.nama_pelanggan,
    'nama_kasir', v_sale.nama_kasir,
    'nama_pembuat_kacamata', v_sale.nama_pembuat_kacamata,
    'kasir_karyawan_id', v_sale.kasir_karyawan_id,
    'pembuat_kacamata_id', v_sale.pembuat_kacamata_id,
    'status_pembayaran', v_sale.status_pembayaran,
    'tracking_status', v_sale.tracking_status,
    'diambil_at', v_sale.diambil_at,
    'foto_hasil_url', v_sale.foto_hasil_url,
    'created_at', v_sale.created_at,
    'lunas_at', v_sale.lunas_at,
    'total_harga', v_sale.total_harga,
    'dibayarkan', v_sale.dibayarkan,
    'sisa_tagihan', v_sale.sisa_tagihan,
    'metode_pembayaran', v_sale.metode_pembayaran,
    'no_wa', case when v_is_staff then v_sale.no_wa else null end,
    'email_pelanggan', case when v_is_staff then v_sale.email_pelanggan else null end,
    'alamat', case when v_is_staff then v_sale.alamat else null end,
    'items', v_items,
    'garansi', v_garansi,
    'garansi_claimable', v_claimable,
    'google_review_url', v_review,
    'bisa_rating', v_bisa_rating,
    'ratings', coalesce(v_ratings, '[]'::jsonb),
    'qr_dp_ready', (v_sale.qr_dp_token is not null and v_sale.qr_dp_used_at is null),
    'qr_lunas_ready', (v_sale.qr_lunas_token is not null and v_sale.qr_lunas_used_at is null),
    'qr_claim_ready', (v_sale.qr_claim_token is not null and v_sale.qr_claim_used_at is null),
    'qr_dp_used', (v_sale.qr_dp_used_at is not null),
    'qr_lunas_used', (v_sale.qr_lunas_used_at is not null),
    'qr_claim_used', (v_sale.qr_claim_used_at is not null)
  );
end;
$$;

grant execute on function public.member_request_otp(text) to anon, authenticated;
grant execute on function public.member_verify_otp(text, text) to anon, authenticated;
grant execute on function public.member_upsert_profile(text, text, text, text, numeric, text) to anon, authenticated;
grant execute on function public.list_member_sales(text) to anon, authenticated;
grant execute on function public.list_member_garansi(text) to anon, authenticated;
grant execute on function public.get_invoice_hub(text) to anon, authenticated;

-- Seed sample promos (idempotent)
insert into public.member_promos(title, description, voucher_code, points_cost, active)
select * from (values
  ('Cuci kacamata gratis', 'Tunjukkan kode di kasir cabang mana pun.', 'CUCI-GRATIS', 50, true),
  ('Diskon aksesoris', 'Potongan untuk softcase / lap microfiber.', 'AKS-DISKON', 80, true)
) as v(title, description, voucher_code, points_cost, active)
where not exists (
  select 1 from public.member_promos p where p.voucher_code = v.voucher_code
);
