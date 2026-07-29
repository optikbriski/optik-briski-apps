-- Inbox sinyal Member: admin/delivery menulis; APK Member baca via RPC (security definer).

create table if not exists public.member_order_alerts (
  id uuid primary key default gen_random_uuid(),
  no_invoice text not null,
  phone_digits text not null,
  title text not null,
  body text not null,
  kind text not null default 'status',
  created_at timestamptz not null default now()
);

create index if not exists member_order_alerts_phone_created_idx
  on public.member_order_alerts (phone_digits, created_at desc);

alter table public.member_order_alerts enable row level security;

create or replace function public.create_member_order_alert(
  p_no_invoice text,
  p_phone text,
  p_title text,
  p_body text,
  p_kind text default 'status'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text;
  v_id uuid;
begin
  v_digits := public.wa_digits(p_phone);
  if v_digits is null or length(v_digits) < 8 then
    raise exception 'phone tidak valid';
  end if;
  if p_no_invoice is null or length(trim(p_no_invoice)) = 0 then
    raise exception 'invoice wajib';
  end if;

  insert into public.member_order_alerts (
    no_invoice, phone_digits, title, body, kind
  ) values (
    trim(p_no_invoice),
    v_digits,
    coalesce(nullif(trim(p_title), ''), 'Update pesanan'),
    coalesce(nullif(trim(p_body), ''), ''),
    coalesce(nullif(trim(p_kind), ''), 'status')
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_member_order_alert(text, text, text, text, text)
  from public;
grant execute on function public.create_member_order_alert(text, text, text, text, text)
  to anon, authenticated;

create or replace function public.list_member_order_alerts(
  p_phone text,
  p_after timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text;
  v_alt text;
begin
  v_digits := public.wa_digits(p_phone);
  if v_digits is null or length(v_digits) < 8 then
    return '[]'::jsonb;
  end if;
  v_alt := case
    when v_digits like '62%' then '0' || substr(v_digits, 3)
    else v_digits
  end;

  return coalesce((
    select jsonb_agg(x.obj order by x.created_at desc)
    from (
      select jsonb_build_object(
        'id', a.id,
        'no_invoice', a.no_invoice,
        'title', a.title,
        'body', a.body,
        'kind', a.kind,
        'created_at', a.created_at
      ) as obj,
      a.created_at
      from public.member_order_alerts a
      where a.phone_digits in (v_digits, v_alt)
        and (p_after is null or a.created_at > p_after)
      order by a.created_at desc
      limit 40
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_member_order_alerts(text, timestamptz) from public;
grant execute on function public.list_member_order_alerts(text, timestamptz)
  to anon, authenticated;

create or replace function public.list_member_order_alerts(p_phone text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.list_member_order_alerts(p_phone, null);
$$;

revoke all on function public.list_member_order_alerts(text) from public;
grant execute on function public.list_member_order_alerts(text) to anon, authenticated;

-- Sertakan flag token QR di list pesanan Member (untuk fingerprint notif).
create or replace function public.list_member_sales(p_phone text)
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
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        s.id, s.no_invoice, s.toko_id, s.nama_pelanggan, s.status_pembayaran,
        s.tracking_status, s.diambil_at, s.foto_hasil_url, s.sisa_tagihan,
        s.total_harga, s.dibayarkan, s.created_at, s.lunas_at,
        (s.qr_dp_token is not null and length(trim(s.qr_dp_token)) >= 8) as has_qr_dp,
        (s.qr_lunas_token is not null and length(trim(s.qr_lunas_token)) >= 8) as has_qr_lunas,
        (s.qr_claim_token is not null and length(trim(s.qr_claim_token)) >= 8) as has_qr_claim
      from public.sales s
      where public.wa_digits(s.no_wa) = v_phone
         or regexp_replace(coalesce(s.no_wa, ''), '\D', '', 'g') in (v_phone, v_alt)
      order by s.created_at desc
      limit 100
    ) x
  ), '[]'::jsonb);
end;
$$;

-- Realtime opsional (UI Member tetap poll RPC; channel membantu bila RLS longgar).
do $$
begin
  alter publication supabase_realtime add table public.member_order_alerts;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
