-- =============================================================================
-- Auto-sync: upload APK ke bucket app-releases → upsert public.versi_app
-- Filename: optik-<flavor>-<semver>.apk  (contoh: optik-karyawan-1.2.7.apk)
-- Flavor: karyawan | admin | member
-- Tidak menyentuh file ABI khusus (…-armeabi-v7a.apk dll).
-- force_update: default false; baris yang sudah ada mempertahankan nilai lama.
-- =============================================================================

-- Pastikan kolom versi_app lengkap (idempotent)
create table if not exists public.versi_app (
  id uuid primary key default gen_random_uuid(),
  versi_terbaru text,
  url_download text,
  created_at timestamptz not null default now()
);

alter table public.versi_app
  add column if not exists force_update boolean not null default false,
  add column if not exists catatan_rilis text,
  add column if not exists app_flavor text not null default 'karyawan';

-- Bandingkan semver sederhana (X.Y.Z); return >0 jika a>b, 0 jika sama, <0 jika a<b
create or replace function public.semver_cmp(a text, b text)
returns integer
language plpgsql
immutable
as $$
declare
  pa text[];
  pb text[];
  n int;
  i int;
  xa int;
  xb int;
begin
  pa := string_to_array(split_part(split_part(coalesce(a, '0'), '-', 1), '+', 1), '.');
  pb := string_to_array(split_part(split_part(coalesce(b, '0'), '-', 1), '+', 1), '.');
  n := greatest(coalesce(array_length(pa, 1), 0), coalesce(array_length(pb, 1), 0));
  for i in 1..n loop
    xa := coalesce(nullif(regexp_replace(coalesce(pa[i], '0'), '[^0-9]', '', 'g'), '')::int, 0);
    xb := coalesce(nullif(regexp_replace(coalesce(pb[i], '0'), '[^0-9]', '', 'g'), '')::int, 0);
    if xa <> xb then
      return xa - xb;
    end if;
  end loop;
  return 0;
end;
$$;

-- Parse basename → flavor + version (null jika pola tidak cocok)
create or replace function public.parse_app_release_filename(object_name text)
returns table (app_flavor text, versi text)
language sql
immutable
as $$
  select m[1]::text as app_flavor, m[2]::text as versi
  from regexp_match(
    regexp_replace(coalesce(object_name, ''), '^.*/', ''),
    '^optik-(karyawan|admin|member)-([0-9]+\.[0-9]+\.[0-9]+)\.apk$'
  ) as m
  where m is not null;
$$;

-- Upsert satu object Storage ke versi_app (bisa dipanggil manual / backfill)
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

  select p.app_flavor, p.versi
    into v_flavor, v_versi
  from public.parse_app_release_filename(p_object_name) p
  limit 1;

  if v_flavor is null or v_versi is null then
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
  order by created_at desc
  limit 1;
  v_has_existing := found;

  -- Skip spam: versi + URL sama sudah ada
  if v_has_existing and coalesce(v_existing.url_download, '') = v_url then
    return v_existing.id;
  end if;

  -- Versi "terbaru" menurut app = baris created_at terbaru per flavor
  select versi_terbaru
    into v_latest_versi
  from public.versi_app
  where app_flavor = v_flavor
  order by created_at desc
  limit 1;

  v_is_latest :=
    v_latest_versi is null
    or public.semver_cmp(v_versi, v_latest_versi) >= 0;

  if v_has_existing then
    update public.versi_app
    set
      url_download = v_url,
      -- Jangan override force_update / catatan yang sudah di-set admin
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
    created_at
  )
  values (
    v_versi,
    v_url,
    false,
    format('Update Optik %s %s', v_label, v_versi),
    v_flavor,
    case
      when v_is_latest then now()
      -- Versi lama: jangan mengalahkan baris terbaru lewat created_at
      else coalesce(
        (select min(created_at) - interval '1 second'
         from public.versi_app
         where app_flavor = v_flavor),
        now() - interval '1 second'
      )
    end
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.sync_versi_app_from_storage_name(text, text, text) from public;
grant execute on function public.sync_versi_app_from_storage_name(text, text, text) to service_role;

-- Trigger function: INSERT/UPDATE object di app-releases
create or replace function public.trg_app_releases_sync_versi_app()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  -- Re-upload (x-upsert) biasanya UPDATE baris storage dengan name sama;
  -- helper no-op jika versi+URL sudah cocok.
  perform public.sync_versi_app_from_storage_name(new.bucket_id, new.name);
  return new;
end;
$$;

drop trigger if exists trg_app_releases_sync_versi_app on storage.objects;
create trigger trg_app_releases_sync_versi_app
  after insert or update on storage.objects
  for each row
  when (new.bucket_id = 'app-releases')
  execute function public.trg_app_releases_sync_versi_app();

-- Backfill semua APK yang cocok pola di bucket (aman diulang)
create or replace function public.backfill_versi_app_from_app_releases(
  p_project_url text default 'https://ualqiiprtjysdmtqkpzr.supabase.co'
)
returns integer
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  r record;
  n int := 0;
  synced uuid;
begin
  for r in
    select bucket_id, name
    from storage.objects
    where bucket_id = 'app-releases'
      and name ~ 'optik-(karyawan|admin|member)-[0-9]+\.[0-9]+\.[0-9]+\.apk$'
    order by name
  loop
    synced := public.sync_versi_app_from_storage_name(r.bucket_id, r.name, p_project_url);
    if synced is not null then
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;

revoke all on function public.backfill_versi_app_from_app_releases(text) from public;
grant execute on function public.backfill_versi_app_from_app_releases(text) to service_role;

comment on function public.sync_versi_app_from_storage_name(text, text, text) is
  'Upsert versi_app dari object Storage app-releases (optik-<flavor>-X.Y.Z.apk).';
comment on function public.backfill_versi_app_from_app_releases(text) is
  'Scan bucket app-releases dan sync semua APK berpola ke versi_app.';
comment on function public.trg_app_releases_sync_versi_app() is
  'Trigger storage.objects → sync versi_app saat upload/update APK.';
