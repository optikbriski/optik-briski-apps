// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/member/member_online_order_labels.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Antrian pesanan online Member untuk cabang / pusat.
/// Dibagi 2: Pre-order (nunggu stok/RO) · Ready (siap ambil/kirim).
class OnlineOrdersPage extends StatefulWidget {
  const OnlineOrdersPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<OnlineOrdersPage> createState() => _OnlineOrdersPageState();
}

class _OnlineOrdersPageState extends State<OnlineOrdersPage>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  String get _tokoId =>
      (widget.profile['toko_id'] ?? '').toString().trim().toUpperCase();

  /// Hanya role pusat yang boleh lihat/proses SEMUA cabang.
  /// Staf cabang — termasuk yang toko_id-nya PUSAT — hanya cabang sendiri.
  bool get _isPusat {
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    return role == 'owner' ||
        role == 'admin_pusat' ||
        role == 'super_admin';
  }

  String get _scopeLabel {
    if (_isPusat) return 'Semua cabang';
    if (_tokoId.isEmpty) return 'Cabang belum di-set';
    return _tokoId;
  }

  bool _orderBelongsHere(Map<String, dynamic> o) {
    if (_isPusat) return true;
    final orderToko = (o['toko_id'] ?? '').toString().trim().toUpperCase();
    return orderToko.isNotEmpty && orderToko == _tokoId;
  }

  /// Ada item pre-order di JSON items / catatan toko.
  bool _hasPreorder(Map<String, dynamic> o) {
    final note = (o['store_note'] ?? '').toString().toLowerCase();
    if (note.contains('pre-order') || note.contains('preorder')) {
      return true;
    }
    final items = o['items'];
    if (items is! List) return false;
    for (final raw in items) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['pre_order'] == true) return true;
      final pq = int.tryParse('${m['preorder_qty'] ?? 0}') ?? 0;
      if (pq > 0) return true;
    }
    return false;
  }

  bool _isActivePaid(Map<String, dynamic> o) {
    final s = (o['status'] ?? '').toString();
    return s == 'paid' ||
        s == 'packing' ||
        s == 'ready' ||
        s == 'shipped';
  }

  List<Map<String, dynamic>> get _unpaidRows => _rows
      .where((o) => (o['status'] ?? '').toString() == 'pending_payment')
      .toList();

  /// Tab Pre-order: masih nunggu stok/RO (belum ready/shipped/fulfilled).
  List<Map<String, dynamic>> get _preorderRows => _rows.where((o) {
        if (!_isActivePaid(o)) return false;
        if (!_hasPreorder(o)) return false;
        final s = (o['status'] ?? '').toString();
        return s == 'paid' || s == 'packing';
      }).toList();

  /// Tab Ready: stok cukup / barang jadi — siap dikemas, ambil, atau kirim.
  List<Map<String, dynamic>> get _readyRows => _rows.where((o) {
        if (!_isActivePaid(o)) return false;
        final s = (o['status'] ?? '').toString();
        if (s == 'ready' || s == 'shipped') return true;
        // Paid/packing tanpa pre-order = langsung masuk antrian ready.
        if ((s == 'paid' || s == 'packing') && !_hasPreorder(o)) return true;
        return false;
      }).toList();

  List<Map<String, dynamic>> get _historyRows => _rows.where((o) {
        final s = (o['status'] ?? '').toString();
        return s == 'fulfilled' || s == 'cancelled' || s == 'expired';
      }).toList();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Soft-expire pending lewat 15 menit (hold stok habis).
      try {
        try {
          await _db.rpc('expire_all_stale_stock_holds');
        } catch (_) {
          await _db.rpc('expire_stale_online_orders');
        }
      } catch (_) {}

      if (!_isPusat && _tokoId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _rows = const [];
          _loading = false;
          _error =
              'Profil staf belum punya toko_id. Tidak bisa muat pesanan online.';
        });
        return;
      }

      // Cabang: filter ketat by toko_id. Pusat (role): semua cabang.
      // RLS server juga membatasi — filter client = defense in depth.
      var q = _db.from('online_orders').select();
      if (!_isPusat) {
        q = q.eq('toko_id', _tokoId);
      }
      final rows = await q.order('created_at', ascending: false).limit(100);
      if (!mounted) return;
      final mapped = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(_orderBelongsHere)
          .toList();
      setState(() {
        _rows = mapped;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> order, String status) async {
    if (!_orderBelongsHere(order)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order milik ${(order['toko_id'] ?? '-')} — bukan cabang Anda ($_tokoId)',
          ),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
      return;
    }
    final tracking = TextEditingController(
        text: (order['courier_tracking'] ?? '').toString());
    final note =
        TextEditingController(text: (order['store_note'] ?? '').toString());
    final label = MemberOnlineOrderLabels.status(status);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'cancelled' ? 'Batalkan pesanan?' : 'Update → $label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status != 'cancelled' && status != 'fulfilled') ...[
              TextField(
                controller: tracking,
                decoration: const InputDecoration(
                    labelText: 'No. resi / tracking kurir'),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Catatan toko'),
              ),
            ] else
              Text(
                status == 'cancelled'
                    ? 'Pesanan akan dipindah ke Riwayat sebagai dibatalkan.'
                    : 'Tandai pesanan selesai untuk Member.',
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(status == 'cancelled' ? 'Batalkan' : 'Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _db.rpc('update_online_order_fulfillment', params: {
      'p_order_id': order['id'],
      'p_status': status,
      'p_courier_tracking': tracking.text.trim(),
      'p_store_note': note.text.trim(),
    });
    if (!mounted) return;
    if (res is Map && res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${res['error'] ?? 'Gagal'}'),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
      return;
    }
    await _load();
  }

  /// Panggil Biteship create-order lalu status shipped + resi otomatis.
  Future<void> _callBiteship(Map<String, dynamic> order) async {
    if (!_orderBelongsHere(order)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order milik ${(order['toko_id'] ?? '-')} — bukan cabang Anda ($_tokoId)',
          ),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
      return;
    }
    // Defense-in-depth: jangan panggil kurir sebelum lunas (edge juga wajib cek).
    final stNow = (order['status'] ?? '').toString();
    if (!const {'paid', 'packing', 'ready'}.contains(stNow)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Status order belum bisa dipanggil kurir ($stNow). '
            'Lunasi & proses dulu. Bisa isi resi manual setelah ready.',
          ),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
      return;
    }
    final oid = (order['id'] ?? '').toString();
    if (oid.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Panggil kurir Biteship?'),
        content: Text(
          'Kurir: ${order['courier_company'] ?? order['courier'] ?? '-'} '
          '· ${(order['courier_service_name'] ?? order['courier_service_code'] ?? '-').toString()}\n\n'
          'Driver/pickup dibuat sekarang (saat barang jadi). '
          'Lanjut?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Panggil kurir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Memanggil Biteship…')),
    );
    try {
      final res = await _db.functions.invoke(
        'biteship-create-order',
        body: {'online_order_id': oid},
      );
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      if (data['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${data['error'] ?? 'Gagal panggil Biteship'}\n'
              'Bisa isi resi manual lewat tombol Resi manual.',
            ),
            backgroundColor: OptikAdminTokens.danger,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }
      final waybill = (data['waybill'] ?? data['courier_tracking'] ?? '-')
          .toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data['already'] == true
                ? 'Sudah ada order Biteship · resi $waybill'
                : 'Kurir dipanggil · resi $waybill',
          ),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal: $e'),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnlineDeliverySettingsPage(profile: widget.profile),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final unpaid = _unpaidRows;
    final pre = _preorderRows;
    final ready = _readyRows;
    final hist = _historyRows;
    final activeQueue = unpaid.length + pre.length + ready.length;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'PESANAN ONLINE',
        subtitle: _scopeLabel,
        actions: [
          IconButton(
            tooltip: 'Ongkir & jual online',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: _premiumTabBar(
            unpaid: unpaid.length,
            pre: pre.length,
            ready: ready.length,
            hist: hist.length,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.navy),
            )
          : _error != null
              ? PremiumEmptyState(
                  icon: Icons.cloud_off_outlined,
                  accent: OptikAdminTokens.danger,
                  title: 'Gagal memuat antrian',
                  message: _error!,
                  action: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Coba lagi'),
                  ),
                )
              : Column(
                  children: [
                    _queuePulse(
                      active: activeQueue,
                      unpaid: unpaid.length,
                      processing: pre.length + ready.length,
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _orderList(
                            unpaid,
                            emptyTitle: 'Menunggu pembayaran',
                            emptyLabel:
                                'Belum ada checkout Member yang belum lunas. '
                                'Order baru dengan hold stok 15 menit muncul di sini.',
                            emptyIcon: Icons.payments_outlined,
                            showPreorderBadge: false,
                            allowCancel: true,
                          ),
                          _orderList(
                            pre,
                            emptyTitle: 'Antrian pre-order kosong',
                            emptyLabel:
                                'Order dengan stok kurang / RO menunggu barang jadi '
                                'akan masuk ke tab ini.',
                            emptyIcon: Icons.inventory_2_outlined,
                            emptyAccent: OptikAdminTokens.warning,
                            showPreorderBadge: true,
                            allowCancel: true,
                          ),
                          _orderList(
                            ready,
                            emptyTitle: 'Siap diproses — kosong',
                            emptyLabel:
                                'Pesanan stok cukup, siap dikemas, diambil, '
                                'atau dikirim muncul di sini.',
                            emptyIcon: Icons.local_shipping_outlined,
                            showPreorderBadge: false,
                            allowCancel: true,
                          ),
                          _orderList(
                            hist,
                            emptyTitle: 'Belum ada riwayat',
                            emptyLabel:
                                'Pesanan selesai, dibatalkan, atau kedaluwarsa '
                                'akan tersimpan di sini.',
                            emptyIcon: Icons.history_rounded,
                            showPreorderBadge: false,
                            allowCancel: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _premiumTabBar({
    required int unpaid,
    required int pre,
    required int ready,
    required int hist,
  }) {
    final items = <(IconData, String, int)>[
      (Icons.schedule_rounded, 'Belum bayar', unpaid),
      (Icons.hourglass_top_rounded, 'Pre-order', pre),
      (Icons.bolt_rounded, 'Proses', ready),
      (Icons.history_rounded, 'Riwayat', hist),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: OptikAdminTokens.snow.withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.55)),
          boxShadow: OptikAdminTokens.cardShadow,
        ),
        child: TabBar(
          controller: _tabs,
          // Full-width: 4 tab dibagi rata kiri → kanan.
          isScrollable: false,
          padding: const EdgeInsets.all(4),
          labelPadding: EdgeInsets.zero,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                OptikAdminTokens.navy.withOpacity(0.92),
                const Color(0xFF123A6B),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: OptikAdminTokens.navy.withOpacity(0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          labelColor: OptikAdminTokens.snow,
          unselectedLabelColor: OptikAdminTokens.slate,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          tabs: [
            for (final t in items)
              Tab(
                height: 48,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.$1, size: 16),
                        const SizedBox(width: 5),
                        Text(t.$2),
                        const SizedBox(width: 5),
                        _countBadge(t.$3),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _countBadge(int n) {
    return Builder(
      builder: (context) {
        final fg = DefaultTextStyle.of(context).style.color ??
            OptikAdminTokens.slate;
        final onSnow = fg == OptikAdminTokens.snow ||
            (fg.computeLuminance() > 0.7);
        return Container(
          constraints: const BoxConstraints(minWidth: 20),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: onSnow
                ? Colors.white.withOpacity(0.2)
                : OptikAdminTokens.ice.withOpacity(0.5),
            borderRadius: BorderRadius.circular(99),
          ),
          alignment: Alignment.center,
          child: Text(
            '$n',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        );
      },
    );
  }

  Widget _queuePulse({
    required int active,
    required int unpaid,
    required int processing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              OptikAdminTokens.navy,
              Color(0xFF163A6E),
              Color(0xFF0E4A62),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: OptikAdminTokens.navy.withOpacity(0.16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: OptikAdminTokens.ice.withOpacity(0.45),
                ),
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: OptikAdminTokens.snow,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active == 0 ? 'Antrian tenang' : '$active order aktif',
                    style: const TextStyle(
                      color: OptikAdminTokens.snow,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unpaid > 0 || processing > 0
                        ? '$unpaid menunggu bayar · $processing diproses'
                        : 'Siap terima pesanan Member kapan saja',
                    style: TextStyle(
                      color: OptikAdminTokens.snow.withOpacity(0.78),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (_isPusat)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: OptikAdminTokens.ice.withOpacity(0.4),
                  ),
                ),
                child: const Text(
                  'PUSAT',
                  style: TextStyle(
                    color: OptikAdminTokens.snow,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _orderList(
    List<Map<String, dynamic>> rows, {
    required String emptyLabel,
    required String emptyTitle,
    required IconData emptyIcon,
    Color emptyAccent = OptikAdminTokens.ice,
    required bool showPreorderBadge,
    bool allowCancel = false,
  }) {
    if (rows.isEmpty) {
      return PremiumEmptyState(
        icon: emptyIcon,
        accent: emptyAccent,
        title: emptyTitle,
        message: emptyLabel,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Muat ulang'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _orderCard(
        rows[i],
        showPreorderBadge: showPreorderBadge,
        allowCancel: allowCancel,
      ),
    );
  }

  String _relativeTime(dynamic raw) {
    final dt = DateTime.tryParse('$raw')?.toLocal();
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'Baru saja';
    if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
    if (d.inHours < 24) return '${d.inHours} jam lalu';
    if (d.inDays < 7) return '${d.inDays} hari lalu';
    return DateFormat('d MMM · HH:mm', 'id_ID').format(dt);
  }

  Widget _orderCard(
    Map<String, dynamic> o, {
    required bool showPreorderBadge,
    bool allowCancel = false,
  }) {
    final status = (o['status'] ?? '').toString();
    final fulfill = (o['fulfillment'] ?? '').toString();
    final items = o['items'];
    final itemCount = items is List ? items.length : 0;
    final preCount = _preorderSkuCount(o);
    // Cancel setelah lunas butuh refund/restock — jangan soft-cancel.
    final canCancel = allowCancel && status == 'pending_payment';
    final name =
        (o['customer_name'] ?? o['phone_e164'] ?? '-').toString().trim();
    final phone = (o['phone_e164'] ?? '').toString().trim();
    final when = _relativeTime(o['created_at'] ?? o['paid_at']);
    final isDelivery = fulfill == 'delivery';
    final total = int.tryParse('${o['total'] ?? 0}') ?? 0;

    return PremiumPanel(
      showAccentBar: true,
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      OptikAdminTokens.ice.withOpacity(0.55),
                      OptikAdminTokens.ice.withOpacity(0.18),
                    ],
                  ),
                  border: Border.all(
                    color: OptikAdminTokens.ice.withOpacity(0.7),
                  ),
                ),
                child: Icon(
                  isDelivery
                      ? Icons.delivery_dining_rounded
                      : Icons.storefront_rounded,
                  color: OptikAdminTokens.navy,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '-' : name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: OptikAdminTokens.navy,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (phone.isNotEmpty && phone != name) phone,
                        '${o['toko_id'] ?? '-'}',
                        if (when.isNotEmpty) when,
                      ].join(' · '),
                      style: const TextStyle(
                        color: OptikAdminTokens.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money.format(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: OptikAdminTokens.navy,
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _statusChip(status),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _metaChip(
                isDelivery ? Icons.local_shipping_outlined : Icons.shopping_bag_outlined,
                MemberOnlineOrderLabels.fulfillment(fulfill),
              ),
              if (o['courier'] != null)
                _metaChip(Icons.two_wheeler_outlined, '${o['courier']}'),
              _metaChip(Icons.category_outlined, '$itemCount item'),
              if (showPreorderBadge || preCount > 0)
                _tagChip(
                  preCount > 0 ? 'PRE-ORDER · $preCount SKU' : 'PRE-ORDER',
                  OptikAdminTokens.warning,
                ),
            ],
          ),
          ..._voucherLines(o),
          if ((o['address_text'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 15,
                  color: OptikAdminTokens.slate.withOpacity(0.75),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    o['address_text'].toString(),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: OptikAdminTokens.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if ((o['store_note'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: OptikAdminTokens.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: OptikAdminTokens.warning.withOpacity(0.28),
                ),
              ),
              child: Text(
                o['store_note'].toString(),
                style: const TextStyle(
                  fontSize: 12,
                  color: OptikAdminTokens.warning,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if ((o['courier_tracking'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Resi · ${o['courier_tracking']}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: OptikAdminTokens.navy,
              ),
            ),
          ],
          if (o['is_obr'] == true) ...[
            const SizedBox(height: 8),
            const Text(
              'OBR Delivery · diantar anak toko',
              style: TextStyle(
                fontSize: 11.5,
                color: OptikAdminTokens.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if ((o['courier_company'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Biteship · ${o['courier_company']}'
              '${(o['courier_service_code'] ?? '').toString().isNotEmpty ? ' / ${o['courier_service_code']}' : ''}',
              style: const TextStyle(
                fontSize: 11.5,
                color: OptikAdminTokens.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'paid') _action('packing', o, 'Dikemas', primary: true),
              if (showPreorderBadge) ...[
                if (status == 'paid' || status == 'packing')
                  _action('ready', o, 'Barang jadi / Ready', primary: true),
              ] else if (status != 'pending_payment' &&
                  status != 'fulfilled' &&
                  status != 'cancelled' &&
                  status != 'expired') ...[
                if (fulfill == 'delivery' &&
                    o['is_obr'] != true &&
                    (status == 'paid' ||
                        status == 'packing' ||
                        status == 'ready') &&
                    (o['biteship_order_id'] ?? '').toString().isEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _callBiteship(o),
                    icon: const Icon(Icons.local_shipping_outlined, size: 16),
                    label: const Text(
                      'Panggil Biteship',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                if (status == 'paid' || status == 'packing' || status == 'ready')
                  _action(
                    fulfill == 'delivery'
                        ? 'shipped'
                        : (status == 'ready' ? 'fulfilled' : 'ready'),
                    o,
                    fulfill == 'delivery'
                        ? (o['is_obr'] == true
                            ? 'Anak toko berangkat'
                            : 'Resi manual')
                        : (status == 'ready' ? 'Selesai' : 'Siap diambil'),
                    primary: true,
                  ),
                if (status == 'shipped')
                  _action(
                    'fulfilled',
                    o,
                    o['is_obr'] == true ? 'Selesai antar' : 'Selesai',
                    primary: true,
                  ),
              ],
              if (canCancel)
                OutlinedButton(
                  onPressed: () => _updateStatus(o, 'cancelled'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OptikAdminTokens.danger,
                    side: BorderSide(
                      color: OptikAdminTokens.danger.withOpacity(0.45),
                    ),
                  ),
                  child: const Text(
                    'Batalkan',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: OptikAdminTokens.bgMid,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: OptikAdminTokens.slate),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: OptikAdminTokens.slate,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _voucherLines(Map<String, dynamic> o) {
    final shipDisc =
        int.tryParse('${o['shipping_voucher_discount'] ?? 0}') ?? 0;
    final prodDisc =
        int.tryParse('${o['product_promo_discount'] ?? 0}') ?? 0;
    final code = (o['product_promo_code'] ?? '').toString().trim();
    final sub = int.tryParse('${o['subtotal'] ?? 0}') ?? 0;
    final ship = int.tryParse('${o['shipping_fee'] ?? 0}') ?? 0;
    final out = <Widget>[];
    if (sub > 0 || ship > 0) {
      out.add(const SizedBox(height: 4));
      out.add(Text(
        [
          if (sub > 0) 'Subtotal ${_money.format(sub)}',
          if (ship > 0) 'Ongkir ${_money.format(ship)}',
        ].join(' · '),
        style: const TextStyle(
          fontSize: 11.5,
          color: OptikAdminTokens.textMuted,
        ),
      ));
    }
    if (shipDisc > 0) {
      out.add(Text(
        'Voucher ongkir −${_money.format(shipDisc)}',
        style: const TextStyle(
          fontSize: 12,
          color: OptikAdminTokens.success,
          fontWeight: FontWeight.w700,
        ),
      ));
    }
    if (prodDisc > 0 || code.isNotEmpty) {
      out.add(Text(
        code.isNotEmpty
            ? 'Diskon $code −${_money.format(prodDisc)}'
            : 'Diskon produk −${_money.format(prodDisc)}',
        style: const TextStyle(
          fontSize: 12,
          color: OptikAdminTokens.success,
          fontWeight: FontWeight.w700,
        ),
      ));
    }
    return out;
  }

  int _preorderSkuCount(Map<String, dynamic> o) {
    final items = o['items'];
    if (items is! List) return 0;
    var n = 0;
    for (final raw in items) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['pre_order'] == true ||
          (int.tryParse('${m['preorder_qty'] ?? 0}') ?? 0) > 0) {
        n++;
      }
    }
    return n;
  }

  Widget _tagChip(String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _action(
    String status,
    Map<String, dynamic> o,
    String label, {
    bool primary = false,
  }) {
    if (primary) {
      return FilledButton(
        onPressed: () => _updateStatus(o, status),
        style: FilledButton.styleFrom(
          backgroundColor: OptikAdminTokens.navy,
          foregroundColor: OptikAdminTokens.snow,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
    }
    return OutlinedButton(
      onPressed: () => _updateStatus(o, status),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color c = OptikAdminTokens.textMuted;
    if (status == 'paid' || status == 'packing') c = OptikAdminTokens.warning;
    if (status == 'ready' || status == 'shipped') c = OptikAdminTokens.navy;
    if (status == 'fulfilled') c = OptikAdminTokens.success;
    if (status == 'pending_payment' ||
        status == 'cancelled' ||
        status == 'expired') {
      c = OptikAdminTokens.danger;
    }
    final wash = (status == 'ready' || status == 'shipped')
        ? OptikAdminTokens.ice
        : c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: wash.withOpacity(0.22),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Text(
        MemberOnlineOrderLabels.status(status),
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class OnlineDeliverySettingsPage extends StatefulWidget {
  const OnlineDeliverySettingsPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<OnlineDeliverySettingsPage> createState() =>
      _OnlineDeliverySettingsPageState();
}

class _OnlineDeliverySettingsPageState
    extends State<OnlineDeliverySettingsPage> {
  final _db = Supabase.instance.client;
  /// Cadangan server bila Biteship gagal — tidak diedit di UI utama.
  int _feeGrab = 15000;
  int _feeGojek = 15000;
  int _feeOther = 15000;
  bool _loading = true;
  bool _saving = false;
  bool _online = true;
  bool _pickup = true;
  bool _obrInstant = true;
  bool _obrSameday = true;
  bool _obrNextday = true;
  bool _showFallback = false;
  String? _tokoId;
  List<String> _tokoOptions = const [];

  static const _obrDiscount = 2000;

  /// Hanya role pusat yang boleh atur semua cabang.
  bool get _isPusat {
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    return role == 'owner' ||
        role == 'admin_pusat' ||
        role == 'super_admin';
  }

  String get _tokoLabel {
    final id = (_tokoId ?? '').toUpperCase();
    if (id == 'PUSAT' || id == 'CABANG-PUSAT') return 'Pusat';
    return id.replaceFirst(RegExp(r'^CABANG-'), '');
  }

  @override
  void initState() {
    super.initState();
    final tid =
        (widget.profile['toko_id'] ?? '').toString().trim().toUpperCase();
    _tokoId = tid.isEmpty ? 'PUSAT' : tid;
    _load();
  }

  Future<List<String>> _loadTokoOptions() async {
    final ids = <String>{};
    try {
      final rows = await _db.from('toko_id').select('id');
      for (final r in (rows as List)) {
        final id = (r['id'] ?? '').toString().trim().toUpperCase();
        if (id.isNotEmpty) ids.add(id);
      }
    } catch (_) {}
    try {
      final rows = await _db.from('toko_delivery_settings').select('toko_id');
      for (final r in (rows as List)) {
        final id = (r['toko_id'] ?? '').toString().trim().toUpperCase();
        if (id.isNotEmpty) ids.add(id);
      }
    } catch (_) {}
    final profileToko =
        (widget.profile['toko_id'] ?? '').toString().trim().toUpperCase();
    if (profileToko.isNotEmpty) ids.add(profileToko);
    ids.add('PUSAT');
    final list = ids.toList()..sort();
    return list;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_isPusat) {
        _tokoOptions = await _loadTokoOptions();
        if (_tokoId == null ||
            _tokoId!.isEmpty ||
            !_tokoOptions.contains(_tokoId)) {
          _tokoId = _tokoOptions.contains('PUSAT')
              ? 'PUSAT'
              : (_tokoOptions.isNotEmpty ? _tokoOptions.first : 'PUSAT');
        }
      } else {
        _tokoOptions = [_tokoId ?? 'PUSAT'];
      }
      final row = await _db
          .from('toko_delivery_settings')
          .select()
          .eq('toko_id', _tokoId!)
          .maybeSingle();
      if (row != null) {
        _online = row['online_selling_enabled'] != false;
        _pickup = row['pickup_enabled'] != false;
        _obrInstant = row['obr_instant_enabled'] != false;
        _obrSameday = row['obr_sameday_enabled'] != false;
        _obrNextday = row['obr_nextday_enabled'] != false;
        _feeGrab = int.tryParse('${row['fee_grab'] ?? 15000}') ?? 15000;
        _feeGojek = int.tryParse('${row['fee_gojek'] ?? 15000}') ?? 15000;
        _feeOther = int.tryParse('${row['fee_other'] ?? 15000}') ?? 15000;
      } else {
        _online = true;
        _pickup = true;
        _obrInstant = true;
        _obrSameday = true;
        _obrNextday = true;
        _feeGrab = 15000;
        _feeGojek = 15000;
        _feeOther = 15000;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCabang() async {
    if (!_isPusat || _tokoOptions.isEmpty) return;

    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih cabang',
      subtitle: 'Pengaturan jual online per cabang',
      headerIcon: Icons.storefront_rounded,
      searchHint: 'Cari kode cabang…',
      selected: _tokoId,
      options: [
        for (final id in _tokoOptions)
          AdminPickerOption(
            value: id,
            label: id,
            subtitle: id == 'PUSAT' ? 'Pusat' : 'Cabang',
            icon: id == 'PUSAT'
                ? Icons.apartment_rounded
                : Icons.storefront_rounded,
          ),
      ],
    );
    if (!mounted || sel == null || sel.isClear) return;
    final next = sel.value;
    if (next == null || next == _tokoId) return;
    setState(() => _tokoId = next);
    await _load();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _db.from('toko_delivery_settings').upsert(
        {
          'toko_id': _tokoId,
          'online_selling_enabled': _online,
          'pickup_enabled': _pickup,
          // Biteship selalu on selama toko jual online.
          'delivery_enabled': _online,
          'obr_instant_enabled': _obrInstant,
          'obr_sameday_enabled': _obrSameday,
          'obr_nextday_enabled': _obrNextday,
          // Cadangan server saja — harga Member tetap dari Biteship live.
          'fee_grab': _feeGrab,
          'fee_gojek': _feeGojek,
          'fee_other': _feeOther,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'toko_id',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengaturan tersimpan'),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      final needMig = msg.contains('obr_instant_enabled') ||
          msg.contains('obr_sameday_enabled') ||
          msg.contains('obr_nextday_enabled') ||
          msg.contains('PGRST204') ||
          msg.contains('schema cache');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            needMig
                ? 'Gagal simpan: jalankan migrasi '
                    '20260805000003_obr_category_toggles.sql dulu. ($e)'
                : 'Gagal: $e',
          ),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _rp(int n) {
    final s = n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    return 'Rp $s';
  }

  Widget _heroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            OptikAdminTokens.navy,
            Color(0xFF1A3A6E),
            Color(0xFF0E4A62),
          ],
        ),
        boxShadow: OptikAdminTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.45)),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: OptikAdminTokens.snow, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tokoLabel.toUpperCase(),
                      style: TextStyle(
                        color: OptikAdminTokens.snow.withOpacity(0.72),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Jual Online',
                      style: TextStyle(
                        color: OptikAdminTokens.snow,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Selama toko buka jual online, Biteship selalu tersedia. '
            'OBR anak toko (Instant / Same Day / Next Day) bisa di-toggle — '
            'hemat Rp ${_obrDiscount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}, '
            'jangkauan ≤10 km (≤15 km bila belanja > Rp 1.000.000).',
            style: TextStyle(
              color: OptikAdminTokens.snow.withOpacity(0.88),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: value
              ? OptikAdminTokens.ice.withOpacity(0.18)
              : OptikAdminTokens.bgMid,
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusMd),
          border: Border.all(
            color: value
                ? OptikAdminTokens.ice.withOpacity(0.55)
                : OptikAdminTokens.line,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: OptikAdminTokens.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: Icon(icon, color: OptikAdminTokens.navy, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: OptikAdminTokens.navy,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: OptikAdminTokens.textMuted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: OptikAdminTokens.navy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pricingCard() {
    return PremiumPanel(
      showAccentBar: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tarif pengiriman',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: OptikAdminTokens.navy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tidak diisi manual — mengikuti pihak ke-3 saat Member checkout.',
            style: TextStyle(
              color: OptikAdminTokens.textMuted,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _rateRow(
            icon: Icons.hub_outlined,
            title: 'Biteship (Grab, Gojek, ekspedisi, …)',
            subtitle: 'Harga real-time per alamat & kategori',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: OptikAdminTokens.ice.withOpacity(0.35),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  color: OptikAdminTokens.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _rateRow(
            icon: Icons.directions_walk_rounded,
            title: 'OBR Delivery (anak toko)',
            subtitle: 'Toggle per kategori di bawah · −${_rp(_obrDiscount)}',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: OptikAdminTokens.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: OptikAdminTokens.success.withOpacity(0.35),
                ),
              ),
              child: const Text(
                '≤10/15 km',
                style: TextStyle(
                  color: OptikAdminTokens.success,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'OBR per kategori (sinkron ke Member)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: OptikAdminTokens.navy,
            ),
          ),
          const SizedBox(height: 8),
          _toggleCard(
            icon: Icons.bolt_rounded,
            title: 'OBR Instant',
            subtitle: 'Anak toko antar segera',
            value: _obrInstant,
            onChanged: (v) => setState(() => _obrInstant = v),
          ),
          _toggleCard(
            icon: Icons.wb_sunny_outlined,
            title: 'OBR Same Day',
            subtitle: 'Anak toko antar hari ini',
            value: _obrSameday,
            onChanged: (v) => setState(() => _obrSameday = v),
          ),
          _toggleCard(
            icon: Icons.nights_stay_outlined,
            title: 'OBR Next Day',
            subtitle: 'Anak toko antar besok',
            value: _obrNextday,
            onChanged: (v) => setState(() => _obrNextday = v),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: OptikAdminTokens.bgMid,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OptikAdminTokens.line),
            ),
            child: const Text(
              'OBR hanya muncul di Member bila jarak ≤ 10 km '
              '(≤15 km bila belanja > Rp 1.000.000) dan toggle kategori ON. '
              'Di luar itu / toggle OFF → hanya Biteship. '
              'Harga OBR = termurah kategori − Rp 2.000.',
              style: TextStyle(
                color: OptikAdminTokens.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _showFallback = !_showFallback),
            icon: Icon(
              _showFallback
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 18,
            ),
            label: Text(
              _showFallback
                  ? 'Sembunyikan cadangan darurat'
                  : 'Cadangan jika Biteship gagal',
            ),
          ),
          if (_showFallback) ...[
            const Text(
              'Hanya dipakai server bila ongkir live tidak terkirim. '
              'Jangan pakai sebagai harga normal Member.',
              style: TextStyle(
                color: OptikAdminTokens.warning,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Grab ${_rp(_feeGrab)} · Gojek ${_rp(_feeGojek)} · Lainnya ${_rp(_feeOther)}',
              style: const TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rateRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OptikAdminTokens.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: OptikAdminTokens.navy, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: OptikAdminTokens.navy,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: OptikAdminTokens.textMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: AppBar(title: const Text('Pengaturan jual online')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                _heroBanner(),
                const SizedBox(height: 16),
                PremiumPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isPusat && _tokoOptions.isNotEmpty) ...[
                        AdminPickerField(
                          label: 'Cabang',
                          valueText: _tokoId ?? _tokoOptions.first,
                          icon: Icons.apartment_rounded,
                          onTap: _pickCabang,
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        Text(
                          'Cabang · $_tokoId',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: OptikAdminTokens.navy,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      const Text(
                        'Layanan cabang',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: OptikAdminTokens.navy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _toggleCard(
                        icon: Icons.storefront_rounded,
                        title: 'Aktif jual online',
                        subtitle: 'Cabang muncul di Belanja Online Member',
                        value: _online,
                        onChanged: (v) => setState(() => _online = v),
                      ),
                      _toggleCard(
                        icon: Icons.shopping_bag_outlined,
                        title: 'Terima ambil di toko',
                        subtitle: 'Member bisa pickup tanpa ongkir',
                        value: _pickup,
                        onChanged: (v) => setState(() => _pickup = v),
                        enabled: _online,
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: _online
                              ? OptikAdminTokens.ice.withOpacity(0.18)
                              : OptikAdminTokens.bgMid,
                          borderRadius:
                              BorderRadius.circular(OptikAdminTokens.radiusMd),
                          border: Border.all(
                            color: _online
                                ? OptikAdminTokens.ice.withOpacity(0.55)
                                : OptikAdminTokens.line,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_shipping_outlined,
                              color: _online
                                  ? OptikAdminTokens.navy
                                  : OptikAdminTokens.textMuted,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pengiriman Biteship',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: _online
                                          ? OptikAdminTokens.navy
                                          : OptikAdminTokens.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _online
                                        ? 'Selalu aktif selama toko jual online'
                                        : 'Aktifkan jual online dulu',
                                    style: const TextStyle(
                                      color: OptikAdminTokens.textMuted,
                                      fontSize: 12,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _online ? 'ON' : 'OFF',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: _online
                                    ? OptikAdminTokens.success
                                    : OptikAdminTokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_online) _pricingCard(),
                if (_online) const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: OptikAdminTokens.navy,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(OptikAdminTokens.radiusMd),
                      ),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Menyimpan…' : 'Simpan pengaturan'),
                  ),
                ),
              ],
            ),
    );
  }
}
