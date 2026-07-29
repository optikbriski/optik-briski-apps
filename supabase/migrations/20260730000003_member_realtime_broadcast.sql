-- Broadcast Realtime ke topic Member saat status sales berubah
-- (pelunasan / barang ready / ambil), tanpa mengandalkan RLS SELECT di tabel sales.

create or replace function public.member_broadcast_sale_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text;
  v_topic text;
  v_label text;
  v_title text;
  v_body text;
begin
  -- Hanya jika field relevan berubah
  if tg_op = 'UPDATE'
     and new.tracking_status is not distinct from old.tracking_status
     and new.status_pembayaran is not distinct from old.status_pembayaran
     and new.diambil_at is not distinct from old.diambil_at
     and new.qr_dp_token is not distinct from old.qr_dp_token
     and new.qr_lunas_token is not distinct from old.qr_lunas_token
     and new.sisa_tagihan is not distinct from old.sisa_tagihan
  then
    return new;
  end if;

  v_digits := public.wa_digits(new.no_wa);
  if v_digits is null or length(v_digits) < 8 then
    return new;
  end if;
  if v_digits like '0%' then
    v_digits := '62' || substr(v_digits, 2);
  end if;
  v_topic := 'obr-member-' || v_digits;

  v_label := case
    when new.diambil_at is not null
      or upper(trim(coalesce(new.tracking_status, ''))) = 'DIAMBIL'
      then 'Sudah diambil'
    when upper(trim(coalesce(new.tracking_status, ''))) in ('SIAP_DIAMBIL', 'CLEAR')
      then 'Siap diambil'
    when upper(trim(coalesce(new.tracking_status, ''))) = 'SIAP_PELUNASAN'
      then 'Siap pelunasan & pengambilan'
    when upper(trim(coalesce(new.tracking_status, ''))) = 'PENDING_PO'
      then 'Menunggu / proses'
    else coalesce(nullif(trim(new.tracking_status), ''), 'Update pesanan')
  end;

  v_title := 'Update pesanan ' || coalesce(new.no_invoice, '');
  v_body := v_label || ' · status ' || coalesce(new.status_pembayaran, '-');

  begin
    perform realtime.send(
      jsonb_build_object(
        'no_invoice', new.no_invoice,
        'title', v_title,
        'body', v_body,
        'kind', 'sale_update',
        'tracking_status', new.tracking_status,
        'status_pembayaran', new.status_pembayaran
      ),
      'order_update',
      v_topic,
      false
    );
  exception
    when others then
      -- Cluster tanpa realtime.send / belum enable — abaikan.
      null;
  end;

  return new;
end;
$$;

drop trigger if exists trg_member_broadcast_sale_update on public.sales;
create trigger trg_member_broadcast_sale_update
  after update on public.sales
  for each row
  execute function public.member_broadcast_sale_update();

comment on function public.member_broadcast_sale_update() is
  'Push Broadcast Realtime ke topic obr-member-{wa} saat status nota berubah.';
