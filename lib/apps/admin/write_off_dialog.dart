// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../shared/logistics/product_identity.dart';
import '../../shared/logistics/stock_actor_gate.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/qr/product_code.dart';
import '../../shared/qr/qr_route.dart';
import '../../shared/qr/universal_qr_scan_page.dart';
import '../../shared/responsive.dart';
import '../../shared/theme.dart';
import 'barcode_scanner.dart';

/// Dialog end-to-end: Stok Rusak / Write-off (scan → preview → potong stok + ledger).
Future<bool> showWriteOffDialog({
  required BuildContext context,
  required Map<String, dynamic> profile,
}) async {
  final allowed = await StockActorGate.requireMatchingViaKaryawanQr(
    context: context,
    profile: profile,
    actionLabel: 'catat stok rusak',
  );
  if (!allowed || !context.mounted) return false;

  final toko = (profile['toko_id'] ?? 'PUSAT').toString().toUpperCase();
  final actorNama =
      (profile['nama'] ?? profile['email'] ?? '').toString();

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => R.constrainedDialog(
      context: ctx,
      preferWidth: 520,
      child: _WriteOffDialogBody(
        tokoId: toko,
        actorNama: actorNama,
      ),
    ),
  );
  return result == true;
}

class _WriteOffDialogBody extends StatefulWidget {
  const _WriteOffDialogBody({
    required this.tokoId,
    required this.actorNama,
  });

  final String tokoId;
  final String actorNama;

  @override
  State<_WriteOffDialogBody> createState() => _WriteOffDialogBodyState();
}

class _WriteOffDialogBodyState extends State<_WriteOffDialogBody> {
  final _skuCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _alasanCtrl = TextEditingController();
  final _skuFocus = FocusNode();

  Map<String, dynamic>? _product;
  String? _lookupError;
  bool _lookingUp = false;
  bool _submitting = false;
  List<Map<String, dynamic>> _recent = const [];
  bool _loadingRecent = true;

  static const _presetAlasan = <String>[
    'Rusak fisik / cacat',
    'Rusak di rak / display',
    'Kadaluarsa / tidak layak jual',
    'Hilang saat opname',
    'Sampel / demo tidak kembali',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _qtyCtrl.dispose();
    _alasanCtrl.dispose();
    _skuFocus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final rows = await StockMutationService().fetchWriteOffs(
        tokoId: widget.tokoId,
        limit: 8,
      );
      if (!mounted) return;
      setState(() {
        _recent = rows;
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecent = false);
    }
  }

  String _resolveLookupKey(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    return ProductCode.resolveSku(t) ??
        ProductCode.parse(t)?.sku ??
        t;
  }

  Future<void> _lookup([String? rawOverride]) async {
    final raw = (rawOverride ?? _skuCtrl.text).trim();
    final key = _resolveLookupKey(raw);
    if (key.isEmpty) {
      setState(() {
        _product = null;
        _lookupError = 'Isi SKU / barcode produk dulu.';
      });
      return;
    }

    setState(() {
      _lookingUp = true;
      _lookupError = null;
    });

    try {
      final prod = await ProductIdentity.findAtToko(
        tokoId: widget.tokoId,
        sku: key,
        barcode: key,
      );
      if (!mounted) return;
      if (prod == null) {
        setState(() {
          _product = null;
          _lookingUp = false;
          _lookupError =
              'Produk tidak ditemukan di ${widget.tokoId}. Cek SKU / barcode.';
        });
        return;
      }
      final sku = (prod['sku'] ?? key).toString();
      _skuCtrl.text = sku;
      setState(() {
        _product = prod;
        _lookingUp = false;
        _lookupError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _product = null;
        _lookingUp = false;
        _lookupError = 'Gagal cari produk: $e';
      });
    }
  }

