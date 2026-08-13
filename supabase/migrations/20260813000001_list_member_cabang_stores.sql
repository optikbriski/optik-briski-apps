-- =============================================================================
-- Member Cabang page: anon-safe store directory (incl. PUSAT + Google Review)
-- =============================================================================
-- invoice_settings RLS is authenticated-only. Member uses anon + custom session,
-- so direct SELECT returns []. list_member_help_stores() omits PUSAT and
-- google_review_url — Cabang UI needs both for map/WA/tanya/review intents.

create or replace function public.list_member_cabang_stores()
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
        'google_review_url', s.google_review_url,
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
      nullif(trim(i.phone), '') as phone,
      nullif(trim(i.google_review_url), '') as google_review_url
    from public.invoice_settings i
    where nullif(trim(i.toko_id), '') is not null
  ) s
  left join public.toko_id t
    on upper(trim(t.id)) = s.toko_id;

  return v_rows;
end;
$$;

comment on function public.list_member_cabang_stores() is
  'Member Cabang directory: toko_id, shop_name, address, phone, google_review_url, lat/lng.';

revoke all on function public.list_member_cabang_stores() from public;
grant execute on function public.list_member_cabang_stores()
  to anon, authenticated, service_role;

-- Keep help-bot directory in sync: expose public Google Review URLs too.
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
        'google_review_url', s.google_review_url,
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
      nullif(trim(i.phone), '') as phone,
      nullif(trim(i.google_review_url), '') as google_review_url
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
  'Member/OBRA store directory: toko_id, shop_name, address, phone, google_review_url, lat/lng.';
