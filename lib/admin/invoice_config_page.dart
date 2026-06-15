// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data'; // Untuk konversi data binary Uint8List gambar hasil crop
import 'package:image_picker/image_picker.dart'; // Driver mengambil berkas dari galeri/file explorer
import 'package:crop_your_image/crop_your_image.dart'; // Engine pemotong citra logo secara real-time
import 'dart:convert';

class InvoiceConfigPage extends StatefulWidget {
  final Map<String, dynamic>
      profile; // Menampung data session user yang sedang aktif
  const InvoiceConfigPage({super.key, required this.profile});

  @override
  State<InvoiceConfigPage> createState() => _InvoiceConfigPageState();
}

class _InvoiceConfigPageState extends State<InvoiceConfigPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isSaving = false;

  // Manajemen Cabang Multi-Branch POS
  String _selectedTokoId = 'PUSAT';
  List<String> _listCabangTerdata = ['PUSAT'];

  // Form Controllers - Konfigurasi Layout & Teks Statis Struk
  final _shopNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();

  // Variabel Pengaturan Desain Utama
  String _alignment = 'CENTER';
  double _fontSizeHeader = 16;
  double _fontSizeBody = 12;
  bool _showQr = true;

  // 🎯 REVISI SAKTI: Penampung data transaksi riil dari database untuk Live Preview
  Map<String, dynamic>? _previewSale;
  List<dynamic> _previewSaleItems = [];

  @override
  void initState() {
    super.initState();
    _eksekusiProteksiAkses();
  }

  // Validasi Hak Akses - Memastikan Hanya Owner & Admin Pusat yang bisa mengonfigurasi layout nota
  void _eksekusiProteksiAkses() {
    String role = widget.profile['role']?.toString().toLowerCase() ?? '';
    if (role != 'owner' && role != 'admin_pusat') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "🛑 Akses Ditolak! Hanya Owner & Admin Pusat yang memiliki otoritas konfigurasi."),
          backgroundColor: Colors.redAccent,
        ));
        Navigator.pop(context);
      });
      return;
    }
    _fetchDaftarCabangTerdata();
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _logoUrlCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  // Formatter mandiri mengubah angka biner menjadi teks Rupiah lokal
  String _formatRupiah(dynamic angka) {
    if (angka == null) return 'Rp0';
    int value = int.tryParse(angka.toString()) ?? 0;
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String hasil =
        value.toString().replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return "Rp$hasil";
  }

  // 🎯 PARSER DINAMIS DENGAN KUNCI PENGAMAN (ANTI-CRASH)
  String _parseResepDariDatabase(String eye, String param) {
    if (_previewSaleItems.isEmpty) return '0.00';

    // ✅ PERBAIKAN 1: Gunakan orElse yang mengembalikan Map kosong hambar, bukan null, agar aman dari crash
    final lensaItem = _previewSaleItems.firstWhere(
      (e) =>
          e['detail_resep'] != null &&
          e['detail_resep'] != 'Normal' &&
          e['detail_resep'].toString().contains('|'),
      orElse: () => <String, dynamic>{},
    );

    if (lensaItem.isEmpty) return param == 'PD' ? '-' : '0.00';
    String resepStr = lensaItem['detail_resep'] ?? '';

    try {
      List<String> parts = resepStr.split('|');
      if (param == 'PD') {
        if (resepStr.contains('PD Pasien:')) {
          return resepStr.split('PD Pasien:')[1].trim();
        }
        return '-';
      }
      String sideStr = eye == 'OD' ? parts[0] : parts[1];
      final regExp = RegExp('$param\\s+([^/|\\s°]+)');
      final match = regExp.firstMatch(sideStr);
      return match?.group(1) ?? '0.00';
    } catch (_) {
      return '0.00';
    }
  }

  // SCANNER UTALITAS: Memindai seluruh id cabang unik dari transaksi produk dan tabel settings
  Future<void> _fetchDaftarCabangTerdata() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final setCabang = <String>{'PUSAT'};

      final resProduk =
          await _supabase.from('products').select('toko_id') as List;
      for (var row in resProduk) {
        String? idToko = row['toko_id']?.toString().toUpperCase();
        if (idToko != null && idToko.isNotEmpty) setCabang.add(idToko);
      }

      final resInvoice =
          await _supabase.from('invoice_settings').select('toko_id') as List;
      for (var row in resInvoice) {
        String? idToko = row['toko_id']?.toString().toUpperCase();
        if (idToko != null && idToko.isNotEmpty) setCabang.add(idToko);
      }

      setState(() {
        _listCabangTerdata = setCabang.toList()..sort();
        if (!_listCabangTerdata.contains(_selectedTokoId)) {
          _selectedTokoId = _listCabangTerdata.first;
        }
      });

      await _loadSettings();
    } catch (e) {
      debugPrint("Gagal sinkronisasi data identitas cabang: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Mengambil konfigurasi template desain nota sekaligus menarik transaksi riil terakhir dari database
  Future<void> _loadSettings() async {
    try {
      final data = await _supabase
          .from('invoice_settings')
          .select()
          .eq('toko_id', _selectedTokoId)
          .maybeSingle();

      // 🎯 SINKRONISASI LIVE PREVIEW: Ambil transaksi riil paling baru dari database cabang terkait
      final saleRes = await _supabase
          .from('sales')
          .select()
          .eq('toko_id', _selectedTokoId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      List<dynamic> itemsRes = [];
      if (saleRes != null) {
        itemsRes = await _supabase
            .from('sales_items')
            .select()
            .eq('sale_id', saleRes['id']);
      }

      if (data != null) {
        setState(() {
          _shopNameCtrl.text = data['shop_name'] ?? 'OPTIK B. RISKI';
          _addressCtrl.text = data['address'] ?? '';
          _phoneCtrl.text = data['phone'] ?? '';
          _logoUrlCtrl.text = data['logo_url'] ?? '';
          _footerCtrl.text = data['footer_text'] ?? '';
          _alignment = data['header_alignment'] ?? 'CENTER';
          _fontSizeHeader = (data['font_size_header'] ?? 16).toDouble();
          _fontSizeBody = (data['font_size_body'] ?? 12).toDouble();
          _showQr = data['show_qr_invoice'] ?? true;
          _previewSale = saleRes;
          _previewSaleItems = itemsRes;
        });
      } else {
        setState(() {
          _shopNameCtrl.text =
              'OPTIK B. RISKI ${_selectedTokoId == 'PUSAT' ? '' : _selectedTokoId}';
          _addressCtrl.clear();
          _phoneCtrl.clear();
          _logoUrlCtrl.clear();
          _footerCtrl.clear();
          _alignment = 'CENTER';
          _fontSizeHeader = 16;
          _fontSizeBody = 12;
          _showQr = true;
          _previewSale = saleRes;
          _previewSaleItems = itemsRes;
        });
      }
    } catch (e) {
      debugPrint("Gagal memuat konfigurasi dari database: $e");
    }
  }

  // Menyimpan atau meng-update template desain nota ke cloud Supabase
  Future<void> _saveSettings() async {
    if (_selectedTokoId.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await _supabase.from('invoice_settings').upsert({
        'toko_id': _selectedTokoId,
        'shop_name': _shopNameCtrl.text,
        'address': _addressCtrl.text,
        'phone': _phoneCtrl.text,
        'logo_url': _logoUrlCtrl.text,
        'footer_text': _footerCtrl.text,
        'header_alignment': _alignment,
        'font_size_header': _fontSizeHeader.toInt(),
        'font_size_body': _fontSizeBody.toInt(),
        'show_qr_invoice': _showQr,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "🎉 Konfigurasi layout $_selectedTokoId sukses disimpan dan disinkronkan ke unit POS!"),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Sistem gagal menyimpan perubahan: $e"),
          backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Mengosongkan data setting cabang tertentu kembali ke setelan pabrik/default
  Future<void> _hapusSettingCabang() async {
    if (_selectedTokoId == 'PUSAT') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "🛑 Regulasi Sistem: Data PUSAT bersifat master dan dilarang keras dihapus!"),
          backgroundColor: Colors.orange));
      return;
    }

    bool confirm = await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text("Hapus Konfigurasi $_selectedTokoId?",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            content: Text(
                "Tindakan ini akan menghapus layout kustom cabang $_selectedTokoId dan mengembalikannya ke format standar template.",
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text("Batal",
                      style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(c, true),
                child: const Text("Hapus Permanen",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ) ??
        false;

    if (confirm) {
      try {
        await _supabase
            .from('invoice_settings')
            .delete()
            .eq('toko_id', _selectedTokoId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "🗑️ Sukses membersihkan berkas konfigurasi $_selectedTokoId."),
          backgroundColor: Colors.orange,
        ));
        _fetchDaftarCabangTerdata();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal menghapus: $e"),
            backgroundColor: Colors.redAccent));
      }
    }
  }

  // DRIVER INTERAKTIF: Memilih gambar, memotong via modal, lalu melempar binary data ke Supabase Storage
  Future<void> _pilihDanCropLogo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;
    final Uint8List imageBytes = await image.readAsBytes();

    if (!mounted) return;
    final cropController = CropController();

    final Uint8List? croppedData = await showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("✂️ Crop Logo Identitas Cabang",
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 450,
          height: 400,
          child: Crop(
            image: imageBytes,
            controller: cropController,
            onCropped: (result) {
              if (result is CropSuccess) {
                Navigator.pop(ctx, result.croppedImage);
              } else {
                Navigator.pop(ctx, null);
              }
            },
            interactive: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text("Batal", style: TextStyle(color: Colors.grey))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            icon: const Icon(Icons.crop_rounded),
            label: const Text("POTONG & UPLOAD",
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => cropController.crop(),
          )
        ],
      ),
    );

    if (croppedData != null) {
      setState(() => _isLoading = true);
      try {
        final String namaFile = "logo_${_selectedTokoId.toLowerCase()}.png";

        await _supabase.storage.from('LOGO').uploadBinary(
              namaFile,
              croppedData,
              fileOptions:
                  const FileOptions(upsert: true, contentType: 'image/png'),
            );

        final String publicUrl =
            _supabase.storage.from('LOGO').getPublicUrl(namaFile);

        setState(() {
          _logoUrlCtrl.text = publicUrl;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                "🚀 Berhasil memotong citra logo & memperbarui Cloud Storage!"),
            backgroundColor: Colors.green));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal mengunggah gambar logo: $e"),
            backgroundColor: Colors.redAccent));
      } finally {
        if (mounted) {
          // ✅ PERBAIKAN 2: Kembalikan _isLoading ke false dengan steril, matikan eror final assignment hantu kemarin!
          setState(() => _isLoading = false);
        }
        _loadSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasLensa = _previewSaleItems.any((item) =>
        item['tipe_produk'].toString().toLowerCase().contains('lensa') ||
        item['nama_produk'].toString().toLowerCase().contains('lensa') ||
        item['nama_produk'].toString().toLowerCase().contains('progresif'));

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("INVOICE DESIGN ADJUSTER (MULTI-BRANCH)",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Row(
        children: [
          // PANEL KONTROL KIRI
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("🛠️ Pilih Cabang & Atur Layout",
                      style: TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          dropdownColor: const Color(0xFF1E293B),
                          value: _selectedTokoId,
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                          decoration: const InputDecoration(
                              labelText: "Pilih Cabang Terdata",
                              labelStyle:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                          items: _listCabangTerdata.map((String cabang) {
                            return DropdownMenuItem<String>(
                                value: cabang, child: Text(cabang));
                          }).toList(),
                          onChanged: (String? newVal) {
                            if (newVal != null) {
                              setState(() => _selectedTokoId = newVal);
                              _loadSettings();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                          icon: const Icon(Icons.sync_rounded,
                              color: Colors.blueAccent),
                          tooltip: "Scan Ulang Cabang Baru",
                          onPressed: _fetchDaftarCabangTerdata),
                      IconButton(
                          icon: const Icon(Icons.delete_forever_rounded,
                              color: Colors.redAccent),
                          tooltip: "Hapus Setting Cabang Ini",
                          onPressed: _hapusSettingCabang),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white10),
                  if (_isLoading)
                    const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: Colors.blueAccent)))
                  else ...[
                    TextField(
                        controller: _shopNameCtrl,
                        decoration: const InputDecoration(
                            labelText: "Nama Toko / Banner Struk")),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _addressCtrl,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(labelText: "Alamat Cabang")),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                            labelText: "Nomor Telepon Cabang")),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _logoUrlCtrl,
                      decoration: InputDecoration(
                        labelText: "Link URL Logo Optik (PNG)",
                        suffixIcon: IconButton(
                            icon: const Icon(Icons.add_photo_alternate_rounded,
                                color: Colors.orangeAccent),
                            tooltip: "Upload & Crop Logo Baru",
                            onPressed: _pilihDanCropLogo),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text("📐 Tata Letak Tulisan Header",
                        style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Row(
                      children: [
                        Radio<String>(
                            value: 'CENTER',
                            groupValue: _alignment,
                            onChanged: (v) => setState(() => _alignment = v!)),
                        const Text("Rata Tengah",
                            style:
                                TextStyle(color: Colors.white, fontSize: 12)),
                        const SizedBox(width: 20),
                        Radio<String>(
                            value: 'LEFT',
                            groupValue: _alignment,
                            onChanged: (v) => setState(() => _alignment = v!)),
                        const Text("Rata Kiri",
                            style:
                                TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                    const Divider(color: Colors.white10),
                    Text(
                        "🔤 Ukuran Font Judul Header: ${_fontSizeHeader.toInt()} px",
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                    Slider(
                        value: _fontSizeHeader,
                        min: 12,
                        max: 28,
                        divisions: 8,
                        onChanged: (v) => setState(() => _fontSizeHeader = v)),
                    Text("📄 Ukuran Font Isi Item: ${_fontSizeBody.toInt()} px",
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                    Slider(
                        value: _fontSizeBody,
                        min: 9,
                        max: 18,
                        divisions: 9,
                        onChanged: (v) => setState(() => _fontSizeBody = v)),
                    SwitchListTile(
                        title: const Text("Tampilkan QR Code Invoice",
                            style:
                                TextStyle(color: Colors.white, fontSize: 12)),
                        value: _showQr,
                        activeColor: Colors.blueAccent,
                        onChanged: (v) => setState(() => _showQr = v)),
                    TextField(
                        controller: _footerCtrl,
                        maxLines: 5,
                        decoration: const InputDecoration(
                            labelText: "Catatan Kaki (Footer Notice)")),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent),
                        onPressed: _isSaving ? null : _saveSettings,
                        icon: _isSaving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.cloud_upload_rounded),
                        label: const Text("PUBLISH ADJUSTMENT",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ],
              ),
            ),
          ),
          const VerticalDivider(color: Colors.white10, width: 1),

          // ===================================================================
          // 📄 PANEL LIVE PREVIEW KANAN: 100% SECURE ZERO HARDCODED SYSTEM
          // ===================================================================
          Expanded(
            flex: 3,
            child: Container(
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.all(20),
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: 420,
                    height: 594,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6))
                      ],
                    ),
                    child: _previewSale == null
                        ? const Center(
                            child: Text(
                                "Belum ada data transaksi di cabang ini\nuntuk disimulasikan sebagai pratinjau.",
                                style: TextStyle(
                                    color: Colors.black38,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 🏢 1. SECTION HEADER (DYNAMIC DESIGN PREVIEW)
                              _alignment == 'CENTER'
                                  ? SizedBox(
                                      width: double.infinity,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          if (_logoUrlCtrl.text.isNotEmpty)
                                            Positioned(
                                              left: 0,
                                              top: -6.0,
                                              child: Image.network(
                                                  _logoUrlCtrl.text,
                                                  height: 32,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (c, e, s) =>
                                                      const Icon(
                                                          Icons.broken_image,
                                                          color: Colors.grey,
                                                          size: 20)),
                                            ),
                                          SizedBox(
                                            width: double.infinity,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                    _shopNameCtrl.text
                                                        .toUpperCase(),
                                                    style: TextStyle(
                                                        color: const Color(
                                                            0xFF0F172A),
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize:
                                                            _fontSizeHeader - 1,
                                                        letterSpacing: 0.5)),
                                                const SizedBox(height: 6),
                                                Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 60.0),
                                                    child: Text(
                                                        _addressCtrl.text,
                                                        style: const TextStyle(
                                                            color:
                                                                Colors.black54,
                                                            fontSize: 8.5,
                                                            height: 1.35),
                                                        textAlign:
                                                            TextAlign.center)),
                                                const SizedBox(height: 3),
                                                Text("Telp: ${_phoneCtrl.text}",
                                                    style: const TextStyle(
                                                        color: Colors.black87,
                                                        fontSize: 8.5,
                                                        fontWeight:
                                                            FontWeight.w600),
                                                    textAlign:
                                                        TextAlign.center),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        if (_logoUrlCtrl.text.isNotEmpty)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 12.0),
                                              child: Image.network(
                                                  _logoUrlCtrl.text,
                                                  height: 40,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (c, e, s) =>
                                                      const Icon(
                                                          Icons.broken_image,
                                                          color: Colors.grey)))
                                        else
                                          const SizedBox(),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                  _shopNameCtrl.text
                                                      .toUpperCase(),
                                                  style: TextStyle(
                                                      color: const Color(
                                                          0xFF0F172A),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize:
                                                          _fontSizeHeader - 1,
                                                      letterSpacing: 0.5)),
                                              const SizedBox(height: 4),
                                              Text(_addressCtrl.text,
                                                  style: const TextStyle(
                                                      color: Colors.black54,
                                                      fontSize: 9,
                                                      height: 1.35),
                                                  textAlign: TextAlign.end),
                                              const SizedBox(height: 1),
                                              Text("Telp: ${_phoneCtrl.text}",
                                                  style: const TextStyle(
                                                      color: Colors.black87,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                              const SizedBox(height: 8),
                              const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Divider(
                                      color: Colors.black87,
                                      thickness: 1.5,
                                      height: 1),
                                  SizedBox(height: 1.5),
                                  Divider(
                                      color: Colors.black12,
                                      thickness: 0.5,
                                      height: 1),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // 📋 2. DATA PELANGGAN (100% DINAMIS DATABASE)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_previewSale!['no_invoice'] ?? '-',
                                          style: TextStyle(
                                              color: const Color(0xFF0F172A),
                                              fontWeight: FontWeight.bold,
                                              fontSize: (_fontSizeBody - 2)
                                                  .clamp(9.0, 18.0),
                                              letterSpacing: 0.2)),
                                      const SizedBox(height: 1),
                                      Row(
                                        children: [
                                          Text("Kasir: ",
                                              style: TextStyle(
                                                  color: Colors.black38,
                                                  fontSize: (_fontSizeBody - 4)
                                                      .clamp(8.0, 18.0))),
                                          Text(
                                              _previewSale!['nama_kasir'] ??
                                                  'Staff',
                                              style: TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: (_fontSizeBody - 4)
                                                      .clamp(8.0, 18.0),
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text("PELANGGAN",
                                          style: TextStyle(
                                              color: Colors.black38,
                                              fontSize: (_fontSizeBody - 4)
                                                  .clamp(8.0, 18.0),
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.8)),
                                      const SizedBox(height: 1),
                                      Text(
                                          _previewSale!['nama_pelanggan'] ??
                                              '-',
                                          style: TextStyle(
                                              color: const Color(0xFF1E293B),
                                              fontSize: (_fontSizeBody - 2)
                                                  .clamp(9.0, 18.0),
                                              fontWeight: FontWeight.bold)),
                                      Text(_previewSale!['no_wa'] ?? '-',
                                          style: TextStyle(
                                              color: Colors.black54,
                                              fontSize: (_fontSizeBody - 3)
                                                  .clamp(8.0, 18.0))),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: _previewSale![
                                                        'status_pembayaran'] ==
                                                    "DP"
                                                ? Colors.orange.shade50
                                                : Colors.green.shade50,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: _previewSale![
                                                            'status_pembayaran'] ==
                                                        "DP"
                                                    ? Colors.orange.shade300
                                                    : Colors.green.shade300)),
                                        child: Text(
                                            _previewSale![
                                                        'status_pembayaran'] ==
                                                    "DP"
                                                ? "DP (SISA TAGIHAN)"
                                                : "LUNAS",
                                            style: TextStyle(
                                                color: _previewSale![
                                                            'status_pembayaran'] ==
                                                        "DP"
                                                    ? Colors.orange.shade900
                                                    : Colors.green.shade900,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 8,
                                                letterSpacing: 0.3)),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text("Masuk: ",
                                              style: TextStyle(
                                                  color: Colors.black38,
                                                  fontSize: (_fontSizeBody - 4)
                                                      .clamp(8.0, 18.0))),
                                          Text(
                                              _previewSale!['created_at']
                                                  .toString()
                                                  .split('T')[0],
                                              style: TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: (_fontSizeBody - 4)
                                                      .clamp(8.0, 18.0))),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Text("Metode: ",
                                              style: TextStyle(
                                                  color: Colors.black38,
                                                  fontSize: (_fontSizeBody - 4)
                                                      .clamp(8.0, 18.0))),
                                          Text(
                                              _previewSale![
                                                      'metode_pembayaran'] ??
                                                  'Tunai',
                                              style: TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: (_fontSizeBody - 4)
                                                      .clamp(8.0, 18.0))),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Divider(color: Colors.black12, height: 1),
                              const SizedBox(height: 6),

                              // 👓 3. SECTION RINCIAN BELANJA ITEM (DINAMIS SINKRON)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("RINCIAN ITEM",
                                      style: TextStyle(
                                          color: Colors.black38,
                                          fontSize: (_fontSizeBody - 4)
                                              .clamp(8.0, 18.0),
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8)),
                                  const SizedBox(height: 4),
                                  ..._previewSaleItems.map((item) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2.0),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                                child: Text(
                                                    "• ${item['nama_produk']} (x${item['qty']})",
                                                    style: TextStyle(
                                                        color: const Color(
                                                            0xFF1E293B),
                                                        fontSize:
                                                            (_fontSizeBody - 1)
                                                                .clamp(
                                                                    9.0, 18.0),
                                                        fontWeight:
                                                            FontWeight.w500))),
                                            const SizedBox(width: 15),
                                            Text(
                                                _formatRupiah(item['subtotal']),
                                                style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize:
                                                        (_fontSizeBody - 1)
                                                            .clamp(9.0, 18.0),
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      )),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // 👁️ 4. SECTION HASIL REFRAKSI MEDIS (SINKRON DATA RIIL SUPABASE)
                              if (hasLensa) ...[
                                Container(
                                  decoration: BoxDecoration(
                                      border: Border.all(color: Colors.black26),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Table(
                                    border:
                                        TableBorder.all(color: Colors.black12),
                                    columnWidths: const {
                                      0: FlexColumnWidth(1.8),
                                      1: FlexColumnWidth(2),
                                      2: FlexColumnWidth(2),
                                      3: FlexColumnWidth(2),
                                      4: FlexColumnWidth(2),
                                    },
                                    children: [
                                      TableRow(
                                        decoration: const BoxDecoration(
                                            color: Color(0xFFF8FAFC)),
                                        children: [
                                          'OD/OS',
                                          'SPH',
                                          'CYL',
                                          'AXIS',
                                          'ADD'
                                        ]
                                            .map((txt) => Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 3),
                                                  child: Text(txt,
                                                      style: const TextStyle(
                                                          fontSize: 8,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.black45,
                                                          letterSpacing: 0.2),
                                                      textAlign:
                                                          TextAlign.center),
                                                ))
                                            .toList(),
                                      ),
                                      TableRow(
                                        children: [
                                          'OD (Kanan)',
                                          _parseResepDariDatabase('OD', 'SPH'),
                                          _parseResepDariDatabase('OD', 'CYL'),
                                          _parseResepDariDatabase('OD', 'AXIS')
                                                  .endsWith('°')
                                              ? _parseResepDariDatabase(
                                                  'OD', 'AXIS')
                                              : "${_parseResepDariDatabase('OD', 'AXIS')}°",
                                          _parseResepDariDatabase('OD', 'ADD'),
                                        ]
                                            .map((txt) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 3),
                                                child: Text(txt,
                                                    style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.black87,
                                                        fontWeight:
                                                            FontWeight.w500),
                                                    textAlign:
                                                        TextAlign.center)))
                                            .toList(),
                                      ),
                                      TableRow(
                                        children: [
                                          'OS (Kiri)',
                                          _parseResepDariDatabase('OS', 'SPH'),
                                          _parseResepDariDatabase('OS', 'CYL'),
                                          _parseResepDariDatabase('OS', 'AXIS')
                                                  .endsWith('°')
                                              ? _parseResepDariDatabase(
                                                  'OS', 'AXIS')
                                              : "${_parseResepDariDatabase('OS', 'AXIS')}°",
                                          _parseResepDariDatabase('OS', 'ADD'),
                                        ]
                                            .map((txt) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 3),
                                                child: Text(txt,
                                                    style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.black87,
                                                        fontWeight:
                                                            FontWeight.w500),
                                                    textAlign:
                                                        TextAlign.center)))
                                            .toList(),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 4, left: 4),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        "PD Pasien (R/L): ${_parseResepDariDatabase('', 'PD')}",
                                        style: TextStyle(
                                            color: Colors.black87,
                                            fontSize: (_fontSizeBody - 3)
                                                .clamp(8.0, 14.0),
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.1)),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              const Divider(
                                  color: Colors.black87, thickness: 1),

                              // 💰 5. SECTION KALKULASI FINANSIAL
                              Expanded(
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ✅ PERBAIKAN 3: Proteksi null-safety global mutlak pada widget summary keuangan bawah
                                    _showQr
                                        ? const Padding(
                                            padding: EdgeInsets.only(top: 4.0),
                                            child: Icon(Icons.qr_code_2,
                                                color: Colors.black87,
                                                size: 46))
                                        : const SizedBox(),
                                    SizedBox(
                                      width: 210,
                                      child: Table(
                                        columnWidths: const {
                                          0: FlexColumnWidth(1.4),
                                          1: FlexColumnWidth(1.2)
                                        },
                                        children: [
                                          TableRow(
                                            children: [
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 1.5),
                                                  child: Text("TOTAL BELANJA",
                                                      style: TextStyle(
                                                          color: Colors.black54,
                                                          fontSize:
                                                              (_fontSizeBody -
                                                                      2)
                                                                  .clamp(9.0,
                                                                      18.0),
                                                          fontWeight: FontWeight
                                                              .w500))),
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 1.5),
                                                  child: Text(
                                                      _formatRupiah(_previewSale?[
                                                              'total_harga'] ??
                                                          0),
                                                      style: TextStyle(
                                                          color: Colors.black,
                                                          fontSize:
                                                              (_fontSizeBody -
                                                                      2)
                                                                  .clamp(9.0,
                                                                      18.0),
                                                          fontWeight:
                                                              FontWeight.bold),
                                                      textAlign:
                                                          TextAlign.end)),
                                            ],
                                          ),
                                          TableRow(
                                            children: [
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 1.5),
                                                  child: Text("UANG MUKA (DP)",
                                                      style: TextStyle(
                                                          color: Colors.black38,
                                                          fontSize:
                                                              (_fontSizeBody -
                                                                      3)
                                                                  .clamp(8.0,
                                                                      18.0)))),
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 1.5),
                                                  child: Text(
                                                      _formatRupiah(_previewSale?[
                                                              'dibayarkan'] ??
                                                          0),
                                                      style: TextStyle(
                                                          color: Colors.black45,
                                                          fontSize:
                                                              (_fontSizeBody -
                                                                      3)
                                                                  .clamp(8.0,
                                                                      18.0)),
                                                      textAlign:
                                                          TextAlign.end)),
                                            ],
                                          ),
                                          TableRow(
                                            children: [
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 3.0),
                                                  child: Text("SISA TAGIHAN",
                                                      style: TextStyle(
                                                          color: const Color(
                                                              0xFF0F172A),
                                                          fontSize:
                                                              (_fontSizeBody -
                                                                      1)
                                                                  .clamp(9.0,
                                                                      18.0),
                                                          fontWeight: FontWeight
                                                              .bold))),
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          vertical: 3.0),
                                                  child: Text(
                                                      _formatRupiah(
                                                          _previewSale?['sisa_tagihan'] ??
                                                              0),
                                                      style: TextStyle(
                                                          color: (_previewSale?['sisa_tagihan'] ?? 0) >
                                                                  0
                                                              ? Colors
                                                                  .red.shade700
                                                              : Colors.green
                                                                  .shade700,
                                                          fontSize:
                                                              (_fontSizeBody - 1)
                                                                  .clamp(9.0, 18.0),
                                                          fontWeight: FontWeight.bold),
                                                      textAlign: TextAlign.end)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(color: Colors.black26),
                              const SizedBox(height: 3),

                              // 🎯 6. SECTION DYNAMIC FOOTER NOTICE
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(_footerCtrl.text,
                                    style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 8.5,
                                        height: 1.35,
                                        letterSpacing: 0.1),
                                    textAlign: TextAlign.left),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
