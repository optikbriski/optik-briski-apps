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
/// - **APK Rekasa Store** (`com.rekasa.store`, `APP_FLAVOR=store`):
///   katalog bidang + paket, beli, kontrak. Bukan kasir.
/// - **APK yang dibeli klien**: Admin / Karyawan / Member
///   (kulit Rekasa + kode usaha, atau white-label paket A).
///   Tidak memuat etalase. Satu repo, APK terpisah — bukan fork.
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
/// - APK etalase (`com.rekasa.store`) tidak menjalankan POS.
/// - APK Admin/Karyawan/Member tidak memuat etalase.
/// - Satu kode usaha = satu tenant. Mix fitur = flag `tenant_modules`,
///   bukan APK baru.
///
/// Sinkron beli → APK (setelah SQL 000011):
/// 1. Etalase: centang fitur + beli → `submit_store_order`.
/// 2. Baris `tenants` + `apply_store_modules` menulis `tenant_modules`.
/// 3. APK toko login / isi kode usaha → `TenantModules.load()`.
/// 4. RPC `my_tenant_entitlements()` = sumber menu. `allows(key)`
///    hanya true untuk modul `enabled`.
/// 5. Upgrade = tenant yang sama, login ulang. Bukan ganti APK
///    (kecuali pindah ke white-label / `BRAND=<slug>`).
library;
