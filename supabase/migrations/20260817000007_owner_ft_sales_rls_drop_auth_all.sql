-- Drop leftover permissive ALL policies that OR-bypass Owner write locks.
-- Live names use *_auth_all (not *_authenticated_all from initial schema).

drop policy if exists finance_transactions_auth_all on public.finance_transactions;
drop policy if exists finance_transactions_authenticated_all on public.finance_transactions;

drop policy if exists sales_auth_all on public.sales;
drop policy if exists sales_authenticated_all on public.sales;

drop policy if exists sales_items_auth_all on public.sales_items;
drop policy if exists sales_items_authenticated_all on public.sales_items;

-- Ensure restrictive policies exist (idempotent recreate)
drop policy if exists finance_transactions_select on public.finance_transactions;
drop policy if exists finance_transactions_insert on public.finance_transactions;
drop policy if exists finance_transactions_update on public.finance_transactions;
drop policy if exists finance_transactions_delete on public.finance_transactions;

create policy finance_transactions_select on public.finance_transactions
  for select to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
    or public.owner_can_access_toko(toko_id)
  );

create policy finance_transactions_insert on public.finance_transactions
  for insert to authenticated
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy finance_transactions_update on public.finance_transactions
  for update to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  )
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy finance_transactions_delete on public.finance_transactions
  for delete to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

drop policy if exists sales_select on public.sales;
drop policy if exists sales_insert on public.sales;
drop policy if exists sales_update on public.sales;
drop policy if exists sales_delete on public.sales;

create policy sales_select on public.sales
  for select to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
    or public.owner_can_access_toko(toko_id)
  );

create policy sales_insert on public.sales
  for insert to authenticated
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy sales_update on public.sales
  for update to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  )
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy sales_delete on public.sales
  for delete to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

drop policy if exists sales_items_select on public.sales_items;
drop policy if exists sales_items_insert on public.sales_items;
drop policy if exists sales_items_update on public.sales_items;
drop policy if exists sales_items_delete on public.sales_items;

create policy sales_items_select on public.sales_items
  for select to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
    or exists (
      select 1 from public.sales s
      where s.id = sales_items.sale_id
        and public.owner_can_access_toko(s.toko_id)
    )
  );

create policy sales_items_insert on public.sales_items
  for insert to authenticated
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy sales_items_update on public.sales_items
  for update to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  )
  with check (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );

create policy sales_items_delete on public.sales_items
  for delete to authenticated
  using (
    not public.is_owner_role()
    or public.is_owner_provisioner()
  );
