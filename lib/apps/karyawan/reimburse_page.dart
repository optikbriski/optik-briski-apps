import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/karyawan/reimburse_service.dart';
import '../../shared/ocr/deskew_document_capture.dart';
import '../../shared/ocr/google_vision_ocr_service.dart';
import '../../shared/theme.dart';

class ReimbursePage extends StatefulWidget {
  const ReimbursePage({super.key});

  @override
  State<ReimbursePage> createState() => _ReimbursePageState();
}

class _ReimbursePageState extends State<ReimbursePage> {
  final _svc = ReimburseService();
  final _ocr = GoogleVisionOcrService();
  final _catatan = TextEditingController();
  final _jumlah = TextEditingController();
  String _kategori = 'Bensin';
  Uint8List? _fotoBytes;
  bool _loading = true;
  bool _sending = false;
  bool _ocrBusy = false;
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _mine = [];

  static const _kats = ['Bensin', 'Parkir', 'Spare / alat', 'Lainnya'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _catatan.dispose();
    _jumlah.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'Belum login.';
      _me = await Supabase.instance.client
          .from('karyawan')
          .select('id, toko_id, nama')
          .eq('id', user.id)
          .maybeSingle();
      _me ??= user.email == null
          ? null
          : await Supabase.instance.client
              .from('karyawan')
              .select('id, toko_id, nama')
              .eq('email', user.email!)
              .maybeSingle();
      if (_me == null) throw 'Data karyawan tidak ditemukan.';
      _mine = await _svc.listMine(_me!['id'].toString());
    } catch (_) {
      _mine = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _kirim() async {
    final jumlah = int.tryParse(_jumlah.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (jumlah == null || jumlah <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi jumlah rupiah.')),
      );
      return;
    }
    if (_catatan.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catatan wajib diisi.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      String? fotoUrl;
      if (_fotoBytes != null) {
        final bytes = _fotoBytes!;
        final path =
            'reimburse/${_me!['id']}/${DateTime.now().millisecondsSinceEpoch}.jpg';
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
        kategori: _kategori,
        jumlahRp: jumlah,
        catatan: _catatan.text,
        fotoUrl: fotoUrl,
      );
      _catatan.clear();
      _jumlah.clear();
      _fotoBytes = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ops_reimburse_ok'.tr()),
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

  Future<void> _ambilFoto() async {
    final bytes = await captureDeskewedBytes(context: context);
    if (bytes == null || !mounted) return;
    setState(() {
      _fotoBytes = bytes;
      _ocrBusy = true;
    });
    try {
      final draft = await _ocr.readReceipt(bytes);
      if (!mounted) return;
      if (draft.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ops_reimburse_ocr_empty'.tr())),
        );
        return;
      }
      if (draft.amountRp != null) {
        _jumlah.text = '${draft.amountRp}';
      }
      final catatan = draft.catatanDraft;
      if (catatan.isNotEmpty) _catatan.text = catatan;
      _kategori = draft.suggestedKategori;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ops_reimburse_ocr_ok'.tr())),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ops_reimburse_ocr_fail'.tr(namedArgs: {'error': '$e'}),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.scaffold,
      appBar: AppBar(title: Text('ops_reimburse_title'.tr())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text('ops_reimburse_hint'.tr(),
                    style: const TextStyle(
                        color: OptikKaryawanTokens.muted, height: 1.35)),
                if (_ocrBusy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text('ops_reimburse_ocr_loading'.tr(),
                      style: const TextStyle(
                          color: OptikKaryawanTokens.muted, fontSize: 13)),
                ],
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _kategori,
                  items: [
                    for (final k in _kats)
                      DropdownMenuItem(value: k, child: Text(k)),
                  ],
                  onChanged: (v) => setState(() => _kategori = v ?? _kategori),
                  decoration: InputDecoration(labelText: 'ops_reimburse_kat'.tr()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _jumlah,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: 'ops_reimburse_jumlah'.tr()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _catatan,
                  maxLines: 3,
                  decoration:
                      InputDecoration(labelText: 'ops_reimburse_catatan'.tr()),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: (_sending || _ocrBusy) ? null : _ambilFoto,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(_fotoBytes == null
                      ? 'ops_reimburse_foto'.tr()
                      : 'ops_reimburse_foto_ok'.tr()),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: (_sending || _ocrBusy) ? null : _kirim,
                  child: Text(_sending ? '…' : 'ops_reimburse_kirim'.tr()),
                ),
                const SizedBox(height: 24),
                Text('ops_reimburse_riwayat'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_mine.isEmpty)
                  Text('ops_reimburse_kosong'.tr(),
                      style: const TextStyle(color: OptikKaryawanTokens.muted)),
                for (final r in _mine)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${r['kategori']} · Rp ${r['jumlah_rp']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${r['status']} · ${r['catatan'] ?? ''}',
                      maxLines: 2,
                    ),
                    trailing: Text(
                      DateFormat('d MMM').format(
                        DateTime.tryParse('${r['created_at']}')?.toLocal() ??
                            DateTime.now(),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
