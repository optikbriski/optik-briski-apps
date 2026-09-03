-- Denah etalase per toko (kardus bertumpuk). Sinkron antar perangkat admin toko.
-- PK (tenant_id, toko_id): cabang lain / merek lain tidak campur.

create table if not exists public.etalase_layouts (
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  toko_id text not null,
  layout jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (tenant_id, toko_id)
);

create index if not exists etalase_layouts_toko_idx
  on public.etalase_layouts (toko_id);

alter table public.etalase_layouts enable row level security;

grant select, insert, update, delete on table public.etalase_layouts
  to authenticated;

drop policy if exists etalase_layouts_select on public.etalase_layouts;
create policy etalase_layouts_select on public.etalase_layouts
  for select to authenticated
  using (
    public.is_platform_user()
    or tenant_id = public.current_tenant_id()
  );

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

comment on table public.etalase_layouts is
  'Denah etalase + isi kardus per toko. Stok angka tetap dari products; di sini hanya lokasi SKU.';
