-- Denah etalase = layout stok toko, bukan checkout POS.
-- Write harus ikut can_manage_inventory_for_toko (admin_toko/admin_pusat),
-- bukan can_pos_checkout_for_toko (yang mengizinkan kasir & menolak owner sama).

grant select, insert, update, delete on table public.etalase_layouts
  to authenticated;

drop policy if exists etalase_layouts_write on public.etalase_layouts;
create policy etalase_layouts_write on public.etalase_layouts
  for all to authenticated
  using (
    public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and public.can_manage_inventory_for_toko(toko_id)
    )
  )
  with check (
    public.is_platform_user()
    or (
      tenant_id = public.current_tenant_id()
      and public.can_manage_inventory_for_toko(toko_id)
    )
  );
