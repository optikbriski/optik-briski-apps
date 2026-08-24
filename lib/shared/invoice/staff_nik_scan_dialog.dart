// ignore_for_file: use_build_context_synchronously
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../attendance/pos_duty_gate.dart';
import '../qr/hid_scan_intake.dart';
import '../qr/qr_scan_rules.dart';
import '../tenant/tenant_service.dart';
import '../theme.dart';
import '../widgets/admin/admin_premium.dart';
import '../widgets/admin/premium_app_bar.dart';

/// Scan barcode NIK karyawan (kamera full-page + HID) sebelum aksi lifecycle.
///
/// Bukan form ketik: barcode masuk lewat kamera / scanner toko.
Future<Map<String, dynamic>?> showStaffNikScanDialog(
  BuildContext context, {
  String title = 'Scan barcode karyawan',
  String subtitle =
      'Arahkan kamera atau scanner toko ke barcode NIK karyawan.',
  String? notaTokoId,
}) {
  return Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _StaffNikScanPage(
        title: title,
        subtitle: subtitle,
        notaTokoId: notaTokoId,
      ),
    ),
  );
}

class _StaffNikScanPage extends StatefulWidget {
  const _StaffNikScanPage({
    required this.title,
    required this.subtitle,
    this.notaTokoId,
  });

  final String title;
  final String subtitle;
  final String? notaTokoId;

  @override
  State<_StaffNikScanPage> createState() => _StaffNikScanPageState();
}

class _StaffNikScanPageState extends State<_StaffNikScanPage> {
  MobileScannerController? _camera;
  bool _busy = false;
  bool _locked = false;
  String? _error;
  bool _cameraReady = false;

  @override
  void initState() {
    super.initState();
    // Di web, kamera di dialog sering zero-size → hit-test error.
    // Full-page + start setelah layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  Future<void> _initCamera() async {
    if (!mounted) return;
    final ctrl = MobileScannerController(
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    _camera = ctrl;
    setState(() => _cameraReady = true);
    try {
      await ctrl.start();
    } catch (_) {
      // Web tanpa izin kamera: tetap bisa HID scanner.
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final nik = raw.trim();
    if (nik.isEmpty || _busy || _locked) return;
    setState(() {
      _busy = true;
      _locked = true;
      _error = null;
    });
    try {
      await _camera?.stop();
    } catch (_) {}
    try {
      final res = await _lookupStaff(nik);
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _busy = false;
          _locked = false;
          _error = QrScanRules.messageForReason('nik_tidak_ditemukan');
        });
        try {
          await _camera?.start();
        } catch (_) {}
        return;
      }
      if (!QrScanRules.staffNikSameStore(
        staffToko: res['toko_id']?.toString(),
        notaToko: widget.notaTokoId,
      )) {
        setState(() {
          _busy = false;
          _locked = false;
          _error = QrScanRules.messageForReason('karyawan_beda_toko');
        });
        try {
          await _camera?.start();
        } catch (_) {}
        return;
      }
      final status = (res['status_approval'] ?? '').toString();
      if (status.isNotEmpty && status.toLowerCase() != 'aktif') {
        setState(() {
          _busy = false;
          _locked = false;
          _error = 'pos_terlibat_not_aktif'.tr();
        });
        try {
          await _camera?.start();
        } catch (_) {}
        return;
      }
      final kid = res['id']?.toString() ?? '';
      if (kid.isNotEmpty) {
        final dutyBlock = await PosDutyGate.blockReason(
          karyawanId: kid,
          nik: nik,
        );
        if (dutyBlock != null) {
          setState(() {
            _busy = false;
            _locked = false;
            _error = dutyBlock.tr();
          });
          try {
            await _camera?.start();
          } catch (_) {}
          return;
        }
      }
      Navigator.pop(context, Map<String, dynamic>.from(res));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _locked = false;
        _error = e.toString();
      });
      try {
        await _camera?.start();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>?> _lookupStaff(String nik) async {
    final client = Supabase.instance.client;
    try {
      final params = <String, dynamic>{
        'p_nik': nik,
        'p_nota_toko_id': (widget.notaTokoId ?? '').trim(),
      };
      final res = await client.rpc(
        'lookup_staff_by_nik',
        params: TenantService.instance.isBound ? withTenant(params) : params,
      );
      if (res is Map) {
        final map = Map<String, dynamic>.from(res);
        if (map['ok'] == true) return map;
        throw QrScanRules.messageForReason(map['reason']?.toString());
      }
    } on PostgrestException catch (e) {
      final code = (e.code ?? '').toUpperCase();
      final msg = e.message.toLowerCase();
      final missing = code == 'PGRST202' ||
          code == 'PGRST204' ||
          msg.contains('could not find the function') ||
          msg.contains('schema cache');
      if (!missing) rethrow;
    }

    var q = client
        .from('karyawan')
        .select('id, nik, nama, jabatan, toko_id, status_approval, tenant_id')
        .eq('nik', nik);
    final bound = AttendanceAdminScope.boundTenantIdOrNull();
    if (bound != null) q = q.eq('tenant_id', bound);
    return q.maybeSingle();
  }

  @override
  Widget build(BuildContext context) {
    return HidScanIntake(
      tryHandleKnown: (result) async {
        await _submit(result.raw);
        return true;
      },
      onUnknown: (raw) async {
        await _submit(raw);
        return true;
      },
      child: PremiumScaffold(
        appBar: PremiumAppBar(
          title: widget.title,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraReady && _camera != null)
              MobileScanner(
                controller: _camera!,
                fit: BoxFit.cover,
                onDetect: (capture) {
                  if (_locked || _busy) return;
                  final barcodes = capture.barcodes;
                  if (barcodes.isEmpty) return;
                  final raw = barcodes.first.rawValue;
                  if (raw == null || raw.trim().isEmpty) return;
                  _submit(raw);
                },
              )
            else
              const ColoredBox(color: Colors.black87),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: OptikAdminTokens.ice, width: 3),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 40,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kIsWeb
                          ? 'Scanner USB/Bluetooth langsung terbaca di halaman ini.'
                          : 'Arahkan barcode NIK ke kotak bidik.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: OptikAdminTokens.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 14),
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
