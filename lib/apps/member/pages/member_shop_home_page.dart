import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/logistics/stock_realtime.dart';
import '../../../shared/member/member_cart.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/member/member_shop_address.dart';
import '../../../shared/theme.dart';
import '../member_layout.dart';
import 'member_shop_address_picker_page.dart';

/// Beranda di dalam Belanja Online — putih–biru premium, ala GrabMart.
class MemberShopHomePage extends StatefulWidget {
  const MemberShopHomePage({
    super.key,
    required this.onBrowseAll,
    required this.onOpenCategory,
    required this.onOpenProductCatalog,
  });

  final VoidCallback onBrowseAll;
  final ValueChanged<String> onOpenCategory;
  final VoidCallback onOpenProductCatalog;

  @override
  State<MemberShopHomePage> createState() => _MemberShopHomePageState();
}

class _MemberShopHomePageState extends State<MemberShopHomePage> {
  final _repo = MemberRepository();
  final _addr = MemberShopAddress.instance;
  final _search = TextEditingController();
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = const [];
  StockRealtimeSubscription? _stockRt;
  Timer? _stockRtDebounce;

  static const _cats = [
    ('Frame', Icons.visibility_outlined),
    ('Lensa', Icons.blur_on_rounded),
    ('Lainnya', Icons.category_outlined),
  ];

  String get _stockTokoId {
    final pref =
        (MemberSession.instance.preferredTokoId ?? '').trim().toUpperCase();
    if (pref.isNotEmpty && pref != 'PUSAT') return pref;
    return 'PUSAT';
  }

