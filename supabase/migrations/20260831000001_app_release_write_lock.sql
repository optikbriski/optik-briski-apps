-- Kunci saluran update APK: hanya service_role (skrip publish) yang boleh
-- menulis versi_app / object app-releases. Anon+auth tetap boleh baca.
-- Tanpa ini, akun Karyawan/Member yang login bisa ganti URL unduhan.

drop policy if exists versi_app_authenticated_write on public.versi_app;
drop policy if exists versi_app_auth_all on public.versi_app;
drop policy if exists versi_app_authenticated_insert on public.versi_app;
drop policy if exists versi_app_authenticated_update on public.versi_app;
drop policy if exists versi_app_authenticated_delete on public.versi_app;

-- Baca tetap terbuka (cek update sebelum login).
drop policy if exists versi_app_anon_select on public.versi_app;
create policy versi_app_anon_select on public.versi_app
  for select to anon using (true);

drop policy if exists versi_app_authenticated_select on public.versi_app;
create policy versi_app_authenticated_select on public.versi_app
  for select to authenticated using (true);

-- Bucket APK: baca publik, tulis hanya service_role (bypass RLS).
drop policy if exists "app_releases_auth_insert" on storage.objects;
drop policy if exists "app_releases_auth_update" on storage.objects;
drop policy if exists "app_releases_auth_delete" on storage.objects;

drop policy if exists "app_releases_public_read" on storage.objects;
create policy "app_releases_public_read"
  on storage.objects for select
  using (bucket_id = 'app-releases');

-- lookup: tolak URL yang tidak cocok flavor + saluran (anti-campur merek).
create or replace function public.lookup_app_release(
  p_flavor text,
  p_channel text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_flavor text := lower(trim(coalesce(p_flavor, '')));
  v_ch text := lower(trim(coalesce(p_channel, '')));
  v_row public.versi_app%rowtype;
  v_parsed record;
begin
  if v_flavor not in ('karyawan', 'admin', 'member') then
    return jsonb_build_object('ok', false, 'reason', 'flavor');
  end if;
  if v_ch is null or v_ch = '' then
    return jsonb_build_object('ok', false, 'reason', 'channel');
  end if;
  if v_ch = 'optik' then
    v_ch := 'optik-briski';
  end if;

  select *
    into v_row
  from public.versi_app
  where app_flavor = v_flavor
    and coalesce(nullif(trim(tenant_slug), ''), 'rekasa') = v_ch
    and nullif(trim(url_download), '') is not null
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'none');
  end if;

  select p.tenant_slug, p.app_flavor, p.versi
    into v_parsed
  from public.parse_app_release_filename(
    regexp_replace(v_row.url_download, '^.*/', '')
  ) p
  limit 1;

  if v_parsed.tenant_slug is null
     or v_parsed.app_flavor is distinct from v_flavor
     or v_parsed.tenant_slug is distinct from v_ch then
    return jsonb_build_object('ok', false, 'reason', 'url');
  end if;

  if split_part(split_part(trim(v_row.versi_terbaru), '+', 1), '-', 1)
       is distinct from v_parsed.versi then
    return jsonb_build_object('ok', false, 'reason', 'versi');
  end if;

  -- Hanya bucket project ini, tanpa query/redirect.
  if v_row.url_download !~* '^https://ualqiiprtjysdmtqkpzr\.supabase\.co/storage/v1/object/public/app-releases/[a-z0-9][a-z0-9.-]*\.apk$' then
    return jsonb_build_object('ok', false, 'reason', 'host');
  end if;

  return jsonb_build_object(
    'ok', true,
    'versi_terbaru', v_row.versi_terbaru,
    'url_download', v_row.url_download,
    'force_update', v_row.force_update,
    'catatan_rilis', v_row.catatan_rilis,
    'app_flavor', v_row.app_flavor,
    'tenant_slug', coalesce(nullif(trim(v_row.tenant_slug), ''), v_ch)
  );
end;
$$;

comment on function public.lookup_app_release(text, text) is
  'Versi APK saluran slug. Tolak URL beda flavor/merek/host. Bukan mutasi.';

revoke all on function public.lookup_app_release(text, text) from public;
grant execute on function public.lookup_app_release(text, text)
  to anon, authenticated, service_role;

revoke insert, update, delete, truncate, references, trigger
  on table public.versi_app from anon, authenticated, public;
grant select on table public.versi_app to anon, authenticated;
