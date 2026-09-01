-- Member boleh kirim pengaduan (bukan partner / pelanggaran karyawan).

alter table public.pengaduan
  alter column karyawan_id drop not null;

alter table public.pengaduan
  add column if not exists member_id uuid references public.members (id) on delete set null,
  add column if not exists sumber text not null default 'KARYAWAN',
  add column if not exists pelapor_nama text,
  add column if not exists pelapor_kontak text,
  add column if not exists tenant_id uuid;

update public.pengaduan
set sumber = 'KARYAWAN'
where sumber is null or btrim(sumber) = '';

alter table public.pengaduan drop constraint if exists pengaduan_pelapor_chk;
alter table public.pengaduan
  add constraint pengaduan_pelapor_chk
  check (karyawan_id is not null or member_id is not null);

alter table public.pengaduan drop constraint if exists pengaduan_sumber_chk;
alter table public.pengaduan
  add constraint pengaduan_sumber_chk
  check (upper(sumber) in ('KARYAWAN', 'MEMBER'));

create index if not exists pengaduan_member_created_idx
  on public.pengaduan (member_id, created_at desc)
  where member_id is not null;

create or replace function public.submit_member_pengaduan(
  p_member_id uuid,
  p_toko_id text,
  p_kategori_kode text,
  p_isi text,
  p_foto_url text,
  p_items jsonb default '[]'::jsonb,
  p_phone text default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.members%rowtype;
  v_kode text := upper(trim(coalesce(p_kategori_kode, '')));
  v_isi text := trim(coalesce(p_isi, ''));
  v_foto text := trim(coalesce(p_foto_url, ''));
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_phone text := public.wa_digits(coalesce(p_phone, ''));
  v_items jsonb := coalesce(p_items, '[]'::jsonb);
  v_id uuid;
  v_tenant uuid;
begin
  if p_member_id is null then
    return jsonb_build_object('ok', false, 'error', 'Login Member dulu');
  end if;
  if v_kode not in ('PRODUK', 'TOKO', 'CUSTOMER', 'SISTEM') then
    return jsonb_build_object(
      'ok', false,
      'error', 'Laporan partner / karyawan lain hanya lewat aplikasi staf'
    );
  end if;
  if v_isi = '' then
    return jsonb_build_object('ok', false, 'error', 'Penjelasan wajib diisi');
  end if;
  if v_foto = '' then
    return jsonb_build_object('ok', false, 'error', 'Foto bukti wajib');
  end if;
  if v_toko = '' then
    return jsonb_build_object('ok', false, 'error', 'Pilih cabang');
  end if;
  if v_kode = 'PRODUK' and (
    jsonb_typeof(v_items) is distinct from 'array' or v_items = '[]'::jsonb
  ) then
    return jsonb_build_object('ok', false, 'error', 'Pilih barang yang rusak');
  end if;

  select * into v_member from public.members where id = p_member_id limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Akun Member tidak ditemukan');
  end if;

  if v_phone is not null and length(v_phone) >= 8 then
    if public.wa_digits(coalesce(v_member.phone_e164, v_member.phone_raw, ''))
       is distinct from v_phone then
      return jsonb_build_object('ok', false, 'error', 'Nomor HP tidak cocok');
    end if;
  end if;

  v_tenant := coalesce(p_tenant_id, v_member.tenant_id, public.current_tenant_id());
  if v_member.tenant_id is not null
     and v_tenant is not null
     and v_member.tenant_id is distinct from v_tenant then
    return jsonb_build_object('ok', false, 'error', 'Tenant tidak cocok');
  end if;

  insert into public.pengaduan (
    karyawan_id,
    member_id,
    toko_id,
    kategori,
    kategori_kode,
    isi,
    foto_url,
    status,
    items,
    sumber,
    pelapor_nama,
    pelapor_kontak,
    tenant_id
  ) values (
    null,
    v_member.id,
    v_toko,
    v_kode,
    v_kode,
    v_isi,
    v_foto,
    'OPEN',
    case when v_kode = 'PRODUK' then v_items else '[]'::jsonb end,
    'MEMBER',
    coalesce(nullif(trim(v_member.nama), ''), 'Member'),
    coalesce(nullif(trim(v_member.phone_e164), ''), p_phone),
    v_tenant
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function public.list_member_pengaduan(
  p_member_id uuid,
  p_limit int default 30
)
returns setof public.pengaduan
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_member_id is null then
    return;
  end if;
  return query
    select p.*
    from public.pengaduan p
    where p.member_id = p_member_id
      and upper(coalesce(p.sumber, 'MEMBER')) = 'MEMBER'
    order by p.created_at desc
    limit greatest(1, least(coalesce(p_limit, 30), 80));
end;
$$;

revoke all on function public.submit_member_pengaduan(
  uuid, text, text, text, text, jsonb, text, uuid
) from public;
grant execute on function public.submit_member_pengaduan(
  uuid, text, text, text, text, jsonb, text, uuid
) to anon, authenticated;

revoke all on function public.list_member_pengaduan(uuid, int) from public;
grant execute on function public.list_member_pengaduan(uuid, int)
  to anon, authenticated;

comment on function public.submit_member_pengaduan(
  uuid, text, text, text, text, jsonb, text, uuid
) is
  'Member kirim pengaduan. PARTNER / PELANGGARAN ditolak — privat staf.';
