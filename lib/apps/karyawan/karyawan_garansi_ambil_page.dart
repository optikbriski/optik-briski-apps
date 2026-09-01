import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/attendance/pos_duty_gate.dart';
import '../../shared/garansi/garansi_rules.dart';
import '../../shared/garansi/garansi_service.dart';
import '../../shared/invoice/invoice_link.dart';
import '../../shared/karyawan/karyawan_action_outbox.dart';
import '../../shared/qr/qr_route.dart';
import '../../shared/qr/universal_qr_scan_page.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/theme.dart';

/// Konfirmasi ambil barang + mulai garansi 7 hari — ringkas di HP Karyawan.
class KaryawanGaransiAmbilPage extends StatefulWidget {
  const KaryawanGaransiAmbilPage({
    super.key,
    required this.profile,
    this.prefillInvoice,
  });

  final Map<String, dynamic> profile;
  final String? prefillInvoice;

  @override
  State<KaryawanGaransiAmbilPage> createState() =>
      _KaryawanGaransiAmbilPageState();
}

class _KaryawanGaransiAmbilPageState extends State<KaryawanGaransiAmbilPage> {
  final _svc = GaransiService();
  final _invoiceCtrl = TextEditingController();
  Uint8List? _fotoBytes;
  bool _saving = false;
  bool _scanning = false;

  String get _tokoId => (widget.profile['toko_id'] ?? '').toString().trim();
  String get _karyawanId => (widget.profile['id'] ?? '').toString().trim();
  String get _nik =>
      (widget.profile['nik'] ?? '').toString().trim().toUpperCase();
  bool get _isPusat => GaransiRules.canViewAllStores(
        tokoId: _tokoId,
        role: widget.profile['role']?.toString(),
        profile: widget.profile,
      );

  @override
  void initState() {
    super.initState();
    final pre = (widget.prefillInvoice ?? '').trim();
    if (pre.isNotEmpty) _invoiceCtrl.text = pre;
  }

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureDuty() async {
    if (_karyawanId.isEmpty || _nik.isEmpty) {
      throw 'antrian_err_profil_nik'.tr();
    }
    final duty = await PosDutyGate.blockReason(
      karyawanId: _karyawanId,
      nik: _nik,
    );
    if (duty != null) throw duty.tr();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final raw = await UniversalQrScanPage.scanRaw(
        context,
        allowedTypes: {
          QrPayloadType.invoice,
          QrPayloadType.unknown,
        },
        titleKey: 'garansi_ambil_fab',
        hintKey: 'garansi_ambil_desc',
      );
      if (!mounted || raw == null || raw.trim().isEmpty) return;
      final inv = InvoiceLink.parse(raw) ?? raw.trim();
      setState(() => _invoiceCtrl.text = inv);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickFoto() async {
    final x = await pickImageSafe(context: context, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() => _fotoBytes = bytes);
  }

  Future<void> _submit() async {
    final inv = _invoiceCtrl.text.trim();
    if (inv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('garansi_err_invoice_kosong'.tr())),
      );
      return;
    }
    if (_fotoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('garansi_err_foto_wajib'.tr())),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _ensureDuty();
      final sale = await _svc.findSaleByInvoice(
        inv,
        tokoId: _tokoId,
        isPusat: _isPusat,
      );
      if (sale == null) throw 'Invoice tidak ditemukan.';

      final url = await _svc.uploadFotoHasil(
        saleId: sale['id'].toString(),
        bytes: _fotoBytes!,
      );
      Map<String, dynamic>? res;
      await KaryawanActionOutbox.instance.runOrEnqueue(
        kind: 'garansi_ambil',
        payload: {
          'noInvoice': inv,
          'fotoHasilUrl': url,
          'tokoId': _tokoId,
          'isPusat': _isPusat,
        },
        action: () async {
          res = await _svc.konfirmasiAmbil(
            noInvoice: inv,
            fotoHasilUrl: url,
            tokoId: _tokoId,
            isPusat: _isPusat,
          );
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'garansi_ambil_ok'.tr(args: [
              res?['tanggal_mulai']?.toString() ?? '',
              res?['tanggal_akhir']?.toString() ?? '',
            ]),
          ),
          backgroundColor: OptikKaryawanTokens.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikKaryawanTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.bg,
      appBar: AppBar(
        backgroundColor: OptikKaryawanTokens.snow,
        foregroundColor: OptikKaryawanTokens.ink,
        title: Text(
          'garansi_ambil_title'.tr(),
          style: GoogleFonts.fraunces(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'garansi_ambil_desc'.tr(),
            style: TextStyle(
              color: OptikKaryawanTokens.muted,
              height: 1.4,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _invoiceCtrl,
            decoration: InputDecoration(
              labelText: 'No. Invoice',
              filled: true,
              fillColor: OptikKaryawanTokens.snow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: OptikKaryawanTokens.border),
              ),
              suffixIcon: IconButton(
                onPressed: _scanning || _saving ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'garansi_foto_hasil'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _saving ? null : _pickFoto,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: OptikKaryawanTokens.snow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OptikKaryawanTokens.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _fotoBytes == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_rounded,
                            size: 40, color: OptikKaryawanTokens.muted),
                        const SizedBox(height: 8),
                        Text(
                          'garansi_foto_tap'.tr(),
                          style: TextStyle(color: OptikKaryawanTokens.muted),
                        ),
                      ],
                    )
                  : Image.memory(
                      _fotoBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: OptikKaryawanTokens.seasideMid,
                foregroundColor: OptikKaryawanTokens.ink,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'garansi_ambil_submit'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
