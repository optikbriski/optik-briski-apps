import 'package:flutter/material.dart';

import '../admin/admin_code_login_service.dart';
import '../qr/obr_codes.dart';
import '../qr/qr_route.dart';
import '../qr/universal_qr_scan_page.dart';
import '../theme.dart';

/// Gate revisi/edit stok: wajib scan QR karyawan yang sama dengan "via siapa" login kode.
abstract final class StockActorGate {
  /// true = boleh lanjut. false = ditolak / batal.
  static Future<bool> requireMatchingViaKaryawanQr({
    required BuildContext context,
    required Map<String, dynamic> profile,
    String actionLabel = 'revisi stok',
  }) async {
    final via = await _resolveVia(profile);
    if (via == null || (via.karyawanId ?? '').isEmpty) {
      if (!context.mounted) return false;
      await _alert(
        context,
        title: 'Login via kode APK wajib',
        message:
            'Untuk $actionLabel, Admin harus login memakai kode dari APK Karyawan '
            'agar sistem tahu "via siapa".\n\n'
            'Login password biasa tidak diizinkan untuk mengubah stok.',
      );
      return false;
    }

    final viaId = via.karyawanId!.trim();
    final viaNama = (via.nama ?? '').trim();

    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text(
          'Verifikasi QR Karyawan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Scan QR karyawan yang sama dengan login via:\n\n'
          '• $viaNama\n'
          '${via.jabatan != null && via.jabatan!.isNotEmpty ? '• ${via.jabatan}\n' : ''}'
          '${via.tokoId != null && via.tokoId!.isNotEmpty ? '• ${via.tokoId}\n' : ''}'
          '\n'
          'QR ada di APK Karyawan → menu Kode Login Admin.\n'
          'Kalau beda orang, otomatis ditolak.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('SCAN QR'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return false;

    final raw = await UniversalQrScanPage.scanRaw(
      context,
      allowedTypes: {QrPayloadType.karyawan},
      titleKey: 'Scan QR Karyawan',
      hintKey: 'Arahkan kamera ke QR di APK karyawan (via $viaNama)',
    );
    if (!context.mounted) return false;
    if (raw == null || raw.trim().isEmpty) {
      await _alert(
        context,
        title: 'Dibatalkan',
        message: 'Scan QR dibatalkan. $actionLabel tidak dijalankan.',
      );
      return false;
    }

    final scanned = ObrKaryawan.parse(raw);
    if (scanned == null) {
      await _alert(
        context,
        title: 'QR ditolak',
        message: 'Bukan QR karyawan yang valid.',
      );
      return false;
    }

    final scanId = scanned.karyawanId.trim();
    final scanNama = scanned.nama.trim();

    if (scanId.toLowerCase() != viaId.toLowerCase()) {
      await _alert(
        context,
        title: 'QR ditolak',
        message:
            'QR milik "$scanNama", bukan "$viaNama" yang login.\n\n'
            'Hanya karyawan yang memberi kode login Admin yang boleh '
            'mengotorisasi $actionLabel.',
      );
      return false;
    }

    if (viaNama.isNotEmpty &&
        scanNama.isNotEmpty &&
        viaNama.toLowerCase() != scanNama.toLowerCase()) {
      await _alert(
        context,
        title: 'QR ditolak',
        message:
            'Nama di QR ("$scanNama") tidak sama dengan via login ("$viaNama").',
      );
      return false;
    }

    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Terverifikasi: $viaNama — lanjut $actionLabel'),
      backgroundColor: Colors.green,
    ));
    return true;
  }

  static Future<AdminCodeLoginActor?> _resolveVia(
      Map<String, dynamic> profile) async {
    final id = (profile['login_via_karyawan_id'] ?? '').toString().trim();
    final nama = (profile['login_via_karyawan_nama'] ?? '').toString().trim();
    if (id.isNotEmpty) {
      return AdminCodeLoginActor(
        karyawanId: id,
        nama: nama.isEmpty ? null : nama,
        tokoId: (profile['login_via_karyawan_toko'] ?? '').toString().nullIfEmpty,
        jabatan:
            (profile['login_via_karyawan_jabatan'] ?? '').toString().nullIfEmpty,
        auditId: (profile['login_via_audit_id'] ?? '').toString().nullIfEmpty,
      );
    }
    return AdminCodeLoginService.loadActor();
  }

  static Future<void> _alert(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(message,
            style: const TextStyle(color: Colors.white70, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String? get nullIfEmpty => trim().isEmpty ? null : this;
}
