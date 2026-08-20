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

/// Member APK terikat satu merek toko (bukan picker multi-UMKM).
/// Build merek lain: `--dart-define=MEMBER_TENANT_SLUG=...` + ganti `app_name`.
const String memberTenantSlug = String.fromEnvironment(
  'MEMBER_TENANT_SLUG',
  defaultValue: 'optik-briski',
);

bool get isBrandedMemberApk => currentFlavor == AppFlavor.member;
