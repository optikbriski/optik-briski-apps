import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/admin/admin_nav_badge_service.dart';
import '../../shared/widgets/admin/admin_nav_badge.dart';
import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/karyawan/pengaduan_case_flow.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/zoomable_network_image.dart';
import 'pengaduan_compose_page.dart';

/// Inbox Admin: terima pengaduan karyawan + laporan dari Admin (tutup loop).
class PengaduanInboxPage extends StatefulWidget {
  const PengaduanInboxPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<PengaduanInboxPage> createState() => _PengaduanInboxPageState();
}

class _PengaduanInboxPageState extends State<PengaduanInboxPage> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String? _busyId;
  String? _statusFilter;
  RealtimeChannel? _rt;
  Timer? _rtDebounce;

  @override
  void initState() {
    super.initState();
    _reload();
    _bindRealtime();
  }

  @override
  void dispose() {
    _rtDebounce?.cancel();
    final ch = _rt;
    _rt = null;
    if (ch != null) {
      unawaited(_db.removeChannel(ch));
    }
    super.dispose();
  }

  void _bindRealtime() {
    final ch = _db
        .channel('pengaduan-inbox')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pengaduan',
          callback: (_) {
            _rtDebounce?.cancel();
            _rtDebounce = Timer(const Duration(milliseconds: 400), () {
              if (mounted) unawaited(_reload(silent: true));
            });
          },
        );
    _rt = ch;
    ch.subscribe();
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _error = null;
    }
    try {
      final toko = AttendanceAdminScope.tokoOf(widget.profile);
      final isPusat = AttendanceAdminScope.isPusatTokoId(toko) ||
          AttendanceAdminScope.isPusatOperator(widget.profile);
      final keys = AttendanceAdminScope.storeIdAliases(toko);
      Future<List<Map<String, dynamic>>> load(String cols) async {
        var q = _db.from('pengaduan').select(cols);
        if (!isPusat && toko.isNotEmpty) {
          q = q.inFilter('toko_id', keys.isEmpty ? [toko] : keys);
        }
        final rows = await q.order('created_at', ascending: false).limit(80);
        return List<Map<String, dynamic>>.from(rows as List);
      }

      List<Map<String, dynamic>> rows;
      try {
        rows = await load(
          'id, karyawan_id, member_id, sumber, pelapor_nama, pelapor_kontak, '
          'pelapor_user_id, toko_id, kategori, kategori_kode, isi, items, '
          'foto_url, status, keputusan, stok_tindakan, stok_ref_id, '
          'balasan, dibalas_at, dibalas_oleh, created_at, '
          'karyawan:karyawan_id(nama, nik)',
        );
      } catch (_) {
        try {
          rows = await load(
            'id, karyawan_id, toko_id, kategori, kategori_kode, isi, items, '
            'foto_url, status, keputusan, stok_tindakan, stok_ref_id, '
            'balasan, dibalas_at, dibalas_oleh, created_at, '
            'karyawan:karyawan_id(nama, nik)',
          );
        } catch (_) {
          rows = await load(
            'id, karyawan_id, toko_id, kategori, isi, foto_url, status, '
            'balasan, dibalas_at, dibalas_oleh, created_at, '
            'karyawan:karyawan_id(nama, nik)',
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visible {
    final f = _statusFilter;
    if (f == null) return _rows;
    return _rows
        .where((r) => (r['status'] ?? 'OPEN').toString().toUpperCase() == f)
        .toList();
  }

  int _count(String status) {
    return _rows
        .where((r) => (r['status'] ?? 'OPEN').toString().toUpperCase() == status)
        .length;
  }

  Future<void> _reply(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    unawaited(AdminNavBadgeService.instance.markEntitySeen('pengaduan', id));
    final current = (row['status'] ?? 'OPEN').toString().toUpperCase();
    final action = await showDialog<_CaseAction>(
      context: context,
      barrierColor: OptikAdminTokens.navy.withOpacity(0.28),
      builder: (ctx) => _PengaduanCaseDialog(
        row: row,
        currentStatus: current,
      ),
    );
    if (action == null || !mounted) return;

    setState(() => _busyId = id);
    try {
      if (!action.close) {
        await _submitCase(
          id: id,
          status: 'IN_PROGRESS',
          body: action.body,
        );
      } else {
        await _decideCase(
          id: id,
          approve: action.approve,
          body: action.body,
          stokTindakan: action.stok,
          kategoriKode: PengaduanCaseFlow.kategoriKodeOf(row),
        );
      }
      if (!mounted) return;
      _snack(
        !action.close
            ? 'pengaduan_admin_open_ok'.tr()
            : action.approve
                ? 'pengaduan_admin_approve_ok'.tr()
                : 'pengaduan_admin_reject_ok'.tr(),
        action.close && !action.approve
            ? OptikAdminTokens.danger
            : OptikAdminTokens.success,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      _snack('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _submitCase({
    required String id,
    required String status,
    required String body,
  }) async {
    Future<Map<String, dynamic>> call(String balasan) async {
      final res = await _db.rpc('reply_pengaduan', params: {
        'p_id': id,
        'p_balasan': balasan,
        'p_status': status,
      });
      return res is Map ? Map<String, dynamic>.from(res) : {};
    }

    var map = await call(body);
    if (map['ok'] != true &&
        status == 'IN_PROGRESS' &&
        body.trim().isEmpty) {
      final err = '${map['error'] ?? ''}'.toLowerCase();
      if (err.contains('wajib') || err.contains('required')) {
        map = await call('pengaduan_admin_open_placeholder'.tr());
      }
    }
    if (map['ok'] != true) {
      throw map['error'] ?? 'Gagal memperbarui kasus';
    }
  }

  Future<void> _decideCase({
    required String id,
    required bool approve,
    required String body,
    String? stokTindakan,
    String kategoriKode = '',
  }) async {
    try {
      final res = await _db.rpc('decide_pengaduan', params: {
        'p_id': id,
        'p_keputusan': approve ? 'APPROVE' : 'REJECT',
        'p_balasan': body,
        'p_stok_tindakan': stokTindakan,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : {};
      if (map['ok'] != true) {
        throw map['error'] ?? 'Gagal memutus kasus';
      }
      return;
    } catch (e) {
      final msg = '$e'.toLowerCase();
      final rpcMissing = msg.contains('could not find') ||
          msg.contains('pgrst202') ||
          msg.contains('schema cache');
      if (!rpcMissing) rethrow;
      if (!PengaduanCaseFlow.canFallbackReplyForDecide(
        approve: approve,
        kategoriKode: kategoriKode,
      )) {
        throw 'RPC decide_pengaduan belum ada. Terapkan migration stok dulu — jangan setujui produk tanpa ledger.';
      }
    }
    await _submitCase(
      id: id,
      status: approve ? 'DONE' : 'REJECTED',
      body: body,
    );
  }

  Future<void> _openCompose() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PengaduanComposePage(profile: widget.profile),
      ),
    );
    if (ok == true && mounted) await _reload();
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          msg,
          style: TextStyle(
            color: OptikAdminTokens.snow,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminNavBadgeService.instance,
      builder: (context, _) {
        final visible = _visible;
        return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'pengaduan_admin_title'.tr(),
        subtitle: 'pengaduan_admin_subtitle'.tr(),
        actions: [
          IconButton(
            tooltip: 'pengaduan_admin_buat'.tr(),
            onPressed: _openCompose,
            icon: Icon(Icons.add_rounded, color: OptikAdminTokens.navy),
          ),
          IconButton(
            tooltip: 'pengaduan_admin_title'.tr(),
            onPressed: _loading ? null : _reload,
            icon: Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: PremiumPanel(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              borderRadius: 16,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _FilterPill(
                          label: 'pengaduan_admin_filter_all'.tr(),
                          count: _rows.length,
                          selected: _statusFilter == null,
                          expand: true,
                          onTap: () => setState(() => _statusFilter = null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilterPill(
                          label: _statusLabel('OPEN'),
                          count: AdminNavBadgeService.instance
                              .displayCount('pengaduan'),
                          selected: _statusFilter == 'OPEN',
                          expand: true,
                          onTap: () => setState(() => _statusFilter = 'OPEN'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilterPill(
                          label: _statusLabel('IN_PROGRESS'),
                          count: _count('IN_PROGRESS'),
                          selected: _statusFilter == 'IN_PROGRESS',
                          expand: true,
                          onTap: () =>
                              setState(() => _statusFilter = 'IN_PROGRESS'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterPill(
                          label: _statusLabel('DONE'),
                          count: _count('DONE'),
                          selected: _statusFilter == 'DONE',
                          expand: true,
                          onTap: () => setState(() => _statusFilter = 'DONE'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilterPill(
                          label: _statusLabel('REJECTED'),
                          count: _count('REJECTED'),
                          selected: _statusFilter == 'REJECTED',
                          expand: true,
                          onTap: () =>
                              setState(() => _statusFilter = 'REJECTED'),
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading && _rows.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      color: OptikAdminTokens.navy,
                    ),
                  )
                : _error != null
                    ? PremiumEmptyState(
                        icon: Icons.cloud_off_outlined,
                        accent: OptikAdminTokens.danger,
                        title: 'pengaduan_admin_title'.tr(),
                        message: _error!,
                        action: FilledButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text('common_retry'.tr()),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _reload,
                        color: OptikAdminTokens.navy,
                        child: visible.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.sizeOf(context).height * 0.45,
                                    child: PremiumEmptyState(
                                      icon: Icons.inbox_outlined,
                                      title: 'pengaduan_admin_empty'.tr(),
                                      message:
                                          'pengaduan_admin_empty_hint'.tr(),
                                      action: FilledButton.icon(
                                        onPressed: _openCompose,
                                        icon: const Icon(
                                          Icons.add_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'pengaduan_admin_buat'.tr(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  32,
                                ),
                                itemCount: visible.length,
                                itemBuilder: (context, i) =>
                                    _card(visible[i]),
                              ),
                      ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final busy = _busyId == id;
    final st = (row['status'] ?? 'OPEN').toString().toUpperCase();
    final nama = PengaduanCaseFlow.pelaporNama(row);
    final kontak = PengaduanCaseFlow.pelaporKontak(row);
    final bukanKaryawan = PengaduanCaseFlow.isNonKaryawanSumber(row);
    final when = DateTime.tryParse((row['created_at'] ?? '').toString());
    final balasan = (row['balasan'] ?? '').toString().trim();
    final foto = (row['foto_url'] ?? '').toString().trim();
    final kode = PengaduanCaseFlow.kategoriKodeOf(row);
    final kategori = kode.isNotEmpty
        ? PengaduanCaseFlow.labelKey(kode).tr()
        : (row['kategori'] ?? '-').toString();
    final toko = (row['toko_id'] ?? '-').toString();
    final items = PengaduanCaseFlow.parseItems(row['items']);
    final stokTindakan = (row['stok_tindakan'] ?? '').toString().toUpperCase();
    final unread = st == 'OPEN' &&
        id.isNotEmpty &&
        AdminNavBadgeService.instance.isEntityUnread('pengaduan', id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPress: st == 'OPEN' && id.isNotEmpty
            ? () => unawaited(AdminNavBadgeService.instance
                .markEntityUnread('pengaduan', id))
            : null,
        child: PremiumPanel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          borderRadius: 20,
          showAccentBar: st != 'DONE' && st != 'REJECTED',
          onTap: busy ? null : () => _reply(row),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminNavBadgeOverlay(
                    count: unread ? 1 : 0,
                    child: PremiumIconBadge(
                      icon: _kategoriIcon(kode.isNotEmpty ? kode : kategori),
                      size: 44,
                      color: st == 'OPEN'
                          ? OptikAdminTokens.warning
                          : st == 'REJECTED'
                              ? OptikAdminTokens.danger
                              : OptikAdminTokens.ice,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kategori.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        nama,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          height: 1.2,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (kontak.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          bukanKaryawan ? kontak : 'NIK $kontak',
                          style: TextStyle(
                            color: OptikAdminTokens.slate,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: st),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${PengaduanCaseFlow.sumberLabelKey(row).tr()} · $toko'
              '${when == null ? '' : ' · ${DateFormat('d MMM · HH:mm').format(when.toLocal())}'}',
              style: TextStyle(
                color: OptikAdminTokens.slate,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              (row['isi'] ?? '').toString(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: OptikAdminTokens.textPrimary,
                height: 1.4,
                fontSize: 13.5,
              ),
            ),
            if (foto.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => showZoomableImageDialog(context, foto),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      foto,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 88,
                        height: 88,
                        color: OptikAdminTokens.bgMid,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: OptikAdminTokens.slate,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...items.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${e.nama}  ×${e.qty}',
                    style: TextStyle(
                      color: OptikAdminTokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            if (stokTindakan == 'BUANG' || stokTindakan == 'BALIK') ...[
              const SizedBox(height: 6),
              Text(
                stokTindakan == 'BUANG'
                    ? 'pengaduan_admin_stok_buang'.tr()
                    : 'pengaduan_admin_stok_balik'.tr(),
                style: TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (balasan.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: OptikAdminTokens.ice.withOpacity(
                    OptikAdminTokens.isDark ? 0.12 : 0.38,
                  ),
                  border: Border.all(
                    color: OptikAdminTokens.chromeEdge.withOpacity(0.8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'pengaduan_admin_sudah_balas'.tr(namedArgs: {
                        'oleh': (row['dibalas_oleh'] ?? 'Admin').toString(),
                      }),
                      style: TextStyle(
                        color: OptikAdminTokens.navy,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      balasan,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: OptikAdminTokens.navy,
                      ),
                    )
                  : Text(
                      PengaduanCaseFlow.tapKey(st).tr(),
                      style: TextStyle(
                        color: OptikAdminTokens.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _CaseAction {
  const _CaseAction.open()
      : close = false,
        approve = false,
        body = '',
        stok = null;
  const _CaseAction.decide({
    required this.approve,
    required this.body,
    this.stok,
  }) : close = true;

  final bool close;
  final bool approve;
  final String body;
  final String? stok;
}

class _PengaduanCaseDialog extends StatefulWidget {
  const _PengaduanCaseDialog({
    required this.row,
    required this.currentStatus,
  });

  final Map<String, dynamic> row;
  final String currentStatus;

  @override
  State<_PengaduanCaseDialog> createState() => _PengaduanCaseDialogState();
}

class _PengaduanCaseDialogState extends State<_PengaduanCaseDialog> {
  late final TextEditingController _ctrl;
  late bool _tindakanMode;
  bool? _approve;
  String? _stok;
  String? _error;

  bool get _canOpen => PengaduanCaseFlow.canOpenCase(widget.currentStatus);
  bool get _closed => PengaduanCaseFlow.isClosed(widget.currentStatus);
  String get _kode => PengaduanCaseFlow.kategoriKodeOf(widget.row);
  bool get _isProduk => PengaduanCaseFlow.isProduk(_kode);
  bool get _tokoPusat =>
      AttendanceAdminScope.isPusatTokoId(widget.row['toko_id']?.toString());

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: (widget.row['balasan'] ?? '').toString(),
    );
    _tindakanMode = widget.currentStatus.toUpperCase() == 'IN_PROGRESS';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      filled: true,
      fillColor: OptikAdminTokens.bgMid.withOpacity(0.7),
      labelStyle: TextStyle(color: OptikAdminTokens.slate),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: OptikAdminTokens.chromeEdge),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: OptikAdminTokens.navy, width: 1.4),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: OptikAdminTokens.navy.withOpacity(0.28),
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: OptikAdminTokens.chromeEdge),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          body,
          style: TextStyle(
            color: OptikAdminTokens.slate,
            height: 1.4,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: OptikAdminTokens.slate),
            child: Text('pengaduan_admin_batal'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.onHighlight,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _openCase() async {
    final ok = await _confirm(
      title: 'pengaduan_admin_confirm_open_title'.tr(),
      body: 'pengaduan_admin_confirm_open_body'.tr(),
      confirmLabel: 'pengaduan_admin_confirm_open_btn'.tr(),
    );
    if (!ok || !mounted) return;
    Navigator.pop(context, const _CaseAction.open());
  }

  Future<void> _submitTindakan() async {
    if (_approve == null) {
      setState(() => _error = 'pengaduan_admin_err_keputusan'.tr());
      return;
    }
    final body = _ctrl.text.trim();
    final block = PengaduanCaseFlow.decideBlocker(
      approve: _approve!,
      alasan: body,
      kategoriKode: _kode,
      stokTindakan: _stok,
      tokoPusat: _tokoPusat,
    );
    if (block != null) {
      setState(() => _error = block.tr());
      return;
    }
    final ok = await _confirm(
      title: _approve!
          ? 'pengaduan_admin_confirm_approve_title'.tr()
          : 'pengaduan_admin_confirm_reject_title'.tr(),
      body: _approve!
          ? '${'pengaduan_admin_confirm_approve_body'.tr()}\n\n“$body”'
          : '${'pengaduan_admin_confirm_reject_body'.tr()}\n\n“$body”',
      confirmLabel: _approve!
          ? 'pengaduan_admin_confirm_approve_btn'.tr()
          : 'pengaduan_admin_confirm_reject_btn'.tr(),
    );
    if (!ok || !mounted) return;
    Navigator.pop(
      context,
      _CaseAction.decide(
        approve: _approve!,
        body: body,
        stok: _approve! && _isProduk ? _stok : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isi = (widget.row['isi'] ?? '').toString();
    final items = PengaduanCaseFlow.parseItems(widget.row['items']);
    final hint = _closed
        ? 'pengaduan_admin_done_hint'.tr()
        : _tindakanMode
            ? 'pengaduan_admin_tindakan_hint'.tr()
            : 'pengaduan_admin_case_choose'.tr();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: PremiumPanel(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          borderRadius: 22,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'pengaduan_admin_case_title'.tr(),
                  style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isi,
                  style: TextStyle(
                    color: OptikAdminTokens.slate,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...items.map(
                    (e) => Text(
                      '• ${e.nama}  ×${e.qty}',
                      style: TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  hint,
                  style: TextStyle(
                    color: OptikAdminTokens.slate,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                if (_closed)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: OptikAdminTokens.slate,
                      ),
                      child: Text('pengaduan_admin_batal'.tr()),
                    ),
                  )
                else if (!_tindakanMode) ...[
                  _CaseChoiceButton(
                    label: 'pengaduan_admin_open_case'.tr(),
                    hint: 'pengaduan_admin_open_hint'.tr(),
                    icon: Icons.folder_open_rounded,
                    filled: false,
                    onPressed: _openCase,
                  ),
                  const SizedBox(height: 10),
                  _CaseChoiceButton(
                    label: 'pengaduan_admin_tindakan'.tr(),
                    hint: 'pengaduan_admin_tindakan_btn_hint'.tr(),
                    icon: Icons.gavel_rounded,
                    filled: true,
                    onPressed: () => setState(() {
                      _tindakanMode = true;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: OptikAdminTokens.slate,
                      ),
                      child: Text('pengaduan_admin_batal'.tr()),
                    ),
                  ),
                ] else ...[
                  Text(
                    'pengaduan_admin_keputusan'.tr().toUpperCase(),
                    style: TextStyle(
                      color: OptikAdminTokens.slate,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterPill(
                          label: 'pengaduan_admin_approve'.tr(),
                          selected: _approve == true,
                          onTap: () => setState(() {
                            _approve = true;
                            _error = null;
                            if (_tokoPusat) _stok = PengaduanCaseFlow.stokBuang;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilterPill(
                          label: 'pengaduan_admin_reject'.tr(),
                          selected: _approve == false,
                          onTap: () => setState(() {
                            _approve = false;
                            _stok = null;
                            _error = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (_approve == true && _isProduk) ...[
                    const SizedBox(height: 14),
                    Text(
                      'pengaduan_admin_stok_label'.tr().toUpperCase(),
                      style: TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _CaseChoiceButton(
                      label: 'pengaduan_admin_stok_buang'.tr(),
                      hint: 'pengaduan_admin_stok_buang_hint'.tr(),
                      icon: Icons.delete_outline_rounded,
                      filled: _stok == PengaduanCaseFlow.stokBuang,
                      onPressed: () => setState(() {
                        _stok = PengaduanCaseFlow.stokBuang;
                        _error = null;
                      }),
                    ),
                    if (!_tokoPusat) ...[
                      const SizedBox(height: 8),
                      _CaseChoiceButton(
                        label: 'pengaduan_admin_stok_balik'.tr(),
                        hint: 'pengaduan_admin_stok_balik_hint'.tr(),
                        icon: Icons.undo_rounded,
                        filled: _stok == PengaduanCaseFlow.stokBalik,
                        onPressed: () => setState(() {
                          _stok = PengaduanCaseFlow.stokBalik;
                          _error = null;
                        }),
                      ),
                    ],
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _ctrl,
                    maxLines: 5,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    decoration: _fieldDeco('pengaduan_admin_close_reply'.tr()),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: OptikAdminTokens.danger,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          if (_canOpen) {
                            setState(() {
                              _tindakanMode = false;
                              _error = null;
                            });
                          } else {
                            Navigator.pop(context);
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: OptikAdminTokens.slate,
                        ),
                        child: Text(
                          _canOpen
                              ? 'pengaduan_admin_kembali'.tr()
                              : 'pengaduan_admin_batal'.tr(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PremiumPrimaryButton(
                          label: 'pengaduan_admin_kirim_tindakan'.tr(),
                          icon: Icons.send_rounded,
                          expand: true,
                          onPressed: _submitTindakan,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaseChoiceButton extends StatelessWidget {
  const _CaseChoiceButton({
    required this.label,
    required this.hint,
    required this.icon,
    required this.onPressed,
    required this.filled,
  });

  final String label;
  final String hint;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? OptikAdminTokens.onHighlight : OptikAdminTokens.navy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: filled ? OptikAdminTokens.navy : OptikAdminTokens.bgMid,
            border: Border.all(
              color: filled
                  ? OptikAdminTokens.navy
                  : OptikAdminTokens.chromeEdge,
            ),
            boxShadow: filled ? OptikAdminTokens.glow(OptikAdminTokens.navy) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: TextStyle(
                        color: filled
                            ? fg.withOpacity(0.82)
                            : OptikAdminTokens.slate,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'IN_PROGRESS':
      return 'pengaduan_status_progress'.tr();
    case 'DONE':
      return 'pengaduan_status_done'.tr();
    case 'REJECTED':
      return 'pengaduan_status_rejected'.tr();
    default:
      return 'pengaduan_status_open'.tr();
  }
}

IconData _kategoriIcon(String kategori) {
  final s = kategori.toLowerCase();
  if (s == 'sistem' ||
      s.contains('sistem') ||
      s.contains('aplikasi') ||
      s.contains('system') ||
      s.contains('app')) {
    return Icons.settings_suggest_rounded;
  }
  if (s == 'toko' ||
      s.contains('alat') ||
      s.contains('toko') ||
      s.contains('equipment')) {
    return Icons.storefront_rounded;
  }
  if (s == 'produk' ||
      s.contains('stok') ||
      s.contains('stock') ||
      s.contains('produk')) {
    return Icons.inventory_2_rounded;
  }
  if (s == 'customer' || s.contains('customer') || s.contains('pelanggan')) {
    return Icons.support_agent_rounded;
  }
  if (s == 'partner' || s.contains('partner') || s.contains('mitra')) {
    return Icons.handshake_rounded;
  }
  if (s == 'pelanggaran' ||
      s.contains('langgar') ||
      s.contains('violation') ||
      s.contains('rahasia') ||
      s.contains('confidential')) {
    return Icons.gavel_rounded;
  }
  return Icons.forum_rounded;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (status == 'DONE') {
      color = OptikAdminTokens.success;
    } else if (status == 'REJECTED') {
      color = OptikAdminTokens.danger;
    } else if (status == 'IN_PROGRESS') {
      color = OptikAdminTokens.navy;
    } else {
      color = OptikAdminTokens.warning;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(OptikAdminTokens.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(
        _statusLabel(status).toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.expand = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ink =
        selected ? OptikAdminTokens.onHighlight : OptikAdminTokens.navy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: expand ? 8 : 12,
            vertical: expand ? 9 : 7,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? OptikAdminTokens.navy
                : OptikAdminTokens.ice.withOpacity(
                    OptikAdminTokens.isKombo ? 0.45 : 0.32,
                  ),
            border: Border.all(
              color: selected
                  ? OptikAdminTokens.navy
                  : OptikAdminTokens.chromeEdge,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: ink.withOpacity(0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
