-- =============================================================================
-- Restore list_member_garansi (phone-scoped SECURITY DEFINER).
-- App Member calls rpc('list_member_garansi', {p_phone}) for kartu list + klaim picker.
-- Defined historically in 20260727000002_member_app_features.sql but missing on linked DB
-- after partial apply of member garansi claim RPCs.
-- =============================================================================

create or replace function public.list_member_garansi(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
begin
  if v_phone is null then return '[]'::jsonb; end if;
  v_alt := case when v_phone like '62%' then '0' || substr(v_phone, 3) else v_phone end;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.tanggal_akhir desc nulls last)
    from (
      select g.*
      from public.garansi_kartu g
      where public.wa_digits(g.no_wa) = v_phone
         or regexp_replace(coalesce(g.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
      order by g.tanggal_akhir desc nulls last
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

comment on function public.list_member_garansi(text) is
  'Daftar kartu garansi Member — hanya baris nomor HP pemanggil.';

grant execute on function public.list_member_garansi(text) to anon, authenticated;
