import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../shared/member/member_cart.dart';
import '../../../shared/member/member_catalog_kategori.dart';
import '../../../shared/member/member_shop_address.dart';
import '../../../shared/theme.dart';
import 'member_cart_page.dart';
import 'member_catalog_page.dart';
import 'member_shop_home_page.dart';

/// Shell Belanja Online — dunia belanja terpisah (ala GrabFood) dari beranda member.
class MemberShopShell extends StatefulWidget {
  const MemberShopShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<MemberShopShell> createState() => _MemberShopShellState();
}

class _MemberShopShellState extends State<MemberShopShell> {
  late int _tab;
  String? _catalogKategori;
  bool _catalogShowSearch = false;
  /// Bumped when returning to shop Beranda so tab Belanja remounts even if
  /// shell kategori/search were already null (local filter/search cleared).
  int _catalogEpoch = 0;
  /// Sentinel: omit [kategori] to leave filter unchanged; pass `null` to clear.
  static const Object _kategoriUnchanged = Object();
  /// State's [context] is above this messenger — use the key to hide snackbars.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 2);
    MemberCart.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    MemberShopAddress.instance.ensureLoaded();
    MemberCart.instance.addListener(_onCart);
  }

  @override
  void dispose() {
    MemberCart.instance.removeListener(_onCart);
    super.dispose();
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  void _goTab(
    int i, {
    Object? kategori = _kategoriUnchanged,
    bool? showSearch,
  }) {
    if (i == 2) {
      _messengerKey.currentState?.hideCurrentSnackBar();
    }
    setState(() {
      _tab = i;
      if (i == 0) {
        // Kembali ke beranda: buang filter/search katalog supaya tab Belanja
        // berikutnya (bottom nav) tidak nyangkut kategori/search dari home.
        _catalogKategori = null;
        _catalogShowSearch = false;
        _catalogEpoch++;
      } else {
        if (!identical(kategori, _kategoriUnchanged)) {
          _catalogKategori = kategori as String?;
        }
        if (showSearch != null) {
          _catalogShowSearch = showSearch;
        }
      }
    });
  }

  /// Back di tab Keranjang/Belanja → beranda shop; di beranda shop → keluar ke app.
  void _handleBack() {
    if (_tab != 0) {
      _goTab(0);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    // Badge = totalQty semua baris (bukan selected-only). Lihat MemberCart.
    final cartQty = MemberCart.instance.totalQty;
    final topPad = MediaQuery.paddingOf(context).top;

    // Own messenger so catalog / sheet snackbars resolve here (not a nested
    // offstage scaffold), and cart-tab hideCurrentSnackBar hits the same one.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goTab(0);
      },
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          backgroundColor: OptikMemberTokens.canvas,
          body: Column(
            children: [
              Container(
                width: double.infinity,
                color: OptikMemberTokens.blueMist,
                padding: EdgeInsets.fromLTRB(4, topPad + 2, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _handleBack,
                      icon: const Icon(Icons.chevron_left_rounded, size: 32),
                      color: OptikMemberTokens.ink,
                    ),
                    Expanded(
                      child: Text(
                        'member_shop_title'.tr(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: OptikMemberTokens.ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (cartQty > 0)
                      TextButton.icon(
                        onPressed: () => _goTab(2),
                        icon: Badge(
                          isLabelVisible: true,
                          backgroundColor: OptikMemberTokens.danger,
                          label: Text('$cartQty'),
                          child: const Icon(
                            Icons.shopping_bag_outlined,
                            size: 20,
                            color: OptikMemberTokens.blueDeep,
                          ),
                        ),
                        label: Text(
                          'member_shop_tab_cart'.tr(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: OptikMemberTokens.blueDeep,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    MemberShopHomePage(
                      onBrowseAll: () =>
                          _goTab(1, kategori: null, showSearch: false),
                      onOpenSearch: () =>
                          _goTab(1, kategori: null, showSearch: true),
                      onOpenCategory: (kat) => _goTab(
                            1,
                            kategori: canonicalizeMemberCatalogKategori(kat),
                            showSearch: false,
                          ),
                      onOpenCart: () => _goTab(2),
                    ),
                    MemberCatalogPage(
                      key: ValueKey(
                        'shop-catalog-$_catalogEpoch-'
                        '$_catalogKategori-$_catalogShowSearch',
                      ),
                      browseOnly: false,
                      embeddedInShop: true,
                      initialKategori: _catalogKategori,
                      initialShowSearch: _catalogShowSearch,
                      onOpenCart: () => _goTab(2),
                    ),
                    const MemberCartPage(embedded: true),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            height: 64,
            backgroundColor: OptikMemberTokens.white,
            indicatorColor: OptikMemberTokens.blueSoft,
            selectedIndex: _tab,
            onDestinationSelected: (i) => _goTab(i),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.storefront_outlined),
                selectedIcon: const Icon(Icons.storefront_rounded),
                label: 'member_shop_tab_home'.tr(),
              ),
              NavigationDestination(
                icon: const Icon(Icons.grid_view_outlined),
                selectedIcon: const Icon(Icons.grid_view_rounded),
                label: 'member_shop_tab_shop'.tr(),
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: cartQty > 0,
                  backgroundColor: OptikMemberTokens.danger,
                  label: Text('$cartQty'),
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: cartQty > 0,
                  backgroundColor: OptikMemberTokens.danger,
                  label: Text('$cartQty'),
                  child: const Icon(Icons.shopping_bag_rounded),
                ),
                label: 'member_shop_tab_cart'.tr(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
