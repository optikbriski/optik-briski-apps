import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart'; // <-- Senjata Utama

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

  // Diubah menjadi getter agar bisa membaca .tr() setelah inisialisasi
  List<String> get _kategoriList => [
        'pengaduan_kat_sistem'.tr(),
        'pengaduan_kat_alat'.tr(),
        'pengaduan_kat_stok'.tr(),
        'pengaduan_kat_pelanggaran'.tr(),
      ];

  // FUNGSI UNTUK MENGAMBIL BUKTI FOTO
  Future<void> pilihBuktiFoto() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        buktiFoto = File(pickedFile.path);
      });
    }
  }

  // FUNGSI SUBMIT LAPORAN
  Future<void> kirimLaporan() async {
    if (formKey.currentState!.validate()) {
      setState(() => isSubmitting = true);

      await Future.delayed(
          const Duration(seconds: 2)); // Simulasi loading server

      if (mounted) {
        setState(() => isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("pengaduan_msg_sukses".tr()),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context); // Kembali ke profil setelah lapor
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title:
            Text("pengaduan title".tr(), // DIPERBAIKI: pakai spasi sesuai JSON
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
              // HEADER INFO
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Colors.blueAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "pengaduan_info_desc".tr(),
                        style: const TextStyle(
                            color: Color(0xFF1E3C72), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),

              // 1. KATEGORI PENGADUAN
              Text("pengaduan_label_kategori".tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: kategoriPilihan,
                decoration: inputStyle("pengaduan_hint_kategori".tr()),
                items: _kategoriList.map((String kategori) {
                  return DropdownMenuItem(
                    value: kategori,
                    child: Text(kategori, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (value) => setState(() => kategoriPilihan = value),
                validator: (value) => value == null
                    ? "pengaduan err kategori".tr()
                    : null, // DIPERBAIKI: pakai spasi
              ),
              const SizedBox(height: 20),

              // 2. DESKRIPSI LENGKAP
              Text("pengaduan_label_penjelasan".tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              TextFormField(
                controller: deskripsiCtrl,
                maxLines: 5,
                decoration: inputStyle("pengaduan_hint_penjelasan".tr()),
                validator: (value) => value == null || value.isEmpty
                    ? "pengaduan_err_penjelasan".tr()
                    : null,
              ),
              const SizedBox(height: 20),

              // 3. UPLOAD BUKTI FOTO (OPSIONAL)
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
                    border: Border.all(
                        color: Colors.grey.shade300, style: BorderStyle.solid),
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
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 13)),
                          ],
                        )
                      : Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.cancel,
                                color: Colors.redAccent, size: 30),
                            onPressed: () => setState(() => buktiFoto = null),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 40),

              // 4. TOMBOL KIRIM LAPORAN
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
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
                        ? "pengaduan_btn_mengirim"
                            .tr() // DIPERBAIKI: pakai underscore
                        : "pengaduan_btn_kirim".tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // WIDGET PEMBANTU: DESAIN FORM INPUT
  InputDecoration inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blueAccent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}
