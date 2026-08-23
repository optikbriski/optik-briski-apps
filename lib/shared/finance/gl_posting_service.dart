import 'package:supabase_flutter/supabase_flutter.dart';

/// Posting jurnal berimbang ke GL (via RPC `post_journal_balanced`).
class GlPostingService {
  GlPostingService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const akunKas = '1101';
  static const akunBank = '1102';
  static const akunPiutang = '1103';
  static const akunPersediaan = '1201';
  static const akunHutang = '2101';
  static const akunPpn = '2102';
  static const akunPenjualan = '4100';
  static const akunPendapatanLain = '4102';
  static const akunHpp = '5100';
  static const akunOpex = '5200';
  static const akunSelisihKas = '5201';

  static String cashOrBank(String? metode) {
    final m = (metode ?? '').toUpperCase();
    if (m.contains('CASH') || m.contains('TUNAI') || m.isEmpty) {
      return akunKas;
    }
    return akunBank;
  }

  /// Split omzet inklusif PPN 11% → (dpp, ppn).
  static ({int dpp, int ppn}) splitPpn(int omzet) {
    if (omzet <= 0) return (dpp: 0, ppn: 0);
    final dpp = (omzet / 1.11).round();
    return (dpp: dpp, ppn: omzet - dpp);
  }

