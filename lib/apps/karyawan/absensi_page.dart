import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../shared/attendance/attendance_config.dart';
import '../../shared/attendance/attendance_qr_service.dart';
import '../../shared/attendance/attendance_service.dart';
import '../../shared/attendance/aws_face_liveness_page.dart';
import '../../shared/attendance/face_from_image.dart';
import '../../shared/attendance/liveness_result.dart';
import '../../shared/liveness_camera_page.dart';

/// Absensi karyawan: GPS toko + QR Admin (masuk) + liveness + face match.
class AbsensiPage extends StatefulWidget {
  const AbsensiPage({super.key});

  @override
  State<AbsensiPage> createState() => _AbsensiPageState();
}

class _AbsensiPageState extends State<AbsensiPage> {
  final _service = AttendanceService();
  final _qrService = AttendanceQrService();
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _karyawan;
  Map<String, dynamic>? _openShift;
  String? _error;

  bool get _faceEnrolled => _service.isFaceEnrolled(_karyawan);

  @override
  void initState() {
    super.initState();
    _refresh();
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _runFlow({required String action}) async {
    if (kIsWeb) {
      _snack('Absensi wajah hanya tersedia di HP (bukan web).', Colors.orange);
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
      // 1) Harus di radius toko
      final geo = await _service.checkGeofence(tokoId);
      if (!geo.inside) {
        _snack(geo.message, Colors.redAccent);
        return;
      }
      _snack(geo.message, Colors.green);

      // 2) Clock-in: wajib scan QR berputar di layar Admin toko
      String? qrTokenId;
      if (action == 'MASUK') {
        if (!mounted) return;
        final raw = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => const _AttendanceQrScannerPage()),
        );
        if (raw == null || raw.trim().isEmpty) {
          _snack('attendance_qr_scan_cancelled'.tr(), Colors.orange);
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

      // 3) Liveness + capture wajah
      if (!mounted) return;
      final liveness = await _captureLiveness();
      if (liveness == null || !liveness.success) {
        _snack('aws_liveness_cancelled'.tr(), Colors.orange);
        return;
      }
      if (liveness.faceTemplate == null || liveness.photoBytes == null) {
        _snack('aws_liveness_face_unclear'.tr(), Colors.redAccent);
        return;
      }

      // 4) Aksi
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
        _snack('Absen masuk berhasil. Shift dimulai.', Colors.green);
      } else if (action == 'PULANG') {
        await _service.clockOut(
          karyawan: _karyawan!,
          liveness: liveness,
          geo: geo,
        );
        _snack('Absen pulang berhasil. Shift ditutup.', Colors.green);
      }

      await _refresh();
    } catch (e) {
      _snack('$e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<LivenessCaptureResult?> _captureLiveness() async {
    if (AttendanceConfig.useAwsFaceLiveness) {
      final raw = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(builder: (_) => const AwsFaceLivenessPage()),
      );
      var result = _asLiveness(raw);
      if (result == null || !result.success) return result;

      // Reference image AWS kadang belum cukup untuk template lokal → fallback kamera.
      if (result.faceTemplate == null && result.photoBytes != null) {
        final tpl = await faceTemplateFromJpeg(result.photoBytes!);
        if (tpl != null) {
          result = LivenessCaptureResult(
            success: true,
            photoBytes: result.photoBytes,
            faceTemplate: tpl,
            livenessProvider: result.livenessProvider,
            livenessSessionId: result.livenessSessionId,
            livenessConfidence: result.livenessConfidence,
          );
        }
      }
      if (result.faceTemplate == null) {
        if (!mounted) return null;
        _snack('aws_liveness_need_local_face'.tr(), Colors.blueAccent);
        final localRaw = await Navigator.push<Object?>(
          context,
          MaterialPageRoute(builder: (_) => const LivenessCameraPage()),
        );
        final local = _asLiveness(localRaw);
        if (local == null ||
            !local.success ||
            local.faceTemplate == null ||
            local.photoBytes == null) {
          return null;
        }
        return LivenessCaptureResult(
          success: true,
          photoBytes: local.photoBytes,
          faceTemplate: local.faceTemplate,
          livenessProvider: 'aws',
          livenessSessionId: result.livenessSessionId,
          livenessConfidence: result.livenessConfidence,
        );
      }
      return result;
    }

    final raw = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const LivenessCameraPage()),
    );
    final local = _asLiveness(raw);
    if (local == null) return null;
    return LivenessCaptureResult(
      success: local.success,
      photoBytes: local.photoBytes,
      faceTemplate: local.faceTemplate,
      livenessProvider: 'local',
      livenessConfidence: local.success ? 100 : 0,
    );
  }

  LivenessCaptureResult? _asLiveness(Object? raw) {
    if (raw is LivenessCaptureResult) return raw;
    if (raw == true) {
      return const LivenessCaptureResult(
        success: true,
        livenessProvider: 'local',
        livenessConfidence: 100,
      );
    }
    return null;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy • HH:mm', 'id_ID');

    return Scaffold(
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
                      AttendanceConfig.useAwsFaceLiveness
                          ? 'absensi_syarat_aws'.tr()
                          : 'absensi_syarat_local'.tr(),
                      style: const TextStyle(color: Colors.white70, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_faceEnrolled)
                    _actionButton(
                      label: 'Daftarkan wajah (sekali)',
                      color: Colors.purpleAccent,
                      onTap: _busy ? null : () => _runFlow(action: 'ENROLL'),
                    ),
                  if (_faceEnrolled && _openShift == null) ...[
                    _actionButton(
                      label: 'Absen masuk',
                      color: Colors.green,
                      onTap: _busy ? null : () => _runFlow(action: 'MASUK'),
                    ),
                  ],
                  if (_faceEnrolled && _openShift != null) ...[
                    _actionButton(
                      label: 'Absen pulang',
                      color: Colors.orangeAccent,
                      onTap: _busy ? null : () => _runFlow(action: 'PULANG'),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 20),
                    const Center(
                      child: CircularProgressIndicator(color: Colors.blueAccent),
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
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
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
            style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ),
      ),
    );
  }
}

class _AttendanceQrScannerPage extends StatefulWidget {
  const _AttendanceQrScannerPage();

  @override
  State<_AttendanceQrScannerPage> createState() =>
      _AttendanceQrScannerPageState();
}

class _AttendanceQrScannerPageState extends State<_AttendanceQrScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('attendance_qr_scan_title'.tr()),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_done) return;
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;
              final raw = barcodes.first.rawValue;
              if (raw == null || raw.isEmpty) return;
              _done = true;
              Navigator.pop(context, raw);
            },
          ),
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Text(
              'attendance_qr_scan_hint'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
