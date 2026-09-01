-- =============================================================================
-- TEMPLEKAN SEKALI di Supabase SQL Editor (proyek Optik B Riski Apps).
-- Gabungan yang BELUM ada di live: 20260829000002 + 000004 + 000005.
-- 000003 (RPC Member) sengaja dilewati — bukan produk.
-- Aman di-run ulang (IF NOT EXISTS / CREATE OR REPLACE / DROP IF EXISTS).
-- =============================================================================

-- Form pengaduan: kategori kode + daftar barang rusak.
-- Keputusan pusat: APPROVE (DONE hijau) / REJECT (REJECTED merah).
-- PRODUK + approve: BUANG (write-off toko) atau BALIK (retur ke Pusat).

alter table public.pengaduan
  add column if not exists kategori_kode text,
  add column if not exists items jsonb not null default '[]'::jsonb,
  add column if not exists keputusan text,
  add column if not exists stok_tindakan text,
  add column if not exists stok_ref_id text,
  add column if not exists stok_applied_at timestamptz;

comment on column public.pengaduan.kategori_kode is
  'PRODUK | TOKO | CUSTOMER | PARTNER | SISTEM | PELANGGARAN';
comment on column public.pengaduan.items is
  'Daftar barang rusak [{sku, nama, qty, barcode}] — wajib jika PRODUK.';
comment on column public.pengaduan.keputusan is 'APPROVE | REJECT setelah tindakan pusat.';
comment on column public.pengaduan.stok_tindakan is 'BUANG | BALIK — hanya PRODUK yang di-approve.';

update public.pengaduan
set kategori_kode = case
  when kategori_kode is not null and btrim(kategori_kode) <> '' then kategori_kode
  when lower(coalesce(kategori, '')) ~ '(stok|produk|stock|barang)' then 'PRODUK'
  when lower(coalesce(kategori, '')) ~ '(customer|pelanggan|member)' then 'CUSTOMER'
  when lower(coalesce(kategori, '')) ~ '(partner|mitra)' then 'PARTNER'
  when lower(coalesce(kategori, '')) ~ '(sistem|aplikasi|system)' then 'SISTEM'
  when lower(coalesce(kategori, '')) ~ '(langgar|violation|rahasia)' then 'PELANGGARAN'
  when lower(coalesce(kategori, '')) ~ '(alat|toko|store|equipment)' then 'TOKO'
  else kategori_kode
end
where kategori_kode is null or btrim(kategori_kode) = '';

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
  if v_status not in ('OPEN', 'IN_PROGRESS', 'DONE', 'REJECTED') then
    v_status := 'DONE';
  end if;
  if v_status in ('DONE', 'REJECTED') and v_body = '' then
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
      keputusan = case
        when v_status = 'REJECTED' then 'REJECT'
        when v_status = 'DONE' then 'APPROVE'
        else keputusan
      end,
      dibalas_at = now(),
      dibalas_oleh = v_nama,
      dibalas_oleh_user_id = v_uid
    where id = p_id;
    v_judul := case
      when v_status = 'REJECTED' then 'Pengaduan ditolak'
      else 'Balasan pengaduan'
    end;
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

