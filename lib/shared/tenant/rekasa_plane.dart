/// Skema kendali Rekasa vs klien per merek.
///
/// Satu project Supabase. Semua merek = baris `tenants`. Data sekat `tenant_id`.
///
/// Rekasa (kontrol):
/// - Web Admin **tanpa pin** (`isRekasaControlPlane`) — Vercel Git.
/// - Akun `profiles.is_platform` atur tenant, paket A/B/C, modul custom.
/// - Tidak menyimpan data toko merek lain sebagai `CABANG-*` Optik.
///
/// Merek (klien):
/// - APK Admin / Karyawan / Member + web Admin **terkunci slug**.
/// - `applicationId` / domain beda per merek. Dalaman kode sama.
/// - Menu ikut `tenant_modules`. Login merek lain ditolak.
///
/// Yang tidak nabrak:
/// - Unique HP/NIK/nota **per tenant**. `PUSAT` Optik ≠ `{kode}-PUSAT`.
/// - Auth email tetap unik global (batas Supabase Auth).
library;
