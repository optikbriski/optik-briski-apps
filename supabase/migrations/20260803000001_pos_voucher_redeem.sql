-- POS: simpan voucher di sales + redeem kuota/poin saat checkout.

alter table public.sales
  add column if not exists voucher_code text,
  add column if not exists voucher_discount bigint not null default 0;

create table if not exists public.member_promo_redemptions (
  id uuid primary key default gen_random_uuid(),
  promo_id uuid not null references public.member_promos(id) on delete restrict,
  sale_id uuid not null references public.sales(id) on delete cascade,
  voucher_code text not null,
  discount_applied bigint not null default 0,
  points_spent int not null default 0,
  member_id uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint member_promo_redemptions_sale_uidx unique (sale_id)
);

create index if not exists member_promo_redemptions_promo_idx
  on public.member_promo_redemptions (promo_id, created_at desc);

alter table public.member_promo_redemptions enable row level security;

drop policy if exists member_promo_redemptions_read on public.member_promo_redemptions;
create policy member_promo_redemptions_read on public.member_promo_redemptions
  for select to authenticated using (true);

create unique index if not exists member_points_ledger_sale_voucher_uidx
  on public.member_points_ledger (sale_id)
  where sale_id is not null
    and reason = 'voucher_redeem';

-- Redeem voucher POS: kurangi kuota + potong poin (jika ada), idempotent per sale.
create or replace function public.redeem_member_promo(
  p_code text,
  p_sale_id uuid,
  p_phone text default null,
  p_discount_applied bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_row public.member_promos%rowtype;
  v_sale public.sales%rowtype;
  v_member_id uuid;
  v_digits text;
  v_alt text;
  v_phone text := trim(coalesce(p_phone, ''));
  v_balance int := 0;
  v_points int := 0;
  v_disc bigint := greatest(0, coalesce(p_discount_applied, 0));
  v_updated int := 0;
  v_existing uuid;
begin
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Kode voucher kosong');
  end if;
  if p_sale_id is null then
    return jsonb_build_object('ok', false, 'error', 'sale_id wajib');
  end if;

  select * into v_sale from public.sales where id = p_sale_id limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Nota penjualan tidak ditemukan');
  end if;

  select id into v_existing
  from public.member_promo_redemptions
  where sale_id = p_sale_id
  limit 1;
  if v_existing is not null then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_redeemed',
      'redemption_id', v_existing
    );
  end if;

  select * into v_row
  from public.member_promos
  where upper(trim(coalesce(voucher_code, ''))) = v_code
    and active = true
    and coalesce(show_on_pos, true) = true
  order by sort_order nulls last, created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Voucher tidak ditemukan / tidak aktif di POS');
  end if;

  if v_row.valid_until is not null and v_row.valid_until < current_date then
    return jsonb_build_object('ok', false, 'error', 'Voucher kedaluwarsa');
  end if;

  if lower(trim(coalesce(v_row.discount_type, 'nominal'))) = 'info' then
    return jsonb_build_object('ok', false, 'error', 'Voucher info tidak bisa di-redeem di POS');
  end if;

  v_points := greatest(0, coalesce(v_row.points_cost, 0));

  -- Resolve member (WA dari param atau dari nota)
  if v_phone = '' then
    v_phone := coalesce(v_sale.no_wa, '');
  end if;
  v_digits := public.wa_digits(v_phone);
  if v_digits is not null and length(v_digits) >= 8 then
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
  end if;

  if v_points > 0 then
    if v_member_id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'Voucher butuh ' || v_points || ' poin — nomor WA harus terdaftar member'
      );
    end if;
    select coalesce(sum(delta), 0)::int into v_balance
    from public.member_points_ledger
    where member_id = v_member_id;
    if v_balance < v_points then
      return jsonb_build_object(
        'ok', false,
        'error',
        'Poin member tidak cukup (saldo ' || v_balance || ', butuh ' || v_points || ')'
      );
    end if;
  end if;

  -- Kurangi kuota atomik (null = tanpa batas)
  if v_row.quantity_remaining is not null then
    update public.member_promos
    set quantity_remaining = quantity_remaining - 1
    where id = v_row.id
      and quantity_remaining is not null
      and quantity_remaining > 0;
    get diagnostics v_updated = row_count;
    if v_updated = 0 then
      return jsonb_build_object('ok', false, 'error', 'Kuota voucher habis');
    end if;
  end if;

  if v_points > 0 and v_member_id is not null then
    insert into public.member_points_ledger (
      member_id, delta, reason, sale_id, meta
    ) values (
      v_member_id,
      -v_points,
      'voucher_redeem',
      p_sale_id,
      jsonb_build_object(
        'voucher_code', v_code,
        'promo_id', v_row.id,
        'no_invoice', v_sale.no_invoice,
        'discount_applied', v_disc
      )
    );
  end if;

  insert into public.member_promo_redemptions (
    promo_id, sale_id, voucher_code, discount_applied, points_spent, member_id
  ) values (
    v_row.id, p_sale_id, v_code, v_disc, v_points, v_member_id
  );

  update public.sales
  set
    voucher_code = v_code,
    voucher_discount = case
      when coalesce(voucher_discount, 0) > 0 then voucher_discount
      else v_disc
    end
  where id = p_sale_id;

  return jsonb_build_object(
    'ok', true,
    'promo_id', v_row.id,
    'voucher_code', v_code,
    'points_spent', v_points,
    'member_id', v_member_id,
    'quantity_remaining', (
      select quantity_remaining from public.member_promos where id = v_row.id
    )
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'already_redeemed_race'
    );
end;
$$;

grant execute on function public.redeem_member_promo(text, uuid, text, bigint)
  to authenticated, service_role;
