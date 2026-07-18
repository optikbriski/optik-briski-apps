import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/karyawan/jadwal_pengajuan_service.dart';

/// Karyawan: ajukan ijin / cuti / tukar jadwal + lihat status.
class PengajuanJadwalPage extends StatefulWidget {
  const PengajuanJadwalPage({super.key});

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

  @override
  void initState() {
    super.initState();
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

  Future<void> _submit() async {
    if (_me == null || _tanggal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih tanggal dulu.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await _svc.submit(
        karyawanId: _me!['id'].toString(),
        tokoId: _me!['toko_id']?.toString() ?? '',
        tipe: _tipe,
        tanggal: _tanggal!,
        alasan: _alasanCtrl.text,
        tanggalTukar: _tipe == 'TUKAR' ? _tanggalTukar : null,
        partnerKaryawanId: _tipe == 'TUKAR' ? _partnerId : null,
      );
      _alasanCtrl.clear();
      _tanggal = null;
      _tanggalTukar = null;
      _partnerId = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengajuan terkirim. Menunggu approval admin.'),
          backgroundColor: Colors.green,
        ),
      );
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
        return Colors.greenAccent;
      case 'REJECTED':
        return Colors.redAccent;
      case 'CANCELLED':
        return Colors.white38;
      default:
        return Colors.orangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Pengajuan Jadwal', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(onPressed: _bootstrap, icon: const Icon(Icons.refresh)),
        ],
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
                    const Text(
                      'Ajukan ijin, cuti, atau tukar jadwal. '
                      'Admin cabang / pusat yang menyetujui.',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Form pengajuan',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _tipe,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDeco('Jenis'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'IJIN', child: Text('Ijin')),
                              DropdownMenuItem(
                                  value: 'CUTI', child: Text('Cuti')),
                              DropdownMenuItem(
                                  value: 'TUKAR',
                                  child: Text('Tukar jadwal')),
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
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white),
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
                          const SizedBox(height: 12),
                          TextField(
                            controller: _alasanCtrl,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 3,
                            decoration: _fieldDeco('Alasan'),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(
                                _submitting ? 'Mengirim…' : 'Kirim pengajuan',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text('Riwayat saya',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    const SizedBox(height: 10),
                    if (_mine.isEmpty)
                      const Text('Belum ada pengajuan.',
                          style: TextStyle(color: Colors.white38))
                    else
                      ..._mine.map(_historyCard),
                  ],
                ),
    );
  }

  InputDecoration _fieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
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
            color: value == null ? Colors.white38 : Colors.white,
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tipe,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Text(status,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item['tanggal']?.toString().substring(0, 10) ?? '-',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (tipe == 'TUKAR' && partnerNama != null)
            Text('dengan $partnerNama',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(item['alasan']?.toString() ?? '-',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          if (status == 'PENDING') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  try {
                    await _svc.cancel(
                        item['id'].toString(), _me!['id'].toString());
                    await _bootstrap();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Gagal batal: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                },
                child: const Text('Batalkan',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
