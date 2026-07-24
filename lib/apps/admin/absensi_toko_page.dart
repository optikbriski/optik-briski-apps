import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/attendance/attendance_config.dart';
import '../../shared/attendance/attendance_geo_unlock_service.dart';
import '../../shared/attendance/attendance_liveness.dart';
import '../../shared/attendance/attendance_qr_service.dart';
import '../../shared/attendance/attendance_service.dart';
import '../../shared/attendance/face_verify_gimmick.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Absensi Toko (Admin web / perangkat toko) — cabang atau Pusat.
/// Alur: tampilkan QR → karyawan scan+GPS di geofence →
/// - belum shift OPEN: Admin liveness + foto → masuk (antrean Monitor)
/// - sudah shift OPEN: Admin auto pulang tanpa face → kembali ke QR.
/// Tanpa GPS di perangkat Admin (Mac OK).
/// Owner / admin_pusat / admin_toko di PUSAT → operasional CABANG-PUSAT
/// (fallback PUSAT).
class AbsensiTokoPage extends StatefulWidget {
  const AbsensiTokoPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<AbsensiTokoPage> createState() => _AbsensiTokoPageState();
}

enum _TokoAbsensiPhase { waitingQr, faceMatch }

class _AbsensiTokoPageState extends State<AbsensiTokoPage> {
  final _service = AttendanceService();
  final _qrService = AttendanceQrService();
  final _unlockService = AttendanceGeoUnlockService();

  Timer? _rotateTimer;
  Timer? _tickTimer;
  Timer? _pollTimer;
  RealtimeChannel? _realtime;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _tokoId;
  AttendanceQrIssue? _issue;
  int _secondsLeft = 0;

  _TokoAbsensiPhase _phase = _TokoAbsensiPhase.waitingQr;
  AttendanceGeoUnlock? _activeUnlock;
  Map<String, dynamic>? _selected;
  String? _statusLine;

  final Set<String> _handledUnlockIds = {};

