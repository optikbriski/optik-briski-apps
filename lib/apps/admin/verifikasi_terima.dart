// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/admin/admin_nav_badge_service.dart';
import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/logistics/do_cart_lines.dart';
import '../../shared/logistics/do_lifecycle_service.dart';
import '../../shared/logistics/logistics_tracking_service.dart';
import '../../shared/logistics/receive_queue_service.dart';
import '../../shared/logistics/receive_verification_rules.dart';
import '../../shared/logistics/request_order_service.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_nav_badge.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Antrian terima paket di cabang: DO · RO · Retur (status TRANSIT / PENDING).
class IncomingVerification extends StatefulWidget {
  final Map<String, dynamic> profile;
  const IncomingVerification({super.key, required this.profile});

  @override
  State<IncomingVerification> createState() => _IncomingVerificationState();
}

class _IncomingVerificationState extends State<IncomingVerification> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  bool _receiving = false;
  String? _error;
  String _kindFilter = 'all'; // all | do | ro | retur

  String get _myToko {
    final t = widget.profile['toko_id']?.toString().trim().toUpperCase() ?? '';
    return t == 'NULL' ? '' : t;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _moveKind(Map<String, dynamic> item) =>
      ReceiveVerificationRules.kindOf(item);

  String _kindLabel(String kind) {
    switch (kind) {
      case 'do':
        return 'DO';
      case 'ro':
        return 'RO';
      case 'retur':
        return 'Retur';
      default:
        return 'Lainnya';
    }
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'do':
        return OptikAdminTokens.warning;
      case 'ro':
        return OptikAdminTokens.ice;
      case 'retur':
        return OptikAdminTokens.slate;
      default:
        return OptikAdminTokens.textMuted;
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_kindFilter == 'all') return _tasks;
    return _tasks.where((e) => _moveKind(e) == _kindFilter).toList();
  }

  int _countKind(String kind) {
    if (kind == 'all') return _tasks.length;
    return _tasks.where((e) => _moveKind(e) == kind).length;
  }

  String _cleanItems(String raw) {
    final parsed = DoCartLines.parseKeterangan(raw);
    if (parsed.isEmpty) {
      return raw.trim().isEmpty ? '-' : raw;
    }
    return parsed
        .map((it) => '${it['nama'] ?? '-'} (${DoCartLines.qtyOf(it)}x)')
        .join(', ');
  }

  String _formatWhen(dynamic iso) {
    final raw = iso?.toString() ?? '';
    if (raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    return DateFormat('dd/MM/yy HH:mm').format(dt);
  }

  Future<void> _load() async {
    if (!ReceiveVerificationRules.canOpenIncomingQueue(widget.profile)) {
      setState(() {
        _tasks = [];
        _loading = false;
        _error = 'Hanya admin toko/pusat yang boleh buka verifikasi terima.';
      });
      return;
    }
    if (_myToko.isEmpty) {
      setState(() {
        _tasks = [];
        _loading = false;
        _error = 'Profil belum punya cabang (toko_id).';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ReceiveQueueService(client: _db).listIncoming(
        tokoId: _myToko,
      );

      if (!mounted) return;
      setState(() {
        _tasks = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
        _tasks = [];
      });
    }
  }

  Future<void> _confirmThenReceive(Map<String, dynamic> task) async {
    if (_receiving || _loading) return;
    final tid = task['id']?.toString() ?? '';
    if (tid.isNotEmpty) {
      unawaited(AdminNavBadgeService.instance.markEntitySeen('logistik', tid));
    }
    final kind = _moveKind(task);
    final resi = (task['product_name'] ?? '-').toString();
    final qty = ReceiveVerificationRules.volumeOf(task);
    final dari = (task['dari_lokasi'] ?? '-').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Terima paket ${_kindLabel(kind)}?',
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        content: Text(
          '$resi\n'
          'Dari $dari · $qty pcs\n\n'
          '${'admin_auto_receive_photo_stock'.tr()}'
          '${kind == 'ro' ? 'admin_auto_ro_complete_suffix'.tr() : '.'}',
          style: TextStyle(
            color: OptikAdminTokens.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('appr_btn_batal'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('smr_btn_foto_terima'.tr()),
          ),
        ],
      ),
    );
    if (ok == true) await _prosesVerifikasi(task);
  }

  Future<void> _prosesVerifikasi(Map<String, dynamic> task) async {
    if (_receiving) return;
    final moveId = task['id'].toString();

    final fresh = await _db
        .from('stock_move_history')
        .select()
        .eq('id', moveId)
        .maybeSingle();
    if (fresh == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_a59ed2aec5'.tr()),
        backgroundColor: OptikAdminTokens.danger,
      ));
      return;
    }

    final row = Map<String, dynamic>.from(fresh);
    final ke = (row['ke_lokasi'] ?? '').toString().trim();
    if (ke.isNotEmpty &&
        _myToko.isNotEmpty &&
        !AttendanceAdminScope.sameTokoId(ke, _myToko) &&
        !AttendanceAdminScope.canReceiveStockToko(widget.profile, ke)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_0a081723e8'.tr(namedArgs: {'dest': ke, 'toko': _myToko})),
        backgroundColor: OptikAdminTokens.danger,
      ));
      return;
    }

    final st = (row['status'] ?? '').toString().toUpperCase();
    if (st == 'SUCCESS') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_bb975cbe2f'.tr()),
        backgroundColor: OptikAdminTokens.warning,
      ));
      _load();
      return;
    }
    if (!ReceiveVerificationRules.canReceiveAtToko(
      widget.profile,
      ke,
      st,
    )) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Tidak bisa terima. Status: ${LogisticsTrackingService.statusLabel(st)}.',
        ),
        backgroundColor: OptikAdminTokens.warning,
      ));
      _load();
      return;
    }

    if (!mounted) return;
    final photo = await pickImageSafe(
      picker: _picker,
      context: context,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 50,
    );
    if (photo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("inc_err_foto".tr()),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }

    setState(() => _receiving = true);
    try {
      final bytes = await photo.readAsBytes();
      final path =
          'konfirmasi/${moveId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _db.storage.from('attendance_photos').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final imgUrl = _db.storage.from('attendance_photos').getPublicUrl(path);
      if (!ReceiveVerificationRules.photoOk(imgUrl)) {
        throw 'Foto terima wajib sebelum stok masuk.';
      }

      final resiName = (row['product_name'] ?? '').toString();
      final kind = _moveKind(row);
      final verifierName = (widget.profile['nama'] ??
              widget.profile['full_name'] ??
              'Admin')
          .toString();
      final verifierId = widget.profile['id']?.toString() ??
          widget.profile['user_id']?.toString() ??
          _db.auth.currentUser?.id ??
          '';

      await DoLifecycleService(client: _db).receive(
        moveId: moveId,
        verifiedBy: verifierId,
        verifiedByName: verifierName,
        buktiFotoPenerima: imgUrl,
      );

      // RO: sync pending_requests → SUCCESS + sales_items READY.
      if (kind == 'ro') {
        try {
          await RequestOrderService().markSuccessFromMove(
            stockMoveId: moveId,
            resi: resiName,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('admin_auto_19b615cc3f'.tr(namedArgs: {'error': '$e'})),
              backgroundColor: OptikAdminTokens.warning,
            ));
          }
        }
      } else {
        // DO juga boleh punya tautan RO partial — coba sync, diam jika kosong.
        try {
          await RequestOrderService().markSuccessFromMove(
            stockMoveId: moveId,
            resi: resiName,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          kind == 'ro'
              ? 'RO diterima. Stok bertambah & request selesai.'
              : "smr_sukses_terima".tr(),
        ),
        backgroundColor: OptikAdminTokens.success,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_81f1f4d587'.tr(namedArgs: {'error': '$e'})),
        backgroundColor: OptikAdminTokens.danger,
      ));
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  void _showDetail(Map<String, dynamic> task) {
    final tid = task['id']?.toString() ?? '';
    if (tid.isNotEmpty) {
      unawaited(AdminNavBadgeService.instance.markEntitySeen('logistik', tid));
    }
    final kind = _moveKind(task);
    final status = (task['status'] ?? '').toString();
    final resi = (task['product_name'] ?? '-').toString();
    final dari = (task['dari_lokasi'] ?? '-').toString();
    final ke = (task['ke_lokasi'] ?? '-').toString();
    final kurir = (task['kurir_nama'] ?? '').toString().trim();
    final items = _cleanItems(task['keterangan']?.toString() ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          resi,
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _badge(_kindLabel(kind), _kindColor(kind)),
                _badge(
                  LogisticsTrackingService.statusLabel(status),
                  OptikAdminTokens.warning,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('admin_auto_c6177e9164'.tr(namedArgs: {'dari': dari, 'dest': ke}),
                style: TextStyle(
                    color: OptikAdminTokens.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text('admin_lbl_jumlah_pcs'.tr(namedArgs: {'n': '${ReceiveVerificationRules.volumeOf(task)}'}),
                style: TextStyle(
                    color: OptikAdminTokens.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text('admin_lbl_dikirim_when'.tr(namedArgs: {'when': _formatWhen(task['created_at'])}),
                style: TextStyle(
                    color: OptikAdminTokens.textMuted, fontSize: 12)),
            if (kurir.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('admin_auto_1a580f45d3'.tr(namedArgs: {'kurir': kurir}),
                  style: TextStyle(
                      color: OptikAdminTokens.textMuted, fontSize: 12)),
            ],
            const SizedBox(height: 10),
            Text('smr_isi_paket'.tr(),
                style: TextStyle(
                    color: OptikAdminTokens.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(items,
                style: TextStyle(
                    color: OptikAdminTokens.navy, fontSize: 12.5, height: 1.35)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('admin_btn_close'.tr()),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmThenReceive(task);
            },
            child: Text('smr_btn_foto_terima'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _kindChip(String kind, String label) {
    final active = _kindFilter == kind;
    final count = _countKind(kind);
    final unreadAll = kind == 'all'
        ? AdminNavBadgeService.instance.displayCount('logistik')
        : 0;
    final color = kind == 'all'
        ? OptikAdminTokens.textSecondary
        : _kindColor(kind);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: active ? color.withOpacity(0.14) : OptikAdminTokens.bgMid,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _kindFilter = kind),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? color.withOpacity(0.5)
                      : OptikAdminTokens.lineStrong,
                ),
              ),
              child: Column(
                children: [
                  if (kind == 'all' && unreadAll > 0)
                    AdminNavBadge(count: unreadAll, compact: true)
                  else
                    Text(
                      '$count',
                      style: TextStyle(
                        color: active ? color : OptikAdminTokens.textSecondary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? color : OptikAdminTokens.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> task) {
    final tid = task['id']?.toString() ?? '';
    final unread = tid.isNotEmpty &&
        AdminNavBadgeService.instance.isEntityUnread('logistik', tid);
    final kind = _moveKind(task);
    final kindColor = _kindColor(kind);
    final resi = (task['product_name'] ?? '-').toString();
    final dari = (task['dari_lokasi'] ?? '-').toString();
    final qty = ReceiveVerificationRules.volumeOf(task);
    final kurir = (task['kurir_nama'] ?? '').toString().trim();
    final when = _formatWhen(task['created_at']);
    final preview = _cleanItems(task['keterangan']?.toString() ?? '');
    final status = LogisticsTrackingService.statusLabel(
      task['status']?.toString(),
    );

    return GestureDetector(
      onLongPress: tid.isNotEmpty
          ? () => unawaited(
              AdminNavBadgeService.instance.markEntityUnread('logistik', tid))
          : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: OptikAdminTokens.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.35)),
        boxShadow: OptikAdminTokens.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AdminNavBadgeOverlay(
                  count: unread ? 1 : 0,
                  child: Icon(Icons.inventory_2_outlined,
                      color: OptikAdminTokens.navy, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    resi,
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _badge(_kindLabel(kind), kindColor),
                const SizedBox(width: 5),
                _badge(status, OptikAdminTokens.warning),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$qty pcs · $dari → $_myToko',
              style: TextStyle(
                color: kindColor.withOpacity(0.95),
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              kurir.isEmpty ? when : '$when · Kurir $kurir',
              style: TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 11,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _receiving ? null : () => _showDetail(task),
                  style: TextButton.styleFrom(
                    foregroundColor: OptikAdminTokens.textSecondary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  icon: const Icon(Icons.info_outline_rounded, size: 16),
                  label: Text('admin_btn_detail'.tr(),
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                if (ReceiveVerificationRules.canReceiveAtToko(
                  widget.profile,
                  (task['ke_lokasi'] ?? '').toString(),
                  (task['status'] ?? '').toString(),
                ))
                FilledButton.icon(
                  onPressed:
                      _receiving ? null : () => _confirmThenReceive(task),
                  style: FilledButton.styleFrom(
                    backgroundColor: OptikAdminTokens.success,
                    foregroundColor: OptikAdminTokens.snow,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: _receiving
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: OptikAdminTokens.snow,
                          ),
                        )
                      : const Icon(Icons.camera_alt_rounded, size: 15),
                  label: Text(
                    kind == 'ro' ? 'Terima RO' : 'Terima',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return ListenableBuilder(
      listenable: AdminNavBadgeService.instance,
      builder: (context, _) {
        return PremiumScaffold(
      appBar: PremiumAppBar(
        title: "inc_title".tr(),
        subtitle: 'admin_auto_385a673363'.tr(namedArgs: {'toko': _myToko}),
        actions: [
          IconButton(
            tooltip: 'admin_btn_refresh'.tr(),
            onPressed: _loading || _receiving ? null : _load,
            icon: Icon(Icons.refresh_rounded,
                color: OptikAdminTokens.textSecondary, size: 18),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: PremiumPanel(
              padding: const EdgeInsets.all(8),
              borderRadius: 14,
              child: Row(
                children: [
                  _kindChip('all', 'Semua'),
                  _kindChip('do', 'DO'),
                  _kindChip('ro', 'RO'),
                  _kindChip('retur', 'Retur'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${list.length} paket menunggu konfirmasi',
                style: TextStyle(
                  color: OptikAdminTokens.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                        color: OptikAdminTokens.ice))
                : _error != null
                    ? PremiumEmptyState(
                        message: 'admin_err_load_antrian'.tr(namedArgs: {'error': '$_error'}),
                        icon: Icons.error_outline_rounded,
                        accent: OptikAdminTokens.danger,
                        action: FilledButton(
                          onPressed: _load,
                          child: Text('common_retry'.tr()),
                        ),
                      )
                    : list.isEmpty
                        ? PremiumEmptyState(
                            message: _kindFilter == 'ro'
                                ? 'Tidak ada RO menunggu terima di cabang ini.'
                                : _kindFilter == 'do'
                                    ? 'Tidak ada DO menunggu terima di cabang ini.'
                                    : _kindFilter == 'retur'
                                        ? 'Tidak ada retur menunggu terima.'
                                        : "inc_kosong".tr(),
                            icon: Icons.inventory_2_outlined,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 4, 14, 20),
                              itemCount: list.length,
                              itemBuilder: (_, i) => _taskCard(list[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
      },
    );
  }
}
