-- =============================================================================
-- Member Resep: phone-scoped list of sales_items with meaningful detail_resep
-- Replaces N+1 get_invoice_hub loops in MemberReorderPage.
-- =============================================================================

create or replace function public.list_member_resep(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.wa_digits(p_phone);
  v_alt text;
begin
  if v_phone is null or length(v_phone) < 8 then
    return '[]'::jsonb;
  end if;

  v_alt := case
    when v_phone like '62%' then '0' || substr(v_phone, 3)
    else v_phone
  end;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc, x.nama_produk)
    from (
      select
        si.id as item_id,
        s.id as sale_id,
        s.no_invoice,
        s.toko_id,
        s.created_at,
        s.foto_hasil_url,
        si.nama_produk,
        si.tipe_produk,
        si.qty,
        si.detail_resep
      from public.sales s
      join public.sales_items si on si.sale_id = s.id
      where (
          public.wa_digits(s.no_wa) = v_phone
          or regexp_replace(coalesce(s.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
        )
        and nullif(trim(coalesce(si.detail_resep, '')), '') is not null
        and lower(trim(si.detail_resep)) <> 'normal'
      order by s.created_at desc, si.nama_produk
      limit 120
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_member_resep(text) from public;
grant execute on function public.list_member_resep(text) to anon, authenticated;

comment on function public.list_member_resep(text) is
  'Riwayat resep Member (phone-scoped) dari sales_items.detail_resep untuk APK Member.';
