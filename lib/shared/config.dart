/// Environment & app identity. Secrets only via --dart-define.
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Publishable / anon key for client apps (never service_role / secret).
/// Accepts either dart-define name for convenience.
const String supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
);

@Deprecated('Use supabasePublishableKey')
const String supabaseAnonKey = supabasePublishableKey;

/// Which product shell is running. Set via --dart-define=APP_FLAVOR=admin|karyawan|member
/// Owner UX lives inside Karyawan APK (post-login route) — not a separate flavor.
const String appFlavor = String.fromEnvironment(
  'APP_FLAVOR',
  defaultValue: 'admin',
);

enum AppFlavor { admin, karyawan, member }

AppFlavor get currentFlavor {
  switch (appFlavor.toLowerCase()) {
    case 'karyawan':
      return AppFlavor.karyawan;
    case 'member':
      return AppFlavor.member;
    case 'admin':
    default:
      return AppFlavor.admin;
  }
}

/// Member / Karyawan / Admin APK toko terikat satu merek.
/// Web Admin (Vercel) tidak di-pin — Rekasa atur paket semua merek di sana.
/// Merek lain: `BRAND=slug bash scripts/release_*_apk.sh` (lihat brands/).
const String memberTenantSlug = String.fromEnvironment(
  'MEMBER_TENANT_SLUG',
  defaultValue: 'optik-briski',
);

const String karyawanTenantSlug = String.fromEnvironment(
  'KARYAWAN_TENANT_SLUG',
  defaultValue: 'optik-briski',
);

const String adminTenantSlug = String.fromEnvironment(
  'ADMIN_TENANT_SLUG',
  defaultValue: 'optik-briski',
);

const bool pinAdminTenant =
    bool.fromEnvironment('ADMIN_PIN_TENANT', defaultValue: false);

bool get isBrandedMemberApk => currentFlavor == AppFlavor.member;

/// Web/APK toko: terkunci satu merek. Bukan konsol Rekasa.
bool get isBrandedStoreApk =>
    currentFlavor == AppFlavor.member ||
    currentFlavor == AppFlavor.karyawan ||
    (currentFlavor == AppFlavor.admin && pinAdminTenant);

/// Hanya web Admin tanpa pin. Di sini Rekasa atur tenant + paket semua merek.
bool get isRekasaControlPlane =>
    currentFlavor == AppFlavor.admin && !pinAdminTenant;

String get brandedStoreSlug {
  switch (currentFlavor) {
    case AppFlavor.member:
      return memberTenantSlug;
    case AppFlavor.karyawan:
      return karyawanTenantSlug;
    case AppFlavor.admin:
      return adminTenantSlug;
  }
}