  void _bindStockRealtime() {
    unawaited(_stockRt?.dispose() ?? Future.value());
    _stockRt = StockRealtime.subscribeToko(
      tokoId: _stockTokoId,
      onEvent: (ev) {
        if (!mounted || ev.sku.isEmpty) return;
        var patched = false;
        final next = _products.map((p) {
          final sku = (p['sku'] ?? '').toString().trim().toUpperCase();
          if (sku != ev.sku) return p;
          patched = true;
          final m = Map<String, dynamic>.from(p);
          if (ev.availableQty != null) {
            m['available_qty'] = ev.availableQty;
          } else if (ev.stock != null || ev.reservedQty != null) {
            final st = ev.stock ?? (int.tryParse('${m['stock'] ?? 0}') ?? 0);
            final rs = ev.reservedQty ??
                (int.tryParse('${m['reserved_qty'] ?? 0}') ?? 0);
            m['stock'] = st;
            m['reserved_qty'] = rs;
            m['available_qty'] = st > rs ? st - rs : 0;
          }
          return m;
        }).toList();
        if (patched) {
          setState(() => _products = next);
        } else {
          _stockRtDebounce?.cancel();
          _stockRtDebounce = Timer(const Duration(milliseconds: 350), () {
            if (mounted) unawaited(_load(silent: true));
          });
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _addr.addListener(_onAddr);
    MemberSession.instance.addListener(_onSession);
    _boot();
    _bindStockRealtime();
  }

  @override
  void dispose() {
    _stockRtDebounce?.cancel();
    unawaited(_stockRt?.dispose() ?? Future.value());
    _addr.removeListener(_onAddr);
    MemberSession.instance.removeListener(_onSession);
    _search.dispose();
    super.dispose();
  }

  void _onAddr() {
    if (mounted) setState(() {});
  }

  void _onSession() {
    _bindStockRealtime();
    unawaited(_load(silent: true));
  }

  Future<void> _boot() async {
    await _addr.ensureLoaded();
    await _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _repo.listCatalog(
        limit: 300,
        tokoId: _stockTokoId,
      );
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
        if (list.isEmpty) _error = 'empty';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickAddress() async {
    await Navigator.of(context).push<MemberShopAddressEntry>(
      MaterialPageRoute(builder: (_) => const MemberShopAddressPickerPage()),
    );
  }

  List<Map<String, dynamic>> get _recommended {
    final buyable = _products.where((p) {
      if (MemberCart.isOnlineBlocked(p)) return false;
      final avail = int.tryParse('${p['available_qty'] ?? ''}');
      if (avail != null && avail <= 0) return false;
      final harga = int.tryParse('${p['harga'] ?? 0}') ?? 0;
      return harga > 0;
    }).toList();
    buyable.sort((a, b) {
      final da = int.tryParse('${a['harga_asli'] ?? 0}') ?? 0;
      final ha = int.tryParse('${a['harga'] ?? 0}') ?? 0;
      final db = int.tryParse('${b['harga_asli'] ?? 0}') ?? 0;
      final hb = int.tryParse('${b['harga'] ?? 0}') ?? 0;
      final discA = da > ha ? da - ha : 0;
      final discB = db > hb ? db - hb : 0;
      return discB.compareTo(discA);
    });
    return buyable.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MemberLayout.of(context).pagePadding;
    final rec = _recommended;
    final confirmed = _addr.isConfirmed;

    return RefreshIndicator(
      color: OptikMemberTokens.blue,
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, 4, pad, 28),
        children: [
          _LocationHeader(
            confirmed: confirmed,
            shortLabel: confirmed
                ? _addr.shortLabel
                : 'member_shop_pick_address'.tr(),
            subtitle: confirmed
                ? _addr.fullAddress
                : 'member_shop_pick_address_sub'.tr(),
            onTap: _pickAddress,
          ),
          const SizedBox(height: 12),
          _SearchBar(
            controller: _search,
            onSubmit: (_) => widget.onBrowseAll(),
            onTapBrowse: widget.onBrowseAll,
          ),
          const SizedBox(height: 16),
          _PromoStrip(onShop: widget.onBrowseAll),
          const SizedBox(height: 22),
          Text(
            'member_shop_categories'.tr(),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: OptikMemberTokens.ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < _cats.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _CategoryChip(
                    label: _cats[i].$1,
                    icon: _cats[i].$2,
                    onTap: () => widget.onOpenCategory(_cats[i].$1),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'member_shop_recommended'.tr(),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: OptikMemberTokens.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onBrowseAll,
                child: Text('member_shop_see_all'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading && _products.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error == 'empty')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'member_shop_empty'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: OptikMemberTokens.inkMuted,
                  height: 1.4,
                ),
              ),
            )
          else if (_error != null && _products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Text(
                    'member_shop_error'.tr(namedArgs: {'error': _error!}),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: OptikMemberTokens.inkMuted),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _load,
                    child: Text('member_shop_retry'.tr()),
                  ),
                ],
              ),
            )
          else if (rec.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'member_shop_no_stock'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: OptikMemberTokens.inkMuted),
              ),
            )
          else
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: rec.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final p = rec[i];
                  return _RecoCard(
                    product: p,
                    money: _money.format,
                    onTap: widget.onOpenProductCatalog,
                  );
                },
              ),
            ),
          const SizedBox(height: 22),
          Material(
            color: OptikMemberTokens.blueMist,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: widget.onBrowseAll,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: OptikMemberTokens.lineSoft),
                      ),
                      child: const Icon(
                        Icons.grid_view_rounded,
                        color: OptikMemberTokens.blueDeep,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'member_shop_browse_title'.tr(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: OptikMemberTokens.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'member_shop_browse_sub'.tr(),
                            style: const TextStyle(
                              fontSize: 13,
                              color: OptikMemberTokens.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: OptikMemberTokens.blueDeep,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({
    required this.confirmed,
    required this.shortLabel,
    required this.subtitle,
    required this.onTap,
  });

  final bool confirmed;
  final String shortLabel;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OptikMemberTokens.lineSoft),
            boxShadow: OptikMemberTokens.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: OptikMemberTokens.blueSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  confirmed
                      ? Icons.location_on_rounded
                      : Icons.add_location_alt_outlined,
                  color: OptikMemberTokens.blueDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'member_shop_deliver_now'.tr(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: OptikMemberTokens.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: OptikMemberTokens.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: OptikMemberTokens.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: OptikMemberTokens.blueDeep,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onSubmit,
    required this.onTapBrowse,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onTapBrowse;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmit,
      onTap: onTapBrowse,
      readOnly: true,
      decoration: InputDecoration(
        hintText: 'member_shop_search_hint'.tr(),
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: OptikMemberTokens.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: OptikMemberTokens.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: OptikMemberTokens.blue,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _PromoStrip extends StatelessWidget {
  const _PromoStrip({required this.onShop});

  final VoidCallback onShop;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A2F6E),
              OptikMemberTokens.blueDeep,
              OptikMemberTokens.blue,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -16,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'member_shop_hero_title'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'member_shop_hero_sub'.tr(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: OptikMemberTokens.blueDeep,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onShop,
                    child: Text(
                      'member_shop_hero_cta'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OptikMemberTokens.lineSoft),
          ),
          child: Column(
            children: [
              Icon(icon, color: OptikMemberTokens.blueDeep, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: OptikMemberTokens.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoCard extends StatelessWidget {
  const _RecoCard({
    required this.product,
    required this.money,
    required this.onTap,
  });

  final Map<String, dynamic> product;
  final String Function(num) money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nama = (product['nama'] ?? '-').toString();
    final img = (product['image_url'] ?? '').toString().trim();
    final harga = int.tryParse('${product['harga'] ?? 0}') ?? 0;
    final asli = int.tryParse('${product['harga_asli'] ?? ''}');

    return SizedBox(
      width: 148,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OptikMemberTokens.lineSoft),
              boxShadow: OptikMemberTokens.cardShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ColoredBox(
                    color: OptikMemberTokens.blueMist,
                    child: img.isEmpty
                        ? const Icon(
                            Icons.visibility_outlined,
                            color: OptikMemberTokens.inkMuted,
                          )
                        : Image.network(
                            img,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.visibility_outlined,
                              color: OptikMemberTokens.inkMuted,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nama,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          color: OptikMemberTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        money(harga),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: (asli != null && asli > harga)
                              ? const Color(0xFFC45C4A)
                              : OptikMemberTokens.blueDeep,
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
}
