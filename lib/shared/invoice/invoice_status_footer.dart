import 'dart:convert';

/// Footer nota otomatis per status board: DP · PENDING · READY · CLEAR.
/// Klasifikasi selaras [RiwayatTransaksiPage] agar tidak tertukar.
enum InvoiceFooterStatus { dp, pending, ready, clear }

/// Empat teks footer yang bisa di-adjust per status (disimpan di `footer_text` JSON).
///
/// [inheritFromPusat] = true → cabang memakai footer PUSAT (awal wajib sama).
/// Setelah di-adjust & disimpan di cabang, flag jadi false.
class InvoiceStatusFooters {
  const InvoiceStatusFooters({
    required this.dp,
    required this.pending,
    required this.ready,
    required this.clear,
    this.inheritFromPusat = false,
  });

  final String dp;
  final String pending;
  final String ready;
  final String clear;
  final bool inheritFromPusat;

  factory InvoiceStatusFooters.defaults({bool inheritFromPusat = false}) =>
      InvoiceStatusFooters(
        dp: InvoiceStatusFooter.dpDefault,
        pending: InvoiceStatusFooter.pendingDefault,
        ready: InvoiceStatusFooter.readyDefault,
        clear: InvoiceStatusFooter.clearDefault,
        inheritFromPusat: inheritFromPusat,
      );

  /// Salin teks dari pack lain, tandai sebagai ikut Pusat.
  factory InvoiceStatusFooters.inheritedFrom(InvoiceStatusFooters pusat) =>
      InvoiceStatusFooters(
        dp: pusat.dp,
        pending: pusat.pending,
        ready: pusat.ready,
        clear: pusat.clear,
        inheritFromPusat: true,
      );

  String of(InvoiceFooterStatus status) {
    switch (status) {
      case InvoiceFooterStatus.dp:
        return dp.trim();
      case InvoiceFooterStatus.pending:
        return pending.trim();
      case InvoiceFooterStatus.ready:
        return ready.trim();
      case InvoiceFooterStatus.clear:
        return clear.trim();
    }
  }

  InvoiceStatusFooters copyWith({
    String? dp,
    String? pending,
    String? ready,
    String? clear,
    bool? inheritFromPusat,
  }) {
    return InvoiceStatusFooters(
      dp: dp ?? this.dp,
      pending: pending ?? this.pending,
      ready: ready ?? this.ready,
      clear: clear ?? this.clear,
      inheritFromPusat: inheritFromPusat ?? this.inheritFromPusat,
    );
  }

  InvoiceStatusFooters withStatus(InvoiceFooterStatus status, String text) {
    switch (status) {
      case InvoiceFooterStatus.dp:
        return copyWith(dp: text);
      case InvoiceFooterStatus.pending:
        return copyWith(pending: text);
      case InvoiceFooterStatus.ready:
        return copyWith(ready: text);
      case InvoiceFooterStatus.clear:
        return copyWith(clear: text);
    }
  }

  /// Edit lokal → lepas dari sync Pusat.
  InvoiceStatusFooters customized() => copyWith(inheritFromPusat: false);

  String encode() => jsonEncode({
        'v': 1,
        'dp': dp,
        'pending': pending,
        'ready': ready,
        'clear': clear,
        'inherit': inheritFromPusat,
      });

  /// Baca JSON status-footers, atau teks lama.
  factory InvoiceStatusFooters.decode(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) {
      return InvoiceStatusFooters.defaults(inheritFromPusat: true);
    }

    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          if (map.containsKey('dp') ||
              map.containsKey('pending') ||
              map.containsKey('ready') ||
              map.containsKey('clear')) {
            final d = InvoiceStatusFooters.defaults();
            return InvoiceStatusFooters(
              dp: (map['dp'] ?? d.dp).toString(),
              pending: (map['pending'] ?? d.pending).toString(),
              ready: (map['ready'] ?? d.ready).toString(),
              clear: (map['clear'] ?? d.clear).toString(),
              // Tanpa key inherit → sudah pernah disimpan sebagai pack kustom.
              inheritFromPusat: map['inherit'] == true,
            );
          }
        }
      } catch (_) {}
    }

    // Legacy single footer di cabang: awalnya ikut Pusat (bukan teks lama acak).
    return InvoiceStatusFooters.defaults(inheritFromPusat: true);
  }
}

