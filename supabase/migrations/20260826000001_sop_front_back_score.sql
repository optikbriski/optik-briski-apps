-- SOP Front/Back ±25: fakta harian cabang (story / display / sapu / stok).

create table if not exists public.sop_story_posts (
  id uuid primary key default gen_random_uuid(),
  toko_id text not null,
  tanggal date not null default (timezone('Asia/Jakarta', now()))::date,
  karyawan_id uuid not null references public.karyawan (id) on delete cascade,
  bukti_url text,
  catatan text,
  tenant_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists sop_story_posts_toko_tgl_idx
  on public.sop_story_posts (toko_id, tanggal);

create table if not exists public.sop_display_slots (
  toko_id text not null,
  tanggal date not null default (timezone('Asia/Jakarta', now()))::date,
  slot_index int not null check (slot_index between 1 and 12),
  completed_by uuid references public.karyawan (id) on delete set null,
  completed_at timestamptz,
  bukti_url text,
  tenant_id uuid,
  primary key (toko_id, tanggal, slot_index)
);

create table if not exists public.sop_sapu_claims (
  toko_id text not null,
  tanggal date not null default (timezone('Asia/Jakarta', now()))::date,
  claimed_by uuid references public.karyawan (id) on delete set null,
  claimed_at timestamptz not null default now(),
  bukti_url text,
  tenant_id uuid,
  primary key (toko_id, tanggal)
);

create table if not exists public.sop_stok_checks (
  toko_id text not null,
  tanggal date not null default (timezone('Asia/Jakarta', now()))::date,
  checked_by uuid references public.karyawan (id) on delete set null,
  checked_at timestamptz not null default now(),
  matched_admin boolean not null default true,
  catatan text,
  tenant_id uuid,
  primary key (toko_id, tanggal)
);

alter table public.sop_story_posts enable row level security;
alter table public.sop_display_slots enable row level security;
alter table public.sop_sapu_claims enable row level security;
alter table public.sop_stok_checks enable row level security;

-- Baca: authenticated (filter toko di app + RLS longgar untuk staff tenant)
drop policy if exists sop_story_posts_select on public.sop_story_posts;
create policy sop_story_posts_select on public.sop_story_posts
  for select to authenticated using (true);

drop policy if exists sop_story_posts_insert on public.sop_story_posts;
create policy sop_story_posts_insert on public.sop_story_posts
  for insert to authenticated
  with check (
    karyawan_id = public.current_karyawan_id()
    and public.pos_duty_ok(public.current_karyawan_id(), toko_id)
  );

drop policy if exists sop_display_slots_select on public.sop_display_slots;
create policy sop_display_slots_select on public.sop_display_slots
  for select to authenticated using (true);

drop policy if exists sop_display_slots_upsert on public.sop_display_slots;
create policy sop_display_slots_upsert on public.sop_display_slots
  for all to authenticated
  using (public.pos_duty_ok(public.current_karyawan_id(), toko_id))
  with check (public.pos_duty_ok(public.current_karyawan_id(), toko_id));

drop policy if exists sop_sapu_claims_select on public.sop_sapu_claims;
create policy sop_sapu_claims_select on public.sop_sapu_claims
  for select to authenticated using (true);

drop policy if exists sop_sapu_claims_upsert on public.sop_sapu_claims;
create policy sop_sapu_claims_upsert on public.sop_sapu_claims
  for all to authenticated
  using (public.pos_duty_ok(public.current_karyawan_id(), toko_id))
  with check (public.pos_duty_ok(public.current_karyawan_id(), toko_id));

drop policy if exists sop_stok_checks_select on public.sop_stok_checks;
create policy sop_stok_checks_select on public.sop_stok_checks
  for select to authenticated using (true);

drop policy if exists sop_stok_checks_upsert on public.sop_stok_checks;
create policy sop_stok_checks_upsert on public.sop_stok_checks
  for all to authenticated
  using (public.pos_duty_ok(public.current_karyawan_id(), toko_id))
  with check (public.pos_duty_ok(public.current_karyawan_id(), toko_id));

grant select, insert on public.sop_story_posts to authenticated;
grant select, insert, update, delete on public.sop_display_slots to authenticated;
grant select, insert, update, delete on public.sop_sapu_claims to authenticated;
grant select, insert, update, delete on public.sop_stok_checks to authenticated;

-- Upsert skor SOP harian (boleh negatif). ref_id = sop-daily-YYYY-MM-DD
create or replace function public.upsert_sop_daily_poin(
  p_karyawan_id uuid,
  p_tanggal date,
  p_poin integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kid uuid;
  v_ref text;
  v_row public.poin_logs%rowtype;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthorized');
  end if;
  v_kid := public.current_karyawan_id();
  if v_kid is null then
    return jsonb_build_object('ok', false, 'error', 'Akun karyawan tidak ditemukan');
  end if;
  if p_karyawan_id is distinct from v_kid then
    return jsonb_build_object('ok', false, 'error', 'Hanya boleh sync skor sendiri');
  end if;
  if p_tanggal is null then
    return jsonb_build_object('ok', false, 'error', 'Tanggal kosong');
  end if;
  if p_poin is null or p_poin < -25 or p_poin > 25 then
    return jsonb_build_object('ok', false, 'error', 'Poin SOP di luar ±25');
  end if;

  v_ref := 'sop-daily-' || to_char(p_tanggal, 'YYYY-MM-DD');

  insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
  values (p_karyawan_id, p_tanggal, p_poin, 'SOP', v_ref)
  on conflict (karyawan_id, sumber, ref_id) where (ref_id is not null)
  do update set poin = excluded.poin, tanggal = excluded.tanggal
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'poin', v_row.poin,
    'ref_id', v_row.ref_id,
    'tanggal', v_row.tanggal
  );
exception
  when others then
    -- Fallback jika unique index beda nama: update lalu insert
    update public.poin_logs
       set poin = p_poin, tanggal = p_tanggal
     where karyawan_id = p_karyawan_id
       and sumber = 'SOP'
       and ref_id = v_ref;
    if found then
      return jsonb_build_object('ok', true, 'poin', p_poin, 'ref_id', v_ref, 'tanggal', p_tanggal);
    end if;
    begin
      insert into public.poin_logs (karyawan_id, tanggal, poin, sumber, ref_id)
      values (p_karyawan_id, p_tanggal, p_poin, 'SOP', v_ref);
      return jsonb_build_object('ok', true, 'poin', p_poin, 'ref_id', v_ref, 'tanggal', p_tanggal);
    exception when unique_violation then
      update public.poin_logs
         set poin = p_poin, tanggal = p_tanggal
       where karyawan_id = p_karyawan_id
         and sumber = 'SOP'
         and ref_id = v_ref;
      return jsonb_build_object('ok', true, 'poin', p_poin, 'ref_id', v_ref, 'tanggal', p_tanggal);
    end;
end;
$$;

revoke all on function public.upsert_sop_daily_poin(uuid, date, integer) from public;
grant execute on function public.upsert_sop_daily_poin(uuid, date, integer) to authenticated;

comment on function public.upsert_sop_daily_poin(uuid, date, integer) is
  'Upsert poin SOP harian ±25 (ref sop-daily-YYYY-MM-DD) untuk karyawan login.';
