import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../shared/theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/jadwal_kerja_rules.dart';
import '../../shared/karyawan/jadwal_pengajuan_service.dart';
import '../../shared/karyawan/karyawan_i18n_display.dart';
import '../../shared/safe_image_picker.dart';

/// Karyawan: ajukan ijin / cuti / tukar / dinas luar + lihat status.
class PengajuanJadwalPage extends StatefulWidget {
  const PengajuanJadwalPage({super.key, this.initialTipe});

  final String? initialTipe;

  @override
  State<PengajuanJadwalPage> createState() => _PengajuanJadwalPageState();
}

class _PengajuanJadwalPageState extends State<PengajuanJadwalPage> {
  final _svc = JadwalPengajuanService();
  final _alasanCtrl = TextEditingController();
  final _dayFmt = DateFormat('EEE, d MMM yyyy', 'id_ID');

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _coworkers = [];

  String _tipe = 'IJIN';
  DateTime? _tanggal;
  DateTime? _tanggalTukar;
  String? _partnerId;
  double? _lat;
  double? _lng;
  File? _foto;
  bool _gpsBusy = false;

  @override
  void initState() {
    super.initState();
    final init = (widget.initialTipe ?? '').trim().toUpperCase();
    if (JadwalKerjaRules.isAllowedTipe(init)) _tipe = init;
    _bootstrap();
  }

