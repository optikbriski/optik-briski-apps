-- Live E2E pengaduan: insert/update/delete baris uji, tidak menyentuh stok produk nyata.
-- Marker: E2E_AUDIT_PENGADUAN — selalu dihapus di akhir.

do $$
declare
  v_k uuid;
  v_toko text;
  v_uid uuid;
  v_id uuid;
  v_st text;
begin
  delete from public.pengaduan where isi like 'E2E_AUDIT_PENGADUAN%';

  select k.id, k.toko_id
    into v_k, v_toko
  from public.karyawan k
  where k.toko_id is not null
    and exists (select 1 from public.toko_id t where t.id = k.toko_id)
  limit 1;
  if v_k is null then
    raise exception 'E2E: tidak ada karyawan dengan toko valid';
  end if;

  select id into v_uid from public.profiles limit 1;

  begin
    insert into public.pengaduan (
      karyawan_id, toko_id, kategori, kategori_kode, isi, status, sumber, items
    ) values (
      v_k, v_toko, 'Kerusakan produk', 'PRODUK',
      'E2E_AUDIT_PENGADUAN noitems', 'OPEN', 'KARYAWAN', '[]'::jsonb
    );
    raise exception 'E2E FAIL: PRODUK tanpa items lolos insert';
  exception
    when others then
      if sqlerrm not like '%Pilih barang%' then
        raise exception 'E2E FAIL produk-empty: %', sqlerrm;
      end if;
  end;

  if v_uid is not null then
    begin
      insert into public.pengaduan (
        toko_id, kategori, kategori_kode, isi, status, sumber,
        pelapor_user_id, pelapor_nama
      ) values (
        v_toko, 'Aduan partner', 'PARTNER',
        'E2E_AUDIT_PENGADUAN partner', 'OPEN', 'ADMIN', v_uid, 'E2E'
      );
      raise exception 'E2E FAIL: Admin PARTNER lolos insert';
    exception
      when others then
        if sqlerrm not like '%privat%' then
          raise exception 'E2E FAIL admin-partner: %', sqlerrm;
        end if;
    end;
  end if;

  insert into public.pengaduan (
    karyawan_id, toko_id, kategori, kategori_kode, isi, status, sumber, foto_url
  ) values (
    v_k, v_toko, 'Kendala Sistem/Aplikasi', 'SISTEM',
    'E2E_AUDIT_PENGADUAN sistem', 'OPEN', 'KARYAWAN',
    'https://example.invalid/e2e.jpg'
  ) returning id into v_id;

  update public.pengaduan set status = 'IN_PROGRESS' where id = v_id;
  select status into v_st from public.pengaduan where id = v_id;
  if v_st is distinct from 'IN_PROGRESS' then
    raise exception 'E2E FAIL: open case status=%', v_st;
  end if;

  update public.pengaduan
  set status = 'REJECTED', keputusan = 'REJECT', balasan = 'E2E reject'
  where id = v_id;
  select status into v_st from public.pengaduan where id = v_id;
  if v_st is distinct from 'REJECTED' then
    raise exception 'E2E FAIL: reject status=%', v_st;
  end if;

  insert into public.pengaduan (
    karyawan_id, toko_id, kategori, kategori_kode, isi, status, sumber, items, foto_url
  ) values (
    v_k, v_toko, 'Kerusakan produk', 'PRODUK',
    'E2E_AUDIT_PENGADUAN produk', 'OPEN', 'KARYAWAN',
    '[{"sku":"E2E-SKU","nama":"E2E","qty":1}]'::jsonb,
    'https://example.invalid/e2e.jpg'
  ) returning id into v_id;

  update public.pengaduan set status = 'IN_PROGRESS' where id = v_id;
  select status into v_st from public.pengaduan where id = v_id;
  if v_st is distinct from 'IN_PROGRESS' then
    raise exception 'E2E FAIL: produk open case status=%', v_st;
  end if;

  if v_uid is not null then
    insert into public.pengaduan (
      toko_id, kategori, kategori_kode, isi, status, sumber,
      pelapor_user_id, pelapor_nama, foto_url
    ) values (
      v_toko, 'Keadaan toko', 'TOKO',
      'E2E_AUDIT_PENGADUAN admin', 'OPEN', 'ADMIN',
      v_uid, 'E2E Admin', 'https://example.invalid/e2e.jpg'
    );
  end if;

  delete from public.pengaduan where isi like 'E2E_AUDIT_PENGADUAN%';
end $$;

select count(*)::int as leftover
from public.pengaduan
where isi like 'E2E_AUDIT_PENGADUAN%';
