// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../shared/garansi/garansi_service.dart';
import '../../shared/invoice/invoice_link.dart';
import '../../shared/safe_image_picker.dart';

class GaransiPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const GaransiPage({super.key, required this.profile});

  @override
  State<GaransiPage> createState() => _GaransiPageState();
}

class _GaransiPageState extends State<GaransiPage>
    with SingleTickerProviderStateMixin {
  final _svc = GaransiService();
  final _searchCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();

  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _kartu = [];
  List<Map<String, dynamic>> _klaim = [];
  Map<String, int> _stats = const {};

  String get _tokoId => widget.profile['toko_id']?.toString() ?? '';
  String get _role => widget.profile['role']?.toString() ?? '';

  bool get _isPusat {
    final t = _tokoId.toUpperCase();
    return t == 'PUSAT' ||
        t == 'CABANG-PUSAT' ||
        _role == 'owner' ||
        _role == 'admin_pusat';
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _isPusat ? 3 : 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _invoiceCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final kartu = await _svc.searchKartu(
        query: _searchCtrl.text,
        tokoId: _tokoId,
        isPusat: _isPusat,
      );
      final klaim = await _svc.listKlaim(tokoId: _tokoId, isPusat: _isPusat);
      Map<String, int> stats = const {};
      if (_isPusat) stats = await _svc.statsPusat();
      if (!mounted) return;
      setState(() {
        _kartu = kartu;
        _klaim = klaim;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _generateFromInvoice() async {
    final inv = _invoiceCtrl.text.trim();
    if (inv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('garansi_err_invoice_kosong'.tr())),
      );
      return;
    }
    try {
      final n = await _svc.generateFromInvoice(
        inv,
        tokoId: _isPusat ? null : _tokoId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('garansi_generate_ok'.tr(args: ['$n'])),
          backgroundColor: Colors.green,
        ),
      );
      _invoiceCtrl.clear();
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openAmbilFlow({String? prefillInvoice}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GaransiKonfirmasiAmbilPage(
          profile: widget.profile,
          prefillInvoice: prefillInvoice,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openKartu(Map<String, dynamic> kartu) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _KartuDetailSheet(
        kartu: kartu,
        isPusat: _isPusat,
        tokoId: _tokoId,
        service: _svc,
        onChanged: _reload,
        onAmbil: () {
          Navigator.pop(ctx);
          _openAmbilFlow(prefillInvoice: kartu['no_invoice']?.toString());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071018),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text('garansi_page_title'.tr()),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFFE8C872),
          tabs: [
            Tab(text: 'garansi_tab_kartu'.tr()),
            Tab(text: 'garansi_tab_klaim'.tr()),
            if (_isPusat) Tab(text: 'garansi_tab_ringkasan'.tr()),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'garansi_ambil_title'.tr(),
            onPressed: () => _openAmbilFlow(),
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAmbilFlow(),
        backgroundColor: const Color(0xFFE8C872),
        foregroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: Text('garansi_ambil_fab'.tr()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildKartuTab(),
                _buildKlaimTab(),
                if (_isPusat) _buildRingkasanTab(),
              ],
            ),
    );
  }

  Widget _buildKartuTab() {
    return Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red.shade800,
            actions: [
              TextButton(
                onPressed: _reload,
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'garansi_rules_short'.tr(),
            style: TextStyle(
              color: const Color(0xFFE8C872).withOpacity(0.9),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'garansi_search_hint'.tr(),
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFE8C872)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white70),
                onPressed: _reload,
              ),
            ),
            onSubmitted: (_) => _reload(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _invoiceCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'garansi_generate_hint'.tr(),
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _generateFromInvoice,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3C72),
                ),
                child: Text('garansi_generate_btn'.tr()),
              ),
            ],
          ),
        ),
        Expanded(
          child: _kartu.isEmpty
              ? Center(
                  child: Text(
                    'garansi_empty_kartu'.tr(),
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                  itemCount: _kartu.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final k = _kartu[i];
                    final jenis = k['jenis_garansi']?.toString() ?? '-';
                    return ListTile(
                      onTap: () => _openKartu(k),
                      tileColor: Colors.white.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: jenis == 'lensa'
                            ? Colors.teal.withOpacity(0.3)
                            : const Color(0xFFE8C872).withOpacity(0.25),
                        child: Icon(
                          jenis == 'lensa'
                              ? Icons.visibility_rounded
                              : Icons.crop_landscape_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        k['nama_produk']?.toString() ?? '-',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${k['no_invoice'] ?? '-'} · ${k['nama_pelanggan'] ?? '-'}\n'
                        '${jenis.toUpperCase()} · ${GaransiService.statusLabel(k)}'
                        '${k['klaim_digunakan'] == true ? ' · Klaim sudah dipakai' : ''}'
                        '${_isPusat ? ' · ${k['toko_id']}' : ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white38),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildKlaimTab() {
    if (_klaim.isEmpty) {
      return Center(
        child: Text(
          'garansi_empty_klaim'.tr(),
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: _klaim.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final row = _klaim[i];
        final kartu = row['garansi_kartu'];
        final kMap = kartu is Map
            ? Map<String, dynamic>.from(kartu)
            : <String, dynamic>{};
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kMap['nama_produk']?.toString() ?? 'garansi_klaim_label'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${row['keputusan']} · ${row['kategori_masalah'] ?? '-'} · '
                '${kMap['no_invoice'] ?? '-'}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                row['alasan']?.toString() ?? '-',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRingkasanTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'garansi_ringkasan_desc'.tr(),
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _statCard(
                'Menunggu ambil',
                '${_stats['menunggu_ambil'] ?? 0}',
                Icons.hourglass_top_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                'garansi_stat_aktif'.tr(),
                '${_stats['kartu_aktif'] ?? 0}',
                Icons.verified_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _statCard(
          'garansi_stat_klaim_bulan'.tr(),
          '${_stats['klaim_bulan_ini'] ?? 0}',
          Icons.assignment_turned_in_rounded,
        ),
        const SizedBox(height: 16),
        Text(
          'garansi_pusat_note'.tr(),
          style: TextStyle(
            color: const Color(0xFFE8C872).withOpacity(0.85),
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8C872).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFE8C872), size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style:
                TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Konfirmasi ambil: scan barcode struk + foto hasil
// ---------------------------------------------------------------------------
/// Halaman scan barcode struk + foto hasil → mulai garansi 7 hari.
class GaransiKonfirmasiAmbilPage extends StatefulWidget {
  const GaransiKonfirmasiAmbilPage({
    super.key,
    required this.profile,
    this.prefillInvoice,
  });

  final Map<String, dynamic> profile;
  final String? prefillInvoice;

  @override
  State<GaransiKonfirmasiAmbilPage> createState() =>
      _GaransiKonfirmasiAmbilPageState();
}

class _GaransiKonfirmasiAmbilPageState
    extends State<GaransiKonfirmasiAmbilPage> {
  final _svc = GaransiService();
  final _invoiceCtrl = TextEditingController();
  File? _foto;
  bool _saving = false;
  bool _scanning = false;

  String get _tokoId => widget.profile['toko_id']?.toString() ?? '';
  String get _role => widget.profile['role']?.toString() ?? '';
  bool get _isPusat {
    final t = _tokoId.toUpperCase();
    return t == 'PUSAT' ||
        t == 'CABANG-PUSAT' ||
        _role == 'owner' ||
        _role == 'admin_pusat';
  }

  @override
  void initState() {
    super.initState();
    if (widget.prefillInvoice != null) {
      _invoiceCtrl.text = widget.prefillInvoice!;
    }
  }

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _InvoiceScannerPage()),
    );
    if (!mounted) return;
    setState(() => _scanning = false);
    if (code != null && code.trim().isNotEmpty) {
      final inv = InvoiceLink.parse(code) ?? code.trim();
      setState(() => _invoiceCtrl.text = inv);
    }
  }

  Future<void> _pickFoto() async {
    final x = await pickImageSafe(context: context, imageQuality: 85);
    if (x == null) return;
    setState(() => _foto = File(x.path));
  }

  Future<void> _submit() async {
    final inv = _invoiceCtrl.text.trim();
    if (inv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('garansi_err_invoice_kosong'.tr())),
      );
      return;
    }
    if (_foto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('garansi_err_foto_wajib'.tr())),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final sale = await _svc.findSaleByInvoice(
        inv,
        tokoId: _tokoId,
        isPusat: _isPusat,
      );
      if (sale == null) throw 'Invoice tidak ditemukan.';

      final url = await _svc.uploadFotoHasilFile(
        saleId: sale['id'].toString(),
        file: _foto!,
      );
      final res = await _svc.konfirmasiAmbil(
        noInvoice: inv,
        fotoHasilUrl: url,
        tokoId: _tokoId,
        isPusat: _isPusat,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'garansi_ambil_ok'.tr(args: [
              res['tanggal_mulai']?.toString() ?? '',
              res['tanggal_akhir']?.toString() ?? '',
            ]),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071018),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text('garansi_ambil_title'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'garansi_ambil_desc'.tr(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _invoiceCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'No. Invoice',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                onPressed: _scanning ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFE8C872)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'garansi_foto_hasil'.tr(),
            style: const TextStyle(
              color: Color(0xFFE8C872),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickFoto,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: _foto == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.camera_alt_rounded,
                            color: Colors.white54, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          'garansi_foto_tap'.tr(),
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                      ],
                    )
                  : Image.file(_foto!, fit: BoxFit.cover, width: double.infinity),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE8C872),
                foregroundColor: const Color(0xFF0F172A),
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

class _InvoiceScannerPage extends StatefulWidget {
  const _InvoiceScannerPage();

  @override
  State<_InvoiceScannerPage> createState() => _InvoiceScannerPageState();
}

class _InvoiceScannerPageState extends State<_InvoiceScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('garansi_scan_invoice'.tr()),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_done) return;
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;
          final raw = barcodes.first.rawValue;
          if (raw == null || raw.isEmpty) return;
          _done = true;
          Navigator.pop(context, raw);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail kartu + form klaim
// ---------------------------------------------------------------------------
class _KartuDetailSheet extends StatefulWidget {
  const _KartuDetailSheet({
    required this.kartu,
    required this.isPusat,
    required this.tokoId,
    required this.service,
    required this.onChanged,
    required this.onAmbil,
  });

  final Map<String, dynamic> kartu;
  final bool isPusat;
  final String tokoId;
  final GaransiService service;
  final Future<void> Function() onChanged;
  final VoidCallback onAmbil;

  @override
  State<_KartuDetailSheet> createState() => _KartuDetailSheetState();
}

class _KartuDetailSheetState extends State<_KartuDetailSheet> {
  final _alasanCtrl = TextEditingController();
  final _catatanCtrl = TextEditingController();
  final _resepRecheckCtrl = TextEditingController();
  final _spekGantiCtrl = TextEditingController();
  String _keputusan = 'selesai_perbaikan';
  String _kategori = 'ukuran_lensa';
  bool _ukuranSesuai = true;
  bool _resepBerbeda = true;
  bool _saving = false;
  List<Map<String, dynamic>> _riwayat = [];

  @override
  void initState() {
    super.initState();
    final jenis = widget.kartu['jenis_garansi']?.toString();
    if (jenis == 'frame') _kategori = 'fitur_tidak_berfungsi';
    _spekGantiCtrl.text =
        widget.kartu['spesifikasi_produk']?.toString() ??
            widget.kartu['nama_produk']?.toString() ??
            '';
    _loadRiwayat();
  }

  @override
  void dispose() {
    _alasanCtrl.dispose();
    _catatanCtrl.dispose();
    _resepRecheckCtrl.dispose();
    _spekGantiCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRiwayat() async {
    final id = widget.kartu['id']?.toString();
    if (id == null) return;
    final rows = await widget.service.klaimForKartu(id);
    if (mounted) setState(() => _riwayat = rows);
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await widget.service.ajukanDanPutuskan(
        kartuId: widget.kartu['id'].toString(),
        tokoId: widget.tokoId.isNotEmpty
            ? widget.tokoId
            : widget.kartu['toko_id']?.toString() ?? 'PUSAT',
        alasan: _alasanCtrl.text,
        keputusan: _keputusan,
        kategoriMasalah: _kategori,
        catatan: _catatanCtrl.text,
        ukuranSesuaiBeli: _ukuranSesuai,
        resepRecheck: _resepRecheckCtrl.text,
        resepBerbeda: _resepBerbeda,
        spesifikasiPengganti: _spekGantiCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('garansi_klaim_ok'.tr()),
          backgroundColor: Colors.green,
        ),
      );
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kartu;
    final menunggu = k['status']?.toString() == 'menunggu_ambil';
    final bisa = widget.service.kartuBisaDiklaim(k) && !widget.isPusat;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final jenis = k['jenis_garansi']?.toString() ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(
              k['nama_produk']?.toString() ?? '-',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${k['no_invoice'] ?? '-'} · ${k['nama_pelanggan'] ?? '-'}\n'
              '${jenis.toUpperCase()} · ${GaransiService.statusLabel(k)}\n'
              'Periode: ${k['tanggal_mulai'] ?? '-'} → ${k['tanggal_akhir'] ?? '-'}'
              '${k['klaim_digunakan'] == true ? '\nKlaim: sudah dipakai (1x/transaksi)' : ''}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                height: 1.4,
                fontSize: 12.5,
              ),
            ),
            if ((k['spesifikasi_produk']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Spek dibeli: ${k['spesifikasi_produk']}',
                style: TextStyle(
                  color: const Color(0xFFE8C872).withOpacity(0.85),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
            if ((k['resep_awal']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Resep awal: ${k['resep_awal']}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11.5,
                ),
              ),
            ],
            if (menunggu && !widget.isPusat) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onAmbil,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text('garansi_ambil_fab'.tr()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE8C872),
                    side: const BorderSide(color: Color(0xFFE8C872)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'garansi_riwayat'.tr(),
              style: const TextStyle(
                color: Color(0xFFE8C872),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (_riwayat.isEmpty)
              Text(
                'garansi_riwayat_kosong'.tr(),
                style: TextStyle(color: Colors.white.withOpacity(0.4)),
              )
            else
              ..._riwayat.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${r['keputusan']} / ${r['kategori_masalah']} — ${r['alasan']}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            if (bisa) ...[
              const SizedBox(height: 18),
              Text(
                'garansi_form_title'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _kategori,
                dropdownColor: const Color(0xFF1A2744),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDeco('Kategori masalah'),
                items: const [
                  DropdownMenuItem(
                    value: 'fitur_tidak_berfungsi',
                    child: Text(
                      'Fitur gagal (anti-baret/bluechromic/elastis)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'ukuran_lensa',
                    child: Text('Ukuran / kenyamanan lensa'),
                  ),
                  DropdownMenuItem(
                    value: 'cacat_pabrik',
                    child: Text('Cacat pabrik'),
                  ),
                  DropdownMenuItem(
                    value: 'kelalaian_customer',
                    child: Text('Kelalaian customer (bukan fitur)'),
                  ),
                  DropdownMenuItem(
                    value: 'lainnya',
                    child: Text('Lainnya'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _kategori = v;
                    if (v == 'kelalaian_customer') {
                      _keputusan = 'ditolak';
                    } else if (v == 'fitur_tidak_berfungsi') {
                      _keputusan = 'selesai_ganti';
                    }
                  });
                },
              ),
              if (_kategori == 'fitur_tidak_berfungsi') ...[
                const SizedBox(height: 8),
                Text(
                  'Contoh valid: anti-baret tapi baret · bluechromic tidak berubah warna / tidak anti radiasi · frame elastis patah. Customer dapat barang baru spek sama.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _spekGantiCtrl,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: _fieldDeco('Spek barang pengganti (sama yang dibeli)'),
                ),
              ],
              if (jenis == 'lensa' && _kategori == 'ukuran_lensa') ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Ukuran lensa sesuai yang dibeli',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  ),
                  value: _ukuranSesuai,
                  activeColor: const Color(0xFFE8C872),
                  onChanged: (v) => setState(() => _ukuranSesuai = v),
                ),
                TextField(
                  controller: _resepRecheckCtrl,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: _fieldDeco('Hasil cek mata ulang (resep baru)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Hasil cek mata BERBEDA dari resep awal',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    'Jika sama (mis. tetap -2.00), klaim tidak valid',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                  value: _resepBerbeda,
                  activeColor: const Color(0xFFE8C872),
                  onChanged: (v) => setState(() => _resepBerbeda = v),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _alasanCtrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: _fieldDeco('garansi_alasan'.tr()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _catatanCtrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: _fieldDeco('garansi_catatan'.tr()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _keputusan,
                dropdownColor: const Color(0xFF1A2744),
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDeco('garansi_keputusan'.tr()),
                items: const [
                  DropdownMenuItem(
                    value: 'selesai_perbaikan',
                    child: Text('Selesai perbaikan'),
                  ),
                  DropdownMenuItem(
                    value: 'selesai_ganti',
                    child: Text('Selesai ganti'),
                  ),
                  DropdownMenuItem(
                    value: 'diterima',
                    child: Text('Diterima (proses)'),
                  ),
                  DropdownMenuItem(
                    value: 'ditolak',
                    child: Text('Ditolak'),
                  ),
                ],
                onChanged: (_kategori == 'kelalaian_customer' ||
                        _kategori == 'fitur_tidak_berfungsi')
                    ? null
                    : (v) {
                        if (v != null) setState(() => _keputusan = v);
                      },
              ),
              if (_kategori == 'fitur_tidak_berfungsi')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Keputusan otomatis: Selesai ganti (barang baru sesuai spek).',
                    style: TextStyle(
                      color: const Color(0xFFE8C872).withOpacity(0.8),
                      fontSize: 11.5,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8C872),
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'garansi_submit'.tr(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ] else if (widget.isPusat) ...[
              const SizedBox(height: 12),
              Text(
                'garansi_pusat_readonly'.tr(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
