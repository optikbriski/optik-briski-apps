// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../shared/invoice/invoice_delivery_result.dart';
import '../../shared/invoice/invoice_delivery_service.dart';
import '../../shared/invoice/invoice_detail_page.dart';
import '../../shared/invoice/invoice_lifecycle_service.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Board admin: DP · PENDING · READY · CLEAR (tanpa scan QR).
/// - DP: sisa tagihan / down payment → aksi Lunasi / Barang Ready
/// - PENDING: lunas, barang belum siap → aksi Barang Ready
/// - READY: barang siap, menunggu pengambilan (DB: SIAP_DIAMBIL)
/// - CLEAR: sudah serah terima (DB: DIAMBIL) · Garansi aktif / mati
class RiwayatTransaksiPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RiwayatTransaksiPage({super.key, required this.profile});

  @override
  State<RiwayatTransaksiPage> createState() => _RiwayatTransaksiPageState();
}

enum _PayBucket { dp, pending, ready, clear }

class _RiwayatTransaksiPageState extends State<RiwayatTransaksiPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final _lifecycle = InvoiceLifecycleService();
  final _delivery = InvoiceDeliveryService();

  bool isLoading = true;
  bool _busy = false;
  String? selectedTokoId;
  /// Kategori aktif di 1 page board (chip → list di bawah).
  _PayBucket _selectedBucket = _PayBucket.dp;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> allSalesRaw = [];
  List<String> listCabangUnik = [];
  List<Map<String, dynamic>> branchSales = [];
  /// sale_id → true = Garansi aktif, false = Garansi mati (hanya CLEAR).
  Map<String, bool> _garansiAktifBySaleId = {};

  String get _search => _searchCtrl.text;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _inisialisasiHakAksesAplikasi();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearSearch() {
    if (_searchCtrl.text.isEmpty) return;
    _searchCtrl.clear();
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

  /// [silent] = refresh tanpa full-page loader (tetap di page kategori).
  Future<bool> _fetchDataTransaksiPerCabang(
    String tokoId, {
    bool silent = false,
  }) async {
    if (!mounted) return false;
    if (!silent) setState(() => isLoading = true);
    try {
      final res = await supabase
          .from('sales')
          .select()
          .eq('toko_id', tokoId)
          .order('created_at', ascending: false);
      final data = List<Map<String, dynamic>>.from(res);
      final garansiMap = await _loadGaransiAktifMap(data);
      if (!mounted) return false;
      setState(() {
        branchSales = data;
        _garansiAktifBySaleId = garansiMap;
        isLoading = false;
      });
      return true;
    } catch (e) {
      _fail('Gagal muat transaksi cabang: $e');
      return false;
    }
  }

  /// CLEAR saja: true = masih ada kartu klaimable, false = mati.
  Future<Map<String, bool>> _loadGaransiAktifMap(
    List<Map<String, dynamic>> sales,
  ) async {
    final clearIds = sales
        .where(isClear)
        .map((s) => s['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    final out = <String, bool>{for (final id in clearIds) id: false};
    if (clearIds.isEmpty) return out;

    for (final s in sales.where(isClear)) {
      final id = s['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (s['qr_claim_used_at'] != null) out[id] = false;
    }

    try {
      final rows = await supabase
          .from('garansi_kartu')
          .select('sale_id, status, klaim_digunakan, tanggal_akhir')
          .inFilter('sale_id', clearIds);
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      for (final raw in rows as List) {
        final g = Map<String, dynamic>.from(raw as Map);
        final sid = g['sale_id']?.toString() ?? '';
        if (sid.isEmpty || !out.containsKey(sid)) continue;
        // CLAIM QR sudah dipakai → mati.
        final sale = sales.firstWhere(
          (s) => s['id']?.toString() == sid,
          orElse: () => <String, dynamic>{},
        );
        if (sale['qr_claim_used_at'] != null) {
          out[sid] = false;
          continue;
        }
        if (g['status']?.toString() != 'aktif') continue;
        if (g['klaim_digunakan'] == true) continue;
        final akhir = DateTime.tryParse(g['tanggal_akhir']?.toString() ?? '');
        if (akhir == null) continue;
        final end = DateTime(akhir.year, akhir.month, akhir.day);
        if (!end.isBefore(today)) out[sid] = true;
      }
    } catch (_) {
      // Chip default mati jika query gagal — list tetap tampil.
    }
    return out;
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: OptikAdminTokens.danger),
    );
  }

  // --- Klasifikasi: DP / PENDING / READY / CLEAR ---

  static bool isDp(Map<String, dynamic> sale) {
    final pay = (sale['status_pembayaran'] ?? '').toString().toUpperCase();
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    return pay == 'DP' || sisa > 0;
  }

  static bool isClear(Map<String, dynamic> sale) {
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    return sale['diambil_at'] != null || tracking == 'DIAMBIL';
  }

  static bool isReady(Map<String, dynamic> sale) {
    if (isDp(sale) || isClear(sale)) return false;
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    return tracking == 'SIAP_DIAMBIL' || tracking == 'CLEAR';
  }

  static bool isPending(Map<String, dynamic> sale) {
    if (isDp(sale) || isClear(sale) || isReady(sale)) return false;
    return true;
  }

  static _PayBucket bucketOf(Map<String, dynamic> sale) {
    if (isDp(sale)) return _PayBucket.dp;
    if (isClear(sale)) return _PayBucket.clear;
    if (isReady(sale)) return _PayBucket.ready;
    if (isPending(sale)) return _PayBucket.pending;
    return _PayBucket.pending;
  }

  List<Map<String, dynamic>> _salesForToko(String tokoId) {
    return allSalesRaw
        .where((e) =>
            (e['toko_id']?.toString().toUpperCase() ?? 'PUSAT') == tokoId)
        .toList();
  }

  ({int dp, int pending, int ready, int clear}) _counts(
    List<Map<String, dynamic>> list,
  ) {
    var dp = 0, pending = 0, ready = 0, clear = 0;
    for (final s in list) {
      switch (bucketOf(s)) {
        case _PayBucket.dp:
          dp++;
        case _PayBucket.pending:
          pending++;
        case _PayBucket.ready:
          ready++;
        case _PayBucket.clear:
          clear++;
      }
    }
    return (dp: dp, pending: pending, ready: ready, clear: clear);
  }

  List<Map<String, dynamic>> _listForBucket(_PayBucket b) {
    final q = _search.trim().toLowerCase();
    return branchSales.where((s) {
      if (bucketOf(s) != b) return false;
      if (q.isEmpty) return true;
      final inv = (s['no_invoice'] ?? '').toString().toLowerCase();
      final nama = (s['nama_pelanggan'] ?? '').toString().toLowerCase();
      final wa = (s['no_wa'] ?? '').toString().toLowerCase();
      return inv.contains(q) || nama.contains(q) || wa.contains(q);
    }).toList();
  }

  void _selectBucket(_PayBucket b) {
    // Jangan hapus filter kalau chip yang sama di-tap ulang / resend READY.
    if (_selectedBucket == b) return;
    _clearSearch();
    setState(() => _selectedBucket = b);
  }

  String _bucketTitle(_PayBucket b) => switch (b) {
        _PayBucket.dp => 'DP',
        _PayBucket.pending => 'PENDING',
        _PayBucket.ready => 'READY',
        _PayBucket.clear => 'CLEAR',
      };

  String _bucketHint(_PayBucket b) => switch (b) {
        _PayBucket.dp =>
          'Belum lunas. Barang Ready → QR pelunasan · Lunasi dari sini.',
        _PayBucket.pending =>
          'Sudah lunas, menunggu Barang Ready → READY + QR pengambilan.',
        _PayBucket.ready =>
          'Barang siap · menunggu pengambilan (scan QR LUNAS).',
        _PayBucket.clear =>
          'Serah terima selesai · status Garansi aktif / Garansi mati.',
      };

  String _bucketEmpty(_PayBucket b) => switch (b) {
        _PayBucket.dp => 'Tidak ada nota DP.',
        _PayBucket.pending => 'Tidak ada nota PENDING.',
        _PayBucket.ready => 'Tidak ada nota READY.',
        _PayBucket.clear => 'Belum ada CLEAR (serah terima).',
      };

  Color _bucketColor(_PayBucket b) => switch (b) {
        _PayBucket.dp => OptikAdminTokens.warning,
        _PayBucket.pending => OptikAdminTokens.trainingSoft,
        _PayBucket.ready => OptikAdminTokens.navy,
        _PayBucket.clear => OptikAdminTokens.success,
      };

  IconData _bucketIcon(_PayBucket b) => switch (b) {
        _PayBucket.dp => Icons.payments_outlined,
        _PayBucket.pending => Icons.hourglass_top_rounded,
        _PayBucket.ready => Icons.inventory_2_outlined,
        _PayBucket.clear => Icons.verified_outlined,
      };

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

  Future<String?> _pickMetode(int sisa, {bool alreadyReady = false}) async {
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
                style: TextStyle(color: OptikAdminTokens.navy, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    alreadyReady
                        ? 'Bayar sisa: ${formatRupiah(sisa)}\n'
                            'Barang sudah ready → setelah lunas langsung READY '
                            '(QR pengambilan dikirim).'
                        : 'Bayar sisa: ${formatRupiah(sisa)}\n'
                            'Barang belum ready → setelah lunas masuk PENDING. '
                            'QR pengambilan muncul setelah admin Barang Ready.',
                    style: TextStyle(
                      color: OptikAdminTokens.navy.withOpacity(0.75),
                      height: 1.4,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AdminPickerField(
                    label: 'Metode bayar',
                    valueText: metode,
                    icon: Icons.payments_outlined,
                    onTap: () async {
                      const options = [
                        AdminPickerOption(
                          value: 'Tunai',
                          label: 'Tunai',
                          icon: Icons.payments_outlined,
                        ),
                        AdminPickerOption(
                          value: 'Debit',
                          label: 'Debit',
                          icon: Icons.credit_card_outlined,
                        ),
                        AdminPickerOption(
                          value: 'Transfer',
                          label: 'Transfer',
                          icon: Icons.account_balance_outlined,
                        ),
                        AdminPickerOption(
                          value: 'QRIS',
                          label: 'QRIS',
                          icon: Icons.qr_code_rounded,
                        ),
                      ];
                      final sel = await showAdminPicker<String>(
                        context: ctx,
                        title: 'Metode bayar',
                        selected: metode,
                        searchable: false,
                        options: options,
                      );
                      if (sel == null || sel.isClear) return;
                      setLocal(() => metode = sel.value!);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal', style: TextStyle(color: OptikAdminTokens.textMuted)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, metode),
                  style: FilledButton.styleFrom(
                    backgroundColor: OptikAdminTokens.trainingSoft,
                    foregroundColor: OptikAdminTokens.bgMid,
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
    // Selaras lifecycle: QR DP hanya valid di SIAP_PELUNASAN.
    return t == 'SIAP_PELUNASAN';
  }

  Future<void> _lunasiDp(Map<String, dynamic> trx) async {
    if (_busy) return;
    final saleId = trx['id']?.toString();
    if (saleId == null) return;
    final sisa = int.tryParse(trx['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final wasReady = _dpQrIssued(trx);
    final metode = await _pickMetode(sisa, alreadyReady: wasReady);
    if (metode == null || !mounted) return;

    final toko = selectedTokoId;
    if (toko == null) {
      _fail('Cabang belum dipilih — buka ulang dari daftar cabang.');
      return;
    }

    setState(() => _busy = true);
    try {
      final updated = await _lifecycle.settleDpByAdmin(
        saleId: saleId,
        metodePembayaran: metode,
        staffNik: _staffNik,
        staffNama: _staffNama,
      );
      InvoiceDeliveryResult? delivered;
      try {
        delivered = await _delivery.deliver(
          sale: updated,
          mode: wasReady
              ? InvoiceDeliveryMode.withQr
              : InvoiceDeliveryMode.paymentConfirm,
        );
      } catch (_) {
        delivered = null;
      }
      if (!mounted) return;
      final tracking =
          (updated['tracking_status'] ?? '').toString().toUpperCase();
      final toReady = tracking == 'SIAP_DIAMBIL' || tracking == 'CLEAR';
      final next = toReady ? _PayBucket.ready : _PayBucket.pending;
      final okRefresh = await _fetchDataTransaksiPerCabang(toko, silent: true);
      if (!mounted) return;
      if (okRefresh) _selectBucket(next);
      final refreshNote = okRefresh
          ? ''
          : ' List belum ter-refresh — tarik Refresh.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${toReady ? 'Pelunasan OK · READY' : 'Pelunasan OK · PENDING'}. '
            '${delivered?.summary ?? 'Email/WA gagal — status DB sudah di-update.'}'
            '$refreshNote',
          ),
          backgroundColor: delivered == null
              ? OptikAdminTokens.warning
              : (delivered.anyOk || delivered.allRequestedOk
                  ? OptikAdminTokens.slate
                  : OptikAdminTokens.warning),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _konfirmasiBarangReady(Map<String, dynamic> trx) async {
    if (_busy) return;
    final saleId = trx['id']?.toString();
    if (saleId == null) return;
    final toko = selectedTokoId;
    if (toko == null) {
      _fail('Cabang belum dipilih — buka ulang dari daftar cabang.');
      return;
    }
    final dpRow = isDp(trx);
    final resendReady = bucketOf(trx) == _PayBucket.ready;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: Text(
          resendReady
              ? 'Kirim ulang QR pengambilan'
              : 'Pesanan sudah siap diambil',
          style: const TextStyle(color: OptikAdminTokens.navy, fontSize: 16),
        ),
        content: Text(
          resendReady
              ? 'Nota ${trx['no_invoice']} · ${trx['nama_pelanggan'] ?? '-'}\n\n'
                  'Kirim ulang QR pengambilan (READY) ke email, WA, Member?\n'
                  'Email/WA boleh gagal — QR tetap valid di sistem.'
              : dpRow
                  ? 'Nota ${trx['no_invoice']} · ${trx['nama_pelanggan'] ?? '-'}\n\n'
                      'Kirim pesan pelunasan + pengambilan + nota + QR pelunasan '
                      'ke email, WA, dan APK Member?'
                  : 'Nota ${trx['no_invoice']} · ${trx['nama_pelanggan'] ?? '-'}\n\n'
                      'Kirim pesan “sudah bisa diambil” + nota + QR pengambilan '
                      '(aktifkan garansi saat serah terima) ke email, WA, Member?',
          style: TextStyle(
            color: OptikAdminTokens.navy.withOpacity(0.78),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal',
                style: TextStyle(color: OptikAdminTokens.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.trainingSoft,
              foregroundColor: OptikAdminTokens.bgMid,
            ),
            child: Text(resendReady ? 'Ya, kirim ulang' : 'Ya, barang ready — kirim'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final invNo = trx['no_invoice']?.toString() ?? saleId;
      final updated = await _lifecycle.markGoodsReadyAndIssueCustomerQr(
        saleId: saleId,
        staffNik: _staffNik,
        staffNama: _staffNama,
      );
      InvoiceDeliveryResult? delivered;
      try {
        delivered = await _delivery.deliver(
          sale: updated,
          mode: InvoiceDeliveryMode.goodsReady,
        );
      } catch (_) {
        delivered = null;
      }
      if (!mounted) return;
      // Hanya 1 nota — pindah chip ke kategori tujuan setelah refresh sukses.
      final nextBucket = bucketOf(Map<String, dynamic>.from(updated));
      final okRefresh = await _fetchDataTransaksiPerCabang(toko, silent: true);
      if (!mounted) return;
      final c = _counts(branchSales);
      final othersHint = nextBucket == _PayBucket.ready && c.ready > 1
          ? '\n$invNo masuk READY. Total READY: ${c.ready} '
              '(nota lain sudah READY sebelumnya, bukan ikut di-update).'
          : '';
      if (okRefresh) _selectBucket(nextBucket);
      final refreshNote = okRefresh
          ? ''
          : '\nList belum ter-refresh — tarik Refresh.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resendReady
                ? 'QR pengambilan di-refresh untuk $invNo.\n'
                    '${delivered?.summary ?? 'Email/WA gagal — QR tetap valid.'}'
                    '$refreshNote'
                : 'Hanya nota $invNo yang di-update'
                    '${dpRow ? ' → siap pelunasan (DP)' : ' → READY'}.\n'
                    '${delivered?.summary ?? 'Email/WA gagal — status DB sudah di-update.'}'
                    '$othersHint'
                    '$refreshNote',
          ),
          backgroundColor: delivered == null
              ? OptikAdminTokens.warning
              : (delivered.anyOk || delivered.allRequestedOk
                  ? OptikAdminTokens.slate
                  : OptikAdminTokens.warning),
          duration: const Duration(seconds: 7),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
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
          style: TextStyle(color: OptikAdminTokens.textMuted, fontSize: 12),
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
          title: BrandService.defaultShopName(tokoId),
          subtitle:
              'DP ${c.dp} · PENDING ${c.pending} · READY ${c.ready} · CLEAR ${c.clear}',
          icon: Icons.store_rounded,
          iconColor: OptikAdminTokens.navy,
          onTap: () {
            _clearSearch();
            setState(() {
              selectedTokoId = tokoId;
              _selectedBucket = _PayBucket.dp;
            });
            _fetchDataTransaksiPerCabang(tokoId);
          },
        );
      },
    );
  }

  // ==========================================================================
  // STAGE 2 — 1 page: chip kategori + list kategori yang dipilih
  // ==========================================================================

  Widget _buildBoard() {
    final c = _counts(branchSales);
    final bucket = _selectedBucket;
    final items = _listForBucket(bucket);
    final counts = {
      _PayBucket.dp: c.dp,
      _PayBucket.pending: c.pending,
      _PayBucket.ready: c.ready,
      _PayBucket.clear: c.clear,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (final b in _PayBucket.values) ...[
                    if (b != _PayBucket.dp) const SizedBox(width: 6),
                    Expanded(
                      child: _categoryChip(
                        bucket: b,
                        count: counts[b]!,
                        selected: bucket == b,
                        onTap: () => _selectBucket(b),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _bucketHint(bucket),
                style: TextStyle(
                  color: OptikAdminTokens.navy.withOpacity(0.5),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                style:
                    const TextStyle(color: OptikAdminTokens.navy, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Cari invoice / nama / WA…',
                  hintStyle: TextStyle(
                      color: OptikAdminTokens.navy.withOpacity(0.35)),
                  prefixIcon: Icon(Icons.search,
                      color: OptikAdminTokens.navy.withOpacity(0.45),
                      size: 20),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus',
                          onPressed: _clearSearch,
                          icon: Icon(Icons.close_rounded,
                              size: 18,
                              color: OptikAdminTokens.navy.withOpacity(0.45)),
                        ),
                  filled: true,
                  fillColor: OptikAdminTokens.snow.withOpacity(0.05),
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
          child: items.isEmpty
              ? Center(
                  child: Text(
                    _bucketEmpty(bucket),
                    style: const TextStyle(
                      color: OptikAdminTokens.textMuted,
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _saleCard(items[i]),
                ),
        ),
      ],
    );
  }

  Widget _categoryChip({
    required _PayBucket bucket,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = _bucketColor(bucket);
    return Material(
      color: selected ? color.withOpacity(0.22) : color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : color.withOpacity(0.25),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(_bucketIcon(bucket), size: 18, color: color),
              const SizedBox(height: 4),
              Text(
                _bucketTitle(bucket),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: OptikAdminTokens.navy.withOpacity(0.85),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saleCard(Map<String, dynamic> trx) {
    final bucket = bucketOf(trx);
    final total = int.tryParse(trx['total_harga']?.toString() ?? '0') ?? 0;
    final sisa = int.tryParse(trx['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final dibayar = int.tryParse(trx['dibayarkan']?.toString() ?? '0') ??
        (total - sisa);
    final tracking =
        (trx['tracking_status'] ?? '-').toString().toUpperCase();
    final created = (trx['created_at'] ?? '').toString();
    final tgl = created.length >= 10 ? created.substring(0, 10) : created;
    final isOnline =
        (trx['channel'] ?? '').toString().toLowerCase() == 'member_online' ||
            (trx['no_invoice'] ?? '').toString().toUpperCase().startsWith('ON-');

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
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (isOnline) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: OptikAdminTokens.ice.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: OptikAdminTokens.navy.withOpacity(0.25),
                    ),
                  ),
                  child: const Text(
                    'ONLINE',
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              _bucketBadge(bucket),
              if (bucket == _PayBucket.clear) ...[
                const SizedBox(width: 6),
                _garansiChip(trx),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            trx['nama_pelanggan']?.toString() ?? 'Tanpa nama',
            style: const TextStyle(
                color: OptikAdminTokens.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Total ${formatRupiah(total)} · Dibayar ${formatRupiah(dibayar)}'
            '${sisa > 0 ? ' · Sisa ${formatRupiah(sisa)}' : ''}',
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.55),
              fontSize: 11.5,
            ),
          ),
          Text(
            '$tgl · Tracking $tracking · '
            '${isOnline ? 'Member App' : 'Kasir ${trx['nama_kasir'] ?? '-'}'}'
            '${isOnline && (trx['fulfillment'] ?? '').toString().isNotEmpty ? ' · ${trx['fulfillment']}' : ''}',
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.4),
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
                  foregroundColor: OptikAdminTokens.navy,
                  side: BorderSide(
                      color: OptikAdminTokens.accentSoft.withOpacity(0.45)),
                ),
              ),
              if (bucket == _PayBucket.dp || bucket == _PayBucket.pending)
                FilledButton.icon(
                  onPressed:
                      _busy ? null : () => _konfirmasiBarangReady(trx),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    bucket == _PayBucket.dp && _dpQrIssued(trx)
                        ? 'Kirim ulang QR pelunasan'
                        : bucket == _PayBucket.pending
                            ? 'Barang Ready · READY'
                            : 'Barang Ready',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: OptikAdminTokens.trainingSoft,
                    foregroundColor: OptikAdminTokens.bgMid,
                  ),
                ),
              if (bucket == _PayBucket.ready)
                FilledButton.icon(
                  onPressed:
                      _busy ? null : () => _konfirmasiBarangReady(trx),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                  label: const Text('Kirim ulang QR pengambilan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: OptikAdminTokens.navy,
                    foregroundColor: OptikAdminTokens.snow,
                  ),
                ),
              if (bucket == _PayBucket.dp)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _lunasiDp(trx),
                  icon: const Icon(Icons.paid_outlined, size: 16),
                  label: const Text('Lunasi'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        OptikAdminTokens.accentSoft.withOpacity(0.85),
                    foregroundColor: OptikAdminTokens.bgMid,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _garansiChip(Map<String, dynamic> trx) {
    final id = trx['id']?.toString() ?? '';
    final aktif = _garansiAktifBySaleId[id] == true;
    final color =
        aktif ? OptikAdminTokens.success : OptikAdminTokens.textMuted;
    final label = aktif ? 'Garansi aktif' : 'Garansi mati';
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

  Widget _bucketBadge(_PayBucket b) {
    late final String label;
    late final Color color;
    switch (b) {
      case _PayBucket.dp:
        label = 'DP';
        color = OptikAdminTokens.warning;
      case _PayBucket.pending:
        label = 'PENDING';
        color = OptikAdminTokens.trainingSoft;
      case _PayBucket.ready:
        label = 'READY';
        color = OptikAdminTokens.navy;
      case _PayBucket.clear:
        label = 'CLEAR';
        color = OptikAdminTokens.success;
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

  bool _handleBack() {
    if (selectedTokoId != null && _isOwnerOrPusat) {
      FocusManager.instance.primaryFocus?.unfocus();
      _clearSearch();
      setState(() {
        selectedTokoId = null;
        _selectedBucket = _PayBucket.dp;
      });
      _fetchSeluruhDataTransaksiOwner();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final title = selectedTokoId == null
        ? 'DP · PENDING · READY · CLEAR'
        : '${selectedTokoId!} · ${_bucketTitle(_selectedBucket)}';

    return PopScope(
      canPop: selectedTokoId == null || !_isOwnerOrPusat,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: PremiumScaffold(
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: OptikAdminTokens.textPrimary),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back,
                color: OptikAdminTokens.navy, size: 20),
            onPressed: () {
              if (!_handleBack()) Navigator.pop(context);
            },
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: OptikAdminTokens.navy,
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
                    : () => _fetchDataTransaksiPerCabang(
                          selectedTokoId!,
                          silent: true,
                        ),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
          ],
        ),
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: OptikAdminTokens.ice),
              )
            : selectedTokoId == null
                ? _buildStage1LayarCabang()
                : _buildBoard(),
      ),
    );
  }
}
