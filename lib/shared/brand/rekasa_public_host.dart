/// Hostname situs perusahaan (Midtrans). Bukan konsol Admin.
const rekasaPublicHost = 'rekasa-karya-indonesia.vercel.app';

bool isRekasaPublicHost(String? hostname) {
  final h = (hostname ?? '').trim().toLowerCase();
  return h == rekasaPublicHost ||
      h == 'www.rekasakaryaindonesia.com' ||
      h == 'rekasakaryaindonesia.com';
}

/// Path yang sudah situs perusahaan tidak diarahkan ulang.
bool shouldRedirectRekasaPublicPath(String? pathname) {
  final path = pathname ?? '';
  return !path.startsWith('/perusahaan');
}
