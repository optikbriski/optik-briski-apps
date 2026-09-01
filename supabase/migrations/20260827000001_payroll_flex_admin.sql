-- =============================================================================
-- Flexible Admin-driven payroll: templates, assignments, period settings,
-- overtime entries, line components, compute/submit RPCs.
-- Idempotent. No business rates hardcoded — values come from Admin payload/DB.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------
create table if not exists public.payroll_rule_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id text,
  toko_id text references public.toko_id (id) on delete cascade,
  nama text not null,
  aktif boolean not null default true,
  components jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payroll_rule_templates_toko_idx
  on public.payroll_rule_templates (toko_id) where aktif;

create table if not exists public.payroll_rule_assignments (
  karyawan_id uuid primary key references public.karyawan (id) on delete cascade,
  template_id uuid references public.payroll_rule_templates (id) on delete set null,
  overrides jsonb not null default '{}'::jsonb,
  -- overrides example:
  -- { "gaji_pokok": 5000000, "overtime_rate_rp": 25000,
  --   "allowances": [{"key":"makan","label":"Makan","amount":300000}],
  --   "deductions": [{"key":"bpjs","label":"BPJS","amount":100000}],
  --   "tax_mode":"percent","tax_percent":5,"tax_nominal":null }
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id)
);

create table if not exists public.payroll_period_settings (
  period_id uuid primary key references public.payroll_period (id) on delete cascade,
  bonus_mode text not null
    check (bonus_mode in ('pool', 'rp_per_poin')),
  bonus_pool_rp bigint,
  rp_per_poin bigint,
  omzet_referensi bigint,
  notes text,
  submitted_at timestamptz,
  submitted_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  constraint payroll_period_settings_pool_chk check (
    (bonus_mode = 'pool' and bonus_pool_rp is not null)
    or (bonus_mode = 'rp_per_poin' and rp_per_poin is not null)
  )
);

create table if not exists public.payroll_overtime_entries (
  id uuid primary key default gen_random_uuid(),
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  toko_id text not null references public.toko_id (id) on delete cascade,
  periode_ym text not null check (periode_ym ~ '^\d{4}-\d{2}$'),
  tanggal date,
  jam numeric(8,2) not null default 0 check (jam >= 0),
  rate_rp bigint not null default 0 check (rate_rp >= 0),
  jumlah_rp bigint not null default 0,
  status text not null default 'approved'
    check (status in ('draft', 'approved')),
  meta jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payroll_ot_toko_ym_idx
  on public.payroll_overtime_entries (toko_id, periode_ym);

create table if not exists public.payroll_line_components (
  id uuid primary key default gen_random_uuid(),
  line_id uuid not null references public.payroll_lines (id) on delete cascade,
  key text not null,
  label text not null,
  kind text not null,
  amount bigint not null default 0,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists payroll_line_components_line_idx
  on public.payroll_line_components (line_id);

-- -----------------------------------------------------------------------------
-- 2. RLS
-- -----------------------------------------------------------------------------
alter table public.payroll_rule_templates enable row level security;
alter table public.payroll_rule_assignments enable row level security;
alter table public.payroll_period_settings enable row level security;
alter table public.payroll_overtime_entries enable row level security;
alter table public.payroll_line_components enable row level security;

drop policy if exists payroll_rule_templates_select on public.payroll_rule_templates;
create policy payroll_rule_templates_select on public.payroll_rule_templates
  for select to authenticated
  using (public.is_admin_pusat_or_owner() or public.is_owner_provisioner());

drop policy if exists payroll_rule_templates_write on public.payroll_rule_templates;
create policy payroll_rule_templates_write on public.payroll_rule_templates
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

drop policy if exists payroll_rule_assignments_select on public.payroll_rule_assignments;
create policy payroll_rule_assignments_select on public.payroll_rule_assignments
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or public.is_owner_provisioner()
    or karyawan_id = auth.uid()
  );

drop policy if exists payroll_rule_assignments_write on public.payroll_rule_assignments;
create policy payroll_rule_assignments_write on public.payroll_rule_assignments
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

drop policy if exists payroll_period_settings_select on public.payroll_period_settings;
create policy payroll_period_settings_select on public.payroll_period_settings
  for select to authenticated
  using (
    exists (
      select 1 from public.payroll_period p
      where p.id = period_id
        and (
          public.is_admin_pusat_or_owner()
          or public.owner_can_access_toko(p.toko_id)
          or (
            p.status in ('dikunci', 'dibayar')
              and exists (
              select 1 from public.payroll_lines l
              where l.period_id = p.id and l.karyawan_id = auth.uid()
            )
          )
        )
    )
  );

drop policy if exists payroll_period_settings_write on public.payroll_period_settings;
create policy payroll_period_settings_write on public.payroll_period_settings
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

drop policy if exists payroll_ot_select on public.payroll_overtime_entries;
create policy payroll_ot_select on public.payroll_overtime_entries
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or public.is_owner_provisioner()
    or karyawan_id = auth.uid()
  );

