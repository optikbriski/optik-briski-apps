-- Realtime stok: Master Data / POS / Member langsung tahu saat stock atau reserved_qty berubah.
-- Dual path: postgres_changes (publication) + broadcast topic per toko (realtime.send).

do $$
begin
  alter publication supabase_realtime add table public.products;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

-- Agar payload UPDATE lengkap (old+new) untuk filter/client patch.
do $$
begin
  alter table public.products replica identity full;
exception
  when others then null;
end $$;

create or replace function public.trg_products_broadcast_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_toko text;
  v_sku text;
  v_real int;
  v_pend int;
  v_avail int;
  v_topic text;
begin
  if TG_OP = 'UPDATE'
     and OLD.stock is not distinct from NEW.stock
     and OLD.reserved_qty is not distinct from NEW.reserved_qty then
    return NEW;
  end if;

  v_toko := upper(trim(coalesce(NEW.toko_id, '')));
  v_sku := upper(trim(coalesce(NEW.sku, '')));
  if v_toko = '' or v_sku = '' then
    return NEW;
  end if;

  v_real := coalesce(NEW.stock, 0);
  v_pend := coalesce(NEW.reserved_qty, 0);
  v_avail := public.product_available_qty(v_real, v_pend);
  v_topic := 'obr-stock-' || v_toko;

  begin
    perform realtime.send(
      jsonb_build_object(
        'toko_id', v_toko,
        'sku', v_sku,
        'stock', v_real,
        'reserved_qty', v_pend,
        'available_qty', v_avail,
        'ts', now()
      ),
      'stock_changed',
      v_topic,
      false
    );
  exception when others then
    -- Project tanpa realtime.send: tetap ada postgres_changes via publication.
    null;
  end;

  return NEW;
end;
$$;

drop trigger if exists trg_products_broadcast_stock on public.products;
create trigger trg_products_broadcast_stock
  after update of stock, reserved_qty on public.products
  for each row
  execute function public.trg_products_broadcast_stock();

comment on function public.trg_products_broadcast_stock() is
  'Broadcast perubahan Real/Pending ke topic obr-stock-{TOKO} agar APK realtime.';
