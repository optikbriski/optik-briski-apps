-- Jangan simpan UUID online_order sebagai no_invoice palsu.
-- Client Inbox/notif sempat buka InvoiceHub dengan UUID → "Nota tidak ditemukan".

create or replace function public.create_member_order_alert(
  p_no_invoice text,
  p_phone text,
  p_title text,
  p_body text,
  p_kind text default 'status',
  p_online_order_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text;
  v_id uuid;
  v_inv text := trim(coalesce(p_no_invoice, ''));
begin
  v_digits := public.wa_digits(p_phone);
  if v_digits is null or length(v_digits) < 8 then
    raise exception 'phone tidak valid';
  end if;
  if v_inv = '' and p_online_order_id is null then
    raise exception 'invoice atau online_order_id wajib';
  end if;

  -- Placeholder lama: online_order_id::text / 'ONLINE' — simpan '' saja.
  if p_online_order_id is not null
     and (
       v_inv = ''
       or upper(v_inv) = 'ONLINE'
       or v_inv = p_online_order_id::text
     ) then
    v_inv := '';
  end if;

  insert into public.member_order_alerts (
    no_invoice, phone_digits, title, body, kind, online_order_id
  ) values (
    v_inv,
    v_digits,
    coalesce(nullif(trim(p_title), ''), 'Update pesanan'),
    coalesce(nullif(trim(p_body), ''), ''),
    coalesce(nullif(trim(p_kind), ''), 'status'),
    p_online_order_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_member_order_alert(text, text, text, text, text, uuid)
  from public;
grant execute on function public.create_member_order_alert(text, text, text, text, text, uuid)
  to anon, authenticated, service_role;

-- Bersihkan baris lama yang menaruh UUID di no_invoice.
update public.member_order_alerts a
set no_invoice = ''
where a.online_order_id is not null
  and (
    a.no_invoice = a.online_order_id::text
    or upper(trim(a.no_invoice)) = 'ONLINE'
  );

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
    when v_digits like '0%' and length(v_digits) >= 9
      then '62' || substr(v_digits, 2)
    else v_digits
  end;

  return coalesce((
    select jsonb_agg(x.obj order by x.created_at desc)
    from (
      select jsonb_build_object(
        'id', a.id,
        'no_invoice', nullif(trim(a.no_invoice), ''),
        'online_order_id', a.online_order_id,
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
  to anon, authenticated, service_role;
