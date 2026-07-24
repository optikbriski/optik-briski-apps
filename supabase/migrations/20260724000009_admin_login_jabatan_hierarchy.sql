-- Siapa boleh kode login Admin (APK):
--   • PUSAT  → jabatan Admin / Owner saja (semua admin punya kode unik → ter-track)
--   • Cabang → Kepala Toko / Kepala Area
--   • Frontliner / Backliner → tidak (posisi karyawan toko cabang)

create or replace function public.karyawan_can_show_admin_login_code(
  p_toko_id text,
  p_jabatan text,
  p_status text
)
returns boolean
language plpgsql
immutable
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_jab text := lower(trim(coalesce(p_jabatan, '')));
begin
  if coalesce(p_status, '') <> 'Aktif' then
    return false;
  end if;

  -- Karyawan lantai toko: tidak ada kode login Admin
  if v_jab in ('frontliner', 'backliner') then
    return false;
  end if;

  if v_toko = 'PUSAT' then
    return v_jab in ('admin', 'owner');
  end if;

  -- Cabang: wewenang akses web toko
  return v_jab in ('kepala toko', 'kepala area');
end;
$$;

comment on function public.karyawan_can_show_admin_login_code is
  'PUSAT: Admin/Owner. Cabang: Kepala Toko/Kepala Area. Front/Back: tidak.';
