-- Karyawan terlibat di invoice POS (tanpa peran).
-- Poin Front + pertanggungjawaban: tiap karyawan unik di sale = +5 (aplikasi).
-- kasir_karyawan_id tetap jejak teknis yang unlock/tekan POS.
-- WAJIB di-apply sebelum pakai fitur terlibat di POS (checkout gagal jika insert gagal).

create table if not exists public.sales_karyawan_terlibat (
  sale_id uuid not null references public.sales (id) on delete cascade,
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (sale_id, karyawan_id)
);

create index if not exists sales_karyawan_terlibat_karyawan_idx
  on public.sales_karyawan_terlibat (karyawan_id, created_at desc);

create index if not exists sales_karyawan_terlibat_sale_idx
  on public.sales_karyawan_terlibat (sale_id);

comment on table public.sales_karyawan_terlibat is
  'Daftar karyawan terlibat per invoice (tanpa label peran). Dedupe via PK.';

alter table public.sales_karyawan_terlibat enable row level security;

drop policy if exists sales_karyawan_terlibat_auth_all on public.sales_karyawan_terlibat;
create policy sales_karyawan_terlibat_auth_all on public.sales_karyawan_terlibat
  for all to authenticated using (true) with check (true);

-- Service role / dashboard SQL juga aman untuk backfill & repair.
grant select, insert, update, delete on public.sales_karyawan_terlibat to authenticated;

-- Backfill: kasir POS lama masuk sebagai terlibat
insert into public.sales_karyawan_terlibat (sale_id, karyawan_id)
select s.id, s.kasir_karyawan_id
from public.sales s
where s.kasir_karyawan_id is not null
on conflict do nothing;
