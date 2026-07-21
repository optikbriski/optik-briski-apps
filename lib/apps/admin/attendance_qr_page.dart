import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_config.dart';
import '../../shared/attendance/attendance_qr_service.dart';
import '../../shared/training/training_mode.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Layar Admin: QR absensi berputar untuk clock-in di toko ini.
/// Cabang → QR cabang itu. Pusat → QR kantor pusat (bukan pilih cabang).
class AttendanceQrPage extends StatefulWidget {
  const AttendanceQrPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<AttendanceQrPage> createState() => _AttendanceQrPageState();
}

class _AttendanceQrPageState extends State<AttendanceQrPage> {
  final _svc = AttendanceQrService();
  Timer? _rotateTimer;
  Timer? _tickTimer;

  bool _loading = true;
  String? _error;
  AttendanceQrIssue? _issue;
  String? _tokoId;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  /// Toko untuk QR = toko admin yang login.
  /// Profile `PUSAT` (meta) → pakai `CABANG-PUSAT` jika ada di DB.
  Future<String?> _resolveTokoId() async {
    final profileToko =
        (widget.profile['toko_id'] ?? '').toString().trim();

    if (profileToko.isNotEmpty && profileToko != 'PUSAT') {
      return profileToko;
    }

    try {
      final row = await Supabase.instance.client
          .from('toko_id')
          .select('id')
          .eq('id', 'CABANG-PUSAT')
          .maybeSingle();
      final id = row?['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}

    if (profileToko == 'PUSAT') return 'PUSAT';
    return profileToko.isEmpty ? null : profileToko;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _tokoId = await _resolveTokoId();

      if (_tokoId == null || _tokoId!.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'attendance_qr_no_toko'.tr();
        });
        return;
      }

      await _rotate();
      _startTimers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _startTimers() {
    _rotateTimer?.cancel();
    _tickTimer?.cancel();
    _rotateTimer = Timer.periodic(
      Duration(seconds: AttendanceConfig.qrRotateSeconds),
      (_) => _rotate(),
    );
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final exp = _issue?.expiresAt;
      if (exp == null) return;
      final left = exp.difference(DateTime.now()).inSeconds;
      if (!mounted) return;
      setState(() => _secondsLeft = left < 0 ? 0 : left);
    });
  }

  Future<void> _rotate() async {
    final toko = _tokoId;
    if (toko == null || toko.isEmpty) return;
    try {
      final issue = await _svc.issueToken(tokoId: toko);
      if (!mounted) return;
      setState(() {
        _issue = issue;
        _secondsLeft = issue.expiresAt.difference(DateTime.now()).inSeconds;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'dash_menu_absen'.tr(),
        actions: [
          IconButton(
            tooltip: 'attendance_qr_refresh'.tr(),
            onPressed: _loading ? null : _rotate,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _issue == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'dash_absen_flow_hint'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.45,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'attendance_qr_hint'.tr(namedArgs: {
                      'toko': _tokoId ?? '-',
                      'detik': '${AttendanceConfig.qrTtlSeconds}',
                    }),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      height: 1.4,
                      fontSize: 12,
                    ),
                  ),
                  if (TrainingMode.instance.isActive) ...[
                    const SizedBox(height: 10),
                    Text(
                      'training_attendance_stub_note'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  Expanded(
                    child: Center(
                      child: _issue == null
                          ? Text(
                              'attendance_qr_waiting'.tr(),
                              style: const TextStyle(color: Colors.white54),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _tokoId ?? '-',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: QrImageView(
                                    data: _issue!.payload,
                                    version: QrVersions.auto,
                                    size: 260,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'attendance_qr_countdown'.tr(
                                    namedArgs: {'detik': '$_secondsLeft'},
                                  ),
                                  style: TextStyle(
                                    color: _secondsLeft <= 8
                                        ? Colors.orangeAccent
                                        : Colors.tealAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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
