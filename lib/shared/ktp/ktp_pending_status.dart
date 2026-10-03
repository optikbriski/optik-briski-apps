/// Status antrean verifikasi — harus sama di daftar, badge, dan update putusan.
const kKtpReviewPendingStatuses = [
  'Pending',
  'pending',
  'PENDING',
  'Menunggu OTP',
  'menunggu otp',
  'Menunggu Persetujuan',
  'menunggu persetujuan',
];

bool isKtpReviewPendingStatus(String? raw) {
  final s = (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return false;
  return kKtpReviewPendingStatuses.any(
    (p) => p.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == s,
  );
}
