import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/export/monthly_data_export_service.dart';
import '../../shared/training/training_mode.dart';
import '../../shared/widgets/app_loading_overlay.dart';
import '../../shared/widgets/premium_date_range_picker.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Admin: ekspor laporan operasional ke PDF premium per rentang tanggal.
class MonthlyExportPage extends StatefulWidget {
  const MonthlyExportPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<MonthlyExportPage> createState() => _MonthlyExportPageState();
}

class _MonthlyExportPageState extends State<MonthlyExportPage> {
  final _service = MonthlyDataExportService();
  final _dayFmt = DateFormat('d MMM yyyy', 'id_ID');
  final _historyDtFmt = DateFormat('d MMM yyyy HH:mm', 'id_ID');
  final _domainScrollCtrl = ScrollController();
  final _domainSearchCtrl = TextEditingController();

  late DateTime _start;
  late DateTime _end;
  String _presetId = 'thisMonth';
  String _domainQuery = '';
  final Set<String> _selectedDomainIds = {
    for (final d in MonthlyDataExportService.allDomains) d.id,
  };
  ExportPdfMode _mode = ExportPdfMode.gabung;
  int? _nextSalinan;
  bool _salinanSchemaMissing = false;
  bool _historySchemaMissing = false;
  String? _infraErrorDetail;
  bool _busy = false;
  bool _historyLoading = true;
  String _progressMsg = '';
  double? _progress;
  List<String> _lastSummaries = const [];
  List<String> _lastErrors = const [];
  List<File> _lastExportFiles = const [];
  List<ExportDownloadHistoryEntry> _history = const [];

  static const _bg = OptikAdminTokens.bgMid;
  static const _card = OptikAdminTokens.card;
  static const _accent = Color(0xFF38BDF8);
  static const _gold = Color(0xFFC9A84C);

  static const _presetLabels = {
    'last7': '7 hari terakhir',
    'last30': '30 hari terakhir',
    'last60': '60 hari terakhir',
    'last90': '90 hari terakhir',
    'thisMonth': 'Bulan ini',
    'lastMonth': 'Bulan lalu',
    'lastYear': 'Tahun lalu',
  };

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String get _rangeTriggerLabel {
    final range = '${_dayFmt.format(_start)} – ${_dayFmt.format(_end)}';
    final name = _presetLabels[_presetId];
    if (name != null) return '$name: $range';
    return range;
  }

  bool get _multiSelected => _selectedDomainIds.length > 1;

  bool get _showInfraBanner =>
      _salinanSchemaMissing || _historySchemaMissing;

  bool get _isPusatExportAllowed {
    final toko = (widget.profile['toko_id'] ?? '').toString();
    final role = (widget.profile['role'] ?? '').toString();
    return toko == 'PUSAT' ||
        toko == 'CABANG-PUSAT' ||
        role == 'owner' ||
        role == 'admin_pusat';
  }

