import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ExportProgress = void Function(String message, double? progress);

/// Mode output PDF saat lebih dari satu domain dipilih.
enum ExportPdfMode {
  gabung,
  pisah;

  String get wire => name;
}

/// Satu domain dalam laporan ekspor.
class ExportDomain {
  const ExportDomain({
    required this.id,
    required this.sheetName,
    required this.table,
    this.dateColumn,
    this.isSnapshot = false,
    this.select = '*',
    this.excludeColumns = const {},
    this.orderBy,
  });

  final String id;
  final String sheetName;
  final String table;
  final String? dateColumn;
  final bool isSnapshot;
  final String select;
  final Set<String> excludeColumns;
  final String? orderBy;

  /// Nama aman untuk judul file (tanpa spasi/karakter aneh).
  String get fileSlug {
    final cleaned = sheetName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
    return cleaned.isEmpty ? id : cleaned;
  }
}

class MonthlyExportResult {
  const MonthlyExportResult({
    required this.files,
    required this.sheetSummaries,
    required this.errors,
    required this.salinanKe,
    this.historyError,
    this.usedLocalSalinan = false,
  });

  final List<File> files;
  final List<String> sheetSummaries;
  final List<String> errors;
  final int salinanKe;
  final String? historyError;
  final bool usedLocalSalinan;

  bool get hasErrors => errors.isNotEmpty;
  bool get historyFailed => historyError != null;
  File get file => files.first;
}

/// Hasil peek nomor Salinan berikutnya.
class PeekSalinanResult {
  const PeekSalinanResult({
    this.next,
    this.schemaReady = true,
    this.error,
  });

  /// Null = tampilkan "—" (schema belum siap).
  final int? next;
  final bool schemaReady;
  final String? error;
}

/// Hasil alokasi nomor Salinan (RPC atau fallback lokal).
class AllocateSalinanResult {
  const AllocateSalinanResult({
    required this.salinanKe,
    this.usedLocalFallback = false,
    this.warning,
  });

  final int salinanKe;
  final bool usedLocalFallback;
  final String? warning;
}

/// Hasil fetch riwayat unduhan.
class HistoryFetchResult {
  const HistoryFetchResult({
    required this.entries,
    this.schemaReady = true,
    this.error,
  });

  final List<ExportDownloadHistoryEntry> entries;
  final bool schemaReady;
  final String? error;
}

/// Baris riwayat unduhan dari Supabase.
class ExportDownloadHistoryEntry {
  const ExportDownloadHistoryEntry({
    required this.id,
    required this.createdAt,
    required this.periodStart,
    required this.periodEnd,
    required this.mode,
    required this.domains,
    required this.salinanKe,
    required this.fileCount,
    this.adminUserId,
    this.adminEmail,
    this.notes,
  });

  final String id;
  final DateTime createdAt;
  final DateTime periodStart;
  final DateTime periodEnd;
  final ExportPdfMode mode;
  final List<String> domains;
  final int salinanKe;
  final int fileCount;
  final String? adminUserId;
  final String? adminEmail;
  final String? notes;

  factory ExportDownloadHistoryEntry.fromRow(Map<String, dynamic> row) {
    final modeRaw = (row['mode'] ?? 'gabung').toString();
    final domainsRaw = row['domains'];
    final domains = domainsRaw is List
        ? domainsRaw.map((e) => e.toString()).toList()
        : <String>[];
    return ExportDownloadHistoryEntry(
      id: row['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
      periodStart:
          DateTime.tryParse(row['period_start']?.toString() ?? '') ??
              DateTime.now(),
      periodEnd:
          DateTime.tryParse(row['period_end']?.toString() ?? '') ??
              DateTime.now(),
      mode: modeRaw == 'pisah' ? ExportPdfMode.pisah : ExportPdfMode.gabung,
      domains: domains,
      salinanKe: (row['salinan_ke'] as num?)?.toInt() ?? 0,
      fileCount: (row['file_count'] as num?)?.toInt() ?? 1,
      adminUserId: row['admin_user_id']?.toString(),
      adminEmail: row['admin_email']?.toString(),
      notes: row['notes']?.toString(),
    );
  }
}

class _DomainExportSlice {
  const _DomainExportSlice({
    required this.domain,
    required this.rows,
    this.error,
  });

  final ExportDomain domain;
  final List<Map<String, dynamic>> rows;
  final String? error;

  int get rowCount => rows.length;
  bool get hasError => error != null;
  bool get isEmpty => rows.isEmpty && error == null;
}

/// Ekspor data operasional ke laporan PDF premium untuk Admin.
class MonthlyDataExportService {
  MonthlyDataExportService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _pageSize = 1000;
  static const _maxPdfRows = 1500;
  static const _maxPdfCols = 8;

