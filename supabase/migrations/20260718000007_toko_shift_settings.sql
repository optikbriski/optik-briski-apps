-- Setting shift per cabang (kuota + jam beda per toko)
create table if not exists public.toko_shift_settings (
  toko_id text primary key references public.toko_id (id) on delete cascade,
  shift1_label text not null default 'Shift Pagi',
  shift1_masuk time not null default '09:00',
  shift1_pulang time not null default '17:00',
  shift1_kuota integer not null default 3 check (shift1_kuota >= 0),
  shift2_label text not null default 'Shift Sore',
  shift2_masuk time not null default '13:00',
  shift2_pulang time not null default '21:00',
  shift2_kuota integer not null default 3 check (shift2_kuota >= 0),
  -- false = libur 1 hari/minggu digilir antar karyawan; true = semua libur Minggu
  minggu_libur boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.toko_shift_settings enable row level security;

drop policy if exists toko_shift_settings_auth_all on public.toko_shift_settings;
create policy toko_shift_settings_auth_all on public.toko_shift_settings
  for all to authenticated using (true) with check (true);

comment on table public.toko_shift_settings is
  'Kuota & jam 2 shift per cabang. Auto-random jadwal memakai setting ini.';
