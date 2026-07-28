-- =============================================================================
-- Konten beranda Member APK — diedit dari Admin Pusat (CMS ringan).
-- =============================================================================

create table if not exists public.member_home_content (
  id text primary key default 'default',
  brand_label text not null default 'OPTIK B. RISKI',
  slides jsonb not null default '[
    {
      "title": "Kacamata siap?\nLangsung tahu di sini",
      "subtitle": "Pantau status pesanan & ambil tanpa ribet"
    },
    {
      "title": "Garansi digital\nOptik B. Riski",
      "subtitle": "Data asli sistem · klaim wajib cek di toko"
    }
  ]'::jsonb,
  greeting_guest text not null default 'Hi, Teman Optik!',
  greeting_subtitle_guest text not null default 'Login untuk lihat pesanan & garansi',
  promo_title text not null default 'Promo & poin',
  promo_subtitle text not null default 'Voucher dan saldo poin kamu',
  updated_at timestamptz not null default now()
);

comment on table public.member_home_content is
  'Konten header/beranda Member APK. Singleton id=default. Diedit Admin Pusat.';

insert into public.member_home_content (id)
values ('default')
on conflict (id) do nothing;

alter table public.member_home_content enable row level security;

drop policy if exists member_home_content_read on public.member_home_content;
create policy member_home_content_read on public.member_home_content
  for select to anon, authenticated
  using (true);

drop policy if exists member_home_content_write_pusat on public.member_home_content;
create policy member_home_content_write_pusat on public.member_home_content
  for all to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('owner', 'admin_pusat', 'super_admin')
    )
  );
