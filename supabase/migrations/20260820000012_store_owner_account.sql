-- =============================================================================
-- Portal akun owner di APK/web etalase Rekasa.
-- Bukan kasir. Sumber: tenant + tagihan + kontrak + modul yang dibeli.
-- Apply setelah 000011. Jangan dari agent ke live.
-- =============================================================================

create or replace function public.my_tenant_account()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tid uuid;
  v_status text;
  v_plan text;
  v_ind text;
  v_wl boolean;
  v_slug text;
  v_name text;
begin
  if public.is_platform_user() then
    return jsonb_build_object(
      'ok', true,
      'platform', true,
      'shell', 'rekasa_store'
    );
  end if;
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'anon', 'error', 'Belum login');
  end if;

  select p.tenant_id into v_tid from public.profiles p where p.id = auth.uid();
  if v_tid is null then
    select k.tenant_id into v_tid from public.karyawan k where k.id = auth.uid() limit 1;
  end if;
  if v_tid is null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'no_tenant',
      'error',
      'Akun belum diikat ke usaha. Setelah beli, Rekasa kirim akses owner.'
    );
  end if;

  select t.status, t.plan_key, t.industry_key, t.white_label, t.slug,
         coalesce(b.display_name, t.legal_name)
    into v_status, v_plan, v_ind, v_wl, v_slug, v_name
  from public.tenants t
  left join public.app_brand b on b.tenant_id = t.id
  where t.id = v_tid;

  return jsonb_build_object(
    'ok', true,
    'platform', false,
    'tenant_id', v_tid,
    'slug', v_slug,
    'display_name', v_name,
    'status', v_status,
    'plan_key', v_plan,
    'industry_key', v_ind,
    'white_label', coalesce(v_wl, false),
    'shell', case
      when coalesce(v_wl, false) then 'white_label'
      else 'rekasa_shared'
    end,
    'modules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'module_key', m.module_key,
        'enabled', m.enabled
      ) order by m.module_key)
      from public.tenant_modules m
      where m.tenant_id = v_tid
    ), '[]'::jsonb),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'invoice_no', i.invoice_no,
        'period', i.period,
        'amount_idr', i.amount_idr,
        'due_at', i.due_at,
        'paid_at', i.paid_at,
        'status', i.status,
        'notes', i.notes
      ) order by i.due_at desc)
      from public.tenant_invoices i
      where i.tenant_id = v_tid and i.status <> 'void'
    ), '[]'::jsonb),
    'contracts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'contract_no', c.contract_no,
        'title', c.title,
        'status', c.status,
        'amount_idr', c.amount_idr,
        'signed_at', c.signed_at,
        'public_token', c.public_token
      ) order by c.created_at desc)
      from public.tenant_contracts c
      where c.tenant_id = v_tid and c.status <> 'void'
    ), '[]'::jsonb),
    'unsigned_contract_token', (
      select c.public_token from public.tenant_contracts c
      where c.tenant_id = v_tid and c.status in ('sent', 'viewed')
      order by c.created_at desc limit 1
    )
  );
end;
$$;

grant execute on function public.my_tenant_account() to authenticated;

comment on function public.my_tenant_account() is
  'Portal owner di etalase: merek, paket, tagihan Rekasa, kontrak. Bukan data kasir.';