create or replace function public.decide_pengaduan(
  p_id uuid,
  p_keputusan text,
  p_balasan text,
  p_stok_tindakan text default null
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
  v_body text := trim(coalesce(p_balasan, ''));
  v_kep text := upper(trim(coalesce(p_keputusan, '')));
  v_stok text := upper(trim(coalesce(p_stok_tindakan, '')));
  v_kode text;
  v_nama text;
  v_status text;
  v_ref text;
  v_it jsonb;
  v_sku text;
  v_qty int;
  v_ret jsonb;
  v_kary_uid uuid;
  v_judul text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  if p_id is null then
    return jsonb_build_object('ok', false, 'error', 'Pengaduan tidak ditemukan');
  end if;
  if v_kep not in ('APPROVE', 'REJECT') then
    return jsonb_build_object('ok', false, 'error', 'Pilih approve atau reject');
  end if;
  if v_body = '' then
    return jsonb_build_object('ok', false, 'error', 'Tanggapan wajib diisi');
  end if;

  if not (
    public.is_platform_user()
    or v_role in ('owner', 'admin_pusat', 'super_admin', 'admin_toko', 'kasir')
  ) then
    return jsonb_build_object('ok', false, 'error', 'Hanya staf Admin yang boleh memutus');
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

  if upper(trim(coalesce(v_row.status, ''))) in ('DONE', 'REJECTED') then
    return jsonb_build_object('ok', false, 'error', 'Kasus sudah diputuskan');
  end if;

  select coalesce(nullif(trim(p.email), ''), 'Admin')
    into v_nama
  from public.profiles p
  where p.id = v_uid
  limit 1;
  v_nama := coalesce(v_nama, 'Admin');

  v_kode := upper(trim(coalesce(v_row.kategori_kode, '')));
  v_status := case when v_kep = 'REJECT' then 'REJECTED' else 'DONE' end;
  if v_stok not in ('BUANG', 'BALIK') then
    v_stok := null;
  end if;

  if v_kep = 'APPROVE' and v_kode = 'PRODUK' then
    if v_stok is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'Pilih buang barang atau balikin barang'
      );
    end if;
    if jsonb_typeof(coalesce(v_row.items, '[]'::jsonb)) is distinct from 'array'
       or coalesce(v_row.items, '[]'::jsonb) = '[]'::jsonb then
      return jsonb_build_object('ok', false, 'error', 'Tidak ada daftar barang rusak');
    end if;
    if v_stok = 'BALIK' and public.is_pusat_warehouse(coalesce(v_row.toko_id, '')) then
      return jsonb_build_object(
        'ok', false,
        'error', 'Retur hanya dari cabang ke Pusat. Pilih buang barang.'
      );
    end if;

    if v_row.stok_applied_at is null then
      if v_stok = 'BUANG' then
        for v_it in select value from jsonb_array_elements(v_row.items)
        loop
          v_sku := nullif(trim(coalesce(v_it->>'sku', v_it->>'barcode', '')), '');
          begin
            v_qty := greatest(coalesce((v_it->>'qty')::int, (v_it->>'jumlah')::int, 0), 0);
          exception when others then
            v_qty := 0;
          end;
          if v_sku is null or v_qty <= 0 then
            continue;
          end if;
          perform public.write_off_stock(
            upper(trim(coalesce(v_row.toko_id, ''))),
            v_sku,
            v_qty,
            v_body,
            v_nama,
            'PGD-' || p_id::text,
            jsonb_build_object(
              'pengaduan_id', p_id,
              'item', v_it,
              'tindakan', 'BUANG'
            )
          );
        end loop;
        v_ref := 'PGD-' || p_id::text;
      else
        v_ret := public.create_return_stock_move(
          upper(trim(coalesce(v_row.toko_id, ''))),
          v_row.items,
          null,
          null
        );
        v_ref := coalesce(v_ret->>'resi', v_ret->>'id');
      end if;
    else
      v_ref := v_row.stok_ref_id;
    end if;
  else
    v_stok := null;
  end if;

  update public.pengaduan
  set
    status = v_status,
    keputusan = v_kep,
    balasan = v_body,
    stok_tindakan = v_stok,
    stok_ref_id = coalesce(v_ref, stok_ref_id),
    stok_applied_at = case
      when v_ref is not null then coalesce(stok_applied_at, now())
      else stok_applied_at
    end,
    dibalas_at = now(),
    dibalas_oleh = v_nama,
    dibalas_oleh_user_id = v_uid
  where id = p_id;

  v_kary_uid := v_row.karyawan_id;
  v_judul := case
    when v_kep = 'REJECT' then 'Pengaduan ditolak'
    else 'Pengaduan disetujui'
  end;
  if v_kary_uid is not null then
    begin
      insert into public.notifikasi (user_id, judul, isi, tipe)
      values (
        v_kary_uid,
        v_judul,
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
    'keputusan', v_kep,
    'stok_tindakan', v_stok,
    'stok_ref_id', v_ref,
    'dibalas_oleh', v_nama
  );