drop policy if exists payroll_ot_write on public.payroll_overtime_entries;
create policy payroll_ot_write on public.payroll_overtime_entries
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

drop policy if exists payroll_line_components_select on public.payroll_line_components;
create policy payroll_line_components_select on public.payroll_line_components
  for select to authenticated
  using (
    exists (
      select 1
      from public.payroll_lines l
      join public.payroll_period p on p.id = l.period_id
      left join public.karyawan k on k.id = l.karyawan_id
      where l.id = line_id
        and (
          public.is_admin_pusat_or_owner()
          or public.owner_can_access_toko(p.toko_id)
          or (
            p.status in ('dikunci', 'dibayar')
            and l.karyawan_id = auth.uid()
          )
        )
    )
  );

drop policy if exists payroll_line_components_write on public.payroll_line_components;
create policy payroll_line_components_write on public.payroll_line_components
  for all to authenticated
  using (public.is_owner_provisioner())
  with check (public.is_owner_provisioner());

-- Karyawan: lihat line sendiri hanya jika period terkunci/dibayar
drop policy if exists payroll_lines_select on public.payroll_lines;
create policy payroll_lines_select on public.payroll_lines
  for select to authenticated
  using (
    exists (
      select 1 from public.payroll_period p
      where p.id = period_id
        and (
          public.is_admin_pusat_or_owner()
          or public.owner_can_access_toko(p.toko_id)
          or (
            p.status in ('dikunci', 'dibayar')
            and karyawan_id = auth.uid()
          )
        )
    )
  );

drop policy if exists payroll_period_select on public.payroll_period;
create policy payroll_period_select on public.payroll_period
  for select to authenticated
  using (
    public.is_admin_pusat_or_owner()
    or public.owner_can_access_toko(toko_id)
    or (
      status in ('dikunci', 'dibayar')
      and exists (
        select 1 from public.payroll_lines l
        where l.period_id = id and l.karyawan_id = auth.uid()
      )
    )
  );