  Future<void> _scanProduct() async {
    // Prefer universal scan: OBRPROD + barcode plain, satu pintu.
    final raw = await UniversalQrScanPage.scanRaw(
      context,
      allowedTypes: {
        QrPayloadType.product,
        QrPayloadType.unknown,
      },
      titleKey: 'Scan produk',
      hintKey: 'Barcode toko atau QR OBRPROD',
    );
    if (!mounted) return;
    var code = (raw ?? '').trim();
    if (code.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OptikBRiskiScanner(
            onDetect: (c) => code = c.trim(),
          ),
        ),
      );
    }
    if (!mounted || code.isEmpty) return;
    _skuCtrl.text = code;
    await _lookup(code);
  }

  int get _qty => int.tryParse(_qtyCtrl.text.trim()) ?? 0;

  int get _real => StockQty.realOf(_product);
  int get _pending => StockQty.pendingOf(_product);
  int get _available => StockQty.availableOf(_product);

  String? _validate() {
    if (_product == null) return 'Cari / scan produk dulu.';
    if (_qty <= 0) return 'Qty rusak harus lebih dari 0.';
    if (_available <= 0) {
      return 'Tidak ada stok tersedia (real $_real · booking $_pending).';
    }
    if (_qty > _available) {
      return 'Qty melebihi tersedia ($_available pcs).';
    }
    if (_alasanCtrl.text.trim().length < 3) {
      return 'Alasan wajib diisi (min. 3 karakter).';
    }
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }

    final sku = ProductIdentity.normalizeSku(_product!['sku'])!;
    final nama = (_product!['nama'] ?? sku).toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text(
          'Konfirmasi stok rusak',
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Potong $_qty pcs dari $nama\n'
          'Toko ${widget.tokoId}\n'
          'Real $_real → ${_real - _qty} '
          '(booking $_pending tetap)\n\n'
          'Alasan: ${_alasanCtrl.text.trim()}\n\n'
          'Ini mengurangi stok rak dan tercatat ledger WRITE_OFF.',
          style: const TextStyle(
            color: OptikAdminTokens.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: OptikAdminTokens.warning,
              foregroundColor: OptikAdminTokens.bg,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, catat'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final res = await StockMutationService().writeOff(
        tokoId: widget.tokoId,
        sku: sku,
        qty: _qty,
        alasan: _alasanCtrl.text.trim(),
        actorNama: widget.actorNama,
      );
      if (!mounted) return;
      final before = res['stock_before'] ?? _real;
      final after = res['stock_after'] ?? (_real - _qty);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Stok rusak tercatat: $sku −$_qty pcs ($before → $after).',
        ),
        backgroundColor: OptikAdminTokens.success,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal catat stok rusak: $e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  String _tokoLabel(String id) {
    final t = id.trim().toUpperCase();
    if (t == 'PUSAT') return 'Pusat';
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  String _fmtWhen(dynamic raw) {
    final s = (raw ?? '').toString();
    if (s.isEmpty) return '-';
    final dt = DateTime.tryParse(s)?.toLocal();
    if (dt == null) return s;
    return DateFormat('dd MMM · HH:mm', 'id_ID').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OptikAdminTokens.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      contentPadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: OptikAdminTokens.warning.withOpacity(0.14),
            ),
            child: const Icon(
              Icons.report_gmailerrorred_rounded,
              color: OptikAdminTokens.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stok Rusak / Write-off',
                  style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                Text(
                  'Toko ${_tokoLabel(widget.tokoId)} · potong stok + jejak ledger',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.45),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 560,
        child: ListView(
          children: [
            Text(
              'Hanya stok tersedia (Real − Booking) yang boleh di-write-off. '
              'Booking DO/RO tidak boleh ditembus.',
              style: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.5),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _skuCtrl,
                    focusNode: _skuFocus,
                    enabled: !_submitting,
                    style: const TextStyle(color: OptikAdminTokens.navy),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _lookup(),
                    decoration: InputDecoration(
                      labelText: 'SKU / barcode',
                      labelStyle:
                          const TextStyle(color: OptikAdminTokens.textMuted),
                      hintText: 'Scan atau ketik lalu cari',
                      filled: true,
                      fillColor: OptikAdminTokens.navy.withOpacity(0.03),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: _lookingUp
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Cari',
                              onPressed: _submitting ? null : () => _lookup(),
                              icon: const Icon(Icons.search_rounded),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _scanProduct,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OptikAdminTokens.navy,
                      side: const BorderSide(color: OptikAdminTokens.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_lookupError != null) ...[
              const SizedBox(height: 8),
              Text(
                _lookupError!,
                style: const TextStyle(
                  color: OptikAdminTokens.danger,
                  fontSize: 12,
                ),
              ),
            ],
            if (_product != null) ...[
              const SizedBox(height: 12),
              _productCard(),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _qtyCtrl,
              enabled: !_submitting && _product != null,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: OptikAdminTokens.navy),
              decoration: InputDecoration(
                labelText: 'Qty rusak',
                labelStyle: const TextStyle(color: OptikAdminTokens.textMuted),
                helperText: _product == null
                    ? null
                    : 'Maks. $_available pcs tersedia',
                filled: true,
                fillColor: OptikAdminTokens.navy.withOpacity(0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              'Alasan cepat',
              style: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.45),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _presetAlasan.map((a) {
                final selected = _alasanCtrl.text.trim() == a;
                return ChoiceChip(
                  label: Text(a, style: const TextStyle(fontSize: 11.5)),
                  selected: selected,
                  onSelected: _submitting
                      ? null
                      : (_) {
                          setState(() => _alasanCtrl.text = a);
                        },
                  selectedColor: OptikAdminTokens.warning.withOpacity(0.22),
                  labelStyle: TextStyle(
                    color: selected
                        ? OptikAdminTokens.navy
                        : OptikAdminTokens.textSecondary,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: selected
                        ? OptikAdminTokens.warning.withOpacity(0.55)
                        : OptikAdminTokens.line,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _alasanCtrl,
              enabled: !_submitting,
              maxLines: 2,
              style: const TextStyle(color: OptikAdminTokens.navy),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Alasan (wajib)',
                labelStyle: const TextStyle(color: OptikAdminTokens.textMuted),
                hintText: 'Jelaskan kondisi barang…',
                filled: true,
                fillColor: OptikAdminTokens.navy.withOpacity(0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'RIWAYAT WRITE-OFF (${_tokoLabel(widget.tokoId)})',
              style: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.45),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            if (_loadingRecent)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Belum ada write-off di toko ini.',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
              )
            else
              ..._recent.map(_recentTile),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: OptikAdminTokens.warning,
            foregroundColor: OptikAdminTokens.bg,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: OptikAdminTokens.bg,
                  ),
                )
              : const Text(
                  'Catat rusak',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ],
    );
  }

  Widget _productCard() {
    final nama = (_product!['nama'] ?? '-').toString();
    final sku = (_product!['sku'] ?? '-').toString();
    final barcode = (_product!['barcode'] ?? '').toString();
    final availOk = _available > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: availOk
              ? OptikAdminTokens.navy.withOpacity(0.18)
              : OptikAdminTokens.warning.withOpacity(0.45),
        ),
        color: OptikAdminTokens.navy.withOpacity(0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nama,
            style: const TextStyle(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'SKU $sku${barcode.isNotEmpty ? ' · $barcode' : ''}',
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.42),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _qtyChip('Real', '$_real', OptikAdminTokens.navy),
              const SizedBox(width: 8),
              _qtyChip('Booking', '$_pending', OptikAdminTokens.ice),
              const SizedBox(width: 8),
              _qtyChip(
                'Tersedia',
                '$_available',
                availOk ? OptikAdminTokens.success : OptikAdminTokens.warning,
              ),
            ],
          ),
          if (!availOk) ...[
            const SizedBox(height: 8),
            Text(
              'Stok ter-booking penuh / kosong — selesaikan paket perjalanan dulu.',
              style: TextStyle(
                color: OptikAdminTokens.warning.withOpacity(0.9),
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _qtyChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.85),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentTile(Map<String, dynamic> r) {
    final sku = (r['sku'] ?? '-').toString();
    final delta = int.tryParse(r['qty_delta']?.toString() ?? '0') ?? 0;
    final alasan = (r['alasan_text'] ?? '-').toString();
    final actor = (r['actor_nama'] ?? '').toString();
    final when = _fmtWhen(r['created_at']);
    final meta = r['meta'];
    final nama = meta is Map ? (meta['nama'] ?? '').toString() : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptikAdminTokens.line),
        color: OptikAdminTokens.navy.withOpacity(0.02),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama.isNotEmpty ? nama : sku,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sku · $when${actor.isNotEmpty ? ' · $actor' : ''}',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.4),
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  alasan,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.55),
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$delta',
            style: const TextStyle(
              color: OptikAdminTokens.warning,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
