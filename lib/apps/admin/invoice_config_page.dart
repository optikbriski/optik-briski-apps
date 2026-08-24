// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data'; // Untuk konversi data binary Uint8List gambar hasil crop
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/invoice/invoice_layout.dart';
import '../../shared/invoice/invoice_lifecycle_rules.dart';
import '../../shared/invoice/invoice_settings_service.dart';
import '../../shared/invoice/invoice_status_footer.dart';
import '../../shared/qr/hid_scan_intake.dart';
import '../../shared/responsive.dart';
import '../../shared/widgets/leave_page_guard.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

class InvoiceConfigPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const InvoiceConfigPage({super.key, required this.profile});

  @override
  State<InvoiceConfigPage> createState() => _InvoiceConfigPageState();
}

class _InvoiceConfigPageState extends State<InvoiceConfigPage> {
  final _supabase = Supabase.instance.client;
  final _settingsSvc = InvoiceSettingsService();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _uploadingLogo = false;
  bool _leaving = false;
  String? _baselineSnapshot;

  String _selectedTokoId = 'PUSAT';
  List<String> _listCabangTerdata = ['PUSAT'];

  // Form Controllers - Konfigurasi Layout & Teks Statis Struk
  final _shopNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();
  final _googleReviewUrlCtrl = TextEditingController();
  final _footerEditCtrl = TextEditingController();
  InvoiceStatusFooters _statusFooters = InvoiceStatusFooters.defaults();
  InvoiceFooterStatus _editFooterStatus = InvoiceFooterStatus.dp;

  // Variabel Pengaturan Desain Utama
  String _alignment = 'CENTER';
  double _fontSizeHeader = 16;
  double _fontSizeBody = 12;
  bool _showQr = true;

  @override
  void initState() {
    super.initState();
    _eksekusiProteksiAkses();
  }