  /// Fallback lokal jika RPC/tabel Salinan belum di-migrate.
  static int _localSalinanSeq = 1;

  /// Deteksi tabel/RPC export belum ada di Supabase.
  static bool isMissingExportSchema(Object e) {
    final raw = e.toString().toLowerCase();
    return raw.contains('export_salinan_counter') ||
        raw.contains('export_download_history') ||
        raw.contains('allocate_export_salinan') ||
        raw.contains('record_export_download') ||
        raw.contains('pgrst202') ||
        raw.contains('pgrst205') ||
        raw.contains('42p01') ||
        raw.contains('42883') ||
        (raw.contains('relation') && raw.contains('does not exist')) ||
        (raw.contains('function') && raw.contains('does not exist')) ||
        (raw.contains('could not find') && raw.contains('schema cache'));
  }

  static const _navy = PdfColor.fromInt(0xFF0F172A);
  static const _navyMid = PdfColor.fromInt(0xFF1E3C72);
  static const _gold = PdfColor.fromInt(0xFFC9A84C);
  static const _goldSoft = PdfColor.fromInt(0xFFE8C872);
  static const _zebra = PdfColor.fromInt(0xFFF8FAFC);
  static const _panel = PdfColor.fromInt(0xFFF1F5F9);
  static const _muted = PdfColor.fromInt(0xFF64748B);
  static const _slate = PdfColor.fromInt(0xFF334155);
  static const _border = PdfColor.fromInt(0xFFE2E8F0);
  static const _ink = PdfColor.fromInt(0xFF0F172A);

  static final _displayDt = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final _displayDtHuman = DateFormat('d MMMM yyyy HH:mm', 'id_ID');
  static final _humanDay = DateFormat('d MMMM yyyy', 'id_ID');
  static final _fileDay = DateFormat('yyyyMMdd');
  static final _isoDay = DateFormat('yyyy-MM-dd');

  /// Kolom sensitif yang tidak boleh ikut ekspor.
  static const _secretColumns = {
    'pin_absensi',
    'face_template',
    'password',
    'otp',
    'otp_hash',
    'refresh_token',
    'access_token',
    'service_role',
  };

  /// Semua domain utama (bukan hanya finance).
  static const List<ExportDomain> allDomains = [
    ExportDomain(
      id: 'sales',
      sheetName: 'Sales',
      table: 'sales',
      dateColumn: 'created_at',
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'sales_items',
      sheetName: 'Sales Items',
      table: 'sales_items',
      orderBy: 'id',
    ),
    ExportDomain(
      id: 'finance',
      sheetName: 'Finance',
      table: 'finance_transactions',
      dateColumn: 'tanggal_transaksi',
      orderBy: 'tanggal_transaksi',
    ),
    ExportDomain(
      id: 'stock_moves',
      sheetName: 'Stock Moves',
      table: 'stock_move_history',
      dateColumn: 'created_at',
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'pending_requests',
      sheetName: 'Request Orders',
      table: 'pending_requests',
      dateColumn: 'created_at',
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'draft_pengiriman',
      sheetName: 'Draft Pengiriman',
      table: 'draft_pengiriman',
      dateColumn: 'created_at',
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'attendance_shifts',
      sheetName: 'Absensi Shift',
      table: 'attendance_shifts',
      dateColumn: 'masuk_at',
      orderBy: 'masuk_at',
    ),
    ExportDomain(
      id: 'attendance_logs',
      sheetName: 'Absensi Logs',
      table: 'attendance_logs',
      dateColumn: 'created_at',
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'jadwal_kerja',
      sheetName: 'Jadwal Kerja',
      table: 'jadwal_kerja',
      dateColumn: 'tanggal',
      orderBy: 'tanggal',
    ),
    ExportDomain(
      id: 'jadwal_pengajuan',
      sheetName: 'Jadwal Pengajuan',
      table: 'jadwal_pengajuan',
      dateColumn: 'created_at',
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'poin_logs',
      sheetName: 'Poin Logs',
      table: 'poin_logs',
      dateColumn: 'tanggal',
      orderBy: 'tanggal',
    ),
    ExportDomain(
      id: 'sop_completions',
      sheetName: 'SOP Completions',
      table: 'sop_completions',
      dateColumn: 'tanggal',
      orderBy: 'tanggal',
    ),
    ExportDomain(
      id: 'pengaduan',
      sheetName: 'Pengaduan',
      table: 'pengaduan',
      dateColumn: 'created_at',
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'session_logs',
      sheetName: 'Session Logs',
      table: 'session_logs',
      dateColumn: 'created_at',
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'notifikasi',
      sheetName: 'Notifikasi',
      table: 'notifikasi',
      dateColumn: 'created_at',
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'products',
      sheetName: 'Products Snapshot',
      table: 'products',
      isSnapshot: true,
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'inventory_stocks',
      sheetName: 'Inventory Stocks',
      table: 'inventory_stocks',
      isSnapshot: true,
      orderBy: 'toko_id',
    ),
    ExportDomain(
      id: 'karyawan',
      sheetName: 'Karyawan Snapshot',
      table: 'karyawan',
      isSnapshot: true,
      excludeColumns: _secretColumns,
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'profiles',
      sheetName: 'Profiles Snapshot',
      table: 'profiles',
      isSnapshot: true,
      orderBy: 'created_at',
    ),
    ExportDomain(
      id: 'toko',
      sheetName: 'Cabang Toko',
      table: 'toko_id',
      isSnapshot: true,
      orderBy: 'id',
    ),
    ExportDomain(
      id: 'toko_shift',
      sheetName: 'Toko Shift Settings',
      table: 'toko_shift_settings',
      isSnapshot: true,
      orderBy: 'toko_id',
    ),
    ExportDomain(
      id: 'sop_templates',
      sheetName: 'SOP Templates',
      table: 'sop_templates',
      isSnapshot: true,
      orderBy: 'urutan',
    ),
    ExportDomain(
      id: 'invoice_settings',
      sheetName: 'Invoice Settings',
      table: 'invoice_settings',
      isSnapshot: true,
      orderBy: 'toko_id',
    ),
    ExportDomain(
      id: 'versi_app',
      sheetName: 'Versi App',
      table: 'versi_app',
      isSnapshot: true,
      orderBy: 'created_at',
    ),
  ];