  /// Tanggal buku = kalender Asia/Jakarta (UTC+7, tanpa DST).
  static DateTime dateJakarta([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final jkt = utc.add(const Duration(hours: 7));
    return DateTime(jkt.year, jkt.month, jkt.day);
  }

  static String dateJakartaYmd([DateTime? now]) {
    final d = dateJakarta(now);
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// SETTLE hanya jika total nota stabil (bukan wobble insert item).
  static bool shouldPostSettle({
    required int oldTotal,
    required int newTotal,
    required int oldSisa,
    required int newSisa,
  }) {
    if (oldTotal != newTotal) return false;
    return newSisa < oldSisa && (oldSisa - newSisa) > 0;
  }

  Future<String?> postBalanced({
    required String tokoId,
    required DateTime tanggal,
    required String sumber,
    required String? referensiId,
    required String memo,
    required List<Map<String, dynamic>> lines,
    String? createdBy,
  }) async {
    final dateStr = dateJakartaYmd(tanggal);
    final cleaned = lines
        .where((l) {
          final d = (l['debit'] as int?) ?? 0;
          final k = (l['kredit'] as int?) ?? 0;
          return d > 0 || k > 0;
        })
        .toList();
    if (cleaned.length < 2) return null;

    try {
      final res = await _db.rpc('post_journal_balanced', params: {
        'p_toko_id': tokoId.toUpperCase(),
        'p_tanggal': dateStr,
        'p_sumber': sumber,
        'p_referensi_id': referensiId,
        'p_memo': memo,
        'p_lines': cleaned,
        'p_created_by': createdBy,
      });
      return res?.toString();
    } catch (e) {
      // Trigger sales mungkin sudah mem-post idempotent; jangan pecahkan alur kasir.
      final msg = e.toString().toLowerCase();
      if (msg.contains('sudah ditutup') || msg.contains('tidak berhak')) {
        rethrow;
      }
      return null;
    }
  }

  /// POS: Dr Kas/Bank + Piutang | Cr Penjualan (DPP) + PPN.
  Future<String?> postPosSale({
    required String tokoId,
    required String noInvoice,
    required int totalHarga,
    required int bayar,
    required int sisaTagihan,
    required String? metode,
    DateTime? tanggal,
    String? createdBy,
    String? namaPelanggan,
  }) async {
    final omzet = totalHarga < 0 ? 0 : totalHarga;
    final bayarSafe = bayar.clamp(0, omzet);
    final sisa = sisaTagihan >= 0
        ? sisaTagihan
        : (omzet - bayarSafe).clamp(0, omzet);
    if (omzet <= 0) return null;

    final tax = splitPpn(omzet);
    final assetAkun = cashOrBank(metode);
    final lines = <Map<String, dynamic>>[];

    if (bayarSafe > 0) {
      lines.add({
        'akun_kode': assetAkun,
        'debit': bayarSafe,
        'kredit': 0,
        'memo': 'Terima bayar $noInvoice',
      });
    }
    if (sisa > 0) {
      lines.add({
        'akun_kode': akunPiutang,
        'debit': sisa,
        'kredit': 0,
        'memo': 'Piutang $noInvoice',
      });
    }
    if (tax.dpp > 0) {
      lines.add({
        'akun_kode': akunPenjualan,
        'debit': 0,
        'kredit': tax.dpp,
        'memo': 'Penjualan $noInvoice',
      });
    }
    if (tax.ppn > 0) {
      lines.add({
        'akun_kode': akunPpn,
        'debit': 0,
        'kredit': tax.ppn,
        'memo': 'PPN $noInvoice',
      });
    }

    // Jaga berimbang jika rounding sisa+bayar ≠ omzet
    final sumD =
        lines.fold<int>(0, (s, l) => s + ((l['debit'] as int?) ?? 0));
    final sumK =
        lines.fold<int>(0, (s, l) => s + ((l['kredit'] as int?) ?? 0));
    final gap = sumD - sumK;
    if (gap != 0 && lines.isNotEmpty) {
      // Sesuaikan kredit penjualan; fallback PPN agar tetap berimbang.
      var adjusted = false;
      for (final l in lines) {
        if (l['akun_kode'] == akunPenjualan) {
          final k = (l['kredit'] as int) - gap;
          if (k > 0) {
            l['kredit'] = k;
            adjusted = true;
          }
          break;
        }
      }
      if (!adjusted) {
        for (final l in lines) {
          if (l['akun_kode'] == akunPpn) {
            final k = (l['kredit'] as int) - gap;
            if (k > 0) {
              l['kredit'] = k;
            }
            break;
          }
        }
      }
    }

    return postBalanced(
      tokoId: tokoId,
      tanggal: tanggal ?? DateTime.now(),
      sumber: 'POS',
      referensiId: noInvoice,
      memo: 'POS $noInvoice${namaPelanggan != null ? ' ($namaPelanggan)' : ''}',
      lines: lines,
      createdBy: createdBy,
    );
  }

  /// Tutup toko selisih kas.
  Future<String?> postClosingShift({
    required String tokoId,
    required String referensiId,
    required int selisih,
    DateTime? tanggal,
    String? createdBy,
    String? deskripsi,
  }) async {
    final abs = selisih.abs();
    if (abs <= 0) return null;

    final lines = selisih >= 0
        ? [
            {
              'akun_kode': akunKas,
              'debit': abs,
              'kredit': 0,
              'memo': 'Surplus tutup toko',
            },
            {
              'akun_kode': akunSelisihKas,
              'debit': 0,
              'kredit': abs,
              'memo': 'Surplus tutup toko',
            },
          ]
        : [
            {
              'akun_kode': akunSelisihKas,
              'debit': abs,
              'kredit': 0,
              'memo': 'Defisit tutup toko',
            },
            {
              'akun_kode': akunKas,
              'debit': 0,
              'kredit': abs,
              'memo': 'Defisit tutup toko',
            },
          ];

    return postBalanced(
      tokoId: tokoId,
      tanggal: tanggal ?? DateTime.now(),
      sumber: 'CLOSING',
      referensiId: referensiId,
      memo: deskripsi ?? 'Penutupan toko',
      lines: lines,
      createdBy: createdBy,
    );
  }

  /// Manual COA dari finance_transactions (hanya APPROVED / sistem).
  Future<String?> postManualFinance({
    required Map<String, dynamic> ft,
    String? createdBy,
  }) async {
    final id = ft['id']?.toString();
    if (id == null) return null;

    final status =
        (ft['status_konfirmasi'] ?? '').toString().toUpperCase();
    final ref = (ft['referensi_id'] ?? '').toString();
    final refU = ref.toUpperCase();
    final isClosing = refU.startsWith('CLOSE-') ||
        (ft['kategori'] ?? '')
            .toString()
            .toUpperCase()
            .contains('PENUTUPAN') ||
        (ft['kategori'] ?? '')
            .toString()
            .toUpperCase()
            .contains('CLOSING');
    final isSettle = refU.startsWith('SETTLE-') ||
        (ft['kategori'] ?? '')
            .toString()
            .toUpperCase()
            .contains('PELUNASAN');

    if (status == 'PENDING') return null;
    // Omzet POS murni di-post lewat postPosSale / trigger sales.
    if (ref.isNotEmpty && !isClosing && !isSettle && !refU.startsWith('FT-')) {
      return null;
    }

    final jenis = (ft['jenis_transaksi'] ?? '').toString().toUpperCase();
    final nominal = int.tryParse(ft['nominal']?.toString() ?? '0') ?? 0;
    if (nominal <= 0) return null;

    final tokoId = (ft['toko_id'] ?? 'PUSAT').toString();
    final metode = ft['metode_pembayaran']?.toString();
    final asset = cashOrBank(metode);
    final tglStr = (ft['tanggal_transaksi'] ??
            ft['created_at']?.toString().split('T').first ??
            DateTime.now().toIso8601String().split('T').first)
        .toString();
    final tanggal = DateTime.tryParse(tglStr) ?? DateTime.now();

    if (isClosing) {
      final signed = (jenis == 'PEMASUKAN' || jenis == 'PIUTANG')
          ? nominal
          : -nominal;
      return postClosingShift(
        tokoId: tokoId,
        referensiId: ref.isNotEmpty ? ref : 'CLOSE-FT-$id',
        selisih: signed,
        tanggal: tanggal,
        createdBy: createdBy,
        deskripsi: ft['deskripsi']?.toString(),
      );
    }

    // SETTLE: single-writer = DB trigger sales.sisa_tagihan (hindari double-post).
    if (isSettle) return null;

    List<Map<String, dynamic>> lines;
    switch (jenis) {
      case 'PEMASUKAN':
        lines = [
          {
            'akun_kode': asset,
            'debit': nominal,
            'kredit': 0,
            'memo': ft['kategori'],
          },
          {
            'akun_kode': akunPendapatanLain,
            'debit': 0,
            'kredit': nominal,
            'memo': ft['kategori'],
          },
        ];
        break;
      case 'PENGELUARAN':
        lines = [
          {
            'akun_kode': akunOpex,
            'debit': nominal,
            'kredit': 0,
            'memo': ft['kategori'],
          },
          {
            'akun_kode': asset,
            'debit': 0,
            'kredit': nominal,
            'memo': ft['kategori'],
          },
        ];
        break;
      case 'PIUTANG':
        lines = [
          {
            'akun_kode': akunPiutang,
            'debit': nominal,
            'kredit': 0,
            'memo': ft['kategori'],
          },
          {
            'akun_kode': akunPendapatanLain,
            'debit': 0,
            'kredit': nominal,
            'memo': ft['kategori'],
          },
        ];
        break;
      case 'HUTANG':
        lines = [
          {
            'akun_kode': akunOpex,
            'debit': nominal,
            'kredit': 0,
            'memo': ft['kategori'],
          },
          {
            'akun_kode': akunHutang,
            'debit': 0,
            'kredit': nominal,
            'memo': ft['kategori'],
          },
        ];
        break;
      default:
        return null;
    }

    return postBalanced(
      tokoId: tokoId,
      tanggal: tanggal,
      sumber: 'MANUAL',
      referensiId: 'FT-$id',
      memo: ft['deskripsi']?.toString() ?? ft['kategori']?.toString() ?? 'Manual',
      lines: lines,
      createdBy: createdBy,
    );
  }

  Future<String?> voidEntry(String entryId, {String? createdBy}) async {
    final res = await _db.rpc('void_journal_entry', params: {
      'p_entry_id': entryId,
      'p_created_by': createdBy,
    });
    return res?.toString();
  }

  Future<int> voidBySumberRef({
    required String sumber,
    required String referensiId,
    String? createdBy,
  }) async {
    final res = await _db.rpc('gl_void_by_sumber_ref', params: {
      'p_sumber': sumber,
      'p_referensi_id': referensiId,
      'p_created_by': createdBy,
    });
    return int.tryParse('$res') ?? 0;
  }

  Future<int> voidSaleJournals({
    required String noInvoice,
    String? createdBy,
  }) async {
    final res = await _db.rpc('gl_void_sale_journals', params: {
      'p_no_invoice': noInvoice,
      'p_created_by': createdBy,
    });
    return int.tryParse('$res') ?? 0;
  }

  Future<void> closePeriod({
    required int tahun,
    required int bulan,
    String? closedBy,
  }) async {
    await _db.rpc('close_fiscal_period', params: {
      'p_tahun': tahun,
      'p_bulan': bulan,
      'p_closed_by': closedBy,
    });
  }

  Future<void> reopenPeriod({
    required int tahun,
    required int bulan,
  }) async {
    await _db.rpc('reopen_fiscal_period', params: {
      'p_tahun': tahun,
      'p_bulan': bulan,
    });
  }

  /// Backfill historis batch SQL — aman untuk histori ratusan toko.
  /// Loop sampai batch kosong atau maxRounds tercapai.
  Future<({int posted, int skipped, int failed})> backfillHistoris({
    String? tokoId,
    String? createdBy,
    void Function(String msg)? onProgress,
    int batchSize = 200,
    int maxRounds = 50,
  }) async {
    var posted = 0;
    var skipped = 0;
    var failed = 0;

    for (var round = 1; round <= maxRounds; round++) {
      onProgress?.call('Backfill penjualan · batch $round…');
      final salesRes = await _db.rpc('gl_backfill_sales_batch', params: {
        'p_toko_id': tokoId,
        'p_limit': batchSize,
        'p_created_by': createdBy,
      });
      final sMap = Map<String, dynamic>.from(salesRes as Map);
      final sPosted = int.tryParse('${sMap['posted'] ?? 0}') ?? 0;
      final sSkipped = int.tryParse('${sMap['skipped'] ?? 0}') ?? 0;
      final sFailed = int.tryParse('${sMap['failed'] ?? 0}') ?? 0;
      final sDone = sMap['done'] == true ||
          (sPosted == 0 && sSkipped == 0 && sFailed == 0);
      posted += sPosted;
      skipped += sSkipped;
      failed += sFailed;
      if (sDone || (sPosted == 0 && sFailed == 0)) break;
    }

    for (var round = 1; round <= maxRounds; round++) {
      onProgress?.call('Backfill kas/closing · batch $round…');
      final ftRes = await _db.rpc('gl_backfill_finance_batch', params: {
        'p_toko_id': tokoId,
        'p_limit': batchSize,
        'p_created_by': createdBy,
      });
      final fMap = Map<String, dynamic>.from(ftRes as Map);
      final fPosted = int.tryParse('${fMap['posted'] ?? 0}') ?? 0;
      final fSkipped = int.tryParse('${fMap['skipped'] ?? 0}') ?? 0;
      final fFailed = int.tryParse('${fMap['failed'] ?? 0}') ?? 0;
      final fDone = fMap['done'] == true ||
          (fPosted == 0 && fSkipped == 0 && fFailed == 0);
      posted += fPosted;
      skipped += fSkipped;
      failed += fFailed;
      if (fDone || (fPosted == 0 && fFailed == 0)) break;
    }

    return (posted: posted, skipped: skipped, failed: failed);
  }
}
