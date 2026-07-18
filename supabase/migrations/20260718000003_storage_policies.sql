-- Storage policies + bucket yang kurang/salah nama
-- RLS storage tetap aktif; ini hanya menambah izin

-- App memakai nama bucket "Foto Frame" (bukan "Foto")
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('Foto Frame', 'Foto Frame', true, 2097152, array['image/jpeg','image/png']),
  ('verification-proofs', 'verification-proofs', true, 2097152, array['image/jpeg','image/png'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Policies untuk semua bucket app
do $$
declare
  b text;
  pol text;
begin
  foreach b in array array[
    'avatars',
    'session_photos',
    'attendance_photos',
    'LOGO',
    'bukti_transaksi',
    'Foto Frame',
    'verification-proofs',
    'Foto'  -- kalau tetap dipakai manual
  ]
  loop
    -- skip jika bucket belum ada
    if not exists (select 1 from storage.buckets where id = b) then
      continue;
    end if;

    pol := 'public_read_' || replace(replace(b, ' ', '_'), '-', '_');
    execute format('drop policy if exists %I on storage.objects', pol);
    execute format(
      'create policy %I on storage.objects for select using (bucket_id = %L)',
      pol, b
    );

    pol := 'auth_insert_' || replace(replace(b, ' ', '_'), '-', '_');
    execute format('drop policy if exists %I on storage.objects', pol);
    execute format(
      'create policy %I on storage.objects for insert to authenticated with check (bucket_id = %L)',
      pol, b
    );

    pol := 'auth_update_' || replace(replace(b, ' ', '_'), '-', '_');
    execute format('drop policy if exists %I on storage.objects', pol);
    execute format(
      'create policy %I on storage.objects for update to authenticated using (bucket_id = %L) with check (bucket_id = %L)',
      pol, b, b
    );

    pol := 'auth_delete_' || replace(replace(b, ' ', '_'), '-', '_');
    execute format('drop policy if exists %I on storage.objects', pol);
    execute format(
      'create policy %I on storage.objects for delete to authenticated using (bucket_id = %L)',
      pol, b
    );
  end loop;
end $$;