-- -----------------------------------------------------------------------------
-- 3. Batch assign rules (group apply)
-- -----------------------------------------------------------------------------
create or replace function public.admin_upsert_payroll_assignments(
  p_karyawan_ids uuid[],
  p_template_id uuid,
  p_overrides jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_n int := 0;
begin
  if not public.is_owner_provisioner() then
    raise exception 'Hanya admin pusat / Owner Utama';
  end if;
  if p_karyawan_ids is null or cardinality(p_karyawan_ids) = 0 then
    raise exception 'Pilih minimal satu karyawan';
  end if;
  if p_template_id is not null
     and not exists (select 1 from public.payroll_rule_templates t where t.id = p_template_id) then
    raise exception 'Template tidak ditemukan';
  end if;

  foreach v_id in array p_karyawan_ids loop
    insert into public.payroll_rule_assignments as a (
      karyawan_id, template_id, overrides, updated_at, updated_by
    ) values (
      v_id, p_template_id, coalesce(p_overrides, '{}'::jsonb), now(), auth.uid()
    )
    on conflict (karyawan_id) do update set
      template_id = excluded.template_id,
      overrides = excluded.overrides,
      updated_at = now(),
      updated_by = auth.uid();
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('ok', true, 'count', v_n);
end;
$$;

revoke all on function public.admin_upsert_payroll_assignments(uuid[], uuid, jsonb) from public;
grant execute on function public.admin_upsert_payroll_assignments(uuid[], uuid, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Save computed period (client engine) — atomic draft or lock
-- -----------------------------------------------------------------------------
create or replace function public.admin_save_payroll_period(
  p_toko_id text,
  p_periode_ym text,
  p_settings jsonb,
  p_lines jsonb,
  p_lock boolean default false,
  p_mark_paid boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ym text := trim(p_periode_ym);
  v_existing public.payroll_period%rowtype;
  v_period_id uuid;
  v_status text;
  v_mode text;
  v_line jsonb;
  v_comp jsonb;
  v_line_id uuid;
  v_total_pokok bigint := 0;
  v_total_tunj bigint := 0;
  v_total_pot bigint := 0;
  v_total_nett bigint := 0;
  v_count int := 0;
  v_out jsonb;
begin
  if not public.is_owner_provisioner() then
    raise exception 'Hanya admin pusat / Owner Utama yang boleh simpan payroll';
  end if;
  if v_ym !~ '^\d{4}-\d{2}$' then
    raise exception 'periode_ym harus YYYY-MM';
  end if;
  if not exists (select 1 from public.toko_id t where t.id = p_toko_id) then
    raise exception 'Toko tidak ditemukan';
  end if;

  select * into v_existing
  from public.payroll_period
  where toko_id = p_toko_id and periode_ym = v_ym;

  if v_existing.id is not null and v_existing.status = 'dibayar' then
    raise exception 'Periode sudah dibayar — tidak bisa diubah';
  end if;
  if v_existing.id is not null
     and v_existing.status = 'dikunci'
     and not p_mark_paid then
    raise exception 'Periode terkunci — buka kunci dulu atau tandai dibayar';
  end if;

  v_mode := coalesce(p_settings->>'bonus_mode', '');
  if v_mode not in ('pool', 'rp_per_poin') then
    raise exception 'bonus_mode harus pool atau rp_per_poin';
  end if;
  if v_mode = 'pool' and (p_settings->>'bonus_pool_rp') is null then
    raise exception 'bonus_pool_rp wajib untuk mode pool';
  end if;
  if v_mode = 'rp_per_poin' and (p_settings->>'rp_per_poin') is null then
    raise exception 'rp_per_poin wajib untuk mode rp_per_poin';
  end if;

  if p_mark_paid then
    if v_existing.id is null or v_existing.status not in ('dikunci', 'dibayar') then
      raise exception 'Tandai dibayar hanya setelah periode dikunci';
    end if;
    update public.payroll_period
    set status = 'dibayar', paid_at = coalesce(paid_at, now()), updated_at = now()
    where id = v_existing.id;
    v_period_id := v_existing.id;
  else
    v_status := case when p_lock then 'dikunci' else 'draft' end;

    insert into public.payroll_period as b (
      toko_id, periode_ym, status,
      total_gaji_pokok, total_tunjangan, total_potongan, total_nett, line_count,
      computed_at, locked_at, computed_by, updated_at
    ) values (
      p_toko_id, v_ym, v_status,
      0, 0, 0, 0, 0,
      now(),
      case when p_lock then now() else null end,
      auth.uid(),
      now()
    )
    on conflict (toko_id, periode_ym) do update set
      status = excluded.status,
      computed_at = excluded.computed_at,
      locked_at = case
        when excluded.status = 'dikunci' then coalesce(b.locked_at, now())
        else null
      end,
      computed_by = excluded.computed_by,
      updated_at = now()
    returning b.id into v_period_id;

    delete from public.payroll_line_components c
    using public.payroll_lines l
    where c.line_id = l.id and l.period_id = v_period_id;
    delete from public.payroll_lines where period_id = v_period_id;

    for v_line in
      select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
    loop
      insert into public.payroll_lines (
        period_id, karyawan_id, nama, jabatan,
        gaji_pokok, tunjangan, potongan, nett, meta
      ) values (
        v_period_id,
        (v_line->>'karyawan_id')::uuid,
        coalesce(v_line->>'nama', '-'),
        v_line->>'jabatan',
        coalesce((v_line->>'gaji_pokok')::bigint, 0),
        coalesce((v_line->>'tunjangan')::bigint, 0),
        coalesce((v_line->>'potongan')::bigint, 0),
        coalesce((v_line->>'nett')::bigint, 0),
        coalesce(v_line->'meta', '{}'::jsonb)
      )
      returning id into v_line_id;

      for v_comp in
        select * from jsonb_array_elements(coalesce(v_line->'components', '[]'::jsonb))
      loop
        insert into public.payroll_line_components (
          line_id, key, label, kind, amount, meta
        ) values (
          v_line_id,
          coalesce(v_comp->>'key', 'x'),
          coalesce(v_comp->>'label', coalesce(v_comp->>'key', 'Komponen')),
          coalesce(v_comp->>'kind', 'manual'),
          coalesce((v_comp->>'amount')::bigint, 0),
          coalesce(v_comp->'meta', '{}'::jsonb)
        );
      end loop;

      v_total_pokok := v_total_pokok + coalesce((v_line->>'gaji_pokok')::bigint, 0);
      v_total_tunj := v_total_tunj + coalesce((v_line->>'tunjangan')::bigint, 0);
      v_total_pot := v_total_pot + coalesce((v_line->>'potongan')::bigint, 0);
      v_total_nett := v_total_nett + coalesce((v_line->>'nett')::bigint, 0);
      v_count := v_count + 1;
    end loop;

    update public.payroll_period
    set
      total_gaji_pokok = v_total_pokok,
      total_tunjangan = v_total_tunj,
      total_potongan = v_total_pot,
      total_nett = v_total_nett,
      line_count = v_count,
      updated_at = now()
    where id = v_period_id;

    insert into public.payroll_period_settings as s (
      period_id, bonus_mode, bonus_pool_rp, rp_per_poin, omzet_referensi, notes,
      submitted_at, submitted_by, updated_at
    ) values (
      v_period_id,
      v_mode,
      nullif(p_settings->>'bonus_pool_rp', '')::bigint,
      nullif(p_settings->>'rp_per_poin', '')::bigint,
      nullif(p_settings->>'omzet_referensi', '')::bigint,
      p_settings->>'notes',
      case when p_lock then now() else null end,
      case when p_lock then auth.uid() else null end,
      now()
    )
    on conflict (period_id) do update set
      bonus_mode = excluded.bonus_mode,
      bonus_pool_rp = excluded.bonus_pool_rp,
      rp_per_poin = excluded.rp_per_poin,
      omzet_referensi = excluded.omzet_referensi,
      notes = excluded.notes,
      submitted_at = coalesce(excluded.submitted_at, s.submitted_at),
      submitted_by = coalesce(excluded.submitted_by, s.submitted_by),
      updated_at = now();
  end if;

  perform public.owner_write_audit(
    case
      when p_mark_paid then 'payroll_mark_paid'
      when p_lock then 'payroll_submit_lock'
      else 'payroll_preview_draft'
    end,
    'payroll_period',
    v_period_id::text,
    jsonb_build_object(
      'toko_id', p_toko_id,
      'periode_ym', v_ym,
      'lock', p_lock,
      'mark_paid', p_mark_paid,
      'line_count', v_count
    )
  );

  select to_jsonb(p.*) || jsonb_build_object(
    'settings', (
      select to_jsonb(s.*) from public.payroll_period_settings s where s.period_id = p.id
    ),
    'lines', coalesce((
      select jsonb_agg(
        to_jsonb(l) || jsonb_build_object(
          'components', coalesce((
            select jsonb_agg(to_jsonb(c) order by c.created_at)
            from public.payroll_line_components c where c.line_id = l.id
          ), '[]'::jsonb)
        )
        order by l.nama
      )
      from public.payroll_lines l where l.period_id = p.id
    ), '[]'::jsonb)
  )
  into v_out
  from public.payroll_period p
  where p.id = v_period_id;

  return v_out;
end;
$$;

revoke all on function public.admin_save_payroll_period(text, text, jsonb, jsonb, boolean, boolean) from public;
grant execute on function public.admin_save_payroll_period(text, text, jsonb, jsonb, boolean, boolean) to authenticated;

-- Unlock draft (admin only) — only from dikunci → draft, not dibayar
create or replace function public.admin_unlock_payroll_period(
  p_toko_id text,
  p_periode_ym text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.payroll_period%rowtype;
begin
  if not public.is_owner_provisioner() then
    raise exception 'Hanya admin pusat / Owner Utama';
  end if;
  select * into v_row
  from public.payroll_period
  where toko_id = p_toko_id and periode_ym = trim(p_periode_ym);
  if v_row.id is null then
    raise exception 'Periode tidak ditemukan';
  end if;
  if v_row.status = 'dibayar' then
    raise exception 'Sudah dibayar — tidak bisa unlock';
  end if;
  update public.payroll_period
  set status = 'draft', locked_at = null, updated_at = now()
  where id = v_row.id;
  update public.payroll_period_settings
  set submitted_at = null, submitted_by = null, updated_at = now()
  where period_id = v_row.id;
  return jsonb_build_object('ok', true, 'period_id', v_row.id, 'status', 'draft');
end;
$$;

revoke all on function public.admin_unlock_payroll_period(text, text) from public;
grant execute on function public.admin_unlock_payroll_period(text, text) to authenticated;

-- Karyawan: daftar slip sendiri (locked/paid)
create or replace function public.karyawan_my_payroll_slips(p_limit int default 12)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kid uuid;
  v_out jsonb;
begin
  v_kid := auth.uid();
  if v_kid is null or not exists (select 1 from public.karyawan k where k.id = v_kid) then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(x order by x->>'periode_ym' desc), '[]'::jsonb)
  into v_out
  from (
    select to_jsonb(l) || jsonb_build_object(
      'periode_ym', p.periode_ym,
      'toko_id', p.toko_id,
      'status', p.status,
      'paid_at', p.paid_at,
      'locked_at', p.locked_at,
      'components', coalesce((
        select jsonb_agg(to_jsonb(c) order by c.created_at)
        from public.payroll_line_components c where c.line_id = l.id
      ), '[]'::jsonb)
    ) as x
    from public.payroll_lines l
    join public.payroll_period p on p.id = l.period_id
    where l.karyawan_id = v_kid
      and p.status in ('dikunci', 'dibayar')
    order by p.periode_ym desc
    limit greatest(1, least(coalesce(p_limit, 12), 36))
  ) q;

  return v_out;
end;
$$;

revoke all on function public.karyawan_my_payroll_slips(int) from public;
grant execute on function public.karyawan_my_payroll_slips(int) to authenticated;

-- Keep legacy admin_run_payroll_period as thin wrapper → pokok-only draft
-- (workspace uses admin_save_payroll_period). Unchanged for OwnerFinanceOpsPage.

comment on table public.payroll_rule_templates is
  'Reusable payroll component system; amounts filled via assignments / period.';
comment on table public.payroll_period_settings is
  'Per-period bonus mode (pool | rp_per_poin) — Admin input, no hardcoded rates.';
comment on function public.admin_save_payroll_period(text, text, jsonb, jsonb, boolean, boolean) is
  'Atomic save of Admin-computed payroll lines + components; lock on submit.';