end;
$$;

revoke all on function public.decide_pengaduan(uuid, text, text, text) from public;
grant execute on function public.decide_pengaduan(uuid, text, text, text) to authenticated;

comment on function public.decide_pengaduan(uuid, text, text, text) is
  'Pusat approve/reject pengaduan. PRODUK + approve wajib BUANG (write-off) atau BALIK (retur ke Pusat).';

-- ---------------------------------------------------------------------------
-- Admin boleh kirim pengaduan publik (bukan partner / pelanggaran karyawan).
-- Member submit RPC dicabut — salah sasaran, bukan produk.

alter table public.pengaduan
  alter column karyawan_id drop not null;

alter table public.pengaduan
  add column if not exists member_id uuid,
  add column if not exists sumber text not null default 'KARYAWAN',
  add column if not exists pelapor_nama text,
  add column if not exists pelapor_kontak text,
  add column if not exists pelapor_user_id uuid,
  add column if not exists tenant_id uuid;

alter table public.pengaduan drop constraint if exists pengaduan_sumber_chk;
alter table public.pengaduan
  add constraint pengaduan_sumber_chk
  check (upper(sumber) in ('KARYAWAN', 'ADMIN', 'MEMBER'));

alter table public.pengaduan drop constraint if exists pengaduan_pelapor_chk;
alter table public.pengaduan
  add constraint pengaduan_pelapor_chk
  check (
    karyawan_id is not null
    or member_id is not null
    or (
      upper(coalesce(sumber, '')) = 'ADMIN'
      and pelapor_user_id is not null
    )
  );

create index if not exists pengaduan_pelapor_user_created_idx
  on public.pengaduan (pelapor_user_id, created_at desc)
  where pelapor_user_id is not null;

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'submit_member_pengaduan'
  ) then
    execute 'revoke all on function public.submit_member_pengaduan(uuid, text, text, text, text, jsonb, text, uuid) from public, anon, authenticated';
  end if;
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'list_member_pengaduan'
  ) then
    execute 'revoke all on function public.list_member_pengaduan(uuid, int) from public, anon, authenticated';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Seal pengaduan: privat staf, tenant, Admin tidak boleh PARTNER/PELANGGARAN.
-- Cabut RPC Member yang salah sasaran.

update public.pengaduan p
set tenant_id = k.tenant_id
from public.karyawan k
where p.karyawan_id = k.id
  and p.tenant_id is null
  and k.tenant_id is not null;

create or replace function public.pengaduan_is_hq()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_platform_user()
    or public.current_profile_role() in (
      'owner', 'admin_pusat', 'super_admin', 'admin_toko', 'kasir'
    );
$$;

revoke all on function public.pengaduan_is_hq() from public, anon;
grant execute on function public.pengaduan_is_hq() to authenticated, service_role;

create or replace function public.pengaduan_fill_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kode text;
begin
  if new.tenant_id is null then
    new.tenant_id := public.current_tenant_id();
  end if;
  if new.tenant_id is null and new.karyawan_id is not null then
    select k.tenant_id into new.tenant_id
    from public.karyawan k
    where k.id = new.karyawan_id
    limit 1;
  end if;

  v_kode := upper(trim(coalesce(new.kategori_kode, '')));
  if v_kode = '' then
    v_kode := case
      when lower(coalesce(new.kategori, '')) ~ '(langgar|violation|rahasia)' then 'PELANGGARAN'
      when lower(coalesce(new.kategori, '')) ~ '(partner|mitra)' then 'PARTNER'
      else v_kode
    end;
  end if;

  if upper(trim(coalesce(new.sumber, 'KARYAWAN'))) = 'ADMIN'
     and v_kode in ('PARTNER', 'PELANGGARAN') then
    raise exception 'Kategori privat hanya dari APK Karyawan';
  end if;

  if v_kode = 'PRODUK' and (
    jsonb_typeof(coalesce(new.items, '[]'::jsonb)) is distinct from 'array'
    or coalesce(new.items, '[]'::jsonb) = '[]'::jsonb
  ) then
    raise exception 'Pilih barang yang rusak';
  end if;

  return new;
