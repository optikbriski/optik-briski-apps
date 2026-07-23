import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/attendance/attendance_config.dart';
import '../../shared/attendance/attendance_geo_unlock_service.dart';
import '../../shared/attendance/attendance_liveness.dart';
import '../../shared/attendance/attendance_qr_service.dart';
import '../../shared/attendance/attendance_service.dart';
import '../../shared/attendance/geofence_exit_monitor.dart';
import '../../shared/qr/hid_scan_intake.dart';
import '../../shared/qr/qr_route.dart';
import '../../shared/qr/universal_qr_scan_page.dart';

/// Absensi karyawan di HP pribadi.
/// Mode toko: scan QR Absensi + GPS geofence → geo unlock untuk Admin.
/// Masuk: face match di Admin. Pulang: QR + geofence saja (tanpa face).
class AbsensiPage extends StatefulWidget {
  const AbsensiPage({super.key, this.initialAttendanceRaw});

  /// Payload OBRATT dari scanner universal (opsional) — lanjut verifikasi lokasi.
  final String? initialAttendanceRaw;

  @override
  State<AbsensiPage> createState() => _AbsensiPageState();
}

class _AbsensiPageState extends State<AbsensiPage> {
  final _service = AttendanceService();
  final _qrService = AttendanceQrService();
  final _unlockService = AttendanceGeoUnlockService();
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _karyawan;
  Map<String, dynamic>? _openShift;
  String? _error;
  String? _lastUnlockMsg;
  Timer? _shiftWatchTimer;
  int _shiftWatchTicks = 0;

  bool get _faceEnrolled => _service.isFaceEnrolled(_karyawan);

  /// Face match clock-in/out dipindah ke perangkat toko.
  bool get _storeDeviceOnly => AttendanceConfig.faceMatchOnStoreDeviceOnly;

