import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_config.dart';
import '../../shared/attendance/attendance_liveness.dart';
import '../../shared/attendance/attendance_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Absensi kiosk di perangkat Admin toko (tablet Android / browser Admin web).
/// Alur: pilih/cari karyawan → (PIN opsional) → liveness + face match → masuk/pulang.
/// Geofence = lokasi perangkat toko. Tidak memakai HP pribadi karyawan.
/// Web: challenge kamera browser + pencocokan foto referensi (tanpa AWS).
class AbsensiTokoPage extends StatefulWidget {
  const AbsensiTokoPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<AbsensiTokoPage> createState() => _AbsensiTokoPageState();
}

class _AbsensiTokoPageState extends State<AbsensiTokoPage> {
  final _service = AttendanceService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _tokoId;
  List<Map<String, dynamic>> _staff = const [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _openShift;

  bool get _faceEnrolled => _service.isFaceEnrolled(_selected);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<String?> _resolveTokoId() async {
    final profileToko = (widget.profile['toko_id'] ?? '').toString().trim();
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
          _error = 'absensi_toko_no_toko'.tr();
        });
        return;
      }
      final staff = await _service.listKaryawanForToko(_tokoId!);
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _selectStaff(Map<String, dynamic> row) async {
    setState(() {
      _busy = true;
      _selected = row;
      _openShift = null;
    });
    try {
      // Ambil ulang agar face_template lengkap.
      final full = await _service.fetchKaryawanById(row['id'].toString());
      final shift = full == null
          ? null
          : await _service.fetchOpenShift(full['id'] as String);
      if (!mounted) return;
      setState(() {
        _selected = full ?? row;
        _openShift = shift;
      });
    } catch (e) {
      _snack('$e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
      _openShift = null;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _staff;
    return _staff.where((k) {
      final nama = (k['nama'] ?? '').toString().toLowerCase();
      final nik = (k['nik'] ?? '').toString().toLowerCase();
      final jabatan = (k['jabatan'] ?? '').toString().toLowerCase();
      return nama.contains(q) || nik.contains(q) || jabatan.contains(q);
    }).toList();
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

  Future<void> _runAction(String action) async {
    final karyawan = _selected;
    final tokoId = _tokoId;
    if (karyawan == null || tokoId == null) return;

    final karyawanToko = (karyawan['toko_id'] ?? '').toString();
    if (karyawanToko.isNotEmpty && karyawanToko != tokoId) {
      _snack(
        'absensi_toko_wrong_toko'.tr(namedArgs: {
          'karyawan': karyawanToko,
          'perangkat': tokoId,
        }),
        Colors.redAccent,
      );
      return;
    }

    if (action != 'ENROLL' && !_faceEnrolled) {
      _snack('absensi_toko_need_enroll'.tr(), Colors.orange);
      return;
    }

    // Absensi web butuh foto referensi (face_photo_url) untuk face match.
    if (action != 'ENROLL' &&
        kIsWeb &&
        (karyawan['face_photo_url'] ?? '').toString().trim().isEmpty) {
      _snack('absensi_toko_need_photo_reenroll'.tr(), Colors.orange);
      return;
    }

    setState(() => _busy = true);
    try {
      if (!await _confirmPinIfNeeded()) return;

      // Geofence perangkat toko (bukan HP karyawan).
      final geo = await _service.checkGeofence(tokoId);
      if (!geo.inside) {
        _snack(geo.message, Colors.redAccent);
        return;
      }
      _snack(geo.message, Colors.green);

      if (!mounted) return;
      final liveness = await captureAttendanceLiveness(
        context,
        onInfo: (key) => _snack(key.tr(), Colors.blueAccent),
      );
      if (liveness == null || !liveness.success) {
        _snack('aws_liveness_cancelled'.tr(), Colors.orange);
        return;
      }
      if (liveness.photoBytes == null) {
        _snack('aws_liveness_face_unclear'.tr(), Colors.redAccent);
        return;
      }
      if (!kIsWeb && liveness.faceTemplate == null) {
        _snack('aws_liveness_face_unclear'.tr(), Colors.redAccent);
        return;
      }

      if (action == 'ENROLL') {
        await _service.enrollFace(
          karyawanId: karyawan['id'] as String,
          tokoId: tokoId,
          liveness: liveness,
          geo: geo,
        );
        _snack('absensi_toko_enroll_ok'.tr(), Colors.green);
      } else if (action == 'MASUK') {
        await _service.clockIn(
          karyawan: karyawan,
          liveness: liveness,
          geo: geo,
          storeKiosk: true,
        );
        _snack('absensi_toko_masuk_ok'.tr(), Colors.green);
      } else if (action == 'PULANG') {
        await _service.clockOut(
          karyawan: karyawan,
          liveness: liveness,
          geo: geo,
          storeKiosk: true,
        );
        _snack('absensi_toko_pulang_ok'.tr(), Colors.green);
      }

      await _selectStaff(karyawan);
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

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy • HH:mm', 'id_ID');

    return PremiumScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('absensi_toko_title'.tr()),
        actions: [
          IconButton(
            onPressed: _busy ? null : _bootstrap,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'attendance_qr_refresh'.tr(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (kIsWeb)
                  _banner(
                    'absensi_toko_web_hint'.tr(),
                    OptikAdminTokens.warning,
                  ),
                if (_error != null) ...[
                  _banner(_error!, Colors.redAccent),
                  const SizedBox(height: 12),
                ],
                _banner(
                  'absensi_toko_hint'.tr(namedArgs: {
                    'toko': _tokoId ?? '-',
                  }),
                  OptikAdminTokens.accentSoft,
                ),
                const SizedBox(height: 16),
                if (_selected == null) ...[
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'absensi_toko_search_hint'.tr(),
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_filtered.isEmpty)
                    Text(
                      'absensi_toko_empty'.tr(),
                      style: const TextStyle(color: Colors.white54),
                    )
                  else
                    ..._filtered.map((k) => _staffTile(k)),
                ] else ...[
                  _selectedCard(df),
                  const SizedBox(height: 16),
                  if (!_faceEnrolled)
                    _actionButton(
                      label: 'absensi_toko_enroll'.tr(),
                      color: Colors.purpleAccent,
                      onTap: _busy ? null : () => _runAction('ENROLL'),
                    ),
                  if (_faceEnrolled && _openShift == null)
                    _actionButton(
                      label: 'absensi_toko_masuk'.tr(),
                      color: Colors.green,
                      onTap: _busy ? null : () => _runAction('MASUK'),
                    ),
                  if (_faceEnrolled && _openShift != null)
                    _actionButton(
                      label: 'absensi_toko_pulang'.tr(),
                      color: Colors.orangeAccent,
                      onTap: _busy ? null : () => _runAction('PULANG'),
                    ),
                  if (_faceEnrolled)
                    TextButton(
                      onPressed: _busy ? null : () => _runAction('ENROLL'),
                      child: Text(
                        'absensi_toko_reenroll'.tr(),
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ),
                  TextButton(
                    onPressed: _busy ? null : _clearSelection,
                    child: Text('absensi_toko_ganti'.tr()),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (!AttendanceConfig.kioskSkipAdminQr) ...[
                  const SizedBox(height: 8),
                  Text(
                    'absensi_toko_qr_note'.tr(),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ],
            ),
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
      child: Text(
        text,
        style: TextStyle(color: color, height: 1.45),
      ),
    );
  }

  Widget _staffTile(Map<String, dynamic> k) {
    final enrolled = _service.isFaceEnrolled(k);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          onTap: _busy ? null : () => _selectStaff(k),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            (k['nama'] ?? '-').toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${k['jabatan'] ?? '-'} • NIK ${k['nik'] ?? '-'}',
            style: const TextStyle(color: Colors.white60),
          ),
          trailing: Icon(
            enrolled ? Icons.face_retouching_natural : Icons.face_outlined,
            color: enrolled ? Colors.greenAccent : Colors.white38,
          ),
        ),
      ),
    );
  }

  Widget _selectedCard(DateFormat df) {
    final k = _selected!;
    return Container(
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
            (k['nama'] ?? '-').toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${k['jabatan'] ?? '-'} • ${k['toko_id'] ?? '-'}',
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            'NIK: ${k['nik'] ?? '-'}',
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                _faceEnrolled
                    ? 'absensi_toko_face_ok'.tr()
                    : 'absensi_toko_face_no'.tr(),
                _faceEnrolled ? Colors.greenAccent : Colors.orange,
              ),
              _chip(
                _openShift == null
                    ? 'absensi_toko_shift_off'.tr()
                    : 'absensi_toko_shift_on'.tr(namedArgs: {
                        'waktu': df.format(
                          DateTime.parse(_openShift!['masuk_at'].toString()),
                        ),
                      }),
                _openShift == null ? Colors.blueAccent : Colors.tealAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
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
