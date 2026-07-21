import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_config.dart';
import '../../shared/attendance/attendance_qr_service.dart';

/// Layar Admin: QR absensi berputar untuk clock-in karyawan di toko.
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
  List<String> _tokoOptions = [];
  int _secondsLeft = 0;

  bool get _isPusat {
    final toko = (widget.profile['toko_id'] ?? '').toString();
    final role = (widget.profile['role'] ?? '').toString();
    return toko == 'PUSAT' ||
        toko == 'CABANG-PUSAT' ||
        role == 'owner' ||
        role == 'admin_pusat';
  }

  @override
  void initState() {
    super.initState();
    _tokoId = _isPusat ? null : widget.profile['toko_id']?.toString();
    _bootstrap();
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isPusat) {
        final rows = await Supabase.instance.client
            .from('toko_id')
            .select('id')
            .order('id');
        _tokoOptions = [
          for (final r in rows) r['id']?.toString() ?? '',
        ].where((e) => e.isNotEmpty && e != 'PUSAT').toList();
        _tokoId ??= _tokoOptions.isNotEmpty ? _tokoOptions.first : null;
      } else {
        _tokoId = widget.profile['toko_id']?.toString();
      }

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

  Future<void> _onTokoChanged(String? id) async {
    if (id == null || id == _tokoId) return;
    setState(() {
      _tokoId = id;
      _loading = true;
      _issue = null;
    });
    await _rotate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('attendance_qr_title'.tr()),
        backgroundColor: const Color(0xFF0F172A),
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
                  if (_isPusat && _tokoOptions.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: _tokoId,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: InputDecoration(
                        labelText: 'attendance_qr_pilih_toko'.tr(),
                        labelStyle: const TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Colors.blueAccent),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      items: [
                        for (final t in _tokoOptions)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: _onTokoChanged,
                    ),
                  if (_isPusat && _tokoOptions.isNotEmpty)
                    const SizedBox(height: 16),
                  Text(
                    'attendance_qr_hint'.tr(namedArgs: {
                      'toko': _tokoId ?? '-',
                      'detik': '${AttendanceConfig.qrTtlSeconds}',
                    }),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.45,
                      fontSize: 13,
                    ),
                  ),
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
