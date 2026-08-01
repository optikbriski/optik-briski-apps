-- Fix: gen_salt/crypt ada di schema extensions (Supabase).
-- Error: function gen_salt(unknown) does not exist (42883)
-- Jalankan file ini di SQL Editor, lalu coba Kirim OTP lagi.

create extension if not exists pgcrypto with schema extensions;

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'member_%'
  loop
    execute format(
      'alter function %s set search_path = public, extensions',
      r.sig
    );
  end loop;
end;
$$;
