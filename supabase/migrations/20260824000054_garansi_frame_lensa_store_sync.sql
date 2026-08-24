-- =============================================================================
-- 000054 — Garansi frame & lensa: tenant wajib, window 7 hari, toko sama.
-- Apply di SQL Editor live SETELAH 000053. Idempotent.
--
-- Celah saat toko jalan:
-- - list/submit default UUID Optik di repo (live sudah fail-closed; kunci ulang)
-- - list expire pakai tanggal_akhir mentah → kartu "aktif" setelah hari ke-7
-- - get_invoice_hub garansi_claimable tanpa hard-cap mulai+7
-- - pengajuan Member (diajukan) tidak tertutup setelah Admin putuskan klaim
-- - cabang kunjungan PUSAT exact ≠ CABANG-PUSAT
-- =============================================================================

create or replace function public.garansi_kartu_masih_klaim(g public.garansi_kartu)
returns boolean
language sql
stable
set search_path = public
as $$
  select
    g.status = 'aktif'
    and coalesce(g.klaim_digunakan, false) = false
    and coalesce(
      (timezone('Asia/Jakarta', g.diambil_at))::date,
      g.tanggal_mulai
    ) is not null
    and least(
      coalesce(
        g.tanggal_akhir,
        coalesce(
          (timezone('Asia/Jakarta', g.diambil_at))::date,
          g.tanggal_mulai
        ) + 7
      ),
      coalesce(
        (timezone('Asia/Jakarta', g.diambil_at))::date,
        g.tanggal_mulai
      ) + 7
    ) >= (timezone('Asia/Jakarta', now()))::date;
$$;

comment on function public.garansi_kartu_masih_klaim(public.garansi_kartu) is
  'Window klaim inklusif hari 0..7 Jakarta. Hard-cap mulai+7.';

