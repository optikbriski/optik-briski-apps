-- =============================================================================
-- SQL audit 2026-08-16: members.password_hash was readable by anon via PostgREST
-- (members_anon_all + table SELECT). Flutter has no .from('members'); access is
-- via SECURITY DEFINER RPCs + Edge service_role. Revoke direct client table
-- privileges so password_hash cannot be scraped.
-- Idempotent / safe to re-run.
-- =============================================================================

revoke all on table public.members from anon, authenticated;

-- Keep RLS policies for defense-in-depth if grants are re-added later, but
-- remove the wide-open anon/authenticated ALL policy.
drop policy if exists members_anon_all on public.members;

-- Staff/admin (authenticated with pusat role) may still need CRM reads via table.
-- Gate with existing approver helper; service_role bypasses RLS.
drop policy if exists members_staff_select on public.members;
create policy members_staff_select on public.members
  for select to authenticated
  using (public.is_admin_pusat_approver());

drop policy if exists members_staff_write on public.members;
create policy members_staff_write on public.members
  for all to authenticated
  using (public.is_admin_pusat_approver())
  with check (public.is_admin_pusat_approver());

-- Re-grant SELECT/DML only to staff path after revoke-all — still constrained by RLS above.
grant select, insert, update, delete on table public.members to authenticated;
-- anon: no direct table grants (RPC only)

comment on table public.members is
  'Member profiles. Direct anon access revoked; use SECURITY DEFINER RPCs. password_hash never exposed to PostgREST anon.';
