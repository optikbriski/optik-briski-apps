-- Poin Member: 10% dari total_harga per 1 invoice, sekali saat jadi LUNAS.
-- Bootstrap tabel bila migrasi Member lama belum pernah di-Run di production.

create extension if not exists pgcrypto;

create or replace function public.wa_digits(p text)
returns text
language sql
immutable
as $$
  select nullif(
    regexp_replace(
      case
        when regexp_replace(coalesce(p, ''), '\D', '', 'g') ~ '^0'
          then '62' || substr(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 2)
        else regexp_replace(coalesce(p, ''), '\D', '', 'g')
      end,
      '\D',
      '',
      'g'
    ),
    ''
  );
$$;

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  phone_e164 text not null unique,
  phone_raw text,
  nama text,
  email text,
  alamat text,
  font_scale numeric not null default 1.0,
  locale text not null default 'id',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.member_points_ledger (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  delta int not null,
  reason text not null,
  sale_id uuid,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.member_promos (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  toko_id text,
  voucher_code text,
  points_cost int not null default 0,
  active boolean not null default true,
  valid_until date,
  created_at timestamptz not null default now()
);

alter table public.members enable row level security;
alter table public.member_points_ledger enable row level security;
alter table public.member_promos enable row level security;

drop policy if exists members_anon_all on public.members;
create policy members_anon_all on public.members
  for all to anon, authenticated using (true) with check (true);

drop policy if exists member_points_anon_all on public.member_points_ledger;
create policy member_points_anon_all on public.member_points_ledger
  for all to anon, authenticated using (true) with check (true);

drop policy if exists member_promos_read on public.member_promos;
create policy member_promos_read on public.member_promos
  for select to anon, authenticated using (active = true);

create index if not exists member_points_ledger_member_idx
  on public.member_points_ledger (member_id, created_at desc);

create unique index if not exists member_points_ledger_sale_purchase_uidx
  on public.member_points_ledger (sale_id)
  where sale_id is not null
    and reason = 'purchase_10pct';

create or replace function public.award_member_points_for_sale(p_sale_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales%rowtype;
  v_digits text;
  v_alt text;
  v_member_id uuid;
  v_points int;
  v_ledger_id uuid;
begin
  if p_sale_id is null then
    return jsonb_build_object('ok', false, 'error', 'sale_id wajib');
  end if;

  select * into v_sale from public.sales where id = p_sale_id limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'nota tidak ditemukan');
  end if;

  if upper(trim(coalesce(v_sale.status_pembayaran, ''))) <> 'LUNAS'
     and coalesce(v_sale.sisa_tagihan, 0) > 0 then
    return jsonb_build_object('ok', false, 'error', 'belum lunas', 'skipped', true);
  end if;

  if exists (
    select 1 from public.member_points_ledger l
    where l.sale_id = v_sale.id and l.reason = 'purchase_10pct'
  ) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_awarded');
  end if;

  v_digits := public.wa_digits(v_sale.no_wa);
  if v_digits is null or length(v_digits) < 8 then
    return jsonb_build_object('ok', false, 'error', 'no_wa tidak valid', 'skipped', true);
  end if;
  v_alt := case
    when v_digits like '62%' then '0' || substr(v_digits, 3)
    when v_digits like '0%' then '62' || substr(v_digits, 2)
    else v_digits
  end;

  select m.id into v_member_id
  from public.members m
  where public.wa_digits(m.phone_e164) in (v_digits, v_alt)
     or regexp_replace(coalesce(m.phone_e164, ''), '\D', '', 'g') in (v_digits, v_alt)
     or regexp_replace(coalesce(m.phone_raw, ''), '\D', '', 'g') in (v_digits, v_alt)
  order by m.created_at
  limit 1;

  if v_member_id is null then
    return jsonb_build_object('ok', false, 'error', 'member tidak terdaftar', 'skipped', true);
  end if;

  v_points := greatest(0, floor(coalesce(v_sale.total_harga, 0) * 0.10)::int);
  if v_points <= 0 then
    return jsonb_build_object('ok', false, 'error', 'poin 0', 'skipped', true);
  end if;

  begin
    insert into public.member_points_ledger (
      member_id, delta, reason, sale_id, meta
    ) values (
      v_member_id,
      v_points,
      'purchase_10pct',
      v_sale.id,
      jsonb_build_object(
        'no_invoice', v_sale.no_invoice,
        'total_harga', v_sale.total_harga,
        'rate', 0.10
      )
    )
    returning id into v_ledger_id;
  exception
    when unique_violation then
      return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_awarded');
  end;

  return jsonb_build_object(
    'ok', true,
    'ledger_id', v_ledger_id,
    'member_id', v_member_id,
    'points', v_points,
    'no_invoice', v_sale.no_invoice
  );
end;
$$;

revoke all on function public.award_member_points_for_sale(uuid) from public;
grant execute on function public.award_member_points_for_sale(uuid) to authenticated;

create or replace function public.trg_award_member_points_on_lunas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_was_lunas boolean;
  v_now_lunas boolean;
begin
  if tg_op = 'INSERT' then
    v_was_lunas := false;
  else
    v_was_lunas := (
      upper(trim(coalesce(old.status_pembayaran, ''))) = 'LUNAS'
      or coalesce(old.sisa_tagihan, 0) <= 0
    );
  end if;

  v_now_lunas := (
    upper(trim(coalesce(new.status_pembayaran, ''))) = 'LUNAS'
    or coalesce(new.sisa_tagihan, 0) <= 0
  );

  if v_now_lunas and not v_was_lunas then
    perform public.award_member_points_for_sale(new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_award_member_points_on_lunas on public.sales;
create trigger trg_award_member_points_on_lunas
  after insert or update of status_pembayaran, sisa_tagihan, total_harga, no_wa
  on public.sales
  for each row
  execute function public.trg_award_member_points_on_lunas();

create or replace function public.get_member_points_summary(p_member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reward int := 0;
  v_status int := 0;
begin
  if p_member_id is null then
    return jsonb_build_object('reward_points', 0, 'status_points', 0);
  end if;

  select
    coalesce(sum(l.delta), 0),
    coalesce(sum(case when l.delta > 0 then l.delta else 0 end), 0)
  into v_reward, v_status
  from public.member_points_ledger l
  where l.member_id = p_member_id;

  return jsonb_build_object(
    'reward_points', v_reward,
    'status_points', v_status
  );
end;
$$;

revoke all on function public.get_member_points_summary(uuid) from public;
grant execute on function public.get_member_points_summary(uuid)
  to anon, authenticated;

comment on function public.award_member_points_for_sale(uuid) is
  'Kredit poin 10% total_harga sekali per invoice saat LUNAS, jika no_wa cocok member.';
