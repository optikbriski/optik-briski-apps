import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/attendance/pos_duty_gate.dart';
import '../../shared/garansi/garansi_service.dart';
import '../../shared/invoice/invoice_lifecycle_rules.dart';
import '../../shared/invoice/invoice_lifecycle_service.dart';
import '../../shared/theme.dart';

/// Klaim garansi dari HP Karyawan: scan QR CLAIM Member + wajib shift OPEN.
class KaryawanClaimPage extends StatefulWidget {
  const KaryawanClaimPage({
    super.key,
    required this.noInvoice,
    required this.rawScan,
    required this.profile,
  });

  final String noInvoice;
  final String rawScan;
  final Map<String, dynamic> profile;

  @override
  State<KaryawanClaimPage> createState() => _KaryawanClaimPageState();
}

class _KaryawanClaimPageState extends State<KaryawanClaimPage> {
  final _lifecycle = InvoiceLifecycleService();
  final _garansi = GaransiService();

  final _alasanCtrl = TextEditingController();
  final _catatanCtrl = TextEditingController();
  final _resepRecheckCtrl = TextEditingController();
  final _spekGantiCtrl = TextEditingController();

  bool _booting = true;
  bool _saving = false;
  String? _error;
  String? _success;
  Map<String, dynamic>? _sale;
  List<Map<String, dynamic>> _kartu = const [];
  Map<String, dynamic>? _selected;

  String _kategori = 'fitur_tidak_berfungsi';
  String _keputusan = 'selesai_ganti';
  bool _ukuranSesuai = true;
  bool _resepBerbeda = true;

  static const _kategoriOptions = <(String, String)>[
    ('fitur_tidak_berfungsi', 'Fitur gagal (anti-baret/bluechromic/elastis)'),
    ('ukuran_lensa', 'Ukuran / kenyamanan lensa'),
    ('cacat_pabrik', 'Cacat pabrik'),
    ('kelalaian_customer', 'Kelalaian customer (bukan fitur)'),
    ('lainnya', 'Lainnya'),
  ];

