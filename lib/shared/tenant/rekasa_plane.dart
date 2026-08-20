/// Skema kendali Rekasa vs klien per merek.
///
/// Satu codebase, satu project Supabase. Semua merek = baris `tenants`.
/// Data sekat `tenant_id`. Bukan fork git, bukan `CABANG-*` Optik.
///
/// Rekasa (kontrol):
/// - Web Admin **tanpa pin** (`isRekasaControlPlane`) — Vercel Git.
/// - Akun `profiles.is_platform` atur tenant, paket A/B/C, modul custom,
///   dan flag `white_label` (APK/web merek sendiri).
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
/// - Auth email tetap unik global (batas Supabase Auth).
library;
