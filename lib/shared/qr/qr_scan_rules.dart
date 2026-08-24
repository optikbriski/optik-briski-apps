import '../attendance/attendance_admin_scope.dart';
import '../invoice/invoice_lifecycle_rules.dart';
import 'obr_codes.dart';
import 'qr_route.dart';

/// Aturan scan QR toko — UI/tes harus sama dengan SQL 000055.
/// Tenant + toko sama. PUSAT = CABANG-PUSAT. Tidak consume token.
abstract final class QrScanRules {
  static bool sameStore(String? a, String? b) =>
      AttendanceAdminScope.sameTokoId(a, b);

  /// Alias kiosk: PUSAT dan CABANG-PUSAT saling menggantikan.
  static List<String> attendanceTokoAliases(String? tokoId) =>
      AttendanceAdminScope.storeIdAliases(tokoId);

  static bool attendancePayloadMatchesToko({
    required String? payloadToko,
    required String? tokenToko,
  }) =>
      sameStore(payloadToko, tokenToko);

  static bool staffNikSameStore({
    required String? staffToko,
    required String? notaToko,
  }) {
    final nota = (notaToko ?? '').trim();
    if (nota.isEmpty) return true;
    return sameStore(staffToko, nota);
  }

  static bool isCustomerLifecyclePayload(String? raw) {
    final parsed = ObrInvoice.parse(raw);
    return parsed != null && parsed.customerLifecycle;
  }

  static bool isAttendancePayload(String? raw) =>
      AttendanceQrPayload.parse(raw) != null;

  /// Alasan tolak scan pelanggan. Null = lolos fase+token (item READY dicek terpisah).
  static String? customerScanReason({
    required String phase,
    required bool isDp,
    required String? tracking,
    required bool diambil,
    required bool tokenUsed,
    required bool tokenMatch,
    bool claimTokenReady = false,
    int readyCount = 0,
  }) {
    final p = phase.trim().toUpperCase();
    if (p != 'DP' && p != 'LUNAS' && p != 'CLAIM') {
      return 'fase_tidak_valid';
    }
    if (!tokenMatch) return 'token_tidak_cocok';
    if (tokenUsed) {
      return switch (p) {
        'DP' => 'qr_dp_sudah_dipakai',
        'LUNAS' => 'qr_lunas_sudah_dipakai',
        _ => 'qr_claim_sudah_dipakai',
      };
    }
    if (!InvoiceLifecycleRules.qrPhaseOk(
      phase: p,
      isDp: isDp,
      tracking: tracking,
      diambil: diambil,
    )) {
      if (p == 'DP') {
        return isDp ? 'qr_dp_belum_ready' : 'qr_dp_sudah_lunas';
      }
      if (p == 'LUNAS') {
        if (isDp) return 'qr_lunas_masih_dp';
        if (diambil) return 'qr_lunas_sudah_serah_terima';
        return 'qr_lunas_belum_ready';
      }
      if (!diambil && !claimTokenReady) return 'qr_claim_belum_berlaku';
    }
    if (p == 'LUNAS' && readyCount <= 0) {
      return 'qr_lunas_belum_ada_ready';
    }
    return null;
  }

  static String messageForReason(String? reason) {
    switch ((reason ?? '').trim()) {
      case 'bukan_qr_invoice':
        return 'QR pelanggan tidak valid. Gunakan QR DP / LUNAS / CLAIM bertoken.';
      case 'invoice_tidak_ditemukan':
        return 'Invoice tidak ditemukan.';
      case 'fase_tidak_valid':
        return 'Fase QR tidak dikenali.';
      case 'token_tidak_cocok':
        return 'Token QR tidak cocok / sudah diganti.';
      case 'qr_dp_sudah_lunas':
        return 'QR DP sudah tidak berlaku (transaksi sudah lunas).';
      case 'qr_dp_belum_ready':
        return 'QR DP belum berlaku. Admin harus konfirmasi Barang Ready dulu.';
      case 'qr_dp_sudah_dipakai':
        return 'QR DP sudah dipakai. Cetak QR LUNAS setelah pelunasan.';
      case 'qr_lunas_masih_dp':
        return 'QR LUNAS belum berlaku. Lunasi sisa tagihan dulu.';
      case 'qr_lunas_sudah_serah_terima':
        return 'QR LUNAS sudah dipakai untuk serah terima. Pakai QR CLAIM.';
      case 'qr_lunas_sudah_dipakai':
        return 'QR LUNAS sudah dipakai (sekali pakai). '
            'Tunggu RO ready / admin kirim QR LUNAS baru.';
      case 'qr_lunas_belum_ready':
        return 'QR LUNAS ready belum berlaku. '
            'Admin harus konfirmasi barang ready dulu, atau ambil item READY.';
      case 'qr_lunas_belum_ada_ready':
        return 'QR LUNAS belum berlaku untuk pengambilan. '
            'Belum ada item READY — selesaikan RO / konfirmasi barang ready.';
      case 'qr_claim_belum_berlaku':
        return 'QR CLAIM belum berlaku. Selesaikan serah terima dulu.';
      case 'qr_claim_sudah_dipakai':
        return 'QR CLAIM sudah dipakai (sekali pakai). Case closed.';
      case 'bukan_kasir_toko_ini':
        return 'QR invoice hanya untuk kasir toko nota ini.';
      case 'nik_kosong':
        return 'Barcode NIK kosong.';
      case 'nik_tidak_ditemukan':
        return 'Barcode NIK tidak ditemukan.';
      case 'karyawan_tidak_aktif':
        return 'Karyawan ini belum aktif.';
      case 'karyawan_beda_toko':
        return 'Karyawan bukan toko nota ini.';
      default:
        return 'QR tidak valid.';
    }
  }
}
