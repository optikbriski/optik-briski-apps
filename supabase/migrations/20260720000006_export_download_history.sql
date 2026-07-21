-- =============================================================================
-- Riwayat unduhan ekspor PDF + counter Salinan ke-N (global per org)
-- Jalankan di Supabase → SQL Editor jika migration belum di-apply.
-- =============================================================================

-- Counter global: setiap aksi ekspor (gabung ATAU pisah) mengambil 1 nomor batch.
create table if not exists public.export_salinan_counter (
  id int primary key default 1 check (id = 1),
  next_salinan int not null default 1
);

insert into public.export_salinan_counter (id, next_salinan)
values (1, 1)
on conflict (id) do nothing;

comment on table public.export_salinan_counter is
  'Counter Salinan ke-N untuk ekspor PDF admin. Satu nomor per aksi unduh (batch).';

-- Riwayat unduhan
create table if not exists public.export_download_history (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  admin_user_id uuid,
  admin_email text,
  period_start date not null,
  period_end date not null,
  mode text not null check (mode in ('gabung', 'pisah')),
  domains text[] not null default '{}',
  salinan_ke int not null,
  file_count int not null default 1,
  notes text
);

create index if not exists export_download_history_created_at_idx
  on public.export_download_history (created_at desc);

create index if not exists export_download_history_admin_user_id_idx
  on public.export_download_history (admin_user_id);

comment on table public.export_download_history is
  'Riwayat unduhan laporan PDF operasional (admin).';
comment on column public.export_download_history.mode is
  'gabung = satu PDF digabung; pisah = satu PDF per domain.';
comment on column public.export_download_history.salinan_ke is
  'Nomor salinan batch (sama untuk semua file dalam satu aksi unduh).';
comment on column public.export_download_history.domains is
  'Daftar id domain yang diekspor.';

alter table public.export_salinan_counter enable row level security;
alter table public.export_download_history enable row level security;

-- Counter: authenticated boleh baca (preview Salinan ke-N)
drop policy if exists export_salinan_counter_auth_select
  on public.export_salinan_counter;
create policy export_salinan_counter_auth_select
  on public.export_salinan_counter
  for select to authenticated
  using (true);

-- History: semua admin authenticated boleh lihat & insert
drop policy if exists export_download_history_auth_select
  on public.export_download_history;
create policy export_download_history_auth_select
  on public.export_download_history
  for select to authenticated
  using (true);

drop policy if exists export_download_history_auth_insert
  on public.export_download_history;
create policy export_download_history_auth_insert
  on public.export_download_history
  for insert to authenticated
  with check (true);

-- Atomic: ambil nomor salinan berikutnya (global org)
create or replace function public.allocate_export_salinan()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  assigned int;
begin
  insert into public.export_salinan_counter (id, next_salinan)
  values (1, 1)
  on conflict (id) do nothing;

  update public.export_salinan_counter
  set next_salinan = next_salinan + 1
  where id = 1
  returning next_salinan - 1 into assigned;

  return assigned;
end;
$$;

revoke all on function public.allocate_export_salinan() from public;
grant execute on function public.allocate_export_salinan() to authenticated;

comment on function public.allocate_export_salinan() is
  'Atomic increment: mengembalikan nomor Salinan ke-N untuk satu aksi ekspor batch.';

-- Optional convenience: allocate + insert history in one call
create or replace function public.record_export_download(
  p_admin_user_id uuid,
  p_admin_email text,
  p_period_start date,
  p_period_end date,
  p_mode text,
  p_domains text[],
  p_file_count int,
  p_notes text default null,
  p_salinan_ke int default null
)
returns public.export_download_history
language plpgsql
security definer
set search_path = public
as $$
declare
  v_salinan int;
  v_row public.export_download_history;
begin
  if p_mode not in ('gabung', 'pisah') then
    raise exception 'mode must be gabung or pisah';
  end if;

  if p_salinan_ke is null then
    v_salinan := public.allocate_export_salinan();
  else
    v_salinan := p_salinan_ke;
  end if;

  insert into public.export_download_history (
    admin_user_id,
    admin_email,
    period_start,
    period_end,
    mode,
    domains,
    salinan_ke,
    file_count,
    notes
  ) values (
    p_admin_user_id,
    p_admin_email,
    p_period_start,
    p_period_end,
    p_mode,
    coalesce(p_domains, '{}'),
    v_salinan,
    greatest(coalesce(p_file_count, 1), 1),
    p_notes
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.record_export_download(
  uuid, text, date, date, text, text[], int, text, int
) from public;
grant execute on function public.record_export_download(
  uuid, text, date, date, text, text[], int, text, int
) to authenticated;

comment on function public.record_export_download is
  'Catat riwayat unduhan. Jika p_salinan_ke null, allocate nomor baru; jika diisi, pakai nomor yang sudah di-allocate di client.';
