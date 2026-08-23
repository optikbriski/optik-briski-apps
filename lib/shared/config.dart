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

/// Which product shell is running.
/// `store` = APK Rekasa (katalog + kontrak). Bukan APK kasir klien.
/// Owner UX lives inside Karyawan APK (post-login route) — not a separate flavor.
const String appFlavor = String.fromEnvironment(
  'APP_FLAVOR',
  defaultValue: 'admin',
);

enum AppFlavor { admin, karyawan, member, store }

AppFlavor get currentFlavor {
  switch (appFlavor.toLowerCase()) {
    case 'karyawan':
      return AppFlavor.karyawan;
    case 'member':
      return AppFlavor.member;
    case 'store':
      return AppFlavor.store;
    case 'admin':
    default:
      return AppFlavor.admin;
  }
}

/// Member / Karyawan / Admin APK toko terikat satu merek (Paket A).
/// Default kosong = kulit Rekasa, login isi kode usaha.
/// Optik B. Riski: `BRAND=optik-briski` (bukan default platform).
const String memberTenantSlug = String.fromEnvironment(
  'MEMBER_TENANT_SLUG',
  defaultValue: '',
);

const String karyawanTenantSlug = String.fromEnvironment(
  'KARYAWAN_TENANT_SLUG',
  defaultValue: '',
);

const String adminTenantSlug = String.fromEnvironment(
  'ADMIN_TENANT_SLUG',
  defaultValue: '',
);

const bool pinAdminTenant =
    bool.fromEnvironment('ADMIN_PIN_TENANT', defaultValue: false);

/// Paket A / white_label: true. Kulit Rekasa (paket C/B): false.
const bool pinStoreTenant =
    bool.fromEnvironment('PIN_STORE_TENANT', defaultValue: false);

/// Maps JavaScript / Geocoding / Android geo key.
/// Terisi = kanvas geofence + cari alamat memakai Google Maps.
/// Kosong = peta OSM/Esri + Nominatim.
const String googleMapsApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: '',
);

bool get hasGoogleMapsKey => googleMapsApiKey.trim().isNotEmpty;

bool get isBrandedMemberApk => currentFlavor == AppFlavor.member;

/// APK/web merek sendiri (paket atas). False = kulit Rekasa + kode usaha.
bool get isBrandedStoreApk {
  switch (currentFlavor) {
    case AppFlavor.member:
    case AppFlavor.karyawan:
      return pinStoreTenant;
    case AppFlavor.admin:
      return pinAdminTenant;
    case AppFlavor.store:
      return false;
  }
}

/// Web Admin tanpa pin, atau APK Rekasa Store. Bukan APK kasir klien.
bool get isRekasaControlPlane =>
    currentFlavor == AppFlavor.store ||
    (currentFlavor == AppFlavor.admin && !pinAdminTenant);

/// APK/web etalase Rekasa (katalog, beli, kontrak). Bukan POS.
bool get isRekasaStorefront => currentFlavor == AppFlavor.store;

String get brandedStoreSlug {
  switch (currentFlavor) {
    case AppFlavor.member:
      return memberTenantSlug;
    case AppFlavor.karyawan:
      return karyawanTenantSlug;
    case AppFlavor.admin:
    case AppFlavor.store:
      return adminTenantSlug;
  }
}
