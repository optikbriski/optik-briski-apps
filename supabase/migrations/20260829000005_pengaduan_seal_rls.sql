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