abstract final class InvoiceStatusFooter {
  InvoiceStatusFooter._();

  static const dpDefault = '''
Terima kasih telah mempercayakan kebutuhan kacamata Anda kepada Optik B. Riski.
Uang muka (DP) sudah kami catat. Sisa tagihan dilunasi saat pengambilan barang.
Simpan nota & QR ini sebagai bukti identitas pesanan sampai barang diambil.''';

  static const pendingDefault = '''
Terima kasih atas kesabaran Anda sementara pesanan diproses di Optik B. Riski.
Barang belum siap diambil — QR pengambilan aktif setelah status Ready.
Pantau status lewat QR invoice, atau hubungi WhatsApp cabang bila perlu.''';

  static const readyDefault = '''
Terima kasih telah menunggu. Pesanan Anda di Optik B. Riski sudah Ready.
Silakan ambil di cabang dengan menunjukkan QR invoice; lunasi sisa tagihan jika ada.
Mohon cek frame & lensa di toko sebelum meninggalkan cabang.''';

  static const clearDefault = '''
Terima kasih atas kepercayaan penuh Anda hingga transaksi selesai di Optik B. Riski.
Nota ini bukti pengambilan barang — simpan untuk garansi, klaim, atau reorder resep yang sama.
Klaim garansi hanya diproses dengan membawa nota sesuai ketentuan toko.''';

  /// Alias kompatibel untuk default tetap.
  static String get dp => dpDefault.trim();
  static String get pending => pendingDefault.trim();
  static String get ready => readyDefault.trim();
  static String get clear => clearDefault.trim();

  static String textFor(InvoiceFooterStatus status) =>
      InvoiceStatusFooters.defaults().of(status);

  /// DP dulu (sisa/tagihan), lalu CLEAR (sudah diambil), READY, sisanya PENDING.
  static InvoiceFooterStatus statusOf(Map<String, dynamic> sale) {
    if (_isDp(sale)) return InvoiceFooterStatus.dp;
    if (_isClear(sale)) return InvoiceFooterStatus.clear;
    if (_isReady(sale)) return InvoiceFooterStatus.ready;
    return InvoiceFooterStatus.pending;
  }

  static String forSale(
    Map<String, dynamic> sale, {
    InvoiceStatusFooters? footers,
    bool forPdf = false,
  }) {
    final pack = footers ?? InvoiceStatusFooters.defaults();
    final raw = pack.of(statusOf(sale));
    if (!forPdf) return raw;
    return raw
        .replaceAll('•', '-')
        .replaceAll('–', '-')
        .replaceAll('—', '-');
  }

  /// Pratinjau POS sebelum sale tersimpan.
  static String forCheckout({
    required bool isDp,
    String? trackingStatus,
    InvoiceStatusFooters? footers,
    bool forPdf = false,
  }) {
    return forSale(
      {
        'status_pembayaran': isDp ? 'DP' : 'LUNAS',
        'sisa_tagihan': isDp ? 1 : 0,
        'tracking_status': trackingStatus ??
            (isDp ? 'PENDING_PO' : 'DIPROSES_DI_CABANG'),
      },
      footers: footers,
      forPdf: forPdf,
    );
  }

  static bool _isDp(Map<String, dynamic> sale) {
    final pay = (sale['status_pembayaran'] ?? '').toString().toUpperCase();
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    return pay == 'DP' || sisa > 0;
  }

  static bool _isClear(Map<String, dynamic> sale) {
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    return sale['diambil_at'] != null || tracking == 'DIAMBIL';
  }

  static bool _isReady(Map<String, dynamic> sale) {
    if (_isDp(sale) || _isClear(sale)) return false;
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    return tracking == 'SIAP_DIAMBIL' || tracking == 'CLEAR';
  }
}
