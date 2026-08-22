-- =============================================================================
-- Hak akses klien = baris tenant + tenant_modules.
-- Etalase menulis. APK toko membaca. Bukan APK terpisah per mix fitur.
-- Apply setelah 000010. Jangan dari agent ke live.
-- =============================================================================

create or replace function public.my_tenant_entitlements()
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
      'shell', 'rekasa_store',
      'modules', '[]'::jsonb
    );
  end if;
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'anon');
  end if;

  -- Baca dari profil/karyawan, bukan current_tenant_id()
  -- (itu bisa null saat trial/suspend).
  select p.tenant_id into v_tid from public.profiles p where p.id = auth.uid();
  if v_tid is null then
    select k.tenant_id into v_tid from public.karyawan k where k.id = auth.uid() limit 1;
  end if;
  if v_tid is null then
    return jsonb_build_object('ok', false, 'reason', 'no_tenant');
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
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.my_tenant_entitlements() to authenticated;

comment on function public.my_tenant_entitlements() is
  'Sumber kebenaran menu APK toko. Etalase menulis tenant_modules; APK membaca ini.';

-- Operator Rekasa lihat hak tenant setelah beli (bukan hak akun platform).
create or replace function public.platform_tenant_entitlements(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_status text;
  v_plan text;
  v_ind text;
  v_wl boolean;
  v_slug text;
  v_name text;
begin
  if not public.is_platform_user() then
    return jsonb_build_object('ok', false, 'error', 'not_platform');
  end if;
  if p_tenant_id is null then
    return jsonb_build_object('ok', false, 'error', 'tenant_required');
  end if;

  select t.status, t.plan_key, t.industry_key, t.white_label, t.slug,
         coalesce(b.display_name, t.legal_name)
    into v_status, v_plan, v_ind, v_wl, v_slug, v_name
  from public.tenants t
  left join public.app_brand b on b.tenant_id = t.id
  where t.id = p_tenant_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'platform', false,
    'tenant_id', p_tenant_id,
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
      where m.tenant_id = p_tenant_id
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.platform_tenant_entitlements(uuid) to authenticated;

-- Struk beli: modul yang baru ditulis + jenis APK yang harus di-install.
create or replace function public.submit_store_order(
  p_plan_key text,
  p_modules jsonb,
  p_white_label boolean,
  p_display_name text,
  p_slug text,
  p_phone text,
  p_email text default null,
  p_legal_name text default null,
  p_signer_name text default null,
  p_industry_key text default 'umum'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote jsonb;
  v_amount bigint;
  v_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_slug text := public.normalize_tenant_slug(p_slug);
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
  v_id uuid := gen_random_uuid();
  v_tid uuid;
  v_pusat text;
  v_code text;
  v_plan text := lower(trim(coalesce(p_plan_key, 'paket_c')));
  v_ind text := lower(trim(coalesce(p_industry_key, 'umum')));
  v_inv uuid := gen_random_uuid();
  v_inv_no text;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_ctr_no text;
  v_body text;
  v_label text;
  v_upgrade boolean := false;
  v_existing uuid;
  v_modules jsonb;
  v_wl boolean := coalesce(p_white_label, false);
begin
  if v_name is null then
    raise exception 'Nama usaha wajib';
  end if;
  if v_slug is null or length(v_slug) < 3 then
    raise exception 'Kode usaha minimal 3 huruf';
  end if;
  if v_phone is null or length(v_phone) < 8 then
    raise exception 'Nomor WA / HP wajib';
  end if;
  if not exists (select 1 from public.store_industries i where i.industry_key = v_ind) then
    v_ind := 'umum';
  end if;

  v_quote := public.quote_store_order(v_plan, p_modules, v_wl, v_ind);
  v_amount := (v_quote ->> 'amount_idr')::bigint;

  if auth.uid() is not null and not public.is_platform_user() then
    select p.tenant_id into v_existing from public.profiles p where p.id = auth.uid();
    if v_existing is not null then
      v_upgrade := true;
      v_tid := v_existing;
    end if;
  end if;

  if not v_upgrade then
    if exists (select 1 from public.tenants t where t.slug = v_slug) then
      raise exception 'Kode usaha sudah dipakai. Pilih slug lain.';
    end if;
    v_tid := gen_random_uuid();
    v_code := upper(regexp_replace(v_slug, '[^a-z0-9]', '', 'g'));
    if length(v_code) > 16 then
      v_code := substr(v_code, 1, 16);
    end if;
    v_pusat := v_code || '-PUSAT';
    if exists (select 1 from public.toko_id t where t.id = v_pusat) then
      v_pusat := substr(replace(v_tid::text, '-', ''), 1, 8) || '-PUSAT';
    end if;

    insert into public.tenants (
      id, slug, legal_name, status, pusat_toko_id, plan_key, white_label, industry_key
    ) values (
      v_tid, v_slug,
      coalesce(nullif(trim(coalesce(p_legal_name, '')), ''), v_name),
      'trial', v_pusat, v_plan, v_wl, v_ind
    );
    insert into public.toko_id (id, toko_id, tenant_id, cabang_code, is_pusat)
    values (v_pusat, v_name || ' — Pusat', v_tid, 'PUSAT', true);
    insert into public.app_brand (id, tenant_id, display_name, short_name, assistant_name)
    values (v_tid::text, v_tid, v_name, left(v_name, 8), left(v_name, 4) || 'A');
    insert into public.member_home_content (
      id, tenant_id, brand_label, greeting_guest, greeting_subtitle_guest
    ) values (
      v_tid::text, v_tid, upper(v_name), 'Hi!', 'Login untuk lihat pesanan'
    );
    insert into public.invoice_settings (toko_id, shop_name, tenant_id)
    values (v_pusat, v_name || ' PUSAT', v_tid)
    on conflict (toko_id) do nothing;
    perform public.apply_tenant_plan(v_tid, v_plan);
  else
    select t.slug into v_slug from public.tenants t where t.id = v_tid;
    update public.tenants
    set plan_key = v_plan, industry_key = v_ind, updated_at = now()
    where id = v_tid;
    perform public.apply_tenant_plan(v_tid, v_plan);
  end if;

  perform public.apply_store_modules(v_tid, coalesce(p_modules, '{}'::jsonb), v_wl);

  v_inv_no := 'RK-INV-' || to_char(now(), 'YYYYMM') || '-'
    || lpad(nextval('public.tenant_invoice_seq')::text, 4, '0');
  insert into public.tenant_invoices (
    id, tenant_id, invoice_no, period, amount_idr, due_at, status, notes
  ) values (
    v_inv, v_tid, v_inv_no,
    case
      when v_upgrade then to_char(now(), 'YYYY-MM') || '-U' || nextval('public.tenant_invoice_seq')::text
      else to_char(now(), 'YYYY-MM')
    end,
    v_amount,
    now() + interval '7 days', 'sent',
    'Pesanan etalase Rekasa · ' || v_ind
  );

  select c.label into v_label from public.tenant_plan_catalog c where c.plan_key = v_plan;
  v_body := public.rekasa_contract_template(v_name, p_legal_name, v_slug, v_label, v_amount);
  v_ctr_no := 'RK-KTR-' || to_char(now(), 'YYYY') || '-'
    || lpad(nextval('public.tenant_contract_seq')::text, 4, '0');
  insert into public.tenant_contracts (
    tenant_id, contract_no, public_token, title, body, plan_key, amount_idr, status
  ) values (
    v_tid, v_ctr_no, v_token,
    'Perjanjian langganan Rekasa — ' || v_name,
    v_body, v_plan, v_amount, 'sent'
  );

  insert into public.store_orders (
    id, tenant_id, plan_key, modules, white_label, amount_idr,
    display_name, slug, legal_name, phone, email, signer_name,
    status, invoice_id, contract_token, industry_key
  ) values (
    v_id, v_tid, v_plan, coalesce(p_modules, '{}'::jsonb),
    v_wl, v_amount,
    v_name, v_slug, p_legal_name, v_phone, p_email, p_signer_name,
    'provisioned', v_inv, v_token, v_ind
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object('module_key', tm.module_key, 'enabled', tm.enabled)
      order by tm.module_key
    ),
    '[]'::jsonb
  )
    into v_modules
    from public.tenant_modules tm
   where tm.tenant_id = v_tid;

  return jsonb_build_object(
    'ok', true,
    'order_id', v_id,
    'tenant_id', v_tid,
    'slug', v_slug,
    'industry_key', v_ind,
    'upgrade', v_upgrade,
    'amount_idr', v_amount,
    'invoice_no', v_inv_no,
    'invoice_id', v_inv,
    'contract_token', v_token,
    'status', 'provisioned',
    'modules', v_modules,
    'shell', case when v_wl then 'white_label' else 'rekasa_shared' end,
    'white_label', v_wl
  );
end;
$$;

grant execute on function public.submit_store_order(text, jsonb, boolean, text, text, text, text, text, text, text)
  to anon, authenticated;
