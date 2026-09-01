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
