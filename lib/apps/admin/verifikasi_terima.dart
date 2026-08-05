// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/logistics/logistics_tracking_service.dart';
import '../../shared/logistics/request_order_service.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/theme.dart';
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

  String _moveKind(Map<String, dynamic> item) {
    final tipe = (item['tipe'] ?? '').toString().toUpperCase();
    final resi = (item['product_name'] ?? '').toString().toUpperCase();
    final ket = (item['keterangan'] ?? '').toString();
    if (tipe == 'RETUR' || resi.startsWith('RET-')) return 'retur';
    if (tipe == 'REQUEST' ||
        resi.startsWith('RO-') ||
        ket.contains('RequestOrder#')) {
      return 'ro';
    }
    if (tipe == 'DELIVERY' || resi.startsWith('DO-')) return 'do';
    return 'other';
  }

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
    if (raw.trim().isEmpty) return '-';
    try {
      if (raw.contains('[{')) {
        final part = raw.substring(raw.indexOf('[{'));
        final items = jsonDecode(part) as List;
        return items
            .map((it) => '${it['nama'] ?? '-'} (${it['qty'] ?? 0}x)')
            .join(', ');
      }
      if (raw.trim().startsWith('[')) {
        final items = jsonDecode(raw) as List;
        return items
            .map((it) => '${it['nama'] ?? '-'} (${it['qty'] ?? 0}x)')
            .join(', ');
      }
    } catch (_) {}
    return raw;
  }

  String _formatWhen(dynamic iso) {
    final raw = iso?.toString() ?? '';
    if (raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    return DateFormat('dd/MM/yy HH:mm').format(dt);
  }

  Future<void> _load() async {
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
      final res = await _db
          .from('stock_move_history')
          .select()
          .eq('ke_lokasi', _myToko)
          .inFilter('status', ['TRANSIT', 'PENDING'])
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      setState(() {
        _tasks = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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
    final kind = _moveKind(task);
    final resi = (task['product_name'] ?? '-').toString();
    final qty = task['jumlah'] ?? 0;
    final dari = (task['dari_lokasi'] ?? '-').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Terima paket ${_kindLabel(kind)}?',
          style: const TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        content: Text(
          '$resi\n'
          'Dari $dari · $qty pcs\n\n'
          'Ambil foto bukti fisik paket. Stok cabang akan bertambah'
          '${kind == 'ro' ? ' dan Request Order ditandai selesai.' : '.'}',
          style: const TextStyle(
            color: OptikAdminTokens.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Foto & terima'),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Surat jalan tidak ditemukan.'),
        backgroundColor: OptikAdminTokens.danger,
      ));
      return;
    }

    final row = Map<String, dynamic>.from(fresh);
    final ke = (row['ke_lokasi'] ?? '').toString().trim().toUpperCase();
    if (ke.isNotEmpty && _myToko.isNotEmpty && ke != _myToko) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Paket ditujukan ke $ke, bukan $_myToko.'),
        backgroundColor: OptikAdminTokens.danger,
      ));
      return;
    }

    final st = (row['status'] ?? '').toString().toUpperCase();
    if (st == 'SUCCESS') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Paket sudah diterima sebelumnya.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      _load();
      return;
    }
    if (st != 'TRANSIT' && st != 'PENDING') {
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

      final tipe = (row['tipe'] ?? '').toString().toUpperCase();
      final resiName = (row['product_name'] ?? '').toString();
      final isReturn =
          tipe == 'RETUR' || resiName.toUpperCase().startsWith('RET-');
      final kind = _moveKind(row);
      final verifierName = (widget.profile['nama'] ??
              widget.profile['full_name'] ??
              'Admin')
          .toString();
      final verifierId = widget.profile['id']?.toString() ??
          widget.profile['user_id']?.toString() ??
          _db.auth.currentUser?.id ??
          '';

      await StockMutationService().receiveItemsFromMoveKeterangan(
        tokoId: _myToko,
        keterangan: row['keterangan']?.toString() ?? '',
        jumlahFlat: int.tryParse(row['jumlah']?.toString() ?? '0') ?? 0,
        reason: StockReason.transferIn,
        refType: 'stock_move',
        refId: moveId,
        actorNama: verifierName,
        isReturn: isReturn,
      );

      await _db.from('stock_move_history').update({
        'status': 'SUCCESS',
        'bukti_foto_penerima': imgUrl,
        'verified_by': verifierId,
        'verified_by_name': verifierName,
        'verified_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', moveId);

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
              content: Text(
                'Paket diterima, tapi sync Request Order gagal: $e',
              ),
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
        content: Text('Gagal terima paket: $e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  void _showDetail(Map<String, dynamic> task) {
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
          style: const TextStyle(
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
            Text('Rute: $dari → $ke',
                style: const TextStyle(
                    color: OptikAdminTokens.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Jumlah: ${task['jumlah'] ?? 0} pcs',
                style: const TextStyle(
                    color: OptikAdminTokens.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Dikirim: ${_formatWhen(task['created_at'])}',
                style: const TextStyle(
                    color: OptikAdminTokens.textMuted, fontSize: 12)),
            if (kurir.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Kurir: $kurir',
                  style: const TextStyle(
                      color: OptikAdminTokens.textMuted, fontSize: 12)),
            ],
            const SizedBox(height: 10),
            const Text('Isi paket',
                style: TextStyle(
                    color: OptikAdminTokens.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(items,
                style: const TextStyle(
                    color: OptikAdminTokens.navy, fontSize: 12.5, height: 1.35)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmThenReceive(task);
            },
            child: const Text('Foto & terima'),
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
    final kind = _moveKind(task);
    final kindColor = _kindColor(kind);
    final resi = (task['product_name'] ?? '-').toString();
    final dari = (task['dari_lokasi'] ?? '-').toString();
    final qty = task['jumlah'] ?? 0;
    final kurir = (task['kurir_nama'] ?? '').toString().trim();
    final when = _formatWhen(task['created_at']);
    final preview = _cleanItems(task['keterangan']?.toString() ?? '');
    final status = LogisticsTrackingService.statusLabel(
      task['status']?.toString(),
    );

    return Container(
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
                Expanded(
                  child: Text(
                    resi,
                    style: const TextStyle(
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
              style: const TextStyle(
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
              style: const TextStyle(
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
                  label: const Text('Detail',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
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
                      ? const SizedBox(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: "inc_title".tr(),
        subtitle: 'Antrian DO · RO · Retur ke $_myToko',
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading || _receiving ? null : _load,
            icon: const Icon(Icons.refresh_rounded,
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
                style: const TextStyle(
                  color: OptikAdminTokens.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: OptikAdminTokens.ice))
                : _error != null
                    ? PremiumEmptyState(
                        message: 'Gagal memuat antrian.\n$_error',
                        icon: Icons.error_outline_rounded,
                        accent: OptikAdminTokens.danger,
                        action: FilledButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
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
  }
}
