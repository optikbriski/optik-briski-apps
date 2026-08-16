-- =============================================================================
-- Blok 10 commercial miss: karyawan JWT bisa PATCH status_approval → Aktif
-- (self-approve / bypass gate login). Kunci lewat trigger BEFORE INSERT/UPDATE.
-- Hanya profiles role owner/admin_pusat/super_admin yang boleh ubah status_approval
-- ke nilai di luar antrean register, atau men-set Aktif / Ditolak.
-- =============================================================================

create or replace function public.is_admin_pusat_approver()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(trim(coalesce(p.role, ''))) in (
        'owner', 'admin_pusat', 'super_admin'
      )
  );
$$;

comment on function public.is_admin_pusat_approver is
  'True jika auth.uid() adalah admin pusat/owner (boleh approve karyawan).';

create or replace function public.karyawan_guard_status_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new text := trim(coalesce(new.status_approval, ''));
  v_old text := trim(coalesce(old.status_approval, ''));
  v_pending constant text[] := array[
    'pending',
    'menunggu otp',
    'menunggu persetujuan'
  ];
begin
  -- INSERT (register): non-admin dipaksa antrean, tidak bisa self-Aktif.
  if tg_op = 'INSERT' then
    if not public.is_admin_pusat_approver() then
      if lower(v_new) = 'aktif'
         or lower(v_new) like 'ditolak%'
         or v_new = '' then
        new.status_approval := 'Menunggu Persetujuan';
      elsif lower(v_new) = any (v_pending) then
        -- biarkan Pending / Menunggu OTP / Menunggu Persetujuan
        null;
      else
        new.status_approval := 'Menunggu Persetujuan';
      end if;
    end if;
    return new;
  end if;

  -- UPDATE: status tidak berubah → OK
  if v_new is not distinct from v_old then
    return new;
  end if;

  -- Admin pusat/owner boleh setuju / tolak / set pending
  if public.is_admin_pusat_approver() then
    return new;
  end if;

  -- Non-admin: hanya boleh tetap di antrean pending (mis. Menunggu OTP → Menunggu Persetujuan)
  if lower(v_old) = any (v_pending)
     and lower(v_new) = any (v_pending) then
    return new;
  end if;

  raise exception 'status_approval hanya diubah Admin Pusat'
    using errcode = '42501';
end;
$$;

drop trigger if exists trg_karyawan_guard_status_approval on public.karyawan;
create trigger trg_karyawan_guard_status_approval
  before insert or update on public.karyawan
  for each row
  execute function public.karyawan_guard_status_approval();

comment on function public.karyawan_guard_status_approval is
  'Blok self-approve: non-admin tidak boleh set/ubah status_approval ke Aktif/Ditolak.';
