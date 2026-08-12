import '../invoice/invoice_hub_service.dart';

/// Baris hasil merge nota toko + pesanan online (Status / Riwayat).
class MemberOrderMergeRow {
  MemberOrderMergeRow.sale(Map<String, dynamic> data)
      : sale = data,
        online = null,
        sortAt = DateTime.tryParse('${data['created_at']}') ??
            DateTime.fromMillisecondsSinceEpoch(0);

  MemberOrderMergeRow.online(Map<String, dynamic> data)
      : online = data,
        sale = null,
        sortAt = DateTime.tryParse('${data['created_at']}') ??
            DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, dynamic>? sale;
  final Map<String, dynamic>? online;
  final DateTime sortAt;

  bool get isOnline => online != null;
}

/// Filter + merge untuk tab Status pesanan (active) vs Riwayat.
///
/// Dedupe online↔sale hanya terhadap baris yang **masuk list** (bukan seluruh
/// sales), supaya online aktif tidak hilang bila nota linked sudah diambil /
/// batal dan ter-filter dari Status.
class MemberOrdersStatus {
  MemberOrdersStatus._();

  static bool isCancelledSale(Map<String, dynamic> sale) {
    final t = (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    final pay =
        (sale['status_pembayaran'] ?? '').toString().trim().toUpperCase();
    return t == 'BATAL_VOUCHER' ||
        t == 'BATAL' ||
        t == 'CANCELLED' ||
        pay == 'BATAL';
  }

  /// Nota masih di Status: belum diambil, belum batal.
  static bool isActiveSale(Map<String, dynamic> sale) {
    if (InvoiceHubService.sudahDiambil(sale)) return false;
    if (isCancelledSale(sale)) return false;
    return true;
  }

  /// Online masih di Status: belum selesai / batal / kedaluwarsa.
  static bool isActiveOnline(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().trim().toLowerCase();
    return status != 'fulfilled' &&
        status != 'cancelled' &&
        status != 'expired';
  }

  /// Badge bayar di list kartu. Null bila tidak relevan (batal).
  static String? payBadge(Map<String, dynamic> sale) {
    if (isCancelledSale(sale)) return null;
    return InvoiceHubService.isDpOpen(sale) ? 'DP' : 'LUNAS';
  }

  /// Merge sales + online. [onlyActive] = membership tab Status pesanan.
  /// [onlyActive] false = Riwayat belanja: **semua** transaksi (termasuk aktif).
  static List<MemberOrderMergeRow> merge({
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> online,
    bool onlyActive = false,
  }) {
    final rows = <MemberOrderMergeRow>[];
    final includedSaleIds = <String>{};
    final includedSaleOnlineIds = <String>{};

    for (final s in sales) {
      if (onlyActive && !isActiveSale(s)) continue;
      final sid = (s['id'] ?? '').toString();
      if (sid.isNotEmpty) includedSaleIds.add(sid);
      final oid = (s['online_order_id'] ?? '').toString();
      if (oid.isNotEmpty) includedSaleOnlineIds.add(oid);
      rows.add(MemberOrderMergeRow.sale(s));
    }

    for (final o in online) {
      final id = (o['id'] ?? '').toString();
      final saleId = (o['sale_id'] ?? '').toString();
      // Sudah punya nota di list → jangan dobel kartu online.
      if (id.isNotEmpty && includedSaleOnlineIds.contains(id)) continue;
      if (saleId.isNotEmpty && includedSaleIds.contains(saleId)) continue;
      if (onlyActive && !isActiveOnline(o)) continue;
      rows.add(MemberOrderMergeRow.online(o));
    }

    rows.sort((a, b) => b.sortAt.compareTo(a.sortAt));
    return rows;
  }
}
