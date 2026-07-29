// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../shared/invoice/invoice_delivery_service.dart';
import '../../shared/invoice/invoice_detail_page.dart';
import '../../shared/invoice/invoice_lifecycle_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Board admin: DP · PENDING · CLEAR (tanpa scan QR).
/// - DP: sisa tagihan / down payment → aksi Lunasi
/// - PENDING: lunas, barang belum ready → aksi Barang Ready
/// - CLEAR: clear payment + history (siap / diambil)
class RiwayatTransaksiPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RiwayatTransaksiPage({super.key, required this.profile});

  @override
  State<RiwayatTransaksiPage> createState() => _RiwayatTransaksiPageState();
}

enum _PayBucket { dp, pending, clear }

class _RiwayatTransaksiPageState extends State<RiwayatTransaksiPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final _lifecycle = InvoiceLifecycleService();
  final _delivery = InvoiceDeliveryService();

  bool isLoading = true;
  bool _busy = false;
  String? selectedTokoId;
  _PayBucket _bucket = _PayBucket.dp;
  String _search = '';

  List<Map<String, dynamic>> allSalesRaw = [];
  List<String> listCabangUnik = [];
  List<Map<String, dynamic>> branchSales = [];

  @override
  void initState() {
    super.initState();
    _inisialisasiHakAksesAplikasi();
  }

  String formatRupiah(int nominal) {
    return NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp', decimalDigits: 0)
        .format(nominal);
  }

  bool get _isOwnerOrPusat {
    final role = widget.profile['role']?.toString().toLowerCase() ?? '';
    final toko =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
    return role == 'owner' || toko == 'PUSAT';
  }

  void _inisialisasiHakAksesAplikasi() {
    if (_isOwnerOrPusat) {
      selectedTokoId = null;
      _fetchSeluruhDataTransaksiOwner();
    } else {
      selectedTokoId =
          widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
      _fetchDataTransaksiPerCabang(selectedTokoId!);
    }
  }

  Future<void> _fetchSeluruhDataTransaksiOwner() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final res = await supabase
          .from('sales')
          .select()
          .order('created_at', ascending: false);
      final data = List<Map<String, dynamic>>.from(res);
      final cabang = data
          .map((e) => e['toko_id']?.toString().toUpperCase() ?? 'PUSAT')
          .toSet()
          .toList()
        ..sort();
      setState(() {
        allSalesRaw = data;
        listCabangUnik = cabang;
        isLoading = false;
      });
    } catch (e) {
      _fail('Gagal muat data cabang: $e');
    }
  }

  Future<void> _fetchDataTransaksiPerCabang(String tokoId) async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final res = await supabase
          .from('sales')
          .select()
          .eq('toko_id', tokoId)
          .order('created_at', ascending: false);
      setState(() {
        branchSales = List<Map<String, dynamic>>.from(res);
        isLoading = false;
      });
    } catch (e) {
      _fail('Gagal muat transaksi cabang: $e');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  // --- Klasifikasi bucket (sederajat: DP / PENDING / CLEAR) ---

  static bool isDp(Map<String, dynamic> sale) {
    final pay = (sale['status_pembayaran'] ?? '').toString().toUpperCase();
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    return pay == 'DP' || sisa > 0;
  }

  static bool isPending(Map<String, dynamic> sale) {
    if (isDp(sale)) return false;
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    if (sale['diambil_at'] != null || tracking == 'DIAMBIL') return false;
    return tracking != 'SIAP_DIAMBIL' && tracking != 'CLEAR';
  }

  static bool isClear(Map<String, dynamic> sale) =>
      !isDp(sale) && !isPending(sale);

  static _PayBucket bucketOf(Map<String, dynamic> sale) {
    if (isDp(sale)) return _PayBucket.dp;
    if (isPending(sale)) return _PayBucket.pending;
    return _PayBucket.clear;
  }

  List<Map<String, dynamic>> _salesForToko(String tokoId) {
    return allSalesRaw
        .where((e) =>
            (e['toko_id']?.toString().toUpperCase() ?? 'PUSAT') == tokoId)
        .toList();
  }

  ({int dp, int pending, int clear}) _counts(List<Map<String, dynamic>> list) {
    var dp = 0, pending = 0, clear = 0;
    for (final s in list) {
      switch (bucketOf(s)) {
        case _PayBucket.dp:
          dp++;
        case _PayBucket.pending:
          pending++;
        case _PayBucket.clear:
          clear++;
      }
    }
    return (dp: dp, pending: pending, clear: clear);
  }

  List<Map<String, dynamic>> get _filteredBucketList {
    final q = _search.trim().toLowerCase();
    return branchSales.where((s) {
      if (bucketOf(s) != _bucket) return false;
      if (q.isEmpty) return true;
      final inv = (s['no_invoice'] ?? '').toString().toLowerCase();
      final nama = (s['nama_pelanggan'] ?? '').toString().toLowerCase();
      final wa = (s['no_wa'] ?? '').toString().toLowerCase();
      return inv.contains(q) || nama.contains(q) || wa.contains(q);
    }).toList();
  }

  String get _staffNik {
    final nik = (widget.profile['nik'] ?? widget.profile['id'] ?? 'ADMIN')
        .toString()
        .trim();
    return nik.isEmpty ? 'ADMIN' : nik;
  }

  String get _staffNama {
    final n = (widget.profile['nama'] ?? 'Admin').toString().trim();
    return n.isEmpty ? 'Admin' : n;
  }

  Future<String?> _pickMetode(int sisa) async {
    var metode = 'Tunai';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              title: const Text(
                'Pelunasan DP',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Bayar sisa: ${formatRupiah(sisa)}\n'
                    'Setelah lunas → langsung CLEAR (LUNAS ready).',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      height: 1.4,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: metode,
                    dropdownColor: OptikAdminTokens.card,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Metode bayar',
                      labelStyle:
                          TextStyle(color: Colors.white.withOpacity(0.55)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Tunai', child: Text('Tunai')),
                      DropdownMenuItem(value: 'Debit', child: Text('Debit')),
                      DropdownMenuItem(
                          value: 'Transfer', child: Text('Transfer')),
                      DropdownMenuItem(value: 'QRIS', child: Text('QRIS')),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => metode = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal', style: TextStyle(color: Colors.grey)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, metode),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8C872),
                    foregroundColor: const Color(0xFF0F172A),
                  ),
                  child: const Text('Lunasi'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _dpQrIssued(Map<String, dynamic> trx) {
    final t = (trx['tracking_status'] ?? '').toString().toUpperCase();
    final token = (trx['qr_dp_token'] ?? '').toString().trim();
    return t == 'SIAP_PELUNASAN' || token.length >= 8;
  }

  Future<void> _lunasiDp(Map<String, dynamic> trx) async {
    if (_busy) return;
    final saleId = trx['id']?.toString();
    if (saleId == null) return;
    final sisa = int.tryParse(trx['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final metode = await _pickMetode(sisa);
    if (metode == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final wasReady = _dpQrIssued(trx);
      final updated = await _lifecycle.settleDpByAdmin(
        saleId: saleId,
        metodePembayaran: metode,
        staffNik: _staffNik,
        staffNama: _staffNama,
      );
      final delivered = await _delivery.deliver(
        sale: updated,
        mode: wasReady
            ? InvoiceDeliveryMode.withQr
            : InvoiceDeliveryMode.paymentConfirm,
      );
      if (!mounted) return;
      final tracking =
          (updated['tracking_status'] ?? '').toString().toUpperCase();
      final toClear = tracking == 'SIAP_DIAMBIL' || tracking == 'CLEAR';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${toClear ? 'Pelunasan OK · CLEAR' : 'Pelunasan OK · PENDING'}. '
            '${delivered.summary}',
          ),
          backgroundColor: delivered.anyOk || delivered.allRequestedOk
              ? const Color(0xFF0F766E)
              : Colors.orange.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
      await _fetchDataTransaksiPerCabang(selectedTokoId!);
      setState(
          () => _bucket = toClear ? _PayBucket.clear : _PayBucket.pending);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _konfirmasiBarangReady(Map<String, dynamic> trx) async {
    if (_busy) return;
    final saleId = trx['id']?.toString();
    if (saleId == null) return;
    final dpRow = isDp(trx);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text(
          'Pesanan sudah siap diambil',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          dpRow
              ? 'Nota ${trx['no_invoice']} · ${trx['nama_pelanggan'] ?? '-'}\n\n'
                  'Kirim pesan pelunasan + pengambilan + nota + QR pelunasan '
                  'ke email, WA, dan APK Member?'
              : 'Nota ${trx['no_invoice']} · ${trx['nama_pelanggan'] ?? '-'}\n\n'
                  'Kirim pesan “sudah bisa diambil” + nota + QR pengambilan '
                  '(aktifkan garansi saat serah terima) ke email, WA, Member?',
          style: TextStyle(
            color: Colors.white.withOpacity(0.78),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE8C872),
              foregroundColor: const Color(0xFF0F172A),
            ),
            child: const Text('Ya, barang ready — kirim'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final updated = await _lifecycle.markGoodsReadyAndIssueCustomerQr(
        saleId: saleId,
        staffNik: _staffNik,
        staffNama: _staffNama,
      );
      final delivered = await _delivery.deliver(
        sale: updated,
        mode: InvoiceDeliveryMode.goodsReady,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Barang ready · ${updated['no_invoice']}. ${delivered.summary}',
          ),
          backgroundColor: delivered.anyOk || delivered.allRequestedOk
              ? const Color(0xFF0F766E)
              : Colors.orange.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
      await _fetchDataTransaksiPerCabang(selectedTokoId!);
      if (!dpRow) setState(() => _bucket = _PayBucket.clear);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openDetail(Map<String, dynamic> trx) {
    final id = trx['id']?.toString();
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailPage(saleId: id)),
    );
  }

  // ==========================================================================
  // STAGE 1 — pilih cabang
  // ==========================================================================

  Widget _buildStage1LayarCabang() {
    if (listCabangUnik.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada transaksi di cabang mana pun.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: listCabangUnik.length,
      itemBuilder: (context, index) {
        final tokoId = listCabangUnik[index];
        final c = _counts(_salesForToko(tokoId));
        return PremiumListTile(
          title: tokoId == 'PUSAT'
              ? 'OPTIK B. RISKI - PUSAT'
              : 'OPTIK B. RISKI - $tokoId',
          subtitle: 'DP ${c.dp} · PENDING ${c.pending} · CLEAR ${c.clear}',
          icon: Icons.store_rounded,
          iconColor: Colors.blueAccent,
          onTap: () {
            setState(() {
              selectedTokoId = tokoId;
              _bucket = _PayBucket.dp;
              _search = '';
            });
            _fetchDataTransaksiPerCabang(tokoId);
          },
        );
      },
    );
  }

  // ==========================================================================
  // STAGE 2 — board DP / PENDING / CLEAR
  // ==========================================================================

  Widget _buildBoard() {
    final c = _counts(branchSales);
    final list = _filteredBucketList;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_PayBucket>(
                segments: [
                  ButtonSegment(
                    value: _PayBucket.dp,
                    label: Text('DP (${c.dp})'),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: _PayBucket.pending,
                    label: Text('PENDING (${c.pending})'),
                    icon: const Icon(Icons.hourglass_top_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: _PayBucket.clear,
                    label: Text('CLEAR (${c.clear})'),
                    icon: const Icon(Icons.verified_outlined, size: 16),
                  ),
                ],
                selected: {_bucket},
                onSelectionChanged: (s) {
                  setState(() {
                    _bucket = s.first;
                    _search = '';
                  });
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFFE8C872).withOpacity(0.22);
                    }
                    return Colors.white.withOpacity(0.04);
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFFE8C872);
                    }
                    return Colors.white70;
                  }),
                  side: WidgetStateProperty.all(
                    BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _bucketHint,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Cari invoice / nama / WA…',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                  prefixIcon: Icon(Icons.search,
                      color: Colors.white.withOpacity(0.45), size: 20),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    _emptyHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _saleCard(list[i]),
                ),
        ),
      ],
    );
  }

  String get _bucketHint {
    switch (_bucket) {
      case _PayBucket.dp:
        return 'DP — setelah bayar hanya konfirmasi + nota (tanpa QR). '
            'Barang Ready → kirim QR pelunasan. Lunasi bisa dari sini.';
      case _PayBucket.pending:
        return 'PENDING — sudah lunas, barang belum ready (tanpa QR). '
            'Barang Ready → kirim QR pengambilan.';
      case _PayBucket.clear:
        return 'CLEAR — clear payment & history (siap diambil / selesai).';
    }
  }

  String get _emptyHint {
    switch (_bucket) {
      case _PayBucket.dp:
        return 'Tidak ada nota DP.';
      case _PayBucket.pending:
        return 'Tidak ada nota PENDING.';
      case _PayBucket.clear:
        return 'Belum ada CLEAR / history.';
    }
  }

  Widget _saleCard(Map<String, dynamic> trx) {
    final total = int.tryParse(trx['total_harga']?.toString() ?? '0') ?? 0;
    final sisa = int.tryParse(trx['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final dibayar = int.tryParse(trx['dibayarkan']?.toString() ?? '0') ??
        (total - sisa);
    final tracking =
        (trx['tracking_status'] ?? '-').toString().toUpperCase();
    final created = (trx['created_at'] ?? '').toString();
    final tgl = created.length >= 10 ? created.substring(0, 10) : created;

    return PremiumPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trx['no_invoice']?.toString() ?? '-',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              _bucketBadge(_bucket),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            trx['nama_pelanggan']?.toString() ?? 'Tanpa nama',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Total ${formatRupiah(total)} · Dibayar ${formatRupiah(dibayar)}'
            '${sisa > 0 ? ' · Sisa ${formatRupiah(sisa)}' : ''}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 11.5,
            ),
          ),
          Text(
            '$tgl · Tracking $tracking · Kasir ${trx['nama_kasir'] ?? '-'}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _openDetail(trx),
                icon: const Icon(Icons.receipt_long, size: 16),
                label: const Text('Nota'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blueAccent,
                  side: BorderSide(color: Colors.blueAccent.withOpacity(0.45)),
                ),
              ),
              if (_bucket == _PayBucket.dp || _bucket == _PayBucket.pending)
                FilledButton.icon(
                  onPressed: _busy ||
                          (_bucket == _PayBucket.dp && _dpQrIssued(trx))
                      ? null
                      : () => _konfirmasiBarangReady(trx),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    _bucket == _PayBucket.dp && _dpQrIssued(trx)
                        ? 'QR pelunasan terkirim'
                        : 'Barang Ready',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8C872),
                    foregroundColor: const Color(0xFF0F172A),
                  ),
                ),
              if (_bucket == _PayBucket.dp)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _lunasiDp(trx),
                  icon: const Icon(Icons.paid_outlined, size: 16),
                  label: const Text('Lunasi'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.tealAccent.withOpacity(0.85),
                    foregroundColor: const Color(0xFF0F172A),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bucketBadge(_PayBucket b) {
    late final String label;
    late final Color color;
    switch (b) {
      case _PayBucket.dp:
        label = 'DP';
        color = Colors.orangeAccent;
      case _PayBucket.pending:
        label = 'PENDING';
        color = const Color(0xFFE8C872);
      case _PayBucket.clear:
        label = 'CLEAR';
        color = Colors.greenAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = selectedTokoId == null
        ? 'DP · PENDING · CLEAR'
        : '${selectedTokoId!} · DP · PENDING · CLEAR';

    return PremiumScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: OptikAdminTokens.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          onPressed: () {
            if (selectedTokoId != null && _isOwnerOrPusat) {
              setState(() {
                selectedTokoId = null;
                _search = '';
              });
              _fetchSeluruhDataTransaksiOwner();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        actions: [
          if (selectedTokoId != null)
            IconButton(
              tooltip: 'Refresh',
              onPressed: isLoading || _busy
                  ? null
                  : () => _fetchDataTransaksiPerCabang(selectedTokoId!),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            )
          : selectedTokoId == null
              ? _buildStage1LayarCabang()
              : _buildBoard(),
    );
  }
}
