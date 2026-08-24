-- =============================================================================
-- 000049 — Slug merek: saluran update APK per brand, bukan satu antrian flavor.
-- Apply di SQL Editor live SETELAH 000048.
--
-- Celah saat toko jalan:
-- - versi_app hanya app_flavor → APK Rekasa bisa unduh file Optik (atau sebaliknya)
-- - nama file warisan optik-<flavor>-x.y.z.apk tidak punya slug
-- =============================================================================

alter table public.versi_app
  add column if not exists tenant_slug text;

comment on column public.versi_app.tenant_slug is
  'Saluran APK: optik-briski / rekasa / slug merek. Bukan kode usaha login APK bersama.';

-- File Optik yang sudah di bucket → saluran Optik, jangan ke APK Rekasa.
update public.versi_app
set tenant_slug = 'optik-briski'
where nullif(trim(tenant_slug), '') is null
  and (
    coalesce(url_download, '') ilike '%/optik-admin-%'
    or coalesce(url_download, '') ilike '%/optik-karyawan-%'
    or coalesce(url_download, '') ilike '%/optik-member-%'
    or coalesce(url_download, '') ilike '%/optik-briski-%'
  );

create index if not exists versi_app_flavor_slug_created_idx
  on public.versi_app (app_flavor, tenant_slug, created_at desc);

drop function if exists public.parse_app_release_filename(text);

create or replace function public.parse_app_release_filename(object_name text)
returns table (tenant_slug text, app_flavor text, versi text)
language sql
immutable
as $$
  select
    case
      when m[1] = 'optik' then 'optik-briski'
      else m[1]
    end as tenant_slug,
    m[2]::text as app_flavor,
    m[3]::text as versi
  from regexp_match(
    regexp_replace(lower(coalesce(object_name, '')), '^.*/', ''),
    '^([a-z0-9]+(?:-[a-z0-9]+)*)-(karyawan|admin|member)-([0-9]+\.[0-9]+\.[0-9]+)\.apk$'
  ) as m
  where m is not null;
$$;

create or replace function public.sync_versi_app_from_storage_name(
  p_bucket_id text,
  p_object_name text,
  p_project_url text default 'https://ualqiiprtjysdmtqkpzr.supabase.co'
)
returns uuid
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_slug text;
  v_flavor text;
  v_versi text;
  v_url text;
  v_existing public.versi_app%rowtype;
  v_has_existing boolean := false;
  v_latest_versi text;
  v_is_latest boolean;
  v_id uuid;
  v_label text;
begin
  if p_bucket_id is distinct from 'app-releases' then
    return null;
  end if;

  select p.tenant_slug, p.app_flavor, p.versi
    into v_slug, v_flavor, v_versi
  from public.parse_app_release_filename(p_object_name) p
  limit 1;

  if v_slug is null or v_flavor is null or v_versi is null then
    return null;
  end if;

  v_url := rtrim(p_project_url, '/')
    || '/storage/v1/object/public/'
    || p_bucket_id
    || '/'
    || ltrim(p_object_name, '/');

  v_label := initcap(v_flavor);
  if v_flavor = 'karyawan' then
    v_label := 'Karyawan';
  elsif v_flavor = 'admin' then
    v_label := 'Admin';
  elsif v_flavor = 'member' then
    v_label := 'Member';
  end if;

  select *
    into v_existing
  from public.versi_app
  where app_flavor = v_flavor
    and versi_terbaru = v_versi
    and coalesce(nullif(trim(tenant_slug), ''), 'rekasa')
        = coalesce(nullif(trim(v_slug), ''), 'rekasa')
  order by created_at desc
  limit 1;
  v_has_existing := found;

  if v_has_existing and coalesce(v_existing.url_download, '') = v_url then
    return v_existing.id;
  end if;

  select versi_terbaru
    into v_latest_versi
  from public.versi_app
  where app_flavor = v_flavor
    and coalesce(nullif(trim(tenant_slug), ''), 'rekasa')
        = coalesce(nullif(trim(v_slug), ''), 'rekasa')
  order by created_at desc
  limit 1;

  v_is_latest :=
    v_latest_versi is null
    or public.semver_cmp(v_versi, v_latest_versi) >= 0;

  if v_has_existing then
    update public.versi_app
    set
      url_download = v_url,
      tenant_slug = v_slug,
      created_at = case
        when v_is_latest then now()
        else created_at
      end
    where id = v_existing.id
    returning id into v_id;
    return v_id;
  end if;

  insert into public.versi_app (
    versi_terbaru,
    url_download,
    force_update,
    catatan_rilis,
    app_flavor,
    tenant_slug,
    created_at
  )
  values (
    v_versi,
    v_url,
    false,
    format('Update %s %s %s', v_slug, v_label, v_versi),
    v_flavor,
    v_slug,
    case
      when v_is_latest then now()
      else coalesce(
        (select min(created_at) - interval '1 second'
         from public.versi_app
         where app_flavor = v_flavor
           and coalesce(nullif(trim(tenant_slug), ''), 'rekasa')
               = coalesce(nullif(trim(v_slug), ''), 'rekasa')),
        now() - interval '1 second'
      )
    end
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.sync_versi_app_from_storage_name(text, text, text)
  from public, anon;
grant execute on function public.sync_versi_app_from_storage_name(text, text, text)
  to service_role;

-- Cek update: saluran slug, bukan unduh merek lain.
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
  'Versi APK saluran slug. Bukan merek lain. Bukan mutasi.';

revoke all on function public.lookup_app_release(text, text) from public;
grant execute on function public.lookup_app_release(text, text)
  to anon, authenticated, service_role;