  @override
  void initState() {
    super.initState();
    final now = _dateOnly(DateTime.now());
    _start = DateTime(now.year, now.month, 1);
    _end = now;
    // Jangan setState dari initState (sync path _loadHistory dulu error di debug).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isPusatExportAllowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('export_pusat_only'.tr()),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        Navigator.pop(context);
        return;
      }
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _domainScrollCtrl.dispose();
    _domainSearchCtrl.dispose();
    super.dispose();
  }

  List<ExportDomain> get _filteredDomains {
    final q = _domainQuery.trim().toLowerCase();
    if (q.isEmpty) return MonthlyDataExportService.allDomains;
    return MonthlyDataExportService.allDomains
        .where((d) => d.sheetName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_refreshSalinanPreview(), _loadHistory()]);
  }

  Future<void> _refreshSalinanPreview() async {
    try {
      final peek = await _service.peekNextSalinan();
      if (!mounted) return;
      setState(() {
        _nextSalinan = peek.next;
        _salinanSchemaMissing = !peek.schemaReady;
        if (peek.error != null) _infraErrorDetail = peek.error;
      });
    } catch (e) {
      debugPrint('refresh salinan preview: $e');
      if (!mounted) return;
      setState(() {
        _nextSalinan = null;
        _salinanSchemaMissing = true;
        _infraErrorDetail = '$e';
      });
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => _historyLoading = true);
    try {
      final result = await _service.fetchHistory();
      if (!mounted) return;
      setState(() {
        _history = result.entries;
        _historySchemaMissing = !result.schemaReady;
        if (result.error != null) _infraErrorDetail = result.error;
        _historyLoading = false;
      });
    } catch (e) {
      debugPrint('load export history: $e');
      if (!mounted) return;
      setState(() {
        _history = const [];
        _historySchemaMissing =
            MonthlyDataExportService.isMissingExportSchema(e);
        _infraErrorDetail = '$e';
        _historyLoading = false;
      });
    }
  }

  Future<void> _openRangePicker() async {
    final result = await showPremiumDateRangePicker(
      context: context,
      initialStart: _start,
      initialEnd: _end,
      initialPresetId: _presetId,
    );
    if (result == null) return;
    setState(() {
      _start = _dateOnly(result.start);
      _end = _dateOnly(result.end);
      _presetId = result.presetId;
    });
  }

  void _selectAllDomains() {
    setState(() {
      _selectedDomainIds
        ..clear()
        ..addAll(MonthlyDataExportService.allDomains.map((d) => d.id));
    });
  }

  void _clearDomains() {
    setState(() => _selectedDomainIds.clear());
  }

  void _toggleDomain(String id, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedDomainIds.add(id);
      } else {
        _selectedDomainIds.remove(id);
      }
    });
  }

  String? get _adminEmail {
    final fromProfile = widget.profile['email']?.toString();
    if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
    return Supabase.instance.client.auth.currentUser?.email;
  }

  String? get _adminUserId {
    final fromProfile = widget.profile['id']?.toString();
    if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
    return Supabase.instance.client.auth.currentUser?.id;
  }

  Future<void> _runExport() async {
    if (_busy) return;

    if (_selectedDomainIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('export_no_domain'.tr()),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    // Training: non-real stub — no PDF generation / no prod export artifacts.
    if (TrainingMode.instance.isActive) {
      setState(() {
        _busy = false;
        _progress = 1;
        _progressMsg = 'training_export_stub_done'.tr();
        _nextSalinan = 1;
        _lastSummaries = ['training_export_stub_summary'.tr()];
        _lastErrors = const [];
        _lastExportFiles = const [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('training_export_stub_done'.tr()),
            backgroundColor: const Color(0xFFB45309),
          ),
        );
      }
      return;
    }

    setState(() {
      _busy = true;
      _progressMsg = 'export_progress_start'.tr();
      _progress = 0;
      _lastSummaries = const [];
      _lastErrors = const [];
      _lastExportFiles = const [];
    });

    try {
      final domains = MonthlyDataExportService.allDomains
          .where((d) => _selectedDomainIds.contains(d.id))
          .toList();

      final alloc = await _service.allocateSalinan();
      if (!mounted) return;
      setState(() {
        _nextSalinan = alloc.salinanKe;
        if (alloc.usedLocalFallback) {
          _salinanSchemaMissing = true;
          if (alloc.warning != null) _infraErrorDetail = alloc.warning;
        }
      });

      if (alloc.usedLocalFallback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('export_salinan_local_warn'.tr()),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      final result = await _service.exportRange(
        start: _start,
        end: _end,
        domains: domains,
        mode: _multiSelected ? _mode : ExportPdfMode.gabung,
        salinanKe: alloc.salinanKe,
        usedLocalSalinan: alloc.usedLocalFallback,
        adminUserId: _adminUserId,
        adminEmail: _adminEmail,
        onProgress: (msg, p) {
          if (!mounted) return;
          setState(() {
            _progressMsg = msg;
            _progress = p;
          });
        },
      );

      if (!mounted) return;
      final exportedFiles = List<File>.from(result.files);
      setState(() {
        _lastSummaries = result.sheetSummaries;
        _lastErrors = result.errors;
        _lastExportFiles = exportedFiles;
        if (result.historyFailed) {
          _historySchemaMissing = true;
          _infraErrorDetail = result.historyError;
        }
      });

      for (final f in exportedFiles) {
        if (!await f.exists()) {
          throw StateError('File ekspor tidak ada di disk: ${f.path}');
        }
      }

      final shareLabel =
          '${DateFormat('yyyy-MM-dd').format(_start)} – '
          '${DateFormat('yyyy-MM-dd').format(_end)}';

      await Share.shareXFiles(
        [
          for (final f in exportedFiles)
            XFile(
              f.path,
              name: f.uri.pathSegments.isNotEmpty
                  ? f.uri.pathSegments.last
                  : 'optik_briski_laporan.pdf',
              mimeType: 'application/pdf',
            ),
        ],
        text:
            'Optik B. Riski laporan $shareLabel · Salinan ke-${result.salinanKe}',
      );

      if (!mounted) return;

      await _refreshSalinanPreview();
      await _loadHistory();

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      if (result.historyFailed || result.usedLocalSalinan) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.usedLocalSalinan
                  ? 'export_salinan_local_warn'.tr()
                  : 'export_history_warn'.tr(),
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      final fileCount = exportedFiles.length;
      final doneMsg = result.hasErrors
          ? 'export_done_partial'.tr()
          : fileCount > 1
              ? 'export_done_ok_multi'.tr(
                  namedArgs: {
                    'n': '${result.salinanKe}',
                    'count': '$fileCount',
                  },
                )
              : 'export_done_ok'.tr(
                  namedArgs: {'n': '${result.salinanKe}'},
                );

      messenger.showSnackBar(
        SnackBar(
          content: Text(doneMsg),
          backgroundColor:
              result.hasErrors ? Colors.orange.shade800 : Colors.teal.shade700,
          duration: Duration(seconds: fileCount > 1 ? 8 : 6),
          action: SnackBarAction(
            label: fileCount > 1
                ? 'export_open_all'.tr(
                    namedArgs: {'count': '$fileCount'},
                  )
                : 'export_open_file'.tr(),
            textColor: Colors.white,
            onPressed: () => _openExportedFiles(exportedFiles),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyExportError(e)),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 8),
        ),
      );
      await _refreshSalinanPreview();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  String _friendlyExportError(Object e) {
    final raw = e.toString();
    if (raw.contains('PathNotFoundException') ||
        raw.contains('No such file or directory')) {
      return '${'export_failed'.tr()}: folder/file ekspor tidak ditemukan. '
          'Coba lagi; jika berulang, restart app. ($e)';
    }
    if (raw.contains('Permission') || raw.contains('Operation not permitted')) {
      return '${'export_failed'.tr()}: izin tulis file ditolak. ($e)';
    }
    if (MonthlyDataExportService.isMissingExportSchema(e) ||
        raw.contains('allocate_export_salinan') ||
        raw.contains('export_salinan')) {
      return '${'export_failed'.tr()}: '
          '${'export_salinan_rpc_missing'.tr()}';
    }
    return '${'export_failed'.tr()}: $e';
  }

  String _fileDisplayName(File f) {
    final segs = f.uri.pathSegments;
    return segs.isNotEmpty ? segs.last : f.path;
  }

  /// Buka semua PDF hasil ekspor (gabung = 1, pisah = N) sekaligus.
  Future<void> _openExportedFiles(List<File> files) async {
    final targets = files.isNotEmpty ? files : _lastExportFiles;
    if (targets.isEmpty) return;

    final missing = <String>[];
    final existing = <File>[];
    for (final f in targets) {
      if (await f.exists()) {
        existing.add(f);
      } else {
        missing.add(_fileDisplayName(f));
      }
    }

    final failed = <String>[...missing];

    if (existing.isNotEmpty) {
      try {
        if (Platform.isMacOS) {
          // Satu panggilan `open` membuka semua PDF di Preview / default app.
          final proc = await Process.run(
            'open',
            [for (final f in existing) f.path],
          );
          if (proc.exitCode != 0) {
            // Fallback per-file jika batch gagal.
            for (final f in existing) {
              final one = await Process.run('open', [f.path]);
              if (one.exitCode != 0) {
                failed.add(_fileDisplayName(f));
              }
            }
          }
        } else {
          for (final f in existing) {
            final opened = await OpenFile.open(
              f.path,
              type: 'application/pdf',
            );
            if (opened.type != ResultType.done) {
              failed.add(_fileDisplayName(f));
            }
          }
        }
      } catch (e) {
        debugPrint('open exported files: $e');
        failed.addAll(existing.map(_fileDisplayName));
      }
    }

    if (!mounted || failed.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'export_open_failed'.tr(
            namedArgs: {
              'failed': '${failed.length}',
              'total': '${targets.length}',
              'names': failed.take(3).join(', '),
            },
          ),
        ),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  String _domainLabel(String id) {
    return MonthlyDataExportService.domainById(id)?.sheetName ?? id;
  }

  String get _salinanPreviewLabel {
    if (_salinanSchemaMissing && _nextSalinan == null) return '—';
    if (_nextSalinan == null) return '…';
    return '$_nextSalinan';
  }

  @override
  Widget build(BuildContext context) {
    final salinanPreview = _salinanPreviewLabel;
    final modeEnabled = _multiSelected && !_busy;
    final filteredDomains = _filteredDomains;

    return PremiumScaffold(
      appBar: PremiumAppBar(title: 'export_page_title'.tr()),
      body: AppLoadingOverlay.gate(
        visible: _busy,
        message: _progressMsg.isEmpty
            ? 'export_progress_start'.tr()
            : _progressMsg,
        subtitle: _progress == null
            ? null
            : '${((_progress ?? 0) * 100).clamp(0, 100).toStringAsFixed(0)}%',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'export_page_desc'.tr(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'export_pdf_note'.tr(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            if (_showInfraBanner) ...[
              const SizedBox(height: 14),
              _infraBanner(),
            ],
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'export_date_range'.tr(),
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: _busy ? 0.5 : 1,
                    child: IgnorePointer(
                      ignoring: _busy,
                      child: PremiumDateRangeTrigger(
                        label: _rangeTriggerLabel,
                        onTap: _openRangePicker,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'export_jakarta_note'.tr(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'export_domains_select'.tr(),
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _selectAllDomains,
                        child: Text(
                          'export_select_all'.tr(),
                          style: TextStyle(
                            color: _accent.withOpacity(_busy ? 0.4 : 1),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _clearDomains,
                        child: Text(
                          'export_clear_all'.tr(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(_busy ? 0.25 : 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'export_selected_count'.tr(
                      namedArgs: {
                        'n': '${_selectedDomainIds.length}',
                        'total':
                            '${MonthlyDataExportService.allDomains.length}',
                      },
                    ),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _domainSearchCtrl,
                    enabled: !_busy,
                    onChanged: (v) => setState(() => _domainQuery = v),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                    ),
                    cursorColor: _accent,
                    decoration: InputDecoration(
                      hintText: 'export_domains_search'.tr(),
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 12.5,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: _accent.withOpacity(0.85),
                        size: 20,
                      ),
                      suffixIcon: _domainQuery.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'export_clear_all'.tr(),
                              onPressed: _busy
                                  ? null
                                  : () {
                                      _domainSearchCtrl.clear();
                                      setState(() => _domainQuery = '');
                                    },
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.white.withOpacity(0.45),
                              ),
                            ),
                      filled: true,
                      fillColor: _bg,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _accent.withOpacity(0.55),
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: filteredDomains.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 28,
                            ),
                            child: Center(
                              child: Text(
                                'export_domains_empty'.tr(),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.45),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          )
                        : Scrollbar(
                            controller: _domainScrollCtrl,
                            child: ListView.separated(
                              controller: _domainScrollCtrl,
                              primary: false,
                              shrinkWrap: true,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filteredDomains.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: Colors.white.withOpacity(0.05),
                              ),
                              itemBuilder: (context, i) {
                                final d = filteredDomains[i];
                                final checked =
                                    _selectedDomainIds.contains(d.id);
                                return CheckboxListTile(
                                  dense: true,
                                  value: checked,
                                  onChanged: _busy
                                      ? null
                                      : (v) => _toggleDomain(d.id, v),
                                  activeColor: _accent,
                                  checkColor: _bg,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text(
                                    d.isSnapshot
                                        ? '${d.sheetName} ★'
                                        : d.sheetName,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'export_snapshot_legend'.tr(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'export_output_mode'.tr(),
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Opacity(
                    opacity: modeEnabled ? 1 : 0.45,
                    child: Column(
                      children: [
                        RadioListTile<ExportPdfMode>(
                          dense: true,
                          value: ExportPdfMode.gabung,
                          groupValue: _multiSelected
                              ? _mode
                              : ExportPdfMode.gabung,
                          onChanged: modeEnabled
                              ? (v) {
                                  if (v != null) {
                                    setState(() => _mode = v);
                                  }
                                }
                              : null,
                          activeColor: _accent,
                          title: Text(
                            'export_mode_gabung'.tr(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'export_mode_gabung_hint'.tr(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        RadioListTile<ExportPdfMode>(
                          dense: true,
                          value: ExportPdfMode.pisah,
                          groupValue: _multiSelected
                              ? _mode
                              : ExportPdfMode.gabung,
                          onChanged: modeEnabled
                              ? (v) {
                                  if (v != null) {
                                    setState(() => _mode = v);
                                  }
                                }
                              : null,
                          activeColor: _accent,
                          title: Text(
                            'export_mode_pisah'.tr(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'export_mode_pisah_hint'.tr(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_multiSelected)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 8),
                      child: Text(
                        'export_mode_single_hint'.tr(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _gold.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.confirmation_number_outlined,
                            size: 18, color: _gold.withOpacity(0.9)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'export_salinan_label'.tr(
                                  namedArgs: {'n': salinanPreview},
                                ),
                                style: TextStyle(
                                  color: _gold.withOpacity(0.95),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _salinanSchemaMissing
                                    ? 'export_salinan_hint_missing'.tr()
                                    : 'export_salinan_hint'.tr(),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _runExport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: OptikAdminTokens.bgMid,
                        disabledBackgroundColor: Colors.blueGrey.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                      label: Text(
                        'export_btn_pdf'.tr(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.print_outlined,
                          size: 14, color: _gold.withOpacity(0.8)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'export_pdf_helper'.tr(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_lastSummaries.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                'export_last_result'.tr(),
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in _lastSummaries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          s,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_lastErrors.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'export_errors_title'.tr(),
                        style: TextStyle(
                          color: Colors.orange.shade300,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      for (final e in _lastErrors)
                        Text(
                          e,
                          style: TextStyle(
                            color: Colors.orange.shade200,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'export_history_title'.tr(),
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'export_history_refresh'.tr(),
                  onPressed: _busy || _historyLoading ? null : _loadHistory,
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_historyLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else if (_history.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _historySchemaMissing
                      ? 'export_history_migration'.tr()
                      : 'export_history_empty'.tr(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              )
            else
              ..._history.map(_historyTile),
          ],
        ),
      ),
    );
  }

  Widget _infraBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF7C2D12).withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade700.withOpacity(0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 20, color: Colors.orange.shade200),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'export_infra_banner'.tr(),
                  style: TextStyle(
                    color: Colors.orange.shade100,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (_infraErrorDetail != null &&
                    _infraErrorDetail!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _infraErrorDetail!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.orange.shade200.withOpacity(0.75),
                      fontSize: 10.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(ExportDownloadHistoryEntry h) {
    final domainNames = h.domains.map(_domainLabel).join(', ');
    final modeLabel = h.mode == ExportPdfMode.pisah
        ? 'export_mode_pisah_short'.tr()
        : 'export_mode_gabung_short'.tr();
    final period =
        '${_dayFmt.format(h.periodStart)} – ${_dayFmt.format(h.periodEnd)}';
    final who = (h.adminEmail != null && h.adminEmail!.isNotEmpty)
        ? h.adminEmail!
        : (h.adminUserId ?? '—');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'export_history_salinan'.tr(
                  namedArgs: {'n': '${h.salinanKe}'},
                ),
                style: TextStyle(
                  color: _gold.withOpacity(0.95),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                _historyDtFmt.format(h.createdAt),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            period,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '$modeLabel · ${'export_history_files'.tr(namedArgs: {
                  'n': '${h.fileCount}',
                })}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            domainNames.isEmpty ? '—' : domainNames,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 11,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'export_history_by'.tr(namedArgs: {'who': who}),
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