  @override
  void dispose() {
    _alasanCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _fetchMe() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final byId = await Supabase.instance.client
        .from('karyawan')
        .select('id, nama, toko_id')
        .eq('id', user.id)
        .maybeSingle();
    if (byId != null) return byId;
    final email = user.email;
    if (email == null) return null;
    return Supabase.instance.client
        .from('karyawan')
        .select('id, nama, toko_id')
        .eq('email', email)
        .maybeSingle();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _me = await _fetchMe();
      if (_me == null) throw 'Data karyawan tidak ditemukan.';
      final kid = _me!['id'].toString();
      final toko = _me!['toko_id']?.toString() ?? '';
      _mine = await _svc.listMine(kid);
      if (toko.isNotEmpty) {
        _coworkers = await _svc.coworkers(tokoId: toko, excludeId: kid);
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({required bool forTukar}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: forTukar
          ? (_tanggalTukar ?? _tanggal ?? now)
          : (_tanggal ?? now),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked == null) return;
    setState(() {
      if (forTukar) {
        _tanggalTukar = picked;
      } else {
        _tanggal = picked;
      }
    });
  }

  Future<void> _pinGps() async {
    setState(() => _gpsBusy = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw 'GPS perangkat mati. Nyalakan lokasi dulu.';
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw 'Izin lokasi ditolak.';
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Izin lokasi diblokir. Buka pengaturan HP.';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  Future<void> _submit() async {
    if (_me == null || _tanggal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih tanggal dulu.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      String? fotoUrl;
      if (_tipe == 'DINAS' && _foto != null) {
        final bytes = await _foto!.readAsBytes();
        final path =
            'dinas/${_me!['id']}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage
            .from('pengaduan_photos')
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        fotoUrl = Supabase.instance.client.storage
            .from('pengaduan_photos')
            .getPublicUrl(path);
      }
      await _svc.submit(
        karyawanId: _me!['id'].toString(),
        tokoId: _me!['toko_id']?.toString() ?? '',
        tipe: _tipe,
        tanggal: _tanggal!,
        alasan: _alasanCtrl.text,
        tanggalTukar: _tipe == 'TUKAR' ? _tanggalTukar : null,
        partnerKaryawanId: _tipe == 'TUKAR' ? _partnerId : null,
        lat: _tipe == 'DINAS' ? _lat : null,
        lng: _tipe == 'DINAS' ? _lng : null,
        fotoUrl: _tipe == 'DINAS' ? fotoUrl : null,
      );
      _alasanCtrl.clear();
      _tanggal = null;
      _tanggalTukar = null;
      _partnerId = null;
      _lat = null;
      _lng = null;
      _foto = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengajuan terkirim. Menunggu approval admin.'),
          backgroundColor: OptikKaryawanTokens.seasideMid,
        ),
      );
      if (!mounted) return;
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Gagal: $e\nPastikan migration jadwal_pengajuan sudah dijalankan.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Color _statusColor(String? s) {
    switch ((s ?? '').toUpperCase()) {
      case 'APPROVED':
        return OptikKaryawanTokens.success;
      case 'REJECTED':
        return OptikKaryawanTokens.danger;
      case 'CANCELLED':
        return OptikKaryawanTokens.muted;
      default:
        return OptikKaryawanTokens.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.scaffold,
      appBar: AppBar(
        backgroundColor: OptikKaryawanTokens.surface,
        foregroundColor: OptikKaryawanTokens.ink,
        title: const Text(
          'Pengajuan Jadwal',
          style: TextStyle(fontSize: 16, color: OptikKaryawanTokens.ink),
        ),
        actions: [
          IconButton(onPressed: _bootstrap, icon: const Icon(Icons.refresh)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: OptikKaryawanTokens.border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      'pengajuan_form_hint'.tr(),
                      style: const TextStyle(
                          color: OptikKaryawanTokens.muted,
                          fontSize: 12,
                          height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: OptikKaryawanTokens.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: OptikKaryawanTokens.border),
                        boxShadow: OptikKaryawanTokens.cardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Form pengajuan',
                              style: TextStyle(
                                  color: OptikKaryawanTokens.ink,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _tipe,
                            dropdownColor: OptikKaryawanTokens.surface,
                            style: const TextStyle(color: OptikKaryawanTokens.ink),
                            decoration: _fieldDeco('Jenis'),
                            items: [
                              DropdownMenuItem(
                                  value: 'IJIN',
                                  child: Text('pengajuan_tipe_ijin'.tr())),
                              DropdownMenuItem(
                                  value: 'CUTI',
                                  child: Text('pengajuan_tipe_cuti'.tr())),
                              DropdownMenuItem(
                                  value: 'TUKAR',
                                  child: Text('pengajuan_tipe_tukar'.tr())),
                              DropdownMenuItem(
                                  value: 'DINAS',
                                  child: Text('pengajuan_tipe_dinas'.tr())),
                            ],
                            onChanged: (v) =>
                                setState(() => _tipe = v ?? 'IJIN'),
                          ),
                          const SizedBox(height: 12),
                          _dateTile(
                            label: _tipe == 'TUKAR'
                                ? 'Hari saya yang ditukar'
                                : 'Tanggal',
                            value: _tanggal,
                            onTap: () => _pickDate(forTukar: false),
                          ),
                          if (_tipe == 'TUKAR') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _partnerId,
                              dropdownColor: OptikKaryawanTokens.surface,
                              style: const TextStyle(
                                  color: OptikKaryawanTokens.ink),
                              decoration: _fieldDeco('Tukar dengan'),
                              items: _coworkers
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c['id']?.toString(),
                                      child: Text(
                                        '${c['nama'] ?? '-'}'
                                        '${c['jabatan'] != null ? ' (${c['jabatan']})' : ''}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => _partnerId = v),
                            ),
                            const SizedBox(height: 12),
                            _dateTile(
                              label: 'Hari partner',
                              value: _tanggalTukar,
                              onTap: () => _pickDate(forTukar: true),
                            ),
                          ],
                          if (_tipe == 'DINAS') ...[
                            const SizedBox(height: 12),
                            Text(
                              'pengajuan_dinas_hint'.tr(),
                              style: const TextStyle(
                                color: OptikKaryawanTokens.muted,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _gpsBusy ? null : _pinGps,
                              icon: const Icon(Icons.my_location_outlined),
                              label: Text(
                                _lat == null
                                    ? 'pengajuan_dinas_gps'.tr()
                                    : 'pengajuan_dinas_gps_ok'.tr(
                                        namedArgs: {
                                          'lat': _lat!.toStringAsFixed(5),
                                          'lng': _lng!.toStringAsFixed(5),
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final f = await pickImageSafe(
                                  context: context,
                                  imageQuality: 70,
                                );
                                if (f != null) {
                                  setState(() => _foto = File(f.path));
                                }
                              },
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(
                                _foto == null
                                    ? 'pengajuan_dinas_foto'.tr()
                                    : 'pengajuan_dinas_foto_ok'.tr(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _alasanCtrl,
                            style: const TextStyle(color: OptikKaryawanTokens.ink),
                            maxLines: 3,
                            decoration: _fieldDeco('Alasan'),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OptikKaryawanTokens.seasideMid,
                                foregroundColor: OptikKaryawanTokens.ink,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(
                                _submitting ? 'Mengirim…' : 'Kirim pengajuan',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: OptikKaryawanTokens.ink),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text('Riwayat saya',
                        style: TextStyle(
                            color: OptikKaryawanTokens.ink,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    const SizedBox(height: 10),
                    if (_mine.isEmpty)
                      const Text('Belum ada pengajuan.',
                          style: TextStyle(color: OptikKaryawanTokens.muted))
                    else
                      ..._mine.map(_historyCard),
                  ],
                ),
    );
  }

  InputDecoration _fieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: OptikKaryawanTokens.muted),
      filled: true,
      fillColor: OptikKaryawanTokens.surfaceMuted,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: OptikKaryawanTokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: OptikKaryawanTokens.seasideMid,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _fieldDeco(label),
        child: Text(
          value == null ? 'Pilih tanggal' : _dayFmt.format(value),
          style: TextStyle(
            color: value == null
                ? OptikKaryawanTokens.muted
                : OptikKaryawanTokens.ink,
          ),
        ),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'PENDING';
    final color = _statusColor(status);
    final tipe = item['tipe']?.toString() ?? '-';
    final partner = item['partner'];
    final partnerNama =
        partner is Map ? partner['nama']?.toString() : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OptikKaryawanTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptikKaryawanTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  KaryawanI18nDisplay.pengajuanTipe(tipe),
                  style: const TextStyle(
                    color: OptikKaryawanTokens.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                KaryawanI18nDisplay.pengajuanStatus(status),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item['tanggal']?.toString().substring(0, 10) ?? '-',
            style: const TextStyle(
              color: OptikKaryawanTokens.muted,
              fontSize: 13,
            ),
          ),
          if (tipe == 'TUKAR' && partnerNama != null)
            Text(
              'pengajuan_dengan'.tr(namedArgs: {'nama': partnerNama}),
              style: const TextStyle(
                color: OptikKaryawanTokens.muted,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            item['alasan']?.toString() ?? '-',
            style: TextStyle(
              color: OptikKaryawanTokens.muted.withOpacity(0.85),
              fontSize: 12,
            ),
          ),
          if (tipe == 'DINAS' && item['lat'] != null && item['lng'] != null)
            Text(
              'GPS ${item['lat']} , ${item['lng']}',
              style: const TextStyle(
                color: OptikKaryawanTokens.muted,
                fontSize: 11,
              ),
            ),
          if ((item['reviewer_note']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'jadwal_catatan_label'.tr(
                  namedArgs: {
                    'note': item['reviewer_note'].toString(),
                  },
                ),
                style: const TextStyle(
                  color: OptikKaryawanTokens.muted,
                  fontSize: 12,
                ),
              ),
            ),
          if (status == 'PENDING') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  try {
                    await _svc.cancel(
                      item['id'].toString(),
                      _me!['id'].toString(),
                    );
                    await _bootstrap();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'pengajuan_err_batal'.tr(
                            namedArgs: {'error': '$e'},
                          ),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Text(
                  'pengajuan_btn_batal'.tr(),
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
