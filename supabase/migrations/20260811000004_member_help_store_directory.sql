-- =============================================================================
-- Member/OBRA: public store directory for help-bot picker + WA (anon-safe)
-- =============================================================================
-- invoice_settings RLS is authenticated-only. Member app uses anon + custom
-- session, so direct SELECT returns []. This SECURITY DEFINER RPC exposes only
-- directory fields needed by OBRA (no secrets / no PII beyond public WA).

create or replace function public.list_member_help_stores()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows json;
begin
  select coalesce(
    json_agg(
      json_build_object(
        'toko_id', s.toko_id,
        'shop_name', s.shop_name,
        'address', s.address,
        'phone', s.phone,
        'latitude', t.latitude,
        'longitude', t.longitude
      )
      order by s.toko_id
    ),
    '[]'::json
  )
  into v_rows
  from (
    select
      upper(trim(i.toko_id)) as toko_id,
      nullif(trim(i.shop_name), '') as shop_name,
      nullif(trim(i.address), '') as address,
      nullif(trim(i.phone), '') as phone
    from public.invoice_settings i
    where nullif(trim(i.toko_id), '') is not null
      and upper(trim(i.toko_id)) not in ('PUSAT', 'CABANG-PUSAT')
  ) s
  left join public.toko_id t
    on upper(trim(t.id)) = s.toko_id;

  return v_rows;
end;
$$;

comment on function public.list_member_help_stores() is
  'Member/OBRA store directory: toko_id, shop_name, address, phone, lat/lng. No PII beyond public branch WA.';

revoke all on function public.list_member_help_stores() from public;
grant execute on function public.list_member_help_stores()
  to anon, authenticated, service_role;
