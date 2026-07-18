import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  List<String> get _kategoriList => [
        'pengaduan_kat_sistem'.tr(),
        'pengaduan_kat_alat'.tr(),
        'pengaduan_kat_stok'.tr(),
        'pengaduan_kat_pelanggaran'.tr(),
      ];

  Future<void> pilihBuktiFoto() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => buktiFoto = File(pickedFile.path));
    }
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

      await Supabase.instance.client.from('pengaduan').insert({
        'karyawan_id': karyawan['id'],
        'toko_id': karyawan['toko_id'],
        'kategori': kategoriPilihan,
        'isi': deskripsiCtrl.text.trim(),
        'foto_url': fotoUrl,
        'status': 'OPEN',
      });

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("pengaduan_msg_sukses".tr()),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text("pengaduan title".tr(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Colors.blueAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text("pengaduan_info_desc".tr(),
                          style: const TextStyle(
                              color: Color(0xFF1E3C72), fontSize: 13)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              Text("pengaduan_label_kategori".tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: kategoriPilihan,
                decoration: inputStyle("pengaduan_hint_kategori".tr()),
                items: _kategoriList
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) => setState(() => kategoriPilihan = v),
                validator: (v) =>
                    v == null ? "pengaduan err kategori".tr() : null,
              ),
              const SizedBox(height: 20),
              Text("pengaduan_label_penjelasan".tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              TextFormField(
                controller: deskripsiCtrl,
                maxLines: 5,
                decoration: inputStyle("pengaduan_hint_penjelasan".tr()),
                validator: (v) => (v == null || v.isEmpty)
                    ? "pengaduan_err_penjelasan".tr()
                    : null,
              ),
              const SizedBox(height: 20),
              Text("pengaduan_label_foto".tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: pilihBuktiFoto,
                child: Container(
                  width: double.infinity,
                  height: buktiFoto == null ? 120 : 250,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                    image: buktiFoto != null
                        ? DecorationImage(
                            image: FileImage(buktiFoto!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: buktiFoto == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_rounded,
                                color: Colors.grey.shade400, size: 40),
                            const SizedBox(height: 10),
                            Text("pengaduan_hint_foto".tr(),
                                style: TextStyle(color: Colors.grey.shade500)),
                          ],
                        )
                      : Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () => setState(() => buktiFoto = null),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isSubmitting ? null : kirimLaporan,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Colors.white),
                  label: Text(
                    isSubmitting
                        ? "pengaduan_btn_mengirim".tr()
                        : "pengaduan_btn_kirim".tr(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
