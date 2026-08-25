import 'dart:io';
import 'package:flutter/material.dart';
import '../../shared/theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/safe_image_picker.dart';

class PengaduanPage extends StatefulWidget {
  const PengaduanPage({super.key});

  @override
  State<PengaduanPage> createState() => _PengaduanPageState();
}

class _PengaduanPageState extends State<PengaduanPage> {
  final formKey = GlobalKey<FormState>();
  final TextEditingController deskripsiCtrl = TextEditingController();
  String? kategoriPilihan;
  File? buktiFoto;
  bool isSubmitting = false;
  bool _loadingMine = true;
  List<Map<String, dynamic>> _mine = [];

  List<String> get _kategoriList => [
        'pengaduan_kat_sistem'.tr(),
        'pengaduan_kat_alat'.tr(),
        'pengaduan_kat_stok'.tr(),
        'pengaduan_kat_pelanggaran'.tr(),
      ];

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  Future<Map<String, dynamic>?> _fetchKaryawan() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final byId = await Supabase.instance.client
        .from('karyawan')
        .select('id, toko_id')
        .eq('id', user.id)
        .maybeSingle();
    if (byId != null) return byId;
    final email = user.email;
    if (email == null) return null;
    return Supabase.instance.client
        .from('karyawan')
        .select('id, toko_id')
        .eq('email', email)
        .maybeSingle();
  }

  Future<void> _loadMine() async {
    setState(() => _loadingMine = true);
    try {
      final karyawan = await _fetchKaryawan();
      if (karyawan == null) {
        if (mounted) setState(() { _mine = []; _loadingMine = false; });
        return;
      }
      final rows = await Supabase.instance.client
          .from('pengaduan')
          .select(
            'id, kategori, isi, status, balasan, dibalas_at, dibalas_oleh, created_at',
          )
          .eq('karyawan_id', karyawan['id'])
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      setState(() {
        _mine = List<Map<String, dynamic>>.from(rows as List);
        _loadingMine = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMine = false);
    }
  }

  Future<void> pilihBuktiFoto() async {
    final pickedFile =
        await pickImageSafe(context: context, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => buktiFoto = File(pickedFile.path));
    }
  }

  Future<void> kirimLaporan() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => isSubmitting = true);
    try {
      final karyawan = await _fetchKaryawan();
      if (karyawan == null) throw 'Data karyawan tidak ditemukan.';

      String? fotoUrl;
      if (buktiFoto != null) {
        final bytes = await buktiFoto!.readAsBytes();
        final path =
            '${karyawan['id']}/${DateTime.now().millisecondsSinceEpoch}.jpg';
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

      final row = {
        'karyawan_id': karyawan['id'],
        'toko_id': karyawan['toko_id'],
        'kategori': kategoriPilihan,
        'isi': deskripsiCtrl.text.trim(),
        'foto_url': fotoUrl,
        'status': 'OPEN',
      };

      await Supabase.instance.client.from('pengaduan').insert(row);

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('notifikasi').insert({
          'user_id': userId,
          'judul': 'Pengaduan terkirim',
          'isi': 'Laporan "$kategoriPilihan" sudah masuk ke pusat.',
          'tipe': 'ADMIN',
        });
      }

      if (!mounted) return;
      deskripsiCtrl.clear();
      setState(() {
        kategoriPilihan = null;
        buktiFoto = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("pengaduan_msg_sukses".tr()),
          backgroundColor: OptikKaryawanTokens.seasideMid,
        ),
      );
      await _loadMine();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal kirim pengaduan: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  InputDecoration inputStyle(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.bg,
      appBar: AppBar(
        title: Text("pengaduan_title".tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: OptikKaryawanTokens.cyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              "pengaduan_info_desc".tr(),
              style: const TextStyle(height: 1.35, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("pengaduan_label_kategori".tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: kategoriPilihan,
                  decoration: inputStyle("pengaduan_hint_kategori".tr()),
                  items: _kategoriList
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => kategoriPilihan = v),
                  validator: (v) =>
                      v == null ? "pengaduan_err_kategori".tr() : null,
                ),
                const SizedBox(height: 12),
                Text("pengaduan_label_penjelasan".tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: deskripsiCtrl,
                  maxLines: 4,
                  decoration: inputStyle("pengaduan_hint_penjelasan".tr()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? "pengaduan_err_penjelasan".tr()
                      : null,
                ),
                const SizedBox(height: 12),
                Text("pengaduan_label_foto".tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: pilihBuktiFoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    buktiFoto == null
                        ? "pengaduan_hint_foto".tr()
                        : buktiFoto!.path.split('/').last,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: isSubmitting ? null : kirimLaporan,
                  child: Text(
                    isSubmitting
                        ? "pengaduan_btn_mengirim".tr()
                        : "pengaduan_btn_kirim".tr(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'pengaduan_riwayat_title'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          if (_loadingMine)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_mine.isEmpty)
            Text(
              'pengaduan_riwayat_empty'.tr(),
              style: TextStyle(color: OptikKaryawanTokens.muted),
            )
          else
            ..._mine.map(_mineCard),
        ],
      ),
    );
  }

  Widget _mineCard(Map<String, dynamic> row) {
    final st = (row['status'] ?? 'OPEN').toString().toUpperCase();
    final balasan = (row['balasan'] ?? '').toString().trim();
    final when = DateTime.tryParse((row['created_at'] ?? '').toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikKaryawanTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (row['kategori'] ?? '-').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                st,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: st == 'DONE'
                      ? OptikKaryawanTokens.cyan
                      : Colors.orange.shade800,
                ),
              ),
            ],
          ),
          if (when != null) ...[
            const SizedBox(height: 2),
            Text(
              DateFormat('d MMM yyyy · HH:mm').format(when.toLocal()),
              style: TextStyle(
                color: OptikKaryawanTokens.muted,
                fontSize: 11.5,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            (row['isi'] ?? '').toString(),
            style: const TextStyle(height: 1.35, fontSize: 13),
          ),
          if (balasan.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: OptikKaryawanTokens.cyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'pengaduan_riwayat_balasan'.tr(namedArgs: {
                      'oleh': (row['dibalas_oleh'] ?? 'Admin').toString(),
                    }),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(balasan, style: const TextStyle(height: 1.35, fontSize: 13)),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'pengaduan_riwayat_menunggu'.tr(),
              style: TextStyle(
                color: OptikKaryawanTokens.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