  bool get _faceEnrolled => _service.isFaceEnrolled(_selected);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _stopWaitingListeners();
    _rotateTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  /// Cabang: toko_id profile. Pusat (owner / admin_pusat / admin_toko PUSAT):
  /// CABANG-PUSAT → PUSAT.
  Future<String?> _resolveTokoId() async {
    final profileToko = AttendanceAdminScope.tokoOf(widget.profile);
    final pusatKiosk =
        AttendanceAdminScope.usesPusatKioskToko(widget.profile);

    if (!pusatKiosk) {
      if (profileToko.isEmpty) return null;
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

    if (profileToko == 'CABANG-PUSAT') return 'CABANG-PUSAT';
    return 'PUSAT';
  }

  String get _kioskTitle {
    final pusat = AttendanceAdminScope.isPusatKioskLabel(widget.profile) ||
        AttendanceAdminScope.isPusatTokoId(_tokoId);
    return pusat
        ? 'dash_menu_absensi_pusat_kiosk'.tr()
        : 'dash_menu_absensi_kiosk'.tr();
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
          _error = 'absensi_toko_no_toko'.tr();
        });
        return;
      }
      await _rotateQr();
      _startQrTimers();
      _startWaitingListeners();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _startQrTimers() {
    _rotateTimer?.cancel();
    _tickTimer?.cancel();
    _rotateTimer = Timer.periodic(
      Duration(seconds: AttendanceConfig.qrRotateSeconds),
      (_) {
        if (_phase == _TokoAbsensiPhase.waitingQr && !_busy) {
          unawaited(_rotateQr());
        }
      },
    );
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final exp = _issue?.expiresAt;
      if (exp == null) return;
      final left = exp.difference(DateTime.now()).inSeconds;
      if (!mounted) return;
      setState(() => _secondsLeft = left < 0 ? 0 : left);
    });
  }

  Future<void> _rotateQr() async {
    final toko = _tokoId;
    if (toko == null || toko.isEmpty) return;
    try {
      final issue = await _qrService.issueToken(tokoId: toko);
      if (!mounted) return;
      setState(() {
        _issue = issue;
        _secondsLeft = issue.expiresAt.difference(DateTime.now()).inSeconds;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _startWaitingListeners() {
    _stopWaitingListeners();
    final toko = _tokoId;
    if (toko == null || toko.isEmpty) return;

    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (_phase != _TokoAbsensiPhase.waitingQr || _busy) return;
      unawaited(_pollLatestUnlock());
    });

    try {
      _realtime = Supabase.instance.client
          .channel('attendance-geo-unlock-$toko')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'attendance_geo_unlocks',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'toko_id',
              value: toko,
            ),
            callback: (payload) {
              if (_phase != _TokoAbsensiPhase.waitingQr || _busy) return;
              final map = payload.newRecord;
              if (map.isEmpty) return;
              try {
                final unlock = AttendanceGeoUnlock.fromJson(
                  Map<String, dynamic>.from(map),
                );
                unawaited(_onUnlockDetected(unlock));
              } catch (_) {
                unawaited(_pollLatestUnlock());
              }
            },
          )
          .subscribe();
    } catch (_) {
      // Poll tetap jalan jika Realtime gagal.
    }

    unawaited(_pollLatestUnlock());
  }

  void _stopWaitingListeners() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final ch = _realtime;
    _realtime = null;
    if (ch != null) {
      unawaited(Supabase.instance.client.removeChannel(ch));
    }
  }

  Future<void> _pollLatestUnlock() async {
    final toko = _tokoId;
    if (toko == null || toko.isEmpty) return;
    if (_phase != _TokoAbsensiPhase.waitingQr || _busy) return;
    try {
      final unlock = await _unlockService.fetchLatestForToko(toko);
      if (unlock == null || !mounted) return;
      await _onUnlockDetected(unlock);
    } catch (_) {
      // Diam saat poll gagal sementara.
    }
  }

  Future<void> _onUnlockDetected(AttendanceGeoUnlock unlock) async {
    if (!mounted) return;
    if (_phase != _TokoAbsensiPhase.waitingQr || _busy) return;
    if (_handledUnlockIds.contains(unlock.id)) return;
    if (!unlock.isValid) return;
    if (_tokoId != null &&
        !AttendanceAdminScope.sameTokoId(unlock.tokoId, _tokoId)) {
      return;
    }

    _handledUnlockIds.add(unlock.id);
    _stopWaitingListeners();

    setState(() {
      _busy = true;
      _activeUnlock = unlock;
      _statusLine = 'absensi_toko_lokasi_ok_auto'.tr();
    });

    try {
      // Geofence wajib di bukti unlock (QR saja tidak cukup).
      if (unlock.latitude == null || unlock.longitude == null) {
        _snack('absensi_toko_unlock_no_gps'.tr(), Colors.redAccent);
        await _returnToQr(consume: true);
        return;
      }

      final full = await _service.fetchKaryawanById(unlock.karyawanId);
      if (!mounted) return;
      if (full == null) {
        _snack('absensi_toko_karyawan_not_found'.tr(), Colors.redAccent);
        await _returnToQr(consume: true);
        return;
      }

      final karyawanToko = (full['toko_id'] ?? '').toString();
      if (karyawanToko.isNotEmpty &&
          _tokoId != null &&
          !AttendanceAdminScope.sameTokoId(karyawanToko, _tokoId)) {
        _snack(
          'absensi_toko_wrong_toko'.tr(namedArgs: {
            'karyawan': karyawanToko,
            'perangkat': _tokoId!,
          }),
          Colors.redAccent,
        );
        await _returnToQr(consume: true);
        return;
      }

      final shift = await _service.fetchOpenShift(full['id'] as String);
      if (!mounted) return;
      setState(() => _selected = full);

      // Shift OPEN → pulang QR-only (tanpa face). Belum masuk → face match.
      if (shift != null) {
        await _runAutoPulang();
        return;
      }

      setState(() {
        _phase = _TokoAbsensiPhase.faceMatch;
        _busy = false;
        _statusLine = 'absensi_toko_lokasi_ok_auto'.tr();
      });
      await _runFaceClock('MASUK');
    } catch (e) {
      _snack('$e', Colors.redAccent);
      await _returnToQr(consume: true);
    }
  }

  /// Pulang: bukti QR + GPS geofence saja — tanpa PIN / face match.
  Future<void> _runAutoPulang() async {
    final karyawan = _selected;
    final unlock = _activeUnlock;
    if (karyawan == null || unlock == null) {
      await _returnToQr(consume: true);
      return;
    }

    setState(() {
      _busy = true;
      _statusLine = 'absensi_toko_pulang_auto_running'.tr(
        namedArgs: {'nama': (karyawan['nama'] ?? '-').toString()},
      );
    });

    try {
      final geo = unlock.toGeofenceResult();
      await _service.clockOutByGeoUnlock(
        karyawan: karyawan,
        geo: geo,
        storeKiosk: true,
        qrTokenId: unlock.qrTokenId,
      );
      if (!mounted) return;
      _snack('absensi_toko_pulang_ok'.tr(), Colors.green);
      await _returnToQr(consume: true);
    } catch (e) {
      _snack('$e', Colors.redAccent);
      await _returnToQr(consume: true);
    }
  }

  Future<void> _returnToQr({required bool consume}) async {
    final unlock = _activeUnlock;
    if (consume && unlock != null) {
      try {
        await _unlockService.consumeUnlock(unlock.id);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _phase = _TokoAbsensiPhase.waitingQr;
      _activeUnlock = null;
      _selected = null;
      _busy = false;
      _statusLine = null;
    });
    _startWaitingListeners();
    unawaited(_rotateQr());
  }

  Future<bool> _confirmPinIfNeeded() async {
    final karyawan = _selected;
    if (karyawan == null) return false;
    final pin = (karyawan['pin_absensi'] ?? '').toString().trim();
    if (pin.isEmpty) return true;

    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'absensi_toko_pin_title'.tr(),
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'absensi_toko_pin_label'.tr(),
            labelStyle: const TextStyle(color: Colors.white70),
            counterText: '',
          ),
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('appr_btn_batal'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('absensi_toko_pin_lanjut'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    if (!_service.verifyPinAbsensi(karyawan, ctrl.text)) {
      _snack('absensi_toko_pin_salah'.tr(), Colors.redAccent);
      return false;
    }
    return true;
  }

  Future<void> _runFaceClock(String action) async {
    final karyawan = _selected;
    final tokoId = _tokoId;
    final unlock = _activeUnlock;
    if (karyawan == null || tokoId == null || unlock == null) return;

    if (action != 'ENROLL' && !_faceEnrolled) {
      // Belum enroll: daftarkan dulu, lalu kembali ke QR untuk absen berikutnya.
      final enrollOk = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            'absensi_toko_need_enroll'.tr(),
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            'absensi_toko_enroll_now_hint'.tr(),
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('appr_btn_batal'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('absensi_toko_enroll'.tr()),
            ),
          ],
        ),
      );
      if (enrollOk == true) {
        await _runFaceClock('ENROLL');
      } else {
        await _returnToQr(consume: true);
      }
      return;
    }

    if (action != 'ENROLL' &&
        kIsWeb &&
        (karyawan['face_photo_url'] ?? '').toString().trim().isEmpty) {
      _snack('absensi_toko_need_photo_reenroll'.tr(), Colors.orange);
      await _returnToQr(consume: true);
      return;
    }

    setState(() => _busy = true);
    try {
      if (!await _confirmPinIfNeeded()) {
        await _returnToQr(consume: true);
        return;
      }

      // Lokasi dari unlock HP karyawan — tanpa GPS Admin/Mac.
      if (unlock.latitude == null || unlock.longitude == null) {
        _snack('absensi_toko_unlock_no_gps'.tr(), Colors.redAccent);
        await _returnToQr(consume: true);
        return;
      }
      final geo = unlock.toGeofenceResult();

      if (!mounted) return;
      setState(() {
        _statusLine = 'absensi_toko_face_match_running'.tr(
          namedArgs: {'nama': (karyawan['nama'] ?? '-').toString()},
        );
      });

      final liveness = await captureAttendanceLiveness(
        context,
        onInfo: (key) => _snack(key.tr(), Colors.blueAccent),
      );
      if (liveness == null || !liveness.success) {
        _snack('aws_liveness_cancelled'.tr(), Colors.orange);
        await _returnToQr(consume: true);
        return;
      }
      if (liveness.photoBytes == null) {
        _snack('aws_liveness_face_unclear'.tr(), Colors.redAccent);
        await _returnToQr(consume: true);
        return;
      }
      // Absensi Toko: cukup foto liveness (tanpa face match ketat).
      // Template ML Kit hanya wajib jika path non-kiosk masih memakainya.

      if (!mounted) return;
      // Gimmick UX "memverifikasi wajah" — selalu lanjut, bukan reject match.
      await showFaceVerifyGimmick(context, photoBytes: liveness.photoBytes!);
      if (!mounted) return;

      if (action == 'ENROLL') {
        await _service.enrollFace(
          karyawanId: karyawan['id'] as String,
          tokoId: tokoId,
          liveness: liveness,
          geo: geo,
        );
        _snack('absensi_toko_enroll_ok'.tr(), Colors.green);
      } else {
        // MASUK: foto liveness → attendance_logs + antrean Monitor Absensi.
        final late = await _service.clockIn(
          karyawan: karyawan,
          liveness: liveness,
          geo: geo,
          storeKiosk: true,
          qrTokenId: unlock.qrTokenId,
        );
        final lateNote = late.isLate ? ' ${late.summary}.' : '';
        _snack(
          '${'absensi_toko_masuk_ok'.tr()}$lateNote',
          late.isLate ? Colors.orange : Colors.green,
        );
      }

      await _returnToQr(consume: true);
    } catch (e) {
      _snack('$e', Colors.redAccent);
      await _returnToQr(consume: true);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_kioskTitle),
        actions: [
          if (_phase == _TokoAbsensiPhase.waitingQr)
            IconButton(
              onPressed: _busy ? null : _rotateQr,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'attendance_qr_refresh'.tr(),
            ),
          if (_phase == _TokoAbsensiPhase.faceMatch)
            TextButton(
              onPressed: _busy ? null : () => _returnToQr(consume: true),
              child: Text('absensi_toko_batal_kembali_qr'.tr()),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _phase == _TokoAbsensiPhase.waitingQr
              ? _buildWaitingQr()
              : _buildFacePhase(),
    );
  }

  Widget _buildWaitingQr() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _banner(
          'absensi_toko_qr_first_banner'.tr(),
          OptikAdminTokens.accentSoft,
        ),
        const SizedBox(height: 10),
        _banner(
          'absensi_toko_web_no_gps_banner'.tr(),
          OptikAdminTokens.warning,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _banner(_error!, Colors.redAccent),
        ],
        const SizedBox(height: 16),
        Text(
          _tokoId ?? '-',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'attendance_qr_hint'.tr(namedArgs: {
            'toko': _tokoId ?? '-',
            'detik': '${AttendanceConfig.qrTtlSeconds}',
          }),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, height: 1.4),
        ),
        const SizedBox(height: 20),
        Center(
          child: _issue == null
              ? Text(
                  'attendance_qr_waiting'.tr(),
                  style: const TextStyle(color: Colors.white54),
                )
              : Column(
                  children: [
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
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 14),
                    Text(
                      _busy && _statusLine != null
                          ? _statusLine!
                          : 'absensi_toko_waiting_scan'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFacePhase() {
    final nama = (_selected?['nama'] ?? '-').toString();
    // Face phase hanya untuk masuk (pulang sudah auto tanpa UI wajah).
    const action = 'MASUK';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _banner(
          'absensi_toko_lokasi_ok_auto'.tr(),
          Colors.greenAccent,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nama,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_selected?['jabatan'] ?? '-'} • ${_selected?['toko_id'] ?? '-'}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              Text(
                'absensi_toko_akan_masuk'.tr(),
                style: const TextStyle(color: Colors.tealAccent),
              ),
              if (_statusLine != null) ...[
                const SizedBox(height: 8),
                Text(
                  _statusLine!,
                  style: const TextStyle(color: Colors.white54, height: 1.35),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else ...[
          _actionButton(
            label: 'absensi_toko_masuk'.tr(),
            color: Colors.green,
            onTap: () => _runFaceClock(action),
          ),
          TextButton(
            onPressed: () => _returnToQr(consume: true),
            child: Text('absensi_toko_batal_kembali_qr'.tr()),
          ),
        ],
      ],
    );
  }

  Widget _banner(String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(text, style: TextStyle(color: color, height: 1.45)),
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
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
