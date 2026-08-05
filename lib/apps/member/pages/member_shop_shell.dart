import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../shared/member/member_cart.dart';
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

  void _goTab(int i, {String? kategori}) {
    setState(() {
      _tab = i;
      if (kategori != null) _catalogKategori = kategori;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartQty = MemberCart.instance.totalQty;
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
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
                  onPressed: () => Navigator.of(context).maybePop(),
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
                  onBrowseAll: () => _goTab(1, kategori: null),
                  onOpenCategory: (kat) => _goTab(1, kategori: kat),
                  onOpenProductCatalog: () => _goTab(1),
                ),
                MemberCatalogPage(
                  key: ValueKey('shop-catalog-$_catalogKategori'),
                  browseOnly: false,
                  embeddedInShop: true,
                  initialKategori: _catalogKategori,
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
    );
  }
}
