import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/admin_code_login_service.dart';
import '../attendance/pos_duty_gate.dart';
import '../qr/obr_codes.dart';
import '../qr/qr_route.dart';
import '../qr/universal_qr_scan_page.dart';
import '../theme.dart';

/// Gate aksi sensitif: scan **barcode karyawan yang sama dipakai POS** (NIK),
/// atau QR OBRKARY dari APK — harus cocok dengan "via siapa" login kode Admin.
///
/// Juga wajib sedang bertugas: aktif, bukan libur, shift OPEN (sudah absen masuk).
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
            'Login password biasa tidak diizinkan.',
      );
      return false;
    }

    final viaId = via.karyawanId!.trim();
    final viaNama = (via.nama ?? '').trim();
    final viaNik = await _lookupNikForId(viaId);

    // Via login juga harus sedang bertugas (belom pulang / bukan libur).
    final viaDuty = await PosDutyGate.blockReason(
      karyawanId: viaId,
      nik: viaNik,
    );
    if (viaDuty != null) {
      if (!context.mounted) return false;
      await _alert(
        context,
        title: 'Tidak bisa $actionLabel',
        message: viaDuty.tr(),
      );
      return false;
    }

    if (!context.mounted) return false;
    final scanned = await _promptKaryawanScan(
      context,
      actionLabel: actionLabel,
      viaNama: viaNama,
      viaNik: viaNik,
    );
    if (!context.mounted) return false;
    if (scanned == null) {
      await _alert(
        context,
        title: 'Dibatalkan',
        message: 'Scan dibatalkan. $actionLabel tidak dijalankan.',
      );
      return false;
    }

    final scanId = scanned.id.trim();
    final scanNik = scanned.nik.trim();
    final scanNama = scanned.nama.trim();

    final idMatch = scanId.isNotEmpty &&
        scanId.toLowerCase() == viaId.toLowerCase();
    final nikMatch = viaNik != null &&
        viaNik.isNotEmpty &&
        scanNik.isNotEmpty &&
        scanNik == viaNik;
    // via.karyawanId kadang terisi NIK (legacy / POS session)
    final viaAsNikMatch =
        scanNik.isNotEmpty && scanNik == viaId;

    if (!idMatch && !nikMatch && !viaAsNikMatch) {
      await _alert(
        context,
        title: 'Barcode / QR ditolak',
        message:
            'Scan milik "$scanNama"${scanNik.isNotEmpty ? ' (NIK $scanNik)' : ''}, '
            'bukan "$viaNama" yang login.\n\n'
            'Pakai barcode karyawan yang sama dengan POS — harus orang yang sama '
            'dengan via login Admin.',
      );
      return false;
    }

    if (viaNama.isNotEmpty &&
        scanNama.isNotEmpty &&
        viaNama.toLowerCase() != scanNama.toLowerCase()) {
      await _alert(
        context,
        title: 'Ditolak',
        message:
            'Nama di barcode/QR ("$scanNama") tidak sama dengan via login ("$viaNama").',
      );
      return false;
    }

    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Terverifikasi: $viaNama — lanjut $actionLabel'),
      backgroundColor: OptikAdminTokens.success,
    ));
    return true;
  }

  static Future<String?> _lookupNikForId(String karyawanId) async {
    try {
      final byId = await Supabase.instance.client
          .from('karyawan')
          .select('nik')
          .eq('id', karyawanId)
          .maybeSingle();
      final nik = (byId?['nik'] ?? '').toString().trim();
      if (nik.isNotEmpty) return nik;
      // Fallback: id field sometimes stores NIK
      final byNik = await Supabase.instance.client
          .from('karyawan')
          .select('nik')
          .eq('nik', karyawanId)
          .maybeSingle();
      return (byNik?['nik'] ?? '').toString().trim().nullIfEmpty;
    } catch (_) {
      return null;
    }
  }

  /// Dialog: HID barcode NIK (sama POS) + opsi kamera QR OBRKARY.
  static Future<_ScannedKaryawan?> _promptKaryawanScan(
    BuildContext context, {
    required String actionLabel,
    required String viaNama,
    String? viaNik,
  }) async {
    final ctrl = TextEditingController();
    final focus = FocusNode();

    final result = await showDialog<_ScannedKaryawan>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? error;
        var busy = false;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> submit(String raw) async {
              if (busy) return;
              setLocal(() {
                busy = true;
                error = null;
              });
              final resolved = await _resolveScanRaw(raw);
              if (!ctx.mounted) return;
              if (resolved == null) {
                setLocal(() {
                  busy = false;
                  error =
                      'Barcode/QR tidak dikenali. Scan NIK karyawan (barcode POS) '
                      'atau QR OBRKARY dari APK.';
                  ctrl.clear();
                });
                focus.requestFocus();
                return;
              }
              if (!resolved.active) {
                setLocal(() {
                  busy = false;
                  error = 'pos_terlibat_not_aktif'.tr();
                  ctrl.clear();
                });
                focus.requestFocus();
                return;
              }
              final dutyBlock = await PosDutyGate.blockReason(
                karyawanId: resolved.id,
                nik: resolved.nik,
              );
              if (!ctx.mounted) return;
              if (dutyBlock != null) {
                setLocal(() {
                  busy = false;
                  error = dutyBlock.tr();
                  ctrl.clear();
                });
                focus.requestFocus();
                return;
              }
              Navigator.pop(ctx, resolved);
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (focus.canRequestFocus) focus.requestFocus();
            });

            return AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              title: const Text(
                'Scan barcode karyawan',
                style: TextStyle(
                    color: OptikAdminTokens.navy, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Untuk $actionLabel, scan barcode karyawan yang sama '
                      'dipakai di POS (NIK).\n\n'
                      'Harus cocok dengan via login:\n'
                      '• $viaNama'
                      '${viaNik != null && viaNik.isNotEmpty ? '\n• NIK $viaNik' : ''}',
                      style: TextStyle(
                          color: OptikAdminTokens.slate, height: 1.4, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: ctrl,
                      focusNode: focus,
                      enabled: !busy,
                      autofocus: true,
                      style: const TextStyle(color: OptikAdminTokens.navy),
                      decoration: InputDecoration(
                        labelText: 'Barcode NIK / tempel QR',
                        labelStyle: const TextStyle(color: OptikAdminTokens.slate),
                        hintText: 'Arahkan scanner toko ke sini…',
                        hintStyle: const TextStyle(color: OptikAdminTokens.slate),
                        filled: true,
                        fillColor: OptikAdminTokens.bgMid,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onSubmitted: submit,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!,
                          style: const TextStyle(
                              color: OptikAdminTokens.danger, fontSize: 12)),
                    ],
                    if (busy) ...[
                      const SizedBox(height: 12),
                      const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('BATAL'),
                ),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final raw = await UniversalQrScanPage.scanRaw(
                            ctx,
                            allowedTypes: {
                              QrPayloadType.karyawan,
                              QrPayloadType.unknown,
                            },
                            titleKey: 'Scan barcode / QR karyawan',
                            hintKey:
                                'Barcode NIK (POS) atau QR di APK → Kode Login Admin',
                          );
                          if (raw != null && raw.trim().isNotEmpty) {
                            await submit(raw);
                          }
                        },
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('KAMERA'),
                ),
                ElevatedButton(
                  onPressed: busy ? null : () => submit(ctrl.text),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );

    ctrl.dispose();
    focus.dispose();
    return result;
  }

  /// Terima NIK (POS) atau payload OBRKARY|v1|...
  static Future<_ScannedKaryawan?> _resolveScanRaw(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final obr = ObrKaryawan.parse(s);
    if (obr != null) {
      final row = await Supabase.instance.client
          .from('karyawan')
          .select('id, nik, nama, status_approval')
          .eq('id', obr.karyawanId)
          .maybeSingle();
      if (row != null) {
        return _ScannedKaryawan(
          id: (row['id'] ?? obr.karyawanId).toString(),
          nik: (row['nik'] ?? '').toString(),
          nama: (row['nama'] ?? obr.nama).toString(),
          active: _isActive(row['status_approval']),
        );
      }
      return _ScannedKaryawan(
        id: obr.karyawanId,
        nik: '',
        nama: obr.nama,
        active: true,
      );
    }

    // Barcode POS = NIK
    final byNik = await Supabase.instance.client
        .from('karyawan')
        .select('id, nik, nama, status_approval')
        .eq('nik', s)
        .maybeSingle();
    if (byNik != null) {
      return _ScannedKaryawan(
        id: (byNik['id'] ?? '').toString(),
        nik: (byNik['nik'] ?? s).toString(),
        nama: (byNik['nama'] ?? '').toString(),
        active: _isActive(byNik['status_approval']),
      );
    }

    // Fallback: raw = UUID id
    final byId = await Supabase.instance.client
        .from('karyawan')
        .select('id, nik, nama, status_approval')
        .eq('id', s)
        .maybeSingle();
    if (byId != null) {
      return _ScannedKaryawan(
        id: (byId['id'] ?? '').toString(),
        nik: (byId['nik'] ?? '').toString(),
        nama: (byId['nama'] ?? '').toString(),
        active: _isActive(byId['status_approval']),
      );
    }
    return null;
  }

  static bool _isActive(dynamic status) {
    final s = (status ?? '').toString().toLowerCase();
    return s.isEmpty || s == 'aktif' || s == 'approved';
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
                color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
        content: Text(message,
            style: const TextStyle(color: OptikAdminTokens.slate, height: 1.4)),
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

class _ScannedKaryawan {
  const _ScannedKaryawan({
    required this.id,
    required this.nik,
    required this.nama,
    required this.active,
  });

  final String id;
  final String nik;
  final String nama;
  final bool active;
}

extension on String {
  String? get nullIfEmpty => trim().isEmpty ? null : this;
}
