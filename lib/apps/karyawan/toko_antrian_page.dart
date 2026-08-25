import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/attendance/pos_duty_gate.dart';
import '../../shared/karyawan/toko_antrian_realtime.dart';
import '../../shared/karyawan/toko_antrian_service.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/theme.dart';

/// Daftar antrian lantai toko + aksi ringan (booking / klaim / online / scan pickup).
class TokoAntrianPage extends StatefulWidget {
  const TokoAntrianPage({
    super.key,
    required this.tokoId,
    required this.karyawanId,
    required this.karyawanNama,
    required this.karyawanNik,
    this.initialItems,
  });

  final String tokoId;
  final String karyawanId;
  final String karyawanNama;
  final String karyawanNik;
  final List<TokoAntrianItem>? initialItems;

  @override
  State<TokoAntrianPage> createState() => _TokoAntrianPageState();
}

class _TokoAntrianPageState extends State<TokoAntrianPage> {
  final _svc = TokoAntrianService();
  late List<TokoAntrianItem> _items;
  bool _loading = false;
  String? _filter;
  String? _busyId;
  TokoAntrianRealtimeSubscription? _rt;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.initialItems ?? const []);
    if (_items.isEmpty) {
      _reload();
    }
    _rt = TokoAntrianRealtime.subscribeToko(
      tokoId: widget.tokoId,
      onChanged: () {
        if (mounted && !_loading && _busyId == null) unawaited(_reload());
      },
    );
    _poll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (mounted && !_loading && _busyId == null) unawaited(_reload());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_rt?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final res = await _svc.loadDetailed(tokoId: widget.tokoId);
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _loading = false;
      });
      if (res.hasErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'antrian_err_muat_partial'.tr(
                namedArgs: {'error': res.errors.join(' · ')},
              ),
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('antrian_err_muat'.tr(namedArgs: {'error': '$e'})),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
  }

  Future<bool> _ensureDuty() async {
    final block = await PosDutyGate.blockReason(
      karyawanId: widget.karyawanId,
      nik: widget.karyawanNik,
    );
    if (block != null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(block.tr()),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return false;
    }
    if (widget.karyawanNik.trim().isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('antrian_err_profil_nik'.tr()),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return false;
    }
    return true;
  }

  List<TokoAntrianItem> get _filtered {
    final f = _filter;
    if (f == null) return _items;
    return _items.where((e) => e.kindKey == f).toList();
  }

  Map<String, dynamic> get _staffProfile => {
        'toko_id': widget.tokoId,
        'role': 'karyawan',
        'id': widget.karyawanId,
        'nama': widget.karyawanNama,
        'nik': widget.karyawanNik,
      };

  Future<void> _scanPickup() async {
    if (!await _ensureDuty()) return;
    if (!mounted) return;
    await UniversalQrNav.open(
      context,
      callerRole: UniversalQrCallerRole.karyawan,
      cabangKaryawan: widget.tokoId,
      karyawanId: widget.karyawanId,
      karyawanNama: widget.karyawanNama,
      profile: _staffProfile,
    );
    if (mounted) await _reload();
  }

  Future<void> _act(TokoAntrianItem item) async {
    if (!await _ensureDuty()) return;
    setState(() => _busyId = item.id);
    try {
      switch (item.kind) {
        case TokoAntrianKind.pickupPos:
          await _scanPickup();
          break;
        case TokoAntrianKind.pickupOnline:
          await _svc.advanceOnlinePickup(
            orderId: item.id,
            currentStatus: item.status ?? '',
          );
          break;
        case TokoAntrianKind.booking:
          final next = (item.status ?? '').toLowerCase() == 'checked_in'
              ? 'done'
              : 'checked_in';
          await _svc.updateBookingStatus(bookingId: item.id, status: next);
          break;
        case TokoAntrianKind.klaim:
          await _svc.markKlaimDiproses(requestId: item.id);
          break;
      }
      if (mounted) await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _actionLabel(TokoAntrianItem item) {
    switch (item.kind) {
      case TokoAntrianKind.pickupPos:
        return 'antrian_aksi_scan'.tr();
      case TokoAntrianKind.pickupOnline:
        final st = (item.status ?? '').toLowerCase();
        return st == 'ready'
            ? 'antrian_aksi_serahkan'.tr()
            : 'antrian_aksi_siap'.tr();
      case TokoAntrianKind.booking:
        return (item.status ?? '').toLowerCase() == 'checked_in'
            ? 'antrian_aksi_selesai'.tr()
            : 'antrian_aksi_checkin'.tr();
      case TokoAntrianKind.klaim:
        return 'antrian_aksi_proses'.tr();
    }
  }

  String _kindLabel(TokoAntrianKind k) => switch (k) {
        TokoAntrianKind.pickupPos => 'antrian_filter_pickup'.tr(),
        TokoAntrianKind.pickupOnline => 'antrian_filter_online'.tr(),
        TokoAntrianKind.booking => 'antrian_filter_booking'.tr(),
        TokoAntrianKind.klaim => 'antrian_filter_klaim'.tr(),
      };

  IconData _kindIcon(TokoAntrianKind k) => switch (k) {
        TokoAntrianKind.pickupPos => Icons.qr_code_2_rounded,
        TokoAntrianKind.pickupOnline => Icons.shopping_bag_outlined,
        TokoAntrianKind.booking => Icons.event_available_rounded,
        TokoAntrianKind.klaim => Icons.verified_user_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final total = _items.length;

    return Scaffold(
      backgroundColor: OptikKaryawanTokens.bg,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: OptikKaryawanTokens.snow.withOpacity(0.92),
        foregroundColor: OptikKaryawanTokens.ink,
        title: Text(
          'antrian_title'.tr(),
          style: GoogleFonts.fraunces(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: -0.4,
            color: OptikKaryawanTokens.ink,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'scan_qr_universal'.tr(),
            onPressed: _scanPickup,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: OptikKaryawanTokens.line),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: OptikKaryawanTokens.authBgGradient,
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -50,
              child: IgnorePointer(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        OptikKaryawanTokens.cyan.withOpacity(0.28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 80,
              left: -60,
              child: IgnorePointer(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OptikKaryawanTokens.mint.withOpacity(0.22),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                _heroBanner(total),
                _filterRow(),
                Expanded(
                  child: _loading && _items.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: OptikKaryawanTokens.cyan,
                          ),
                        )
                      : rows.isEmpty
                          ? _emptyState()
                          : RefreshIndicator(
                              color: OptikKaryawanTokens.cyan,
                              onRefresh: _reload,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 28),
                                itemCount: rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) =>
                                    _itemCard(rows[i]),
                              ),
                            ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: OptikKaryawanTokens.navyGradient,
            borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusLg),
            boxShadow: [
              BoxShadow(
                color: OptikKaryawanTokens.cyan.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _scanPickup,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: OptikKaryawanTokens.ink,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(OptikKaryawanTokens.radiusLg),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
              label: Text(
                'scan_qr_universal'.tr().toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroBanner(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusXl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusXl),
              color: OptikKaryawanTokens.snow.withOpacity(0.72),
              border: Border.all(
                color: OptikKaryawanTokens.cyan.withOpacity(0.28),
              ),
              boxShadow: OptikKaryawanTokens.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: OptikKaryawanTokens.navyGradient,
                    borderRadius:
                        BorderRadius.circular(OptikKaryawanTokens.radiusMd),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: OptikKaryawanTokens.ink,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        total == 0
                            ? 'antrian_home_kosong'.tr()
                            : 'antrian_home_count'
                                .tr(namedArgs: {'count': '$total'}),
                        style: GoogleFonts.fraunces(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: OptikKaryawanTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'antrian_home_desc'.tr(),
                        style: TextStyle(
                          color: OptikKaryawanTokens.muted.withOpacity(0.95),
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          _chip(null, 'antrian_filter_semua'.tr(), _items.length),
          _chip(
            'pickup_pos',
            'antrian_filter_pickup'.tr(),
            _items.where((e) => e.kind == TokoAntrianKind.pickupPos).length,
          ),
          _chip(
            'pickup_online',
            'antrian_filter_online'.tr(),
            _items.where((e) => e.kind == TokoAntrianKind.pickupOnline).length,
          ),
          _chip(
            'booking',
            'antrian_filter_booking'.tr(),
            _items.where((e) => e.kind == TokoAntrianKind.booking).length,
          ),
          _chip(
            'klaim',
            'antrian_filter_klaim'.tr(),
            _items.where((e) => e.kind == TokoAntrianKind.klaim).length,
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    OptikKaryawanTokens.cyan.withOpacity(0.35),
                    OptikKaryawanTokens.mint.withOpacity(0.45),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: OptikKaryawanTokens.cyan.withOpacity(0.22),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.inbox_outlined,
                size: 40,
                color: OptikKaryawanTokens.ink,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'antrian_empty_title'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: OptikKaryawanTokens.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'antrian_empty'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: OptikKaryawanTokens.muted.withOpacity(0.95),
                height: 1.45,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(TokoAntrianItem item) {
    final busy = _busyId == item.id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusXl),
        onTap: busy ? null : () => _act(item),
        child: Ink(
          decoration: BoxDecoration(
            color: OptikKaryawanTokens.snow.withOpacity(0.94),
            borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusXl),
            border: Border.all(
              color: OptikKaryawanTokens.cyan.withOpacity(0.22),
            ),
            boxShadow: OptikKaryawanTokens.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        OptikKaryawanTokens.cyan.withOpacity(0.35),
                        OptikKaryawanTokens.pale.withOpacity(0.55),
                      ],
                    ),
                    borderRadius:
                        BorderRadius.circular(OptikKaryawanTokens.radiusMd),
                  ),
                  child: Icon(
                    _kindIcon(item.kind),
                    color: OptikKaryawanTokens.ink,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: OptikKaryawanTokens.cyan.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          _kindLabel(item.kind).toUpperCase(),
                          style: TextStyle(
                            color: OptikKaryawanTokens.ink.withOpacity(0.78),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: OptikKaryawanTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: OptikKaryawanTokens.muted.withOpacity(0.95),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (item.when != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          DateFormat('HH:mm · d MMM').format(item.when!),
                          style: TextStyle(
                            color: OptikKaryawanTokens.muted.withOpacity(0.75),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: OptikKaryawanTokens.ink,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          _actionLabel(item),
                          style: const TextStyle(
                            color: OptikKaryawanTokens.snow,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String? key, String label, int count) {
    final selected = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => setState(() => _filter = key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: selected ? OptikKaryawanTokens.navyGradient : null,
              color: selected
                  ? null
                  : OptikKaryawanTokens.snow.withOpacity(0.78),
              border: Border.all(
                color: selected
                    ? OptikKaryawanTokens.cyan.withOpacity(0.55)
                    : OptikKaryawanTokens.lineStrong,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: OptikKaryawanTokens.cyan.withOpacity(0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              '$label  $count',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: OptikKaryawanTokens.ink.withOpacity(selected ? 0.95 : 0.78),
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