  bool _startedFromInitialQr = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _shiftWatchTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final karyawan = await _service.fetchKaryawan();
      Map<String, dynamic>? shift;
      if (karyawan != null) {
        shift = await _service.fetchOpenShift(karyawan['id'] as String);
      }
      if (!mounted) return;
      setState(() {
        _karyawan = karyawan;
        _openShift = shift;
        _loading = false;
        if (karyawan == null) {
          _error = 'Data karyawan tidak ditemukan untuk akun ini.';
        }
      });
      final kid = karyawan?['id']?.toString();
      final tid = karyawan?['toko_id']?.toString();
      if (kid != null && tid != null) {
        unawaited(
          GeofenceExitMonitor.instance.syncFromOpenShift(
            karyawanId: kid,
            tokoId: tid,
            hasOpenShift: shift != null,
            permissionContext: mounted ? context : null,
          ),
        );
      }
      _maybeContinueFromInitialQr();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _maybeContinueFromInitialQr() {
    if (_startedFromInitialQr) return;
    final raw = widget.initialAttendanceRaw?.trim();
    if (raw == null || raw.isEmpty) return;
    if (_karyawan == null || _busy) return;
    if (!AttendanceQrPayload.looksLike(raw)) {
      _snack('universal_qr_need_attendance'.tr(), Colors.orange);
      return;
    }
    _startedFromInitialQr = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_storeDeviceOnly) {
        unawaited(_runGeoUnlock(preScannedAttendanceRaw: raw));
      } else {
        unawaited(_runFlow(action: 'MASUK', preScannedAttendanceRaw: raw));
      }
    });
  }

  /// Scan QR Admin + GPS di geofence → tulis unlock singkat untuk Admin web.
  Future<void> _runGeoUnlock({String? preScannedAttendanceRaw}) async {
    if (kIsWeb) {
      _snack('Absensi lokasi hanya tersedia di HP (bukan web).', Colors.orange);
      return;
    }
    if (_karyawan == null) return;

    final tokoId = (_karyawan!['toko_id'] ?? '').toString();
    if (tokoId.isEmpty) {
      _snack('Toko karyawan belum terisi.', Colors.red);
      return;
    }

    setState(() => _busy = true);
    try {
      if (!mounted) return;
      final raw = (preScannedAttendanceRaw ?? '').trim().isNotEmpty
          ? preScannedAttendanceRaw!.trim()
          : await UniversalQrScanPage.scanRaw(
              context,
              allowedTypes: {QrPayloadType.attendance},
              titleKey: 'scan_qr',
              hintKey: 'attendance_qr_scan_hint',
            );
      if (raw == null || raw.trim().isEmpty) {
        _snack('attendance_qr_scan_cancelled'.tr(), Colors.orange);
        return;
      }
      if (!AttendanceQrPayload.looksLike(raw)) {
        _snack('universal_qr_need_attendance'.tr(), Colors.orange);
        return;
      }

      final validated = await _qrService.validatePayload(raw);
      if (validated.tokoId != tokoId) {
        _snack(
          'attendance_qr_wrong_toko'.tr(namedArgs: {
            'qr': validated.tokoId,
            'akun': tokoId,
          }),
          Colors.redAccent,
        );
        return;
      }

      // Strict: QR valid saja TIDAK cukup — GPS HP harus di dalam geofence.
      final geo = await _service.checkGeofence(tokoId);
      if (!geo.inside || geo.latitude == null || geo.longitude == null) {
        final detail = geo.message.trim();
        _snack(
          detail.isNotEmpty
              ? 'absensi_hp_geo_outside_detail'.tr(namedArgs: {
                  'detail': detail,
                })
              : 'absensi_hp_geo_outside'.tr(),
          Colors.redAccent,
        );
        return;
      }

      final hadOpenShift = _openShift != null;
      await _unlockService.createUnlock(
        karyawanId: _karyawan!['id'] as String,
        tokoId: tokoId,
        geo: geo,
        qrTokenId: validated.tokenId,
        source: hadOpenShift ? 'qr+gps:pulang' : 'qr+gps:masuk',
      );

      // Pulang: Admin auto tanpa face. Masuk: lanjut wajah di Admin.
      final msg = hadOpenShift
          ? 'absensi_hp_lokasi_ok_pulang'.tr()
          : 'absensi_hp_lokasi_ok_ke_admin'.tr();
      if (!mounted) return;
      setState(() => _lastUnlockMsg = msg);
      _snack(msg, Colors.green);
      // Pantau Admin menyelesaikan masuk (face) atau pulang (auto).
      _armShiftWatchAfterUnlock();
    } catch (e) {
      _snack('$e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Setelah unlock: tunggu Admin menyelesaikan face match, lalu start/stop
  /// [GeofenceExitMonitor] sesuai status shift OPEN.
  void _armShiftWatchAfterUnlock() {
    _shiftWatchTimer?.cancel();
    _shiftWatchTicks = 0;
    final kid = _karyawan?['id']?.toString();
    final tid = _karyawan?['toko_id']?.toString();
    if (kid == null || tid == null) return;

    final hadOpen = _openShift != null;
    _shiftWatchTimer = Timer.periodic(const Duration(seconds: 4), (t) async {
      _shiftWatchTicks++;
      if (_shiftWatchTicks > 90) {
        t.cancel();
        return;
      }
      try {
        final shift = await _service.fetchOpenShift(kid);
        final open = shift != null;
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _openShift = shift);
        await GeofenceExitMonitor.instance.syncFromOpenShift(
          karyawanId: kid,
          tokoId: tid,
          hasOpenShift: open,
          permissionContext: open && !hadOpen && mounted ? context : null,
        );
        // Perubahan status (masuk atau pulang) → cukup.
        if (open != hadOpen) {
          t.cancel();
          if (open) {
            if (!mounted) return;
            setState(() {
              _lastUnlockMsg = 'absensi_hp_masuk_tercatat'.tr();
            });
            _snack('absensi_hp_monitor_started'.tr(), Colors.teal);
          } else {
            if (!mounted) return;
            setState(() {
              _lastUnlockMsg = 'absensi_hp_pulang_tercatat'.tr();
            });
            _snack('absensi_hp_monitor_stopped'.tr(), Colors.blueGrey);
          }
        }
      } catch (e) {
        debugPrint('shift watch after unlock: $e');
      }
    });
  }

  Future<void> _runFlow({
    required String action,
    String? preScannedAttendanceRaw,
  }) async {
    if (kIsWeb) {
      _snack('Absensi wajah hanya tersedia di HP (bukan web).', Colors.orange);
      return;
    }
    if (_karyawan == null) return;

    // Masuk/pulang face match hanya di perangkat toko.
    if (_storeDeviceOnly && action != 'ENROLL') {
      await _runGeoUnlock(preScannedAttendanceRaw: preScannedAttendanceRaw);
      return;
    }

    final tokoId = (_karyawan!['toko_id'] ?? '').toString();
    if (tokoId.isEmpty) {
      _snack('Toko karyawan belum terisi.', Colors.red);
      return;
    }

    setState(() => _busy = true);
    try {
      final geo = await _service.checkGeofence(tokoId);
      if (!geo.inside) {
        _snack(geo.message, Colors.redAccent);
        return;
      }
      _snack(geo.message, Colors.green);

      String? qrTokenId;
      if (action == 'MASUK') {
        if (!mounted) return;
        final raw = (preScannedAttendanceRaw ?? '').trim().isNotEmpty
            ? preScannedAttendanceRaw!.trim()
            : await UniversalQrScanPage.scanRaw(
                context,
                allowedTypes: {QrPayloadType.attendance},
                titleKey: 'scan_qr',
                hintKey: 'attendance_qr_scan_hint',
              );
        if (raw == null || raw.trim().isEmpty) {
          _snack('attendance_qr_scan_cancelled'.tr(), Colors.orange);
          return;
        }
        if (!AttendanceQrPayload.looksLike(raw)) {
          _snack('universal_qr_need_attendance'.tr(), Colors.orange);
          return;
        }
        final validated = await _qrService.validatePayload(raw);
        if (validated.tokoId != tokoId) {
          _snack(
            'attendance_qr_wrong_toko'.tr(namedArgs: {
              'qr': validated.tokoId,
              'akun': tokoId,
            }),
            Colors.redAccent,
          );
          return;
        }
        qrTokenId = validated.tokenId;
        _snack('attendance_qr_ok'.tr(), Colors.green);
      }

      if (!mounted) return;
      final liveness = await captureAttendanceLiveness(
        context,
        onInfo: (key) => _snack(key.tr(), Colors.blueAccent),
      );
      if (liveness == null || !liveness.success) {
        _snack('aws_liveness_cancelled'.tr(), Colors.orange);
        return;
      }
      if (liveness.faceTemplate == null || liveness.photoBytes == null) {
        _snack('aws_liveness_face_unclear'.tr(), Colors.redAccent);
        return;
      }

      if (action == 'ENROLL') {
        await _service.enrollFace(
          karyawanId: _karyawan!['id'] as String,
          tokoId: tokoId,
          liveness: liveness,
          geo: geo,
        );
        _snack('Wajah berhasil didaftarkan.', Colors.green);
      } else if (action == 'MASUK') {
        await _service.clockIn(
          karyawan: _karyawan!,
          liveness: liveness,
          geo: geo,
          qrTokenId: qrTokenId,
        );
        final kid = _karyawan!['id']?.toString();
        final tid = _karyawan!['toko_id']?.toString();
        if (kid != null && tid != null) {
          await GeofenceExitMonitor.instance.start(
            karyawanId: kid,
            tokoId: tid,
            permissionContext: mounted ? context : null,
          );
        }
        _snack(
          'Absen masuk berhasil. Shift dimulai — lokasi dipantau '
          '(termasuk di background jika izin selalu diberikan).',
          Colors.green,
        );
      } else if (action == 'PULANG') {
        await _service.clockOut(
          karyawan: _karyawan!,
          liveness: liveness,
          geo: geo,
        );
        GeofenceExitMonitor.instance.stop();
        _snack('Absen pulang berhasil. Shift ditutup.', Colors.green);
      }

      await _refresh();
    } catch (e) {
      _snack('$e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<bool> _tryHandleAttendanceQr(QrRouteResult result) async {
    if (result.type != QrPayloadType.attendance) return false;
    if (_busy) return true;
    if (_storeDeviceOnly) {
      await _runGeoUnlock(preScannedAttendanceRaw: result.raw);
      return true;
    }
    if (_openShift != null) {
      _snack('Shift sudah aktif.', Colors.blueAccent);
      return true;
    }
    if (_karyawan == null || !_faceEnrolled) {
      _snack('Lengkapi data/wajah dulu, lalu absen masuk.', Colors.orange);
      return true;
    }
    await _runFlow(action: 'MASUK', preScannedAttendanceRaw: result.raw);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy • HH:mm', 'id_ID');

    return HidScanIntake(
      tryHandleKnown: _tryHandleAttendanceQr,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          title: const Text('Absensi'),
          backgroundColor: const Color(0xFF0F172A),
          actions: [
            IconButton(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.blueAccent))
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_error != null)
                      _card(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.redAccent)),
                      ),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _karyawan?['nama']?.toString() ?? '-',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_karyawan?['jabatan'] ?? '-'} • ${_karyawan?['toko_id'] ?? '-'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statusChip(
                                _faceEnrolled
                                    ? 'Wajah terdaftar'
                                    : 'Wajah belum didaftarkan',
                                _faceEnrolled
                                    ? Colors.greenAccent
                                    : Colors.orange,
                              ),
                              _statusChip(
                                _openShift == null
                                    ? 'Belum absen masuk'
                                    : 'Shift aktif sejak ${df.format(DateTime.parse(_openShift!['masuk_at']))}',
                                _openShift == null
                                    ? Colors.blueAccent
                                    : Colors.tealAccent,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _card(
                      child: Text(
                        _storeDeviceOnly
                            ? 'absensi_hp_syarat_kiosk'.tr()
                            : (AttendanceConfig.useAwsFaceLiveness
                                ? 'absensi_syarat_aws'.tr()
                                : 'absensi_syarat_local'.tr()),
                        style:
                            const TextStyle(color: Colors.white70, height: 1.5),
                      ),
                    ),
                    if (_lastUnlockMsg != null) ...[
                      const SizedBox(height: 12),
                      _card(
                        child: Text(
                          _lastUnlockMsg!,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (!_faceEnrolled)
                      _actionButton(
                        label: 'Daftarkan wajah (sekali)',
                        color: Colors.purpleAccent,
                        onTap: _busy ? null : () => _runFlow(action: 'ENROLL'),
                      ),
                    if (_storeDeviceOnly) ...[
                      _card(
                        child: Text(
                          'absensi_hp_kiosk_banner'.tr(),
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            height: 1.45,
                          ),
                        ),
                      ),
                      if (_openShift != null) ...[
                        const SizedBox(height: 12),
                        _card(
                          child: Text(
                            'absensi_hp_monitor_active_note'.tr(),
                            style: const TextStyle(
                              color: Colors.white60,
                              height: 1.45,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _actionButton(
                        label: 'absensi_hp_scan_qr_lokasi'.tr(),
                        color: Colors.teal,
                        onTap: _busy ? null : () => _runGeoUnlock(),
                      ),
                    ] else ...[
                      if (_faceEnrolled && _openShift == null) ...[
                        _actionButton(
                          label: 'Absen masuk',
                          color: Colors.green,
                          onTap:
                              _busy ? null : () => _runFlow(action: 'MASUK'),
                        ),
                      ],
                      if (_faceEnrolled && _openShift != null) ...[
                        _card(
                          child: Text(
                            'absensi_hp_monitor_active_note'.tr(),
                            style: const TextStyle(
                              color: Colors.white60,
                              height: 1.45,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _actionButton(
                          label: 'Absen pulang',
                          color: Colors.orangeAccent,
                          onTap:
                              _busy ? null : () => _runFlow(action: 'PULANG'),
                        ),
                      ],
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 20),
                      const Center(
                        child: CircularProgressIndicator(
                            color: Colors.blueAccent),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _busy || !_faceEnrolled
                          ? null
                          : () => _runFlow(action: 'ENROLL'),
                      child: const Text(
                        'Daftar ulang wajah',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: onTap,
          child: Text(
            label,
            style:
                const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ),
      ),
    );
  }
}
