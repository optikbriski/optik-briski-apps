import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/payroll/payroll_service.dart';
import '../../shared/theme.dart';

class PengajuanLemburPage extends StatefulWidget {
  const PengajuanLemburPage({super.key});

  @override
  State<PengajuanLemburPage> createState() => _PengajuanLemburPageState();
}

class _PengajuanLemburPageState extends State<PengajuanLemburPage> {
  final _svc = PayrollService();
  final _jam = TextEditingController();
  final _alasan = TextEditingController();
  DateTime _tanggal = DateTime.now();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _mine = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _jam.dispose();
    _alasan.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'Belum login.';
      _me = await Supabase.instance.client
          .from('karyawan')
          .select('id, toko_id')
          .eq('id', user.id)
          .maybeSingle();
      _me ??= user.email == null
          ? null
          : await Supabase.instance.client
              .from('karyawan')
              .select('id, toko_id')
              .eq('email', user.email!)
              .maybeSingle();
      if (_me == null) throw 'Data karyawan tidak ditemukan.';
      _mine = await _svc.listMineOvertime(_me!['id'].toString());
      _error = null;
    } catch (e) {
      _mine = [];
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _kirim() async {
    final jam = num.tryParse(_jam.text.replaceAll(',', '.'));
    setState(() => _sending = true);
    try {
      await _svc.submitKaryawanOvertime(
        karyawanId: _me!['id'].toString(),
        tokoId: _me!['toko_id']?.toString() ?? '',
        tanggal: _tanggal,
        jam: jam ?? 0,
        alasan: _alasan.text,
      );
      _jam.clear();
      _alasan.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ops_lembur_ok'.tr()),
          backgroundColor: OptikKaryawanTokens.seasideMid,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.scaffold,
      appBar: AppBar(title: Text('ops_lembur_title'.tr())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text('ops_lembur_hint'.tr(),
                    style: const TextStyle(
                        color: OptikKaryawanTokens.muted, height: 1.35)),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('ops_lembur_tanggal'.tr()),
                  subtitle: Text(DateFormat('EEE, d MMM yyyy', 'id_ID')
                      .format(_tanggal)),
                  trailing: const Icon(Icons.event),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _tanggal,
                      firstDate: DateTime.now().subtract(const Duration(days: 14)),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _tanggal = d);
                  },
                ),
                TextField(
                  controller: _jam,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'ops_lembur_jam'.tr()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _alasan,
                  maxLines: 3,
                  decoration:
                      InputDecoration(labelText: 'ops_lembur_alasan'.tr()),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _sending ? null : _kirim,
                  child: Text(_sending ? '…' : 'ops_lembur_kirim'.tr()),
                ),
                const SizedBox(height: 24),
                Text('ops_lembur_riwayat'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                for (final r in _mine)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${r['jam']} jam · ${r['status']}'),
                    subtitle: Text(() {
                      final meta = r['meta'];
                      final alasan =
                          meta is Map ? '${meta['alasan'] ?? ''}' : '';
                      return '${r['tanggal'] ?? ''} · $alasan';
                    }()),
                  ),
              ],
            ),
    );
  }
}