create or replace function public.list_member_garansi(
  p_phone text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_today date := (timezone('Asia/Jakarta', now()))::date;
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null then return '[]'::jsonb; end if;
  v_alt := case
    when v_phone like '62%' then '0' || substr(v_phone, 3)
    else v_phone
  end;

  update public.garansi_kartu g
     set status = 'habis'
   where g.tenant_id = v_tenant
     and coalesce(g.klaim_digunakan, false) = false
     and g.status = 'aktif'
     and (
       public.wa_digits(g.no_wa) = v_phone
       or regexp_replace(coalesce(g.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
     )
     and coalesce(
       (timezone('Asia/Jakarta', g.diambil_at))::date,
       g.tanggal_mulai
     ) + 7 < v_today;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.tanggal_akhir desc nulls last)
    from (
      select g.*
      from public.garansi_kartu g
      where g.tenant_id = v_tenant
        and (
          public.wa_digits(g.no_wa) = v_phone
          or regexp_replace(coalesce(g.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
        )
      order by g.tanggal_akhir desc nulls last
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_member_garansi(text, uuid) from public;
grant execute on function public.list_member_garansi(text, uuid)
  to anon, authenticated;

create or replace function public.list_member_claim_requests(
  p_phone text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_tenant uuid := public.require_member_tenant(p_tenant_id);
begin
  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select r.*
      from public.garansi_klaim_request r
      where public.wa_digits(r.phone_e164) = v_phone
        and (
          r.tenant_id = v_tenant
          or exists (
            select 1 from public.garansi_kartu g
            where g.id = r.kartu_id and g.tenant_id = v_tenant
          )
          or exists (
            select 1 from public.toko_id t
            where public.same_store_toko(t.id, r.toko_id)
              and t.tenant_id = v_tenant
          )
        )
      order by r.created_at desc
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_member_claim_requests(text, uuid) from public;
grant execute on function public.list_member_claim_requests(text, uuid)
  to anon, authenticated;

create or replace function public.submit_member_garansi_klaim(
  p_phone text,
  p_kartu_id uuid,
  p_toko_id text,
  p_alasan text,
  p_jadwal_kunjungan timestamptz,
  p_sale_id uuid default null,
  p_member_id uuid default null,
  p_foto_url text default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_kartu public.garansi_kartu%rowtype;
  v_alasan text := trim(coalesce(p_alasan, ''));
  v_toko text := trim(coalesce(p_toko_id, ''));
  v_row public.garansi_klaim_request%rowtype;
  v_today date := (timezone('Asia/Jakarta', now()))::date;
  v_start date;
  v_end date;
  v_tenant uuid;
begin
  v_tenant := public.require_member_tenant(p_tenant_id);

  if v_phone is null or length(v_phone) < 8 then
    raise exception 'Nomor HP tidak valid';
  end if;
  if p_kartu_id is null then
    raise exception 'Kartu garansi wajib dipilih';
  end if;
  if v_toko = '' then
    raise exception 'Cabang kunjungan wajib dipilih';
  end if;
  if not exists (
    select 1 from public.toko_id t
    where public.same_store_toko(t.id, v_toko)
      and t.tenant_id = v_tenant
  ) then
    raise exception 'Cabang bukan milik usaha ini';
  end if;
  if v_alasan = '' then
    raise exception 'Alasan / keluhan wajib diisi';
  end if;
  if p_jadwal_kunjungan is null then
    raise exception 'Jadwal kunjungan wajib diisi';
  end if;
  if coalesce(trim(p_foto_url), '') = '' then
    raise exception 'Foto kondisi barang wajib diunggah';
  end if;

  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;

  select * into v_kartu
  from public.garansi_kartu g
  where g.id = p_kartu_id
    and g.tenant_id = v_tenant
  limit 1;
  if not found then
    raise exception 'Kartu garansi tidak ditemukan';
  end if;

  if not (
    public.wa_digits(v_kartu.no_wa) = v_phone
    or regexp_replace(coalesce(v_kartu.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
  ) then
    raise exception 'Kartu garansi tidak milik nomor ini';
  end if;

  if coalesce(v_kartu.status, '') = 'menunggu_ambil' then
    raise exception 'Garansi belum aktif — ambil barang di toko dulu';
  end if;
  if coalesce(v_kartu.klaim_digunakan, false)
     or coalesce(v_kartu.status, '') = 'diklaim' then
    raise exception 'Klaim untuk transaksi ini sudah dipakai (maks. 1×)';
  end if;
  if coalesce(v_kartu.status, '') = 'batal' then
    raise exception 'Garansi dibatalkan — tidak bisa klaim';
  end if;
  if coalesce(v_kartu.status, '') = 'habis' then
    raise exception 'Garansi mati — lebih dari 7 hari sejak diambil';
  end if;
  if coalesce(v_kartu.status, '') <> 'aktif' then
    raise exception 'Garansi tidak aktif — ambil barang di toko dulu atau masa sudah habis';
  end if;

  v_start := coalesce(
    (timezone('Asia/Jakarta', v_kartu.diambil_at))::date,
    v_kartu.tanggal_mulai
  );
  if v_start is null then
    raise exception 'Garansi belum aktif — ambil barang di toko dulu';
  end if;

  v_end := least(coalesce(v_kartu.tanggal_akhir, v_start + 7), v_start + 7);

  if v_today > v_end then
    update public.garansi_kartu
       set status = 'habis'
     where id = v_kartu.id
       and status = 'aktif'
       and coalesce(klaim_digunakan, false) = false;
    raise exception 'Garansi mati — lebih dari 7 hari sejak diambil';
  end if;

  if (timezone('Asia/Jakarta', p_jadwal_kunjungan))::date > v_end then
    raise exception 'Jadwal kunjungan di luar masa garansi (maks. 7 hari sejak diambil)';
  end if;

  if exists (
    select 1
    from public.garansi_klaim_request r
    where r.kartu_id = p_kartu_id
      and r.status in ('diajukan', 'diproses_toko')
      and (r.tenant_id is null or r.tenant_id = v_tenant)
  ) then
    raise exception 'Pengajuan untuk kartu ini masih terbuka';
  end if;

  insert into public.garansi_klaim_request (
    phone_e164,
    member_id,
    kartu_id,
    sale_id,
    toko_id,
    alasan,
    foto_url,
    jadwal_kunjungan,
    status,
    tenant_id
  ) values (
    v_phone,
    p_member_id,
    p_kartu_id,
    coalesce(p_sale_id, v_kartu.sale_id),
    v_toko,
    v_alasan,
    trim(p_foto_url),
    p_jadwal_kunjungan,
    'diajukan',
    v_tenant
  )
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

revoke all on function public.submit_member_garansi_klaim(
  text, uuid, text, text, timestamptz, uuid, uuid, text, uuid
) from public;
grant execute on function public.submit_member_garansi_klaim(
  text, uuid, text, text, timestamptz, uuid, uuid, text, uuid
) to anon, authenticated;

create or replace function public.trg_close_garansi_klaim_requests()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.garansi_klaim_request
     set status = 'selesai'
   where sale_id = new.sale_id
     and status in ('diajukan', 'diproses_toko');
  return new;
end;
$$;

drop trigger if exists trg_close_garansi_klaim_requests on public.garansi_klaim;
create trigger trg_close_garansi_klaim_requests
  after insert on public.garansi_klaim
  for each row
  execute function public.trg_close_garansi_klaim_requests();

create or replace function public.get_invoice_hub(
  p_no_invoice text,
  p_phone text default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sale public.sales%rowtype;
  v_items jsonb;
  v_garansi jsonb;
  v_ratings jsonb;
  v_is_staff boolean := false;
  v_can_mint boolean := false;
  v_uid uuid := auth.uid();
  v_claimable boolean := false;
  v_review text;
  v_bisa_rating boolean := false;
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
  v_owner boolean := false;
  v_is_dp boolean := false;
  v_diambil boolean := false;
  v_phase text;
  v_token text;
  v_payload text;
  v_token_col text;
  v_channel text;
  v_tenant uuid;
begin
  if p_no_invoice is null or length(trim(p_no_invoice)) = 0 then
    return null;
  end if;

  if public.is_platform_user() then
    v_tenant := null;
  else
    v_tenant := coalesce(
      public.current_tenant_id(),
      public.require_member_tenant(p_tenant_id)
    );
  end if;

  select * into v_sale
  from public.sales
  where no_invoice = trim(p_no_invoice)
    and (v_tenant is null or tenant_id = v_tenant)
  limit 1;
  if not found then return null; end if;

  v_is_staff := public.invoice_can_staff_hub(v_sale.toko_id);
  v_can_mint := public.can_pos_checkout_for_toko(v_sale.toko_id);

  if v_phone is not null then
    v_alt := case
      when v_phone like '62%' then '0' || substr(v_phone, 3)
      else v_phone
    end;
    v_owner := (
      public.wa_digits(v_sale.no_wa) = v_phone
      or regexp_replace(coalesce(v_sale.no_wa, ''), '\D', '', 'g')
        in (v_phone, v_alt)
    );
  end if;

  if not v_is_staff and not v_owner then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', si.id,
    'nama_produk', si.nama_produk,
    'tipe_produk', si.tipe_produk,
    'qty', si.qty,
    'subtotal', si.subtotal,
    'detail_resep', si.detail_resep,
    'needs_fulfillment', coalesce(si.needs_fulfillment, false),
    'fulfillment_status', coalesce(si.fulfillment_status, 'READY'),
    'diambil_at', si.diambil_at
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
    'diambil_at', g.diambil_at,
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
      and public.garansi_kartu_masih_klaim(g)
  ) into v_claimable;

  select coalesce(i.google_review_url, p.google_review_url)
  into v_review
  from (select 1) _
  left join public.invoice_settings i
    on public.same_store_toko(i.toko_id, v_sale.toko_id)
  left join public.invoice_settings p
    on public.same_store_toko(p.toko_id, 'PUSAT');

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

  v_is_dp := public.invoice_is_dp(v_sale.status_pembayaran, v_sale.sisa_tagihan);
  v_diambil := (
    v_sale.diambil_at is not null
    or upper(trim(coalesce(v_sale.tracking_status, ''))) = 'DIAMBIL'
  );
  v_channel := case
    when lower(trim(coalesce(v_sale.channel, ''))) = 'online' then 'ONLINE'
    else 'OFFLINE'
  end;

  if v_is_dp then
    if v_sale.qr_dp_used_at is null
       and upper(trim(coalesce(v_sale.tracking_status, ''))) = 'SIAP_PELUNASAN'
    then
      v_phase := 'DP';
      v_token := nullif(trim(coalesce(v_sale.qr_dp_token, '')), '');
      v_token_col := 'qr_dp_token';
    end if;
  elsif not v_diambil then
    if upper(trim(coalesce(v_sale.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR') then
      v_phase := 'LUNAS';
      v_token := nullif(trim(coalesce(v_sale.qr_lunas_token, '')), '');
      v_token_col := 'qr_lunas_token';
      if v_sale.qr_lunas_used_at is not null then
        v_phase := null;
        v_token := null;
        v_token_col := null;
      end if;
    end if;
  else
    v_phase := 'CLAIM';
    v_token := nullif(trim(coalesce(v_sale.qr_claim_token, '')), '');
    v_token_col := 'qr_claim_token';
    if v_sale.qr_claim_used_at is not null then
      v_phase := null;
      v_token := null;
      v_token_col := null;
    end if;
  end if;

  if v_phase is null
     and v_sale.qr_claim_used_at is null
     and length(trim(coalesce(v_sale.qr_claim_token, ''))) >= 8
  then
    v_phase := 'CLAIM';
    v_token := nullif(trim(coalesce(v_sale.qr_claim_token, '')), '');
    v_token_col := 'qr_claim_token';
  end if;

  if v_can_mint
     and v_phase is not null
     and v_token_col is not null
     and (v_token is null or length(v_token) < 8)
  then
    v_token := encode(extensions.gen_random_bytes(16), 'hex');
    if v_token_col = 'qr_dp_token' then
      update public.sales set qr_dp_token = v_token where id = v_sale.id;
    elsif v_token_col = 'qr_lunas_token' then
      update public.sales set qr_lunas_token = v_token where id = v_sale.id;
    else
      update public.sales set qr_claim_token = v_token where id = v_sale.id;
    end if;
  end if;

  if (v_owner or v_is_staff)
     and v_phase is not null
     and v_token is not null
     and length(v_token) >= 8
  then
    v_payload := 'OBRINV|v1|' || trim(v_sale.no_invoice) || '|' || v_phase
      || '|' || v_token || '|' || v_channel;
  else
    v_payload := null;
  end if;

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
    'channel', v_sale.channel,
    'fulfillment', v_sale.fulfillment,
    'courier', v_sale.courier,
    'online_order_id', v_sale.online_order_id,
    'no_wa', case when v_is_staff then v_sale.no_wa else null end,
    'email_pelanggan', case when v_is_staff then v_sale.email_pelanggan else null end,
    'alamat', case when v_is_staff then v_sale.alamat else null end,
    'items', v_items,
    'garansi', v_garansi,
    'garansi_claimable', v_claimable,
    'google_review_url', v_review,
    'bisa_rating', v_bisa_rating,
    'ratings', coalesce(v_ratings, '[]'::jsonb),
    'qr_dp_ready',
      upper(trim(coalesce(v_sale.tracking_status, ''))) = 'SIAP_PELUNASAN'
      and v_sale.qr_dp_token is not null
      and v_sale.qr_dp_used_at is null,
    'qr_lunas_ready',
      upper(trim(coalesce(v_sale.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR')
      and v_sale.qr_lunas_token is not null
      and v_sale.qr_lunas_used_at is null,
    'qr_claim_ready', (v_sale.qr_claim_token is not null and v_sale.qr_claim_used_at is null)
      or (v_phase = 'CLAIM' and v_payload is not null),
    'qr_dp_used', (v_sale.qr_dp_used_at is not null),
    'qr_lunas_used', (v_sale.qr_lunas_used_at is not null),
    'qr_claim_used', (v_sale.qr_claim_used_at is not null),
    'qr_phase', v_phase,
    'qr_payload', v_payload,
    'qr_owner_verified', v_owner
  );
end;
$$;

comment on function public.get_invoice_hub(text, text, uuid) is
  'Hub nota. Tenant wajib. Garansi claimable = window 7 hari hard-cap.';

revoke all on function public.get_invoice_hub(text, text, uuid) from public;
grant execute on function public.get_invoice_hub(text, text, uuid)
  to anon, authenticated, service_role;