end;
$$;

drop trigger if exists pengaduan_fill_tenant_trg on public.pengaduan;
create trigger pengaduan_fill_tenant_trg
before insert or update on public.pengaduan
for each row execute function public.pengaduan_fill_tenant();

alter table public.pengaduan drop constraint if exists pengaduan_admin_public_cat_chk;
alter table public.pengaduan
  add constraint pengaduan_admin_public_cat_chk
  check (
    upper(coalesce(sumber, 'KARYAWAN')) <> 'ADMIN'
    or upper(coalesce(kategori_kode, '')) not in ('PARTNER', 'PELANGGARAN')
  );

drop policy if exists pengaduan_auth_all on public.pengaduan;
drop policy if exists pengaduan_tenant_seal on public.pengaduan;
drop policy if exists pengaduan_select_scoped on public.pengaduan;
drop policy if exists pengaduan_insert_scoped on public.pengaduan;
drop policy if exists pengaduan_update_hq on public.pengaduan;
drop policy if exists pengaduan_delete_hq on public.pengaduan;

create policy pengaduan_select_scoped on public.pengaduan
for select to authenticated
using (
  public.current_tenant_id() is not null
  and tenant_id is not distinct from public.current_tenant_id()
  and (
    (
      public.pengaduan_is_hq()
      and (
        public.current_profile_role() in ('owner', 'admin_pusat', 'super_admin')
        or public.is_platform_user()
        or public.same_store_toko(
          public.current_profile_toko_id(),
          coalesce(toko_id, '')
        )
      )
    )
    or karyawan_id is not distinct from public.current_karyawan_id()
    or pelapor_user_id is not distinct from auth.uid()
  )
);

create policy pengaduan_insert_scoped on public.pengaduan
for insert to authenticated
with check (
  public.current_tenant_id() is not null
  and tenant_id is not distinct from public.current_tenant_id()
  and (
    (
      karyawan_id is not distinct from public.current_karyawan_id()
      and upper(coalesce(sumber, 'KARYAWAN')) = 'KARYAWAN'
    )
    or (
      public.pengaduan_is_hq()
      and upper(coalesce(sumber, '')) = 'ADMIN'
      and pelapor_user_id is not distinct from auth.uid()
      and upper(coalesce(kategori_kode, '')) not in ('PARTNER', 'PELANGGARAN')
    )
  )
);

create policy pengaduan_update_hq on public.pengaduan
for update to authenticated
using (
  public.pengaduan_is_hq()
  and public.current_tenant_id() is not null
  and tenant_id is not distinct from public.current_tenant_id()
)
with check (
  public.pengaduan_is_hq()
  and public.current_tenant_id() is not null
  and tenant_id is not distinct from public.current_tenant_id()
);

create policy pengaduan_delete_hq on public.pengaduan
for delete to authenticated
using (
  public.pengaduan_is_hq()
  and public.current_tenant_id() is not null
  and tenant_id is not distinct from public.current_tenant_id()
);

drop function if exists public.submit_member_pengaduan(uuid, text, text, text, text, jsonb, text, uuid);
drop function if exists public.list_member_pengaduan(uuid, int);

revoke all on function public.reply_pengaduan(uuid, text, text) from public;
grant execute on function public.reply_pengaduan(uuid, text, text) to authenticated;