  static ExportDomain? domainById(String id) {
    for (final d in allDomains) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Preview nomor Salinan berikutnya (tidak mengunci / tidak increment).
  Future<PeekSalinanResult> peekNextSalinan() async {
    String? lastSchemaError;
    try {
      final row = await _client
          .from('export_salinan_counter')
          .select('next_salinan')
          .eq('id', 1)
          .maybeSingle();
      final n = (row?['next_salinan'] as num?)?.toInt();
      if (n != null && n > 0) {
        if (n > _localSalinanSeq) _localSalinanSeq = n;
        return PeekSalinanResult(next: n);
      }
    } catch (e) {
      debugPrint('peekNextSalinan counter: $e');
      if (isMissingExportSchema(e)) lastSchemaError = '$e';
    }
    try {
      final rows = await _client
          .from('export_download_history')
          .select('salinan_ke')
          .order('salinan_ke', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isNotEmpty) {
        final max = (list.first['salinan_ke'] as num?)?.toInt() ?? 0;
        final next = max + 1;
        if (next > _localSalinanSeq) _localSalinanSeq = next;
        return PeekSalinanResult(next: next);
      }
      // Tabel ada tapi masih kosong.
      return const PeekSalinanResult(next: 1);
    } catch (e) {
      debugPrint('peekNextSalinan history: $e');
      if (isMissingExportSchema(e)) lastSchemaError = '$e';
    }
    if (lastSchemaError != null) {
      return PeekSalinanResult(
        next: null,
        schemaReady: false,
        error: lastSchemaError,
      );
    }
    return const PeekSalinanResult(next: 1);
  }

  /// Ambil nomor salinan batch secara atomic; fallback lokal jika RPC belum ada.
  Future<AllocateSalinanResult> allocateSalinan() async {
    try {
      final raw = await _client.rpc('allocate_export_salinan');
      final n = raw is int
          ? raw
          : int.tryParse(raw?.toString() ?? '') ?? 0;
      if (n < 1) {
        throw StateError('Gagal mengalokasikan nomor salinan.');
      }
      if (n >= _localSalinanSeq) _localSalinanSeq = n + 1;
      return AllocateSalinanResult(salinanKe: n);
    } catch (e) {
      debugPrint('allocateSalinan RPC: $e');
      if (!isMissingExportSchema(e)) rethrow;
      final local = _localSalinanSeq++;
      return AllocateSalinanResult(
        salinanKe: local,
        usedLocalFallback: true,
        warning: '$e',
      );
    }
  }

  Future<HistoryFetchResult> fetchHistory({int limit = 40}) async {
    try {
      final rows = await _client
          .from('export_download_history')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      final list = List<Map<String, dynamic>>.from(rows as List);
      return HistoryFetchResult(
        entries: list.map(ExportDownloadHistoryEntry.fromRow).toList(),
      );
    } catch (e) {
      debugPrint('fetchHistory: $e');
      if (isMissingExportSchema(e)) {
        return HistoryFetchResult(
          entries: const [],
          schemaReady: false,
          error: '$e',
        );
      }
      return HistoryFetchResult(
        entries: const [],
        schemaReady: true,
        error: '$e',
      );
    }
  }

  Future<void> recordHistory({
    required int salinanKe,
    required DateTime periodStart,
    required DateTime periodEnd,
    required ExportPdfMode mode,
    required List<String> domainIds,
    required int fileCount,
    String? adminUserId,
    String? adminEmail,
    String? notes,
  }) async {
    await _client.from('export_download_history').insert({
      'admin_user_id': adminUserId,
      'admin_email': adminEmail,
      'period_start': _isoDay.format(periodStart),
      'period_end': _isoDay.format(periodEnd),
      'mode': mode.wire,
      'domains': domainIds,
      'salinan_ke': salinanKe,
      'file_count': fileCount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  /// Ekspor domain terpilih ke PDF (gabung satu file atau pisah per domain).
  Future<MonthlyExportResult> exportRange({
    required DateTime start,
    required DateTime end,
    required List<ExportDomain> domains,
    required ExportPdfMode mode,
    required int salinanKe,
    String? adminUserId,
    String? adminEmail,
    bool recordHistoryRow = true,
    bool usedLocalSalinan = false,
    ExportProgress? onProgress,
  }) async {
    if (domains.isEmpty) {
      throw StateError('Tidak ada domain yang dipilih.');
    }

    final selected = List<ExportDomain>.from(domains);
    final effectiveMode =
        selected.length == 1 ? ExportPdfMode.gabung : mode;
    final range = _buildRange(start, end);
    final created = DateTime.now();
    final slices = <_DomainExportSlice>[];
    final summaries = <String>[];
    final errors = <String>[];

    final buildJobs = effectiveMode == ExportPdfMode.pisah
        ? selected.length
        : 1;
    final total = selected.length + buildJobs + 2;
    var step = 0;

    void tick(String msg) {
      step++;
      onProgress?.call(msg, step / total);
    }

    List<Map<String, dynamic>>? salesInRange;

    for (final domain in selected) {
      tick('Mengambil ${domain.sheetName}…');
      try {
        List<Map<String, dynamic>> rows;
        if (domain.id == 'sales_items') {
          salesInRange ??= await _fetchTable(
            table: 'sales',
            dateColumn: 'created_at',
            start: range.startIso,
            end: range.endIso,
            orderBy: 'created_at',
          );
          rows = await _fetchSalesItems(salesInRange);
        } else if (domain.isSnapshot || domain.dateColumn == null) {
          rows = await _fetchTable(
            table: domain.table,
            orderBy: domain.orderBy,
          );
        } else {
          rows = await _fetchTable(
            table: domain.table,
            dateColumn: domain.dateColumn,
            start: range.startIso,
            end: range.endIso,
            orderBy: domain.orderBy,
          );
        }

        rows = rows.map((r) => _sanitizeRow(r, domain.excludeColumns)).toList();
        slices.add(_DomainExportSlice(domain: domain, rows: rows));
        if (rows.isEmpty) {
          summaries.add('${domain.sheetName}: Tidak ada data');
        } else {
          summaries.add('${domain.sheetName}: ${rows.length} baris');
        }
      } catch (e, st) {
        debugPrint('Export ${domain.id} gagal: $e\n$st');
        errors.add('${domain.sheetName}: $e');
        slices.add(
          _DomainExportSlice(domain: domain, rows: const [], error: '$e'),
        );
        summaries.add('${domain.sheetName}: ERROR');
      }
    }

    final files = <File>[];

    if (effectiveMode == ExportPdfMode.pisah) {
      for (final slice in slices) {
        tick('Menyusun PDF ${slice.domain.sheetName}…');
        final bytes = await _buildPdf(
          range: range,
          created: created,
          slices: [slice],
          salinanKe: salinanKe,
          reportTitle: slice.domain.sheetName,
          docSubjectDomain: slice.domain.sheetName,
        );
        final file = await _writeExportFile(
          bytes: bytes,
          range: range,
          salinanKe: salinanKe,
          domainSlug: slice.domain.fileSlug,
        );
        files.add(file);
      }
    } else {
      tick('Menyusun laporan PDF…');
      final bytes = await _buildPdf(
        range: range,
        created: created,
        slices: slices,
        salinanKe: salinanKe,
        reportTitle: selected.length == 1
            ? selected.first.sheetName
            : 'Laporan Ekspor Operasional',
        docSubjectDomain: selected.length == 1
            ? selected.first.sheetName
            : null,
      );
      final file = await _writeExportFile(
        bytes: bytes,
        range: range,
        salinanKe: salinanKe,
        domainSlug: selected.length == 1 ? selected.first.fileSlug : 'Laporan',
      );
      files.add(file);
    }

    onProgress?.call('Menyimpan riwayat…', 0.97);

    String? historyError;
    if (recordHistoryRow) {
      try {
        await recordHistory(
          salinanKe: salinanKe,
          periodStart: range.startDay,
          periodEnd: range.endDay,
          mode: effectiveMode,
          domainIds: selected.map((d) => d.id).toList(),
          fileCount: files.length,
          adminUserId: adminUserId,
          adminEmail: adminEmail,
        );
      } catch (e, st) {
        debugPrint('recordHistory gagal: $e\n$st');
        historyError = '$e';
      }
    }

    onProgress?.call('Selesai', 1);

    return MonthlyExportResult(
      files: files,
      sheetSummaries: summaries,
      errors: errors,
      salinanKe: salinanKe,
      historyError: historyError,
      usedLocalSalinan: usedLocalSalinan,
    );
  }

  Future<File> _writeExportFile({
    required Uint8List bytes,
    required _ExportRange range,
    required int salinanKe,
    required String domainSlug,
  }) async {
    final dir = await _exportDirectory();
    await dir.create(recursive: true);

    final startStamp = _fileDay.format(range.startDay);
    final endStamp = _fileDay.format(range.endDay);
    final safeSlug = domainSlug.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final slug = safeSlug.isEmpty ? 'Laporan' : safeSlug;
    final fileName =
        'OptikBRiski_${slug}_$startStamp-${endStamp}_Salinan$salinanKe.pdf';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');

    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);

    if (!await file.exists()) {
      throw StateError(
        'File ekspor tidak ditemukan setelah ditulis: ${file.path}',
      );
    }
    return file;
  }

  Future<Directory> _exportDirectory() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return await getApplicationDocumentsDirectory();
    }
  }

  // ---------------------------------------------------------------------------
  // PDF builder
  // ---------------------------------------------------------------------------

  Future<Uint8List> _buildPdf({
    required _ExportRange range,
    required DateTime created,
    required List<_DomainExportSlice> slices,
    required int salinanKe,
    required String reportTitle,
    String? docSubjectDomain,
  }) async {
    final subjectDomain = docSubjectDomain ?? 'multi-domain';
    final doc = pw.Document(
      title: '$reportTitle — Optik B. Riski (Salinan $salinanKe)',
      author: 'Optik B. Riski',
      subject:
          'Operational export $subjectDomain ${range.label} Salinan $salinanKe',
      creator: 'Optik B. Riski App',
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (context) => _buildCoverPage(
          range: range,
          created: created,
          salinanKe: salinanKe,
          reportTitle: reportTitle,
          domainCount: slices.length,
          totalRows: slices.fold<int>(0, (a, s) => a + s.rowCount),
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        header: (context) => _pageHeader('Ringkasan Domain'),
        footer: (context) => _pageFooter(context, salinanKe: salinanKe),
        build: (context) => [
          _sectionTitle('RINGKASAN DOMAIN'),
          pw.SizedBox(height: 6),
          pw.Text(
            'Jumlah baris per domain untuk periode ${range.labelHuman}. '
            'Snapshot = master data terkini (tidak difilter tanggal).',
            style: const pw.TextStyle(
              fontSize: 9,
              color: _muted,
              lineSpacing: 1.3,
            ),
          ),
          pw.SizedBox(height: 14),
          _summaryTable(slices),
          if (slices.any((s) => s.hasError)) ...[
            pw.SizedBox(height: 16),
            _sectionTitle('ERROR'),
            pw.SizedBox(height: 8),
            for (final s in slices.where((s) => s.hasError))
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(
                  '• ${s.domain.sheetName}: ${s.error}',
                  style: const pw.TextStyle(fontSize: 9, color: _slate),
                ),
              ),
          ],
        ],
      ),
    );

    for (final slice in slices) {
      if (slice.isEmpty || slice.hasError) continue;
      final tableData = _prepareTable(slice.rows);
      final truncated = slice.rowCount > _maxPdfRows;
      final shownRows = truncated ? _maxPdfRows : slice.rowCount;

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 32),
          header: (context) => _pageHeader(slice.domain.sheetName),
          footer: (context) => _pageFooter(context, salinanKe: salinanKe),
          build: (context) => [
            _domainDetailHeader(slice, shownRows: shownRows),
            pw.SizedBox(height: 10),
            _dataTable(tableData),
            if (truncated) ...[
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: pw.BoxDecoration(
                  color: _panel,
                  border: pw.Border.all(color: _gold, width: 0.6),
                ),
                child: pw.Text(
                  'Ditampilkan $shownRows dari ${slice.rowCount} baris '
                  '(batas laporan PDF). Data lengkap tersedia di sistem sumber.',
                  style: const pw.TextStyle(fontSize: 8, color: _slate),
                ),
              ),
            ],
            if (tableData.hiddenColumnCount > 0) ...[
              pw.SizedBox(height: 6),
              pw.Text(
                'Kolom ditampilkan: ${tableData.headers.length} dari '
                '${tableData.headers.length + tableData.hiddenColumnCount} '
                '(prioritas kolom utama untuk keterbacaan cetak).',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ],
          ],
        ),
      );
    }

    return doc.save();
  }

  pw.Widget _buildCoverPage({
    required _ExportRange range,
    required DateTime created,
    required int salinanKe,
    required String reportTitle,
    required int domainCount,
    required int totalRows,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          color: _navy,
          padding: const pw.EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'OPTIK B. RISKI',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(height: 3, width: 72, color: _gold),
              pw.SizedBox(height: 18),
              pw.Text(
                reportTitle,
                style: pw.TextStyle(
                  color: _goldSoft,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'CONFIDENTIAL — INTERNAL USE ONLY',
                style: pw.TextStyle(
                  color: _gold,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 28),
        pw.Container(
          padding: const pw.EdgeInsets.all(18),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _border),
            color: _panel,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'PERIODE',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _gold,
                  letterSpacing: 1.2,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                range.labelHuman,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                range.label,
                style: const pw.TextStyle(fontSize: 10, color: _slate),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Zona waktu: Waktu Jakarta (hari lokal perangkat)',
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: pw.BoxDecoration(
            color: _navy,
            border: pw.Border.all(color: _gold, width: 1.2),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'SALINAN KE-$salinanKe',
                style: pw.TextStyle(
                  color: _goldSoft,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              pw.Text(
                'Otomatis · tidak dapat diubah',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        _coverMetaRow('Dibuat', _displayDtHuman.format(created)),
        _coverMetaRow('Domain', '$domainCount section'),
        _coverMetaRow(
          'Total baris',
          NumberFormat.decimalPattern('id').format(totalRows),
        ),
        _coverMetaRow('Format', 'PDF — laporan lihat & cetak'),
        pw.Spacer(),
        pw.Container(height: 1, color: _gold),
        pw.SizedBox(height: 12),
        pw.Text(
          'Dokumen ini untuk keperluan internal Optik B. Riski. '
          'Jangan sebarkan di luar pihak yang berwenang.',
          style: const pw.TextStyle(
            fontSize: 8,
            color: _muted,
            lineSpacing: 1.35,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          '© Optik B. Riski  ·  Operational Report  ·  Salinan $salinanKe',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    );
  }

  pw.Widget _coverMetaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: _navyMid,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 10, color: _ink),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionTitle(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      color: _navy,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: _gold,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  pw.Widget _pageHeader(String section) {
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'OPTIK B. RISKI',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _navy,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Container(width: 1, height: 10, color: _gold),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                section,
                style: const pw.TextStyle(fontSize: 8, color: _muted),
                maxLines: 1,
              ),
            ),
            pw.Text(
              'CONFIDENTIAL',
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: _gold,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 1.2, color: _navy),
        pw.Container(height: 1.5, color: _gold),
        pw.SizedBox(height: 10),
      ],
    );
  }

  pw.Widget _pageFooter(pw.Context context, {required int salinanKe}) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 8),
        pw.Container(height: 0.6, color: _border),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Optik B. Riski · Internal · Salinan $salinanKe',
              style: const pw.TextStyle(fontSize: 7, color: _muted),
            ),
            pw.Text(
              'Halaman ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: _muted),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _summaryTable(List<_DomainExportSlice> slices) {
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.5),
        1: pw.FlexColumnWidth(3.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.6),
        4: pw.FlexColumnWidth(1.8),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navy),
          children: [
            _th('No'),
            _th('Domain'),
            _th('Tipe'),
            _th('Baris'),
            _th('Status'),
          ],
        ),
        for (var i = 0; i < slices.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.white : _zebra,
            ),
            children: [
              _td('${i + 1}', align: pw.TextAlign.center),
              _td(
                slices[i].domain.sheetName +
                    (slices[i].domain.isSnapshot ? ' ★' : ''),
              ),
              _td(
                slices[i].domain.isSnapshot ? 'Snapshot' : 'Periode',
                align: pw.TextAlign.center,
              ),
              _td(
                slices[i].hasError
                    ? '—'
                    : NumberFormat.decimalPattern('id')
                        .format(slices[i].rowCount),
                align: pw.TextAlign.right,
              ),
              _td(
                slices[i].hasError
                    ? 'Error'
                    : slices[i].isEmpty
                        ? 'Tidak ada data'
                        : 'Ada data',
                align: pw.TextAlign.center,
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _domainDetailHeader(
    _DomainExportSlice slice, {
    required int shownRows,
  }) {
    final typeLabel =
        slice.domain.isSnapshot ? 'SNAPSHOT MASTER DATA' : 'DATA PERIODE';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(
                slice.domain.sheetName,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              color: slice.domain.isSnapshot ? _goldSoft : _panel,
              child: pw.Text(
                typeLabel,
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${NumberFormat.decimalPattern('id').format(shownRows)} baris ditampilkan'
          '${slice.domain.isSnapshot ? ' · snapshot terkini' : ''}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 1.5, color: _gold),
      ],
    );
  }

  pw.Widget _th(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _td(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 8, color: _ink),
        textAlign: align,
        maxLines: 2,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  pw.Widget _dataTable(_PreparedTable data) {
    if (data.headers.isEmpty) {
      return pw.Text(
        'Tidak ada kolom untuk ditampilkan.',
        style: const pw.TextStyle(fontSize: 9, color: _muted),
      );
    }

    final colWidths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < data.headers.length; i++)
        i: const pw.FlexColumnWidth(),
    };

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.4),
      columnWidths: colWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navy),
          children: [
            for (final h in data.headers)
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: pw.Text(
                  h,
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  maxLines: 2,
                ),
              ),
          ],
        ),
        for (var r = 0; r < data.cells.length; r++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: r.isEven ? PdfColors.white : _zebra,
            ),
            children: [
              for (final cell in data.cells[r])
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: pw.Text(
                    cell,
                    style: const pw.TextStyle(fontSize: 6.5, color: _ink),
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  _PreparedTable _prepareTable(List<Map<String, dynamic>> rows) {
    final keys = <String>{};
    for (final r in rows) {
      keys.addAll(r.keys.map((k) => k.toString()));
    }
    final allKeys = keys.toList()..sort();
    final preferred = _preferColumns(allKeys);
    final selected = preferred.take(_maxPdfCols).toList();
    final hidden = allKeys.length - selected.length;
    final limitedRows =
        rows.length > _maxPdfRows ? rows.sublist(0, _maxPdfRows) : rows;

    final headers = selected.map(_humanizeHeader).toList();
    final cells = <List<String>>[];
    for (final row in limitedRows) {
      cells.add([
        for (final k in selected) _formatCellDisplay(row[k], maxLen: 48),
      ]);
    }
    return _PreparedTable(
      headers: headers,
      cells: cells,
      hiddenColumnCount: hidden < 0 ? 0 : hidden,
    );
  }

  List<String> _preferColumns(List<String> keys) {
    const priority = [
      'id',
      'no_invoice',
      'nama_pelanggan',
      'nama_produk',
      'nama',
      'toko_id',
      'karyawan_id',
      'tanggal',
      'tanggal_transaksi',
      'created_at',
      'updated_at',
      'status',
      'qty',
      'jumlah',
      'total_harga',
      'harga_jual',
      'subtotal',
      'tipe',
      'jenis',
      'keterangan',
      'catatan',
    ];
    final ranked = <String>[];
    for (final p in priority) {
      if (keys.contains(p)) ranked.add(p);
    }
    for (final k in keys) {
      if (!ranked.contains(k)) ranked.add(k);
    }
    return ranked;
  }

  // ---------------------------------------------------------------------------
  // Fetch helpers
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _fetchTable({
    required String table,
    String? dateColumn,
    String? start,
    String? end,
    String? orderBy,
  }) async {
    final all = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      var filter = _client.from(table).select();
      if (dateColumn != null && start != null && end != null) {
        final isDateOnly = dateColumn == 'tanggal' ||
            dateColumn == 'tanggal_transaksi' ||
            (!dateColumn.endsWith('_at') &&
                dateColumn != 'created_at' &&
                dateColumn != 'updated_at' &&
                dateColumn != 'timestamp_open');
        if (isDateOnly) {
          filter = filter
              .gte(dateColumn, start.substring(0, 10))
              .lte(dateColumn, end.substring(0, 10));
        } else {
          filter = filter.gte(dateColumn, start).lte(dateColumn, end);
        }
      }
      final page = orderBy != null
          ? await filter
              .order(orderBy, ascending: true)
              .range(from, from + _pageSize - 1)
          : await filter.range(from, from + _pageSize - 1);
      final list = List<Map<String, dynamic>>.from(page as List);
      all.addAll(list);
      if (list.length < _pageSize) break;
      from += _pageSize;
    }
    return all;
  }

  Future<List<Map<String, dynamic>>> _fetchSalesItems(
    List<Map<String, dynamic>> sales,
  ) async {
    if (sales.isEmpty) return [];
    final ids = sales
        .map((s) => s['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return [];

    final all = <Map<String, dynamic>>[];
    const chunk = 80;
    for (var i = 0; i < ids.length; i += chunk) {
      final slice =
          ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk);
      var from = 0;
      while (true) {
        final page = await _client
            .from('sales_items')
            .select()
            .inFilter('sale_id', slice)
            .order('id', ascending: true)
            .range(from, from + _pageSize - 1);
        final list = List<Map<String, dynamic>>.from(page as List);
        all.addAll(list);
        if (list.length < _pageSize) break;
        from += _pageSize;
      }
    }
    return all;
  }

  Map<String, dynamic> _sanitizeRow(
    Map<String, dynamic> row,
    Set<String> extraExclude,
  ) {
    final out = <String, dynamic>{};
    for (final e in row.entries) {
      final key = e.key;
      if (_secretColumns.contains(key) || extraExclude.contains(key)) continue;
      if (key == 'face_template') continue;
      out[key] = e.value;
    }
    return out;
  }

  String _humanizeHeader(String key) {
    final parts = key.split('_').where((p) => p.isNotEmpty);
    return parts.map((p) {
      if (p.length == 1) return p.toUpperCase();
      return '${p[0].toUpperCase()}${p.substring(1)}';
    }).join(' ');
  }

  String _formatCellDisplay(dynamic v, {int maxLen = 80}) {
    String raw;
    if (v == null) {
      raw = '';
    } else if (v is bool) {
      raw = v ? 'true' : 'false';
    } else if (v is DateTime) {
      raw = _displayDt.format(v.toLocal());
    } else if (v is Map || v is List) {
      try {
        raw = jsonEncode(v);
      } catch (_) {
        raw = v.toString();
      }
    } else if (v is String) {
      final s = v.trim();
      if (_looksLikeIsoDateTime(s)) {
        final parsed = DateTime.tryParse(s);
        if (parsed != null) {
          raw = s.length == 10
              ? _isoDay.format(parsed)
              : _displayDt.format(parsed.toLocal());
        } else {
          raw = v;
        }
      } else {
        raw = v;
      }
    } else {
      raw = v.toString();
    }
    if (raw.length > maxLen) return '${raw.substring(0, maxLen - 1)}…';
    return raw;
  }

  bool _looksLikeIsoDateTime(String s) {
    if (s.length < 10) return false;
    final day = RegExp(r'^\d{4}-\d{2}-\d{2}');
    if (!day.hasMatch(s)) return false;
    return s.contains('T') || s.contains(' ') || s.length == 10;
  }

  _ExportRange _buildRange(DateTime start, DateTime end) {
    var startDay = DateTime(start.year, start.month, start.day);
    var endDay = DateTime(end.year, end.month, end.day);
    if (endDay.isBefore(startDay)) {
      final tmp = startDay;
      startDay = endDay;
      endDay = tmp;
    }
    final startInclusive = startDay;
    final endInclusive =
        DateTime(endDay.year, endDay.month, endDay.day, 23, 59, 59, 999);
    final startIso =
        DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(startInclusive);
    final endIso =
        DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS").format(endInclusive);
    final label =
        '${_isoDay.format(startDay)} s/d ${_isoDay.format(endDay)}';
    final labelHuman =
        '${_humanDay.format(startDay)} – ${_humanDay.format(endDay)}';
    return _ExportRange(
      startDay: startDay,
      endDay: endDay,
      startIso: startIso,
      endIso: endIso,
      label: label,
      labelHuman: labelHuman,
    );
  }
}

class _PreparedTable {
  const _PreparedTable({
    required this.headers,
    required this.cells,
    required this.hiddenColumnCount,
  });

  final List<String> headers;
  final List<List<String>> cells;
  final int hiddenColumnCount;
}

class _ExportRange {
  const _ExportRange({
    required this.startDay,
    required this.endDay,
    required this.startIso,
    required this.endIso,
    required this.label,
    required this.labelHuman,
  });

  final DateTime startDay;
  final DateTime endDay;
  final String startIso;
  final String endIso;
  final String label;
  final String labelHuman;
}
