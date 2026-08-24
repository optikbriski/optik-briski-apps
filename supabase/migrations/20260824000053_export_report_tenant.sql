-- =============================================================================
-- 000053 — Laporan PDF: counter salinan + riwayat per tenant, bukan global.
-- Apply di SQL Editor live SETELAH 000052. Idempotent.
--
-- Celah saat toko jalan:
-- - allocate_export_salinan() 0-arg GRANT anon → siapa pun dengan anon key
--   bisa menaikkan counter bersama semua merek
-- - export_salinan_counter id=1 dipakai semua tenant
-- - export_download_history RLS using(true) → staf satu merek lihat email /
--   periode merek lain
-- =============================================================================

create table if not exists public.export_salinan_counter_tenant (
  tenant_id uuid primary key
    references public.tenants (id) on delete cascade,
  next_salinan int not null default 1
    check (next_salinan >= 1)
);

comment on table public.export_salinan_counter_tenant is
  'Nomor Salinan berikutnya. Satu baris per tenant, bukan counter global.';

insert into public.export_salinan_counter_tenant (tenant_id, next_salinan)
select t.id, greatest(
  coalesce(
    (select c.next_salinan from public.export_salinan_counter c where c.id = 1),
    1
  ),
  4
)
from public.tenants t
on conflict (tenant_id) do update
set next_salinan = greatest(
  public.export_salinan_counter_tenant.next_salinan,
  excluded.next_salinan
);

alter table public.export_download_history
  add column if not exists tenant_id uuid
    references public.tenants (id) on delete cascade;

update public.export_download_history h
set tenant_id = t.id
from public.tenants t
where h.tenant_id is null
  and t.slug = 'optik-briski';

create index if not exists export_download_history_tenant_period_idx
  on public.export_download_history (tenant_id, period_start, period_end);

alter table public.export_salinan_counter_tenant enable row level security;

revoke all on table public.export_salinan_counter_tenant from public, anon;
grant select on table public.export_salinan_counter_tenant to authenticated;

drop policy if exists export_salinan_counter_tenant_staff
  on public.export_salinan_counter_tenant;
create policy export_salinan_counter_tenant_staff
  on public.export_salinan_counter_tenant
  for select
  to authenticated
  using (
    public.is_platform_user()
    or tenant_id = public.current_tenant_id()
  );

drop policy if exists export_salinan_counter_auth_select
  on public.export_salinan_counter;
create policy export_salinan_counter_platform
  on public.export_salinan_counter
  for select
  to authenticated
  using (public.is_platform_user());

drop policy if exists export_download_history_auth_select
  on public.export_download_history;
drop policy if exists export_download_history_auth_insert
  on public.export_download_history;
drop policy if exists export_download_history_all
  on public.export_download_history;
drop policy if exists export_download_history_staff
  on public.export_download_history;
create policy export_download_history_staff
  on public.export_download_history
  for all
  to authenticated
  using (
    public.is_platform_user()
    or tenant_id = public.current_tenant_id()
  )
  with check (
    public.is_platform_user()
    or tenant_id = public.current_tenant_id()
  );

do $$
begin
  revoke all on function public.allocate_export_salinan()
    from public, anon, authenticated;
exception
  when undefined_function then
    null;
end $$;

drop function if exists public.allocate_export_salinan();

create or replace function public.allocate_export_salinan(
  p_tenant_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_next int;
begin
  v_tenant := coalesce(p_tenant_id, public.current_tenant_id());
  if v_tenant is null then
    raise exception 'Sesi tenant tidak valid.';
  end if;
  v_tenant := public.require_member_tenant(v_tenant);
  if not public.is_platform_user()
     and public.current_tenant_id() is not null
     and public.current_tenant_id() <> v_tenant then
    raise exception 'Tenant tidak cocok.';
  end if;

  insert into public.export_salinan_counter_tenant (tenant_id, next_salinan)
  values (v_tenant, 2)
  on conflict (tenant_id) do update
    set next_salinan = public.export_salinan_counter_tenant.next_salinan + 1
  returning next_salinan - 1 into v_next;

  update public.export_salinan_counter
  set next_salinan = greatest(next_salinan, v_next + 1)
  where id = 1;

  return v_next;
end;
$$;

comment on function public.allocate_export_salinan(uuid) is
  'Nomor Salinan ke-N per tenant. Anon tidak boleh. Null tenant ditolak.';

revoke all on function public.allocate_export_salinan(uuid) from public;
revoke all on function public.allocate_export_salinan(uuid) from anon;
grant execute on function public.allocate_export_salinan(uuid) to authenticated;

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
  v_tenant uuid;
  v_row public.export_download_history;
begin
  if p_mode not in ('gabung', 'pisah') then
    raise exception 'mode must be gabung or pisah';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Sesi tenant tidak valid.';
  end if;
  v_tenant := public.require_member_tenant(v_tenant);

  if p_salinan_ke is null then
    v_salinan := public.allocate_export_salinan(v_tenant);
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
    notes,
    tenant_id
  ) values (
    p_admin_user_id,
    p_admin_email,
    p_period_start,
    p_period_end,
    p_mode,
    coalesce(p_domains, '{}'),
    v_salinan,
    greatest(coalesce(p_file_count, 1), 1),
    p_notes,
    v_tenant
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.record_export_download(
  uuid, text, date, date, text, text[], int, text, int
) from public;
revoke all on function public.record_export_download(
  uuid, text, date, date, text, text[], int, text, int
) from anon;
grant execute on function public.record_export_download(
  uuid, text, date, date, text, text[], int, text, int
) to authenticated;
