-- =============================================================================
-- 000051 — Konten home Member: tenant wajib, tanpa default Optik.
-- Apply di SQL Editor live SETELAH 000050. Idempotent.
--
-- Celah di file 000003 (live 000007 sudah menutup default):
-- - get_member_home_content / list_member_promos / lookup_member_promo
--   tertulis default UUID Optik → merek lain / tanpa tenant bisa jatuh ke #1
-- =============================================================================

create or replace function public.get_member_home_content(
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
  v jsonb;
begin
  select to_jsonb(x) into v
  from (
    select brand_label, slides, greeting_guest, greeting_subtitle_guest,
           promo_title, promo_subtitle, sections, feature_flags
    from public.member_home_content
    where tenant_id = v_tenant
    limit 1
  ) x;
  return v;
end;
$$;
grant execute on function public.get_member_home_content(uuid) to anon, authenticated;

create or replace function public.list_member_promos(
  p_for_member boolean default true,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p) order by p.sort_order nulls last, p.created_at)
    from public.member_promos p
    where p.tenant_id = v_tenant
      and p.active = true
      and (p_for_member is not true or coalesce(p.show_on_member, true) = true)
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.list_member_promos(boolean, uuid)
  to anon, authenticated;

create or replace function public.lookup_member_promo(
  p_code text,
  p_channel text default 'pos',
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.member_promos%rowtype;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_ch text := lower(trim(coalesce(p_channel, 'pos')));
  v_tenant uuid := coalesce(public.current_tenant_id(), public.require_member_tenant(p_tenant_id));
begin
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Kode kosong');
  end if;
  if v_ch not in ('pos', 'online', 'member', 'any') then
    v_ch := 'pos';
  end if;

  select * into v_row
  from public.member_promos
  where tenant_id = v_tenant
    and upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and (
      (v_ch = 'pos' and coalesce(show_on_pos, true) = true)
      or (v_ch in ('online', 'member') and coalesce(show_on_member, true) = true)
      or (
        v_ch = 'any'
        and (coalesce(show_on_pos, true) = true or coalesce(show_on_member, true) = true)
      )
    )
  order by sort_order nulls last, created_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error',
      case
        when v_ch in ('online', 'member')
          then 'Voucher tidak ditemukan / tidak aktif di Member'
        else 'Voucher tidak ditemukan / tidak aktif di POS'
      end
    );
  end if;
  if v_row.valid_until is not null and v_row.valid_until < current_date then
    return jsonb_build_object('ok', false, 'error', 'Voucher kedaluwarsa');
  end if;
  if v_row.quantity_remaining is not null and v_row.quantity_remaining <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Kuota voucher habis');
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'title', v_row.title,
    'description', v_row.description,
    'voucher_code', v_row.voucher_code,
    'discount_type', v_row.discount_type,
    'discount_value', v_row.discount_value,
    'quantity_remaining', v_row.quantity_remaining,
    'points_cost', v_row.points_cost,
    'terms', v_row.terms,
    'channel', v_ch
  );
end;
$$;
grant execute on function public.lookup_member_promo(text, text, uuid)
  to anon, authenticated, service_role;