  static const _keputusanOptions = <(String, String)>[
    ('selesai_perbaikan', 'Selesai perbaikan'),
    ('selesai_ganti', 'Selesai ganti'),
    ('diterima', 'Diterima (proses)'),
    ('ditolak', 'Ditolak'),
  ];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _alasanCtrl.dispose();
    _catatanCtrl.dispose();
    _resepRecheckCtrl.dispose();
    _spekGantiCtrl.dispose();
    super.dispose();
  }

  String get _nik =>
      (widget.profile['nik'] ?? '').toString().trim().toUpperCase();
  String get _karyawanId => (widget.profile['id'] ?? '').toString().trim();
  String get _nama => (widget.profile['nama'] ?? '').toString().trim();
  String get _toko => (widget.profile['toko_id'] ?? '').toString().trim();

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _error = null;
      _success = null;
    });
    try {
      if (_karyawanId.isEmpty || _nik.isEmpty) {
        throw 'antrian_err_profil_nik'.tr();
      }

      final duty = await PosDutyGate.blockReason(
        karyawanId: _karyawanId,
        nik: _nik,
      );
      if (duty != null) throw duty.tr();

      final validated = await _lifecycle.validateClaimScan(widget.rawScan);
      if (validated.sale['no_invoice']?.toString() != widget.noInvoice) {
        throw 'antrian_err_invoice_mismatch'.tr();
      }

      final saleToko = (validated.sale['toko_id'] ?? '').toString();
      if (!InvoiceLifecycleRules.isPusatToko(_toko) &&
          !InvoiceLifecycleRules.sameStore(_toko, saleToko)) {
        throw 'antrian_err_beda_cabang'.tr();
      }

      final cards = await _garansi.kartuForSale(validated.sale['id'].toString());
      final claimable = cards
          .where((k) => GaransiService.kartuBisaDiklaim(k))
          .toList(growable: false);
      if (claimable.isEmpty) {
        throw 'antrian_claim_err_tidak_claimable'.tr();
      }

      final first = claimable.first;
      final jenis = first['jenis_garansi']?.toString();
      _kategori =
          jenis == 'frame' ? 'fitur_tidak_berfungsi' : 'ukuran_lensa';
      _keputusan =
          _kategori == 'fitur_tidak_berfungsi' ? 'selesai_ganti' : 'selesai_perbaikan';
      _spekGantiCtrl.text = first['spesifikasi_produk']?.toString() ??
          first['nama_produk']?.toString() ??
          '';

      if (!mounted) return;
      setState(() {
        _sale = validated.sale;
        _kartu = claimable;
        _selected = first;
        _booting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onKategori(String value) {
    setState(() {
      _kategori = value;
      if (value == 'kelalaian_customer') {
        _keputusan = 'ditolak';
      } else if (value == 'fitur_tidak_berfungsi') {
        _keputusan = 'selesai_ganti';
      }
    });
  }

  Future<void> _submit() async {
    final kartu = _selected;
    final sale = _sale;
    if (kartu == null || sale == null || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final duty = await PosDutyGate.blockReason(
        karyawanId: _karyawanId,
        nik: _nik,
      );
      if (duty != null) throw duty.tr();

      // Re-validate CLAIM still open before write.
      await _lifecycle.validateClaimScan(widget.rawScan);

      final saleToko = (sale['toko_id'] ?? '').toString().trim();
      final tokoKlaim = saleToko.isNotEmpty ? saleToko : _toko;

      await _garansi.ajukanDanPutuskan(
        kartuId: kartu['id'].toString(),
        tokoId: tokoKlaim,
        alasan: _alasanCtrl.text,
        keputusan: _keputusan,
        kategoriMasalah: _kategori,
        catatan: _catatanCtrl.text,
        ukuranSesuaiBeli: _ukuranSesuai,
        resepRecheck: _resepRecheckCtrl.text,
        resepBerbeda: _resepBerbeda,
        spesifikasiPengganti: _spekGantiCtrl.text,
      );

      await _lifecycle.consumeClaimQr(
        rawScan: widget.rawScan,
        staffNik: _nik,
      );

      if (!mounted) return;
      setState(() {
        _saving = false;
        _success = 'antrian_claim_ok'.tr();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pelanggan = (_sale?['nama_pelanggan'] ?? '-').toString();
    final jenis = (_selected?['jenis_garansi'] ?? '').toString();
    final showLensaFields = jenis == 'lensa' && _kategori == 'ukuran_lensa';
    final lockKeputusan = _kategori == 'kelalaian_customer' ||
        _kategori == 'fitur_tidak_berfungsi';

    return Scaffold(
      backgroundColor: OptikKaryawanTokens.pale,
      appBar: AppBar(
        backgroundColor: OptikKaryawanTokens.surface,
        foregroundColor: OptikKaryawanTokens.ink,
        title: Text('antrian_claim_title'.tr()),
      ),
      body: _booting
          ? const Center(
              child: CircularProgressIndicator(
                color: OptikKaryawanTokens.gold,
              ),
            )
          : _success != null
              ? _doneBody()
              : _error != null && _sale == null
                  ? _errorOnlyBody()
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          widget.noInvoice,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: OptikKaryawanTokens.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          pelanggan,
                          style: const TextStyle(
                            color: OptikKaryawanTokens.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_nama.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${'antrian_staff_label'.tr()}: $_nama',
                            style: const TextStyle(
                              color: OptikKaryawanTokens.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'antrian_claim_pilih_kartu'.tr(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: OptikKaryawanTokens.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._kartu.map((k) {
                          final id = k['id']?.toString() ?? '';
                          final selected =
                              _selected?['id']?.toString() == id;
                          final label =
                              '${k['jenis_garansi'] ?? '-'} · ${k['nama_produk'] ?? '-'}';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: selected
                                  ? OptikKaryawanTokens.seasideMid
                                      .withOpacity(0.35)
                                  : OptikKaryawanTokens.surface,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _saving
                                    ? null
                                    : () {
                                        setState(() {
                                          _selected = k;
                                          _spekGantiCtrl.text = k[
                                                      'spesifikasi_produk']
                                                  ?.toString() ??
                                              k['nama_produk']?.toString() ??
                                              '';
                                          final j =
                                              k['jenis_garansi']?.toString();
                                          if (j == 'frame') {
                                            _onKategori(
                                                'fitur_tidak_berfungsi');
                                          }
                                        });
                                      },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        color: OptikKaryawanTokens.ink,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: OptikKaryawanTokens.ink,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                        _label('antrian_claim_kategori'.tr()),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _kategoriOptions.map((o) {
                            final selected = _kategori == o.$1;
                            return ChoiceChip(
                              label: Text(o.$2),
                              selected: selected,
                              onSelected: _saving
                                  ? null
                                  : (_) => _onKategori(o.$1),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        _label('antrian_claim_keputusan'.tr()),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _keputusanOptions.map((o) {
                            final selected = _keputusan == o.$1;
                            return ChoiceChip(
                              label: Text(o.$2),
                              selected: selected,
                              onSelected: (_saving || lockKeputusan)
                                  ? null
                                  : (_) =>
                                      setState(() => _keputusan = o.$1),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        _field(
                          controller: _alasanCtrl,
                          label: 'antrian_claim_alasan'.tr(),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 10),
                        _field(
                          controller: _catatanCtrl,
                          label: 'antrian_claim_catatan'.tr(),
                          maxLines: 2,
                        ),
                        if (_keputusan == 'selesai_ganti' ||
                            _kategori == 'fitur_tidak_berfungsi') ...[
                          const SizedBox(height: 10),
                          _field(
                            controller: _spekGantiCtrl,
                            label: 'antrian_claim_spek_ganti'.tr(),
                            maxLines: 2,
                          ),
                        ],
                        if (showLensaFields) ...[
                          const SizedBox(height: 10),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('antrian_claim_ukuran_ok'.tr()),
                            value: _ukuranSesuai,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _ukuranSesuai = v),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('antrian_claim_resep_beda'.tr()),
                            value: _resepBerbeda,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _resepBerbeda = v),
                          ),
                          _field(
                            controller: _resepRecheckCtrl,
                            label: 'antrian_claim_resep_recheck'.tr(),
                            maxLines: 2,
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          _statusCard(
                            color: Colors.orange.shade800,
                            icon: Icons.error_outline_rounded,
                            text: _error!,
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _saving ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: OptikKaryawanTokens.seasideMid,
                            foregroundColor: OptikKaryawanTokens.ink,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: OptikKaryawanTokens.ink,
                                  ),
                                )
                              : Text('antrian_claim_submit'.tr()),
                        ),
                      ],
                    ),
    );
  }

  Widget _doneBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusCard(
            color: OptikKaryawanTokens.success,
            icon: Icons.check_circle_rounded,
            text: _success!,
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: OptikKaryawanTokens.seasideMid,
              foregroundColor: OptikKaryawanTokens.ink,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text('btn_mengerti'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _errorOnlyBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusCard(
            color: Colors.orange.shade800,
            icon: Icons.error_outline_rounded,
            text: _error ?? '-',
          ),
          const Spacer(),
          FilledButton(
            onPressed: _booting ? null : _boot,
            style: FilledButton.styleFrom(
              backgroundColor: OptikKaryawanTokens.seasideMid,
              foregroundColor: OptikKaryawanTokens.ink,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text('btn_coba_lagi'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: OptikKaryawanTokens.ink,
          fontSize: 13,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: !_saving,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: OptikKaryawanTokens.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _statusCard({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OptikKaryawanTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: OptikKaryawanTokens.ink.withOpacity(0.9),
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
