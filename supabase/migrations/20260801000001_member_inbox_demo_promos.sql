-- Contoh 2 promo untuk Inbox Member (tampil jika belum ada data serupa).
insert into public.member_promos (
  title,
  description,
  terms,
  voucher_code,
  points_cost,
  active,
  show_on_member,
  show_on_pos,
  discount_type,
  discount_value,
  valid_until,
  sort_order
)
select
  v.title,
  v.description,
  v.terms,
  v.voucher_code,
  0,
  true,
  true,
  false,
  v.discount_type,
  v.discount_value,
  (current_date + v.days_valid)::date,
  v.sort_order
from (
  values
    (
      'Diskon lensa progressive 20%',
      'Spesial Member bulan ini — hemat untuk upgrade lensa progressive di semua cabang.',
      'Berlaku untuk Member yang sudah login di aplikasi.
Tidak dapat digabung dengan promo lain.
Tunjukkan kode voucher ke kasir saat transaksi.
Kuota terbatas selama periode promo.',
      'INBOXDEMO20',
      'percent',
      20::numeric,
      30,
      10
    ),
    (
      'Gratis coating anti radiasi',
      'Beli frame + lensa single vision, gratis coating anti radiasi. Hanya lewat aplikasi Member.',
      'Minimal transaksi frame + lensa single vision.
Berlaku di cabang peserta promo.
Tidak berlaku untuk lensa progressive / bifocal.
Promo dapat berakhir lebih awal jika kuota habis.',
      'INBOXDEMOAR',
      'info',
      null::numeric,
      14,
      11
    )
) as v(
  title,
  description,
  terms,
  voucher_code,
  discount_type,
  discount_value,
  days_valid,
  sort_order
)
where not exists (
  select 1 from public.member_promos p where p.voucher_code = v.voucher_code
);
