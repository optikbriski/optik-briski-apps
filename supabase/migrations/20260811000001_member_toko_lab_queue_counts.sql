-- =============================================================================
-- Member/OBRA: aggregate lab / production queue counts per toko (no PII)
-- =============================================================================
-- Waiting   = lab_jobs OPEN (belum diklaim)
-- In progress = lab_jobs CLAIMED (sedang dikerjakan)
-- Ready     = sales siap diambil (SIAP_DIAMBIL / CLEAR, belum diambil_at)
-- Never returns invoice numbers, names, phones, or claimed_by.

create or replace function public.get_toko_lab_queue_counts(p_toko_id text)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_toko text := upper(trim(coalesce(p_toko_id, '')));
  v_waiting int := 0;
  v_in_progress int := 0;
  v_ready int := 0;
  v_exists boolean := false;
begin
  if v_toko = '' then
    return json_build_object(
      'toko_id', null,
      'waiting', 0,
      'in_progress', 0,
      'ready', 0,
      'ok', false,
      'error', 'toko_id_required'
    );
  end if;

  select exists(
    select 1 from public.toko_id t where upper(trim(t.id)) = v_toko
  ) into v_exists;

  if not v_exists then
    -- Also accept invoice_settings.toko_id (some envs seed settings first).
    select exists(
      select 1
      from public.invoice_settings s
      where upper(trim(s.toko_id)) = v_toko
    ) into v_exists;
  end if;

  if not v_exists then
    return json_build_object(
      'toko_id', v_toko,
      'waiting', 0,
      'in_progress', 0,
      'ready', 0,
      'ok', false,
      'error', 'toko_not_found'
    );
  end if;

  select count(*)::int into v_waiting
  from public.lab_jobs j
  where upper(trim(coalesce(j.toko_id, ''))) = v_toko
    and upper(trim(j.status)) = 'OPEN';

  select count(*)::int into v_in_progress
  from public.lab_jobs j
  where upper(trim(coalesce(j.toko_id, ''))) = v_toko
    and upper(trim(j.status)) = 'CLAIMED';

  select count(*)::int into v_ready
  from public.sales s
  where upper(trim(coalesce(s.toko_id, ''))) = v_toko
    and upper(trim(coalesce(s.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR')
    and s.diambil_at is null;

  return json_build_object(
    'toko_id', v_toko,
    'waiting', v_waiting,
    'in_progress', v_in_progress,
    'ready', v_ready,
    'ok', true
  );
end;
$$;

comment on function public.get_toko_lab_queue_counts(text) is
  'Member-safe aggregates: lab waiting/in_progress + siap-ambil counts for one toko. No PII.';

revoke all on function public.get_toko_lab_queue_counts(text) from public;
grant execute on function public.get_toko_lab_queue_counts(text)
  to anon, authenticated, service_role;