  void _eksekusiProteksiAkses() {
    final role = widget.profile['role']?.toString().toLowerCase() ?? '';
    if (role != 'owner' && role != 'admin_pusat') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Akses ditolak. Hanya Owner & Admin Pusat yang dapat mengatur layout invoice.'),
          backgroundColor: OptikAdminTokens.danger,
        ));
        Navigator.pop(context);
      });
      return;
    }
    _fetchDaftarCabangTerdata();
  }

  bool get _isPusatSelected =>
      InvoiceSettingsService.normalizeTokoId(_selectedTokoId) == 'PUSAT';

  InvoiceStatusFooters _footersFromForm() {
    return _statusFooters.withStatus(
      _editFooterStatus,
      _footerEditCtrl.text,
    );
  }

  InvoiceSettings _settingsFromForm() {
    var footers = _footersFromForm();
    if (_isPusatSelected) {
      footers = footers.copyWith(inheritFromPusat: false);
    }
    return InvoiceSettings(
      tokoId: InvoiceSettingsService.normalizeTokoId(_selectedTokoId),
      shopName: _shopNameCtrl.text.trim().isEmpty
          ? InvoiceSettingsService.defaultShopName(_selectedTokoId)
          : _shopNameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? '-' : _phoneCtrl.text.trim(),
      logoUrl: _logoUrlCtrl.text.trim(),
      statusFooters: footers,
      googleReviewUrl: _googleReviewUrlCtrl.text.trim(),
      headerAlignment: _alignment,
      fontSizeHeader: _fontSizeHeader,
      fontSizeBody: _fontSizeBody,
      showQrInvoice: _showQr,
    );
  }

  void _applySettingsToForm(InvoiceSettings s) {
    _shopNameCtrl.text = s.shopName;
    _addressCtrl.text = s.address;
    _phoneCtrl.text = s.phone == '-' ? '' : s.phone;
    _logoUrlCtrl.text = s.logoUrl;
    _statusFooters = s.statusFooters;
    _editFooterStatus = InvoiceFooterStatus.dp;
    _footerEditCtrl.text = _statusFooters.of(_editFooterStatus);
    _googleReviewUrlCtrl.text = s.googleReviewUrl;
    _alignment = s.isCenter ? 'CENTER' : 'LEFT';
    _fontSizeHeader = s.fontSizeHeader;
    _fontSizeBody = s.fontSizeBody;
    _showQr = s.showQrInvoice;
  }

  void _selectFooterStatus(InvoiceFooterStatus status) {
    if (status == _editFooterStatus) return;
    setState(() {
      _statusFooters = _footersFromForm();
      _editFooterStatus = status;
      _footerEditCtrl.text = _statusFooters.of(status);
    });
  }

  void _onFooterTextEdited(String _) {
    setState(() {
      // Edit di cabang = lepas dari sync Pusat.
      _statusFooters = _footersFromForm().customized();
    });
  }

  void _resetFooterStatusDefault() {
    final def = InvoiceStatusFooters.defaults().of(_editFooterStatus);
    setState(() {
      _footerEditCtrl.text = def;
      _statusFooters =
          _statusFooters.withStatus(_editFooterStatus, def).customized();
    });
  }

  Future<void> _samakanFooterDenganPusat() async {
    if (_isPusatSelected) return;
    try {
      final pusat = await _settingsSvc.fetchForToko('PUSAT');
      if (!mounted) return;
      setState(() {
        _statusFooters =
            InvoiceStatusFooters.inheritedFrom(pusat.statusFooters);
        _footerEditCtrl.text = _statusFooters.of(_editFooterStatus);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal ambil footer Pusat: $e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _logoUrlCtrl.dispose();
    _googleReviewUrlCtrl.dispose();
    _footerEditCtrl.dispose();
    super.dispose();
  }

  // Formatter mandiri mengubah angka biner menjadi teks Rupiah lokal
  String _formatRupiah(dynamic angka) {
    if (angka == null) return 'Rp0';
    int value = InvoiceLifecycleRules.moneyOf(angka);
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String hasil =
        value.toString().replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return "Rp$hasil";
  }

  /// Selalu pakai contoh penuh (frame + lensa + lainnya + resep).
  List<Map<String, dynamic>> get _effectivePreviewItems =>
      _samplePreviewData().items;

  bool get _effectiveHasLensa => _effectivePreviewItems.any((item) {
        final tipe = item['tipe_produk'].toString().toLowerCase();
        final nama = item['nama_produk'].toString().toLowerCase();
        return tipe.contains('lensa') ||
            nama.contains('lensa') ||
            nama.contains('progresif');
      });

  String _parseResepDariDatabase(String eye, String param) {
    final items = _effectivePreviewItems;
    if (items.isEmpty) return '0.00';

    final lensaItem = items.firstWhere(
      (e) =>
          e['detail_resep'] != null &&
          e['detail_resep'] != 'Normal' &&
          e['detail_resep'].toString().contains('|'),
      orElse: () => <String, dynamic>{},
    );

    if (lensaItem.isEmpty) return param == 'PD' ? '-' : '0.00';
    final resepStr = lensaItem['detail_resep']?.toString() ?? '';

    try {
      final parts = resepStr.split('|');
      if (param == 'PD') {
        if (resepStr.contains('PD Pasien:')) {
          return resepStr.split('PD Pasien:')[1].trim();
        }
        return '-';
      }
      // Format simpan: "R: SPH … | L: SPH … | PD Pasien: …"
      final sideStr = (eye == 'OD' || eye == 'R')
          ? parts[0]
          : (parts.length > 1 ? parts[1] : '');
      final match = RegExp('$param\\s+([^/|\\s°]+)').firstMatch(sideStr);
      return match?.group(1) ?? '0.00';
    } catch (_) {
      return '0.00';
    }
  }

  Future<void> _fetchDaftarCabangTerdata() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final cabang = await _settingsSvc.listCabang();
      if (!mounted) return;
      setState(() {
        _listCabangTerdata = cabang;
        _selectedTokoId =
            InvoiceSettingsService.normalizeTokoId(_selectedTokoId);
        if (!_listCabangTerdata.contains(_selectedTokoId)) {
          _selectedTokoId = _listCabangTerdata.first;
        }
      });
      await _loadSettings();
    } catch (e) {
      debugPrint('Gagal memuat daftar cabang: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final toko = InvoiceSettingsService.normalizeTokoId(_selectedTokoId);
      // fetchForToko sudah resolve footer inherit → teks Pusat untuk cabang baru/awal.
      final settings = await _settingsSvc.fetchForToko(toko);
      if (!mounted) return;
      setState(() {
        _selectedTokoId = toko;
        _applySettingsToForm(settings);
        _baselineSnapshot = _formSnapshot();
      });
    } catch (e) {
      debugPrint('Gagal memuat konfigurasi invoice: $e');
    }
  }

  String _formSnapshot() {
    return [
      _selectedTokoId,
      _shopNameCtrl.text,
      _addressCtrl.text,
      _phoneCtrl.text,
      _logoUrlCtrl.text,
      _footersFromForm().encode(),
      _googleReviewUrlCtrl.text,
      _alignment,
      _fontSizeHeader.toString(),
      _fontSizeBody.toString(),
      _showQr.toString(),
    ].join('|');
  }

  bool get _hasEdits =>
      _baselineSnapshot != null && _formSnapshot() != _baselineSnapshot;

  Future<void> _pickCabang() async {
    if (_listCabangTerdata.isEmpty) return;
    if (_hasEdits) {
      final ok = await LeavePageGuard.handlePop(
        context,
        hasEdits: true,
        onSave: _saveSettings,
      );
      if (!ok || !mounted) return;
    }

    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih cabang',
      subtitle: 'Layout invoice per cabang',
      headerIcon: Icons.storefront_rounded,
      searchHint: 'Cari kode cabang…',
      selected: _selectedTokoId,
      options: [
        for (final cabang in _listCabangTerdata)
          AdminPickerOption(
            value: cabang,
            label: cabang,
            subtitle: cabang == 'PUSAT' ? 'Pusat (master)' : 'Cabang',
            icon: cabang == 'PUSAT'
                ? Icons.apartment_rounded
                : Icons.storefront_rounded,
          ),
      ],
    );
    if (!mounted || sel == null || sel.isClear) return;
    final next = InvoiceSettingsService.normalizeTokoId(sel.value);
    if (next == _selectedTokoId) return;
    setState(() {
      _isLoading = true;
      _selectedTokoId = next;
    });
    await _loadSettings();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _requestLeaveInvoiceConfig() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final ok = await LeavePageGuard.handlePop(
        context,
        hasEdits: _hasEdits,
        onSave: _saveSettings,
      );
      // ok=false → user batal ATAU simpan gagal: tetap di halaman.
      if (ok && mounted) Navigator.of(context).pop();
    } finally {
      _leaving = false;
    }
  }

  /// Return `true` hanya jika semua field benar-benar tersimpan di DB.
  Future<bool> _saveSettings() async {
    if (_selectedTokoId.isEmpty) return false;

    setState(() => _isSaving = true);
    try {
      final saved = await _settingsSvc.save(_settingsFromForm());
      if (!mounted) return false;
      // Terapkan ulang dari DB — bukti semua kolom (logo, font, QR, footer, dll) kesimpan.
      setState(() {
        _applySettingsToForm(saved);
        _baselineSnapshot = _formSnapshot();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Layout invoice ${saved.tokoId} tersimpan lengkap. POS, PDF, dan Hub memakai setting ini.'),
        backgroundColor: OptikAdminTokens.success,
      ));
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: OptikAdminTokens.danger));
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _hapusSettingCabang() async {
    final toko = InvoiceSettingsService.normalizeTokoId(_selectedTokoId);
    if (toko == 'PUSAT') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Setting PUSAT tidak boleh dihapus.'),
          backgroundColor: OptikAdminTokens.warning));
      return;
    }

    final confirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: OptikAdminTokens.card,
            title: Text('Hapus layout $toko?',
                style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            content: Text(
                'Layout kustom $toko dihapus. Cetak akan memakai fallback PUSAT / default.',
                style: const TextStyle(
                    color: OptikAdminTokens.textSecondary, fontSize: 12)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Batal',
                      style: TextStyle(color: OptikAdminTokens.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: OptikAdminTokens.danger),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Hapus',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ) ??
        false;

    if (!confirm) return;
    try {
      await _settingsSvc.deleteCabang(toko);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Layout $toko dihapus.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      await _loadSettings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menghapus: $e'),
          backgroundColor: OptikAdminTokens.danger));
    }
  }

  Future<void> _pilihDanCropLogo() async {
    if (_uploadingLogo) return;
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 92,
    );

    if (image == null) return;
    final Uint8List imageBytes = await image.readAsBytes();

    if (!mounted) return;
    final cropController = CropController();
    var popped = false;
    // interactive:true otomatis scaleToCover (nge-zoom). Blokir sekali di awal,
    // setelah ready user boleh pinch/scroll zoom + geser frame bebas.
    var userZoomUnlocked = false;

    void safePop(BuildContext ctx, Uint8List? value) {
      if (popped) return;
      popped = true;
      Navigator.of(ctx, rootNavigator: true).pop(value);
    }

    final Uint8List? croppedData = await showDialog<Uint8List?>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (ctx) => R.constrainedDialog(
        context: ctx,
        preferWidth: 480,
        child: AlertDialog(
          backgroundColor: OptikAdminTokens.card,
          title: const Text(
            'Crop logo cabang',
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            height: 380,
            child: Crop(
              image: imageBytes,
              controller: cropController,
              interactive: true,
              scrollZoomSensitivity: 0.06,
              willUpdateScale: (nextScale) {
                if (!userZoomUnlocked) {
                  // Tolak auto cover-zoom saat buka dialog.
                  return nextScale <= 1.001;
                }
                return nextScale >= 1.0 && nextScale <= 5.0;
              },
              onStatusChanged: (status) {
                if (status == CropStatus.ready && !userZoomUnlocked) {
                  Future.microtask(() => userZoomUnlocked = true);
                }
              },
              initialRectBuilder: InitialRectBuilder.withBuilder(
                (viewportRect, imageRect) {
                  const pad = 8.0;
                  return Rect.fromLTRB(
                    imageRect.left + pad,
                    imageRect.top + pad,
                    imageRect.right - pad,
                    imageRect.bottom - pad,
                  );
                },
              ),
              baseColor: const Color(0xFFE8EEF5),
              maskColor: Colors.black.withOpacity(0.45),
              onCropped: (result) {
                if (result is CropSuccess) {
                  safePop(ctx, result.croppedImage);
                } else {
                  safePop(ctx, null);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => safePop(ctx, null),
              child: const Text(
                'Batal',
                style: TextStyle(color: OptikAdminTokens.textMuted),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: OptikAdminTokens.accent),
              icon: const Icon(Icons.crop_rounded),
              label: const Text(
                'Potong & upload',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => cropController.crop(),
            ),
          ],
        ),
      ),
    );

    if (croppedData == null || !mounted) return;

    setState(() => _uploadingLogo = true);
    try {
      final toko =
          InvoiceSettingsService.normalizeTokoId(_selectedTokoId).toLowerCase();
      final namaFile =
          'logo_${toko}_${DateTime.now().millisecondsSinceEpoch}.png';

      await _supabase.storage.from('LOGO').uploadBinary(
            namaFile,
            croppedData,
            fileOptions:
                const FileOptions(upsert: true, contentType: 'image/png'),
          );

      final publicUrl = _supabase.storage.from('LOGO').getPublicUrl(namaFile);

      if (!mounted) return;
      setState(() {
        _logoUrlCtrl.text = publicUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Logo diunggah. Simpan layout agar dipakai di POS/PDF.'),
        backgroundColor: OptikAdminTokens.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal mengunggah logo: $e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Map<String, dynamic> _saleForFooterPreview(Map<String, dynamic> base) {
    final sale = Map<String, dynamic>.from(base);
    final total = (sale['total_harga'] as num?)?.toInt() ?? 1485000;
    switch (_editFooterStatus) {
      case InvoiceFooterStatus.dp:
        sale['status_pembayaran'] = 'DP';
        sale['sisa_tagihan'] = 500000;
        sale['dibayarkan'] = (total - 500000).clamp(0, total);
        sale['tracking_status'] = 'PENDING_PO';
        sale.remove('diambil_at');
      case InvoiceFooterStatus.pending:
        sale['status_pembayaran'] = 'LUNAS';
        sale['sisa_tagihan'] = 0;
        sale['dibayarkan'] = total;
        sale['tracking_status'] = 'DIPROSES_DI_CABANG';
        sale.remove('diambil_at');
      case InvoiceFooterStatus.ready:
        sale['status_pembayaran'] = 'LUNAS';
        sale['sisa_tagihan'] = 0;
        sale['dibayarkan'] = total;
        sale['tracking_status'] = 'SIAP_DIAMBIL';
        sale.remove('diambil_at');
      case InvoiceFooterStatus.clear:
        sale['status_pembayaran'] = 'LUNAS';
        sale['sisa_tagihan'] = 0;
        sale['dibayarkan'] = total;
        sale['tracking_status'] = 'DIAMBIL';
        sale['diambil_at'] = DateTime.now().toIso8601String();
    }
    return sale;
  }

  Widget _statusFooterEditor() {
    const labels = <InvoiceFooterStatus, String>{
      InvoiceFooterStatus.dp: 'DP',
      InvoiceFooterStatus.pending: 'PENDING',
      InvoiceFooterStatus.ready: 'READY',
      InvoiceFooterStatus.clear: 'CLEAR',
    };
    final inherit = !_isPusatSelected && _statusFooters.inheritFromPusat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Footer per status invoice',
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _isPusatSelected
              ? 'Pilih status, lalu ubah teks footer master Pusat. Cabang baru mengikuti teks ini sampai di-adjust sendiri.'
              : 'Awalnya footer cabang sama dengan Pusat. Boleh diubah kapan saja; setelah diubah, cabang pakai teks sendiri.',
          style: TextStyle(
            color: OptikAdminTokens.slate.withOpacity(0.95),
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (!_isPusatSelected) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: inherit
                  ? OptikAdminTokens.ice.withOpacity(0.28)
                  : OptikAdminTokens.bgMid,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: OptikAdminTokens.line),
            ),
            child: Text(
              inherit
                  ? 'Status: mengikuti footer Pusat (sync otomatis).'
                  : 'Status: footer kustom cabang (tidak ikut perubahan Pusat).',
              style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final status in InvoiceFooterStatus.values)
              ChoiceChip(
                label: Text(
                  labels[status]!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                selected: _editFooterStatus == status,
                onSelected: (_) => _selectFooterStatus(status),
                selectedColor: OptikAdminTokens.ice.withOpacity(0.45),
                labelStyle: TextStyle(
                  color: _editFooterStatus == status
                      ? OptikAdminTokens.navy
                      : OptikAdminTokens.slate,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _footerEditCtrl,
          maxLines: 6,
          onChanged: _onFooterTextEdited,
          decoration: InputDecoration(
            labelText: 'Teks footer ${labels[_editFooterStatus]}',
            alignLabelWithHint: true,
            helperText: inherit
                ? 'Mengedit teks ini membuat footer cabang lepas dari Pusat.'
                : 'Hanya berlaku untuk invoice berstatus ${labels[_editFooterStatus]}.',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.end,
          children: [
            if (!_isPusatSelected)
              TextButton.icon(
                onPressed: _samakanFooterDenganPusat,
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('Samakan dengan Pusat'),
                style: TextButton.styleFrom(
                  foregroundColor: OptikAdminTokens.navy,
                ),
              ),
            TextButton.icon(
              onPressed: _resetFooterStatusDefault,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset default status ini'),
              style: TextButton.styleFrom(
                foregroundColor: OptikAdminTokens.slate,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Data contoh — frame + lensa + aksesoris + resep agar layout penuh.
  ({Map<String, dynamic> sale, List<Map<String, dynamic>> items})
      _samplePreviewData() {
    final now = DateTime.now();
    final date = now.toIso8601String();
    const resep =
        'R: SPH -1.25/CYL -0.50/AXIS 90/ADD +1.00 | '
        'L: SPH -1.00/CYL -0.25/AXIS 85/ADD +1.00 | '
        'PD Pasien: 32/32 mm';
    return (
      sale: <String, dynamic>{
        'no_invoice':
            'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-DEMO',
        'nama_pelanggan': 'Contoh Pelanggan',
        'no_wa': '081234567890',
        'alamat': 'Jl. Contoh No. 12, Cimahi',
        'email_pelanggan': 'contoh@email.com',
        'nama_kasir': 'Kasir Demo',
        'created_at': date,
        'metode_pembayaran': 'Tunai',
        'status_pembayaran': 'LUNAS',
        'tracking_status': 'DIPROSES_DI_CABANG',
        'total_harga': 1485000,
        'dibayarkan': 1485000,
        'sisa_tagihan': 0,
      },
      items: <Map<String, dynamic>>[
        {
          'nama_produk': 'Frame: Prime - Downey, Acetate, Hitam',
          'qty': 1,
          'subtotal': 450000,
          'tipe_produk': 'Frame',
          'kategori': 'Frame',
        },
        {
          'nama_produk': 'Lensa (R): New Vision, Progresif, Bluecoat',
          'qty': 1,
          'subtotal': 350000,
          'tipe_produk': 'Lensa',
          'kategori': 'Lensa',
          'detail_resep': resep,
        },
        {
          'nama_produk': 'Lensa (L): New Vision, Progresif, Bluecoat',
          'qty': 1,
          'subtotal': 350000,
          'tipe_produk': 'Lensa',
          'kategori': 'Lensa',
          'detail_resep': resep,
        },
        {
          'nama_produk': 'Hardcase Premium',
          'qty': 1,
          'subtotal': 75000,
          'tipe_produk': 'Lainnya',
          'kategori': 'Lainnya',
        },
        {
          'nama_produk': 'Softlens Daily (box)',
          'qty': 1,
          'subtotal': 180000,
          'tipe_produk': 'Lainnya',
          'kategori': 'Lainnya',
        },
        {
          'nama_produk': 'Cairan Softlens 120ml',
          'qty': 1,
          'subtotal': 45000,
          'tipe_produk': 'Lainnya',
          'kategori': 'Lainnya',
        },
        {
          'nama_produk': 'Kain Microfiber',
          'qty': 1,
          'subtotal': 35000,
          'tipe_produk': 'Lainnya',
          'kategori': 'Lainnya',
        },
      ],
    );
  }

  Widget _previewLensTable() {
    String axis(String eye) {
      final a = _parseResepDariDatabase(eye, 'AXIS');
      return a.endsWith('°') ? a : '$a°';
    }

    Widget cell(String txt, {bool header = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            txt,
            style: TextStyle(
              fontSize: header ? 8 : 9,
              fontWeight: header ? FontWeight.bold : FontWeight.w500,
              color: OptikAdminTokens.navy,
            ),
            textAlign: TextAlign.center,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: OptikAdminTokens.lineStrong),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            border: TableBorder.all(color: OptikAdminTokens.line),
            columnWidths: const {
              0: FlexColumnWidth(1.8),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
              4: FlexColumnWidth(2),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: OptikAdminTokens.bgMid),
                children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                    .map((t) => cell(t, header: true))
                    .toList(),
              ),
              TableRow(
                children: [
                  'OD (Kanan)',
                  _parseResepDariDatabase('OD', 'SPH'),
                  _parseResepDariDatabase('OD', 'CYL'),
                  axis('OD'),
                  _parseResepDariDatabase('OD', 'ADD'),
                ].map(cell).toList(),
              ),
              TableRow(
                children: [
                  'OS (Kiri)',
                  _parseResepDariDatabase('OS', 'SPH'),
                  _parseResepDariDatabase('OS', 'CYL'),
                  axis('OS'),
                  _parseResepDariDatabase('OS', 'ADD'),
                ].map(cell).toList(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
            'PD Pasien (R/L): ${_parseResepDariDatabase('', 'PD')}',
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontSize: (_fontSizeBody - 3).clamp(8.0, 14.0),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return HidScanIntake(
      isDirty: () => _hasEdits,
      onSaveBeforeLeave: _saveSettings,
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _requestLeaveInvoiceConfig();
      },
      child: PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Adjust Invoice',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _requestLeaveInvoiceConfig,
        ),
        automaticallyImplyLeading: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 720;
          final panels = <Widget>[
          // PANEL KONTROL KIRI
          Expanded(
            flex: narrow ? 1 : 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pilih cabang & atur layout',
                      style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(height: 6),
                  const Text(
                    'Setting ini dipakai POS, PDF, detail nota, dan Hub — tanpa jalur terpisah.',
                    style: TextStyle(
                        color: OptikAdminTokens.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: AdminPickerField(
                          label: 'Cabang',
                          valueText: _selectedTokoId,
                          icon: Icons.storefront_rounded,
                          badgeColor: OptikAdminTokens.warning,
                          onTap: _pickCabang,
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                          icon: const Icon(Icons.sync_rounded,
                              color: OptikAdminTokens.navy),
                          tooltip: 'Muat ulang daftar cabang',
                          onPressed: _fetchDaftarCabangTerdata),
                      IconButton(
                          icon: const Icon(Icons.delete_forever_rounded,
                              color: OptikAdminTokens.danger),
                          tooltip: 'Hapus setting cabang ini',
                          onPressed: _hapusSettingCabang),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: OptikAdminTokens.line),
                  if (_isLoading)
                    const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Center(
                            child: CircularProgressIndicator(color: OptikAdminTokens.ice)))
                  else ...[
                    TextField(
                        controller: _shopNameCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            labelText: 'Nama toko / banner struk')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _addressCtrl,
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                        decoration:
                            const InputDecoration(labelText: 'Alamat cabang')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _phoneCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            labelText: 'Nomor telepon cabang')),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _logoUrlCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'URL logo (PNG)',
                        suffixIcon: _uploadingLogo
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: OptikAdminTokens.ice,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    color: OptikAdminTokens.warning),
                                tooltip: 'Upload & crop logo',
                                onPressed: _pilihDanCropLogo,
                              ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text('Tata letak header',
                        style: TextStyle(
                            color: OptikAdminTokens.textMuted, fontSize: 11)),
                    Row(
                      children: [
                        Radio<String>(
                            value: 'CENTER',
                            groupValue: _alignment,
                            onChanged: (v) => setState(() => _alignment = v!)),
                        const Text('Rata tengah',
                            style: TextStyle(
                                color: OptikAdminTokens.navy, fontSize: 12)),
                        const SizedBox(width: 20),
                        Radio<String>(
                            value: 'LEFT',
                            groupValue: _alignment,
                            onChanged: (v) => setState(() => _alignment = v!)),
                        const Text('Rata kiri',
                            style: TextStyle(
                                color: OptikAdminTokens.navy, fontSize: 12)),
                      ],
                    ),
                    const Divider(color: OptikAdminTokens.line),
                    Text(
                        'Ukuran font judul: ${_fontSizeHeader.toInt()} px',
                        style: const TextStyle(
                            color: OptikAdminTokens.navy, fontSize: 12)),
                    Slider(
                        value: _fontSizeHeader,
                        min: 12,
                        max: 28,
                        divisions: 8,
                        onChanged: (v) => setState(() => _fontSizeHeader = v)),
                    Text('Ukuran font isi: ${_fontSizeBody.toInt()} px',
                        style: const TextStyle(
                            color: OptikAdminTokens.navy, fontSize: 12)),
                    Slider(
                        value: _fontSizeBody,
                        min: 9,
                        max: 18,
                        divisions: 9,
                        onChanged: (v) => setState(() => _fontSizeBody = v)),
                    SwitchListTile(
                        title: const Text('Tampilkan QR code invoice',
                            style: TextStyle(
                                color: OptikAdminTokens.navy, fontSize: 12)),
                        value: _showQr,
                        activeColor: OptikAdminTokens.navy,
                        onChanged: (v) => setState(() => _showQr = v)),
                    TextField(
                      controller: _googleReviewUrlCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'URL Google Review (Maps / g.page)',
                        helperText:
                            'Tombol review di Hub QR invoice. Kosongkan jika belum ada.',
                        helperMaxLines: 2,
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 10),
                    _statusFooterEditor(),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveSettings,
                        icon: _isSaving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: OptikAdminTokens.navy,
                                    strokeWidth: 2))
                            : const Icon(Icons.save_rounded),
                        label: const Text(
                          'Simpan layout',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  ],
                ],
              ),
            ),
          ),
          narrow
              ? const Divider(color: OptikAdminTokens.line, height: 1)
              : const VerticalDivider(color: OptikAdminTokens.line, width: 1),

          // ===================================================================
          // 📄 PANEL LIVE PREVIEW KANAN: 100% SECURE ZERO HARDCODED SYSTEM
          // ===================================================================
          Expanded(
            flex: narrow ? 1 : 3,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Center(
                child: LayoutBuilder(
                  builder: (context, previewConstraints) {
                    final previewW =
                        (previewConstraints.maxWidth - 8).clamp(280.0, 420.0);
                    final settings = _settingsFromForm();
                    // Selalu contoh penuh — jangan pakai transaksi asli (bisa cuma frame).
                    final sample = _samplePreviewData();
                    final sale = _saleForFooterPreview(
                      Map<String, dynamic>.from(sample.sale),
                    );
                    final items = sample.items;
                    final sisa =
                        (sale['sisa_tagihan'] as num?)?.toInt() ?? 0;
                    final isDp =
                        sale['status_pembayaran']?.toString() == 'DP' ||
                            sisa > 0;
                    final showLens = _effectiveHasLensa;
                    final footerPreview = InvoiceStatusFooter.forSale(
                      sale,
                      footers: settings.statusFooters,
                    );
                    final demoQrPayload =
                        'OBR|DEMO|${sale['no_invoice']}|preview';
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Pratinjau contoh lengkap — Frame, Lensa, Lainnya, resep, QR & footer.',
                              style: TextStyle(
                                color: OptikAdminTokens.slate.withOpacity(0.9),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          InvoiceLayout.paper(
                            width: previewW,
                            child: InvoiceLayout.documentBody(
                              settings: settings,
                              footerText: footerPreview,
                              meta: InvoiceDocMeta(
                                noInvoice:
                                    sale['no_invoice']?.toString() ?? '-',
                                customerName: sale['nama_pelanggan']
                                        ?.toString() ??
                                    '-',
                                whatsapp: sale['no_wa']?.toString(),
                                address: (sale['alamat']?.toString() ?? '')
                                        .trim()
                                        .isEmpty
                                    ? null
                                    : sale['alamat']?.toString(),
                                email: (sale['email_pelanggan']?.toString() ??
                                            '')
                                        .trim()
                                        .isEmpty
                                    ? null
                                    : sale['email_pelanggan']?.toString(),
                                cashier:
                                    sale['nama_kasir']?.toString() ?? 'Staff',
                                dateLabel:
                                    'Masuk: ${sale['created_at'].toString().split('T').first}',
                                createdAtLabel:
                                    InvoiceLayout.formatInvoiceCreatedAt(
                                  sale['created_at'],
                                ),
                                method: sale['metode_pembayaran']
                                        ?.toString() ??
                                    'Tunai',
                                status: isDp ? 'DP' : 'LUNAS',
                                boardStatus:
                                    InvoiceStatusFooter.statusOf(sale),
                              ),
                              lines: [
                                for (final item in items)
                                  InvoiceDocLine(
                                    label:
                                        '${item['nama_produk']}  ×${item['qty']}',
                                    amount: _formatRupiah(item['subtotal']),
                                    group: InvoiceLayout.groupOfProduct(
                                      tipe: item['tipe_produk']?.toString() ??
                                          item['kategori']?.toString(),
                                      nama: item['nama_produk']?.toString(),
                                    ),
                                  ),
                              ],
                              totalFormatted:
                                  _formatRupiah(sale['total_harga'] ?? 0),
                              paidLabel:
                                  isDp ? 'Uang muka (DP)' : 'Dibayar',
                              paidFormatted:
                                  _formatRupiah(sale['dibayarkan'] ?? 0),
                              remainingFormatted:
                                  _formatRupiah(sale['sisa_tagihan'] ?? 0),
                              hasRemainingDebt: sisa > 0,
                              extras: showLens ? _previewLensTable() : null,
                              qrChild: settings.showQrInvoice
                                  ? SizedBox(
                                      height: 52,
                                      width: 52,
                                      child: QrImageView(
                                        data: demoQrPayload,
                                        version: QrVersions.auto,
                                        gapless: true,
                                        eyeStyle: const QrEyeStyle(
                                          eyeShape: QrEyeShape.square,
                                          color: OptikAdminTokens.navy,
                                        ),
                                        dataModuleStyle:
                                            const QrDataModuleStyle(
                                          dataModuleShape:
                                              QrDataModuleShape.square,
                                          color: OptikAdminTokens.navy,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          ];
          return narrow
              ? Column(children: panels)
              : Row(children: panels);
        },
      ),
    ),
    ),
    );
  }
}
