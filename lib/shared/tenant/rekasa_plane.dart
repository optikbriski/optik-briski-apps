/// Skema kendali Rekasa vs klien per merek.
///
/// Satu codebase, satu project Supabase. Semua merek = baris `tenants`.
/// Data sekat `tenant_id`. Bukan fork git, bukan `CABANG-*` Optik.
///
/// Rekasa (kontrol):
/// - Web Admin **tanpa pin** (`isRekasaControlPlane`) — Vercel Git.
/// - Akun `profiles.is_platform` atur tenant, paket A/B/C, modul custom,
///   flag `white_label` (APK/web merek sendiri), **tagihan langganan**,
///   dan **kontrak online** (taut `?kontrak=`).
/// - Hari H tagihan belum lunas → `tenants.status = suspend` (sistem down,
///   data tidak dihapus). Lunas / Rekasa nyalakan lagi → `aktif`.
/// - APK/web Rekasa = **etalase**: katalog paket C→A, nyala/mati fitur,
///   Detail (video + teks), beli langsung (tagihan + kontrak).
///
/// Paket bawah (C Starter, B Bisnis):
/// - Kulit **Rekasa** (`brands/rekasa.json`, `pinTenant=false`).
/// - Satu APK/web bersama. Login isi **kode usaha**. Dalaman `app_brand`
///   + `tenant_id` biar merek tidak nabrak.
///
/// Paket atas (A Pro) / `white_label=true`:
/// - APK + web nama dan ikon merek sendiri (`BRAND=<slug>`).
/// - Tenant di-pin. Login merek lain ditolak.
///
/// Yang tidak nabrak:
/// - Unique HP/NIK/nota **per tenant**. `PUSAT` Optik ≠ `{kode}-PUSAT`.
/// - RPC Member/stok/owner wajib `tenant_id`. Null tidak jatuh ke Optik.
/// - Auth email tetap unik global (batas Supabase Auth).
library;
