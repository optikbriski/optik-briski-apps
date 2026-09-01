-- SOP story cabang: hitung dari Instagram Business (Graph API), bukan tap honor.
-- ig_user_id / ig_username per toko. Satu akun merek → isi ID yang sama di tiap cabang.

alter table public.toko_id
  add column if not exists ig_user_id text,
  add column if not exists ig_username text;

comment on column public.toko_id.ig_user_id is
  'Instagram Business / Creator user id (angka). Token Graph tetap di Edge secret.';
comment on column public.toko_id.ig_username is
  'Handle IG tanpa @, hanya tampilan. Boleh sama di semua cabang jika 1 akun merek.';

create or replace function public.toko_id_normalize_ig()
returns trigger
language plpgsql
as $$
begin
  if new.ig_username is not null then
    new.ig_username := lower(regexp_replace(btrim(new.ig_username), '^@+', ''));
    if new.ig_username = '' then
      new.ig_username := null;
    end if;
    if char_length(new.ig_username) > 64 then
      raise exception 'Username Instagram terlalu panjang.' using errcode = '22023';
    end if;
  end if;
  if new.ig_user_id is not null then
    new.ig_user_id := regexp_replace(btrim(new.ig_user_id), '[^0-9]', '', 'g');
    if new.ig_user_id = '' then
      new.ig_user_id := null;
    end if;
    if new.ig_user_id is not null and char_length(new.ig_user_id) > 32 then
      raise exception 'IG user id tidak valid.' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_toko_id_normalize_ig on public.toko_id;
create trigger trg_toko_id_normalize_ig
  before insert or update of ig_user_id, ig_username on public.toko_id
  for each row
  execute function public.toko_id_normalize_ig();

create table if not exists public.sop_ig_story_cache (
  toko_id text not null,
  tanggal date not null,
  story_count int not null default 0 check (story_count >= 0),
  ig_user_id text,
  ig_username text,
  fetched_at timestamptz not null default now(),
  tenant_id uuid,
  primary key (toko_id, tanggal)
);

create index if not exists sop_ig_story_cache_fetched_idx
  on public.sop_ig_story_cache (fetched_at desc);

alter table public.sop_ig_story_cache enable row level security;

drop policy if exists sop_ig_story_cache_select on public.sop_ig_story_cache;
create policy sop_ig_story_cache_select
  on public.sop_ig_story_cache
  for select to authenticated
  using (
    public.is_platform_user()
    or public.toko_belongs_to_current_tenant(toko_id)
  );

revoke all on table public.sop_ig_story_cache from public, anon;
grant select on table public.sop_ig_story_cache to authenticated;
grant all on table public.sop_ig_story_cache to service_role;
