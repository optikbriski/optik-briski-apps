-- Break RLS recursion: payroll_period <-> payroll_lines <-> components/settings.
-- Policies must not SELECT each other under RLS (Postgres 42P17).

create or replace function public.payroll_period_has_my_slip(p_period_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.payroll_lines l
    where l.period_id = p_period_id
      and l.karyawan_id = auth.uid()
  );
$$;

create or replace function public.payroll_line_visible(
  p_period_id uuid,
  p_karyawan_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.payroll_period p
    where p.id = p_period_id
      and (
        public.is_admin_pusat_or_owner()
        or public.is_owner_provisioner()
        or public.owner_can_access_toko(p.toko_id)
        or (
          p.status in ('dikunci', 'dibayar')
          and p_karyawan_id = auth.uid()
        )
      )
  );
$$;

create or replace function public.payroll_component_visible(p_line_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.payroll_lines l
    where l.id = p_line_id
      and public.payroll_line_visible(l.period_id, l.karyawan_id)
  );
$$;

create or replace function public.payroll_settings_visible(p_period_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.payroll_period p
    where p.id = p_period_id
      and (
        public.is_admin_pusat_or_owner()
        or public.is_owner_provisioner()
        or public.owner_can_access_toko(p.toko_id)
        or (
          p.status in ('dikunci', 'dibayar')
          and public.payroll_period_has_my_slip(p.id)
        )
      )
  );
$$;

revoke all on function public.payroll_period_has_my_slip(uuid) from public;
revoke all on function public.payroll_line_visible(uuid, uuid) from public;
revoke all on function public.payroll_component_visible(uuid) from public;
revoke all on function public.payroll_settings_visible(uuid) from public;
grant execute on function public.payroll_period_has_my_slip(uuid) to authenticated;
grant execute on function public.payroll_line_visible(uuid, uuid) to authenticated;
grant execute on function public.payroll_component_visible(uuid) to authenticated;
grant execute on function public.payroll_settings_visible(uuid) to authenticated;

drop policy if exists payroll_period_select on public.payroll_period;
create policy payroll_period_select on public.payroll_period
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or public.is_owner_provisioner()
    or public.owner_can_access_toko(toko_id)
    or (
      status in ('dikunci', 'dibayar')
      and public.payroll_period_has_my_slip(id)
    )
  );

drop policy if exists payroll_lines_select on public.payroll_lines;
create policy payroll_lines_select on public.payroll_lines
  for select to authenticated
  using (public.payroll_line_visible(period_id, karyawan_id));

drop policy if exists payroll_period_settings_select on public.payroll_period_settings;
create policy payroll_period_settings_select on public.payroll_period_settings
  for select to authenticated
  using (public.payroll_settings_visible(period_id));

drop policy if exists payroll_line_components_select on public.payroll_line_components;
create policy payroll_line_components_select on public.payroll_line_components
  for select to authenticated
  using (public.payroll_component_visible(line_id));

comment on function public.payroll_line_visible(uuid, uuid) is
  'SECURITY DEFINER: visibility without RLS recursion across payroll_period/lines.';
