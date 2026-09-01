-- Harden pengaduan E2E setelah 000002–000005.
-- 1) Trigger jangan blokir Open/Reject kasus lama (items hanya wajib di INSERT PRODUK).
-- 2) Owner/kasir yang memutus kasus boleh gerakkan stok (hanya di transaksi decide).
-- 3) decide: infer kategori lama, hitung item BUANG, error stok jadi jsonb (bukan 500).

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

  if tg_op = 'INSERT'
     and v_kode = 'PRODUK'
     and (
       jsonb_typeof(coalesce(new.items, '[]'::jsonb)) is distinct from 'array'
       or coalesce(new.items, '[]'::jsonb) = '[]'::jsonb
     ) then
    raise exception 'Pilih barang yang rusak';
  end if;

  return new;
end;
$$;

create or replace function public.can_manage_inventory_for_toko(p_toko text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.toko_belongs_to_current_tenant(p_toko)
    and (
      current_setting('rekasa.pengaduan_decide', true) = '1'
      or (
        not public.is_owner_role()
        and (
          public.is_platform_user()
          or public.current_profile_role() in ('admin_pusat', 'super_admin')
          or (
            public.current_profile_role() = 'admin_toko'
            and public.same_store_toko(public.current_profile_toko_id(), p_toko)
          )
        )
      )
    );
$$;

comment on function public.can_manage_inventory_for_toko(text) is
  'Mutasi stok toko: pusat semua cabang tenant; admin_toko toko sendiri. Bukan owner/kasir — kecuali transaksi decide_pengaduan.';

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
  v_applied int := 0;
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
  if v_kode = '' then
    v_kode := case
      when lower(coalesce(v_row.kategori, '')) ~ '(stok|produk|stock|barang)' then 'PRODUK'
      when lower(coalesce(v_row.kategori, '')) ~ '(customer|pelanggan|member)' then 'CUSTOMER'
      when lower(coalesce(v_row.kategori, '')) ~ '(partner|mitra)' then 'PARTNER'
      when lower(coalesce(v_row.kategori, '')) ~ '(sistem|aplikasi|system)' then 'SISTEM'
      when lower(coalesce(v_row.kategori, '')) ~ '(langgar|violation|rahasia)' then 'PELANGGARAN'
      when lower(coalesce(v_row.kategori, '')) ~ '(alat|toko|store|equipment)' then 'TOKO'
      else v_kode
    end;
  end if;

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

    begin
      perform set_config('rekasa.pengaduan_decide', '1', true);
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
            v_applied := v_applied + 1;
          end loop;
          if v_applied = 0 then
            return jsonb_build_object(
              'ok', false,
              'error', 'Tidak ada barang valid untuk dipotong stok'
            );
          end if;
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
    exception when others then
      return jsonb_build_object('ok', false, 'error', sqlerrm);
    end;
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
revoke all on function public.reply_pengaduan(uuid, text, text) from public;
grant execute on function public.reply_pengaduan(uuid, text, text) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.pengaduan;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

do $$
begin
  alter table public.pengaduan replica identity full;
exception
  when others then null;
end $$;

