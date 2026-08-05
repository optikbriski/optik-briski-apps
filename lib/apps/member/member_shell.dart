import 'package:flutter/material.dart';

import '../../shared/member/member_home_controller.dart';
import '../../shared/member/member_session.dart';
import '../../shared/member/member_status_watch.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/theme.dart';
import 'home_member_page.dart';
import 'member_layout.dart';
import 'member_update_coordinator.dart';
import 'member_widgets.dart';
import 'pages/member_claim_terms_gate.dart';
import 'pages/member_feature_pages.dart';
import 'pages/member_orders_list_page.dart';
import 'pages/member_warranty_list_page.dart';

class MemberShell extends StatefulWidget {
  const MemberShell({super.key});

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> with WidgetsBindingObserver {
  int _index = 0;
  final _update = MemberUpdateCoordinator();

  late final List<Widget> _pages = const [
    HomeMemberPage(embedded: true),
    _OrdersTab(),
    MemberStoresPage(embedded: true),
    MemberProfilePage(embedded: true),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (MemberSession.instance.isLoggedIn) {
      MemberStatusWatch.instance.start();
    }
    MemberSession.instance.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _update.checkSilent(context);
    });
  }

  void _selectTab(int i) {
    final prev = _index;
    setState(() => _index = i);
    // Kembali ke Beranda → refresh CMS bila cache stale.
    if (i == 0 && prev != 0) {
      MemberHomeController.instance.ensureLoaded();
    }
  }

  /// Jaga state tiap tab tanpa IndexedStack (tinggi tab lain tidak merenggangkan Beranda).
  Widget _tabBody() {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < _pages.length; i++)
          Positioned.fill(
            child: Visibility(
              visible: _index == i,
              maintainState: true,
              maintainAnimation: false,
              maintainSize: false,
              child: TickerMode(
                enabled: _index == i,
                child: _pages[i],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MemberSession.instance.removeListener(_onSession);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _update.onAppResumed(context);
      // Setelah admin Update CMS, buka ulang app → beranda ikut segar.
      MemberHomeController.instance.ensureLoaded(force: true);
    }
  }

  void _onSession() {
    if (mounted) setState(() {});
    if (MemberSession.instance.isLoggedIn) {
      MemberStatusWatch.instance.start();
    } else {
      MemberStatusWatch.instance.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = MemberSession.instance.fontScale.clamp(0.9, 1.35);
    final m = MemberLayout.of(context);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        backgroundColor: OptikMemberTokens.canvas,
        body: m.useNavigationRail
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _selectTab,
                    backgroundColor: OptikMemberTokens.white,
                    indicatorColor: OptikMemberTokens.blueSoft,
                    selectedIconTheme: const IconThemeData(
                      color: OptikMemberTokens.blue,
                    ),
                    unselectedIconTheme: const IconThemeData(
                      color: OptikMemberTokens.inkMuted,
                    ),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      NavigationRailDestination(
                        icon: Icon(Icons.home_outlined, size: m.navIconSize),
                        selectedIcon:
                            Icon(Icons.home_rounded, size: m.navIconSize),
                        label: Text(
                          'Beranda',
                          style: TextStyle(fontSize: m.navLabelSize),
                        ),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.receipt_long_outlined,
                            size: m.navIconSize),
                        selectedIcon:
                            Icon(Icons.receipt_long, size: m.navIconSize),
                        label: Text(
                          'Pesanan',
                          style: TextStyle(fontSize: m.navLabelSize),
                        ),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.storefront_outlined,
                            size: m.navIconSize),
                        selectedIcon: Icon(Icons.storefront_rounded,
                            size: m.navIconSize),
                        label: Text(
                          'Cabang',
                          style: TextStyle(fontSize: m.navLabelSize),
                        ),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.person_outline_rounded,
                            size: m.navIconSize),
                        selectedIcon:
                            Icon(Icons.person_rounded, size: m.navIconSize),
                        label: Text(
                          'Akun',
                          style: TextStyle(fontSize: m.navLabelSize),
                        ),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _tabBody()),
                ],
              )
            : _tabBody(),
        floatingActionButton: FloatingActionButton(
          onPressed: () => UniversalQrNav.open(
            context,
            callerRole: UniversalQrCallerRole.member,
          ),
          tooltip: 'Scan QR',
          child: const Icon(Icons.qr_code_scanner_rounded),
        ),
        floatingActionButtonLocation: m.useNavigationRail
            ? FloatingActionButtonLocation.endFloat
            : FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: m.useNavigationRail
            ? null
            : BottomAppBar(
                color: OptikMemberTokens.white,
                elevation: 0,
                notchMargin: 6,
                shape: const CircularNotchedRectangle(),
                child: SizedBox(
                  height: m.bottomNavHeight,
                  child: Row(
                    children: [
                      _navItem(
                          0, Icons.home_outlined, Icons.home_rounded, 'Beranda', m),
                      _navItem(1, Icons.receipt_long_outlined,
                          Icons.receipt_long, 'Pesanan', m),
                      const SizedBox(width: 56),
                      _navItem(2, Icons.storefront_outlined,
                          Icons.storefront_rounded, 'Cabang', m),
                      _navItem(3, Icons.person_outline_rounded,
                          Icons.person_rounded, 'Akun', m),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _navItem(
    int i,
    IconData icon,
    IconData iconActive,
    String label,
    MemberLayoutMetrics m,
  ) {
    final selected = _index == i;
    return Expanded(
      child: InkWell(
        onTap: () => _selectTab(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? iconActive : icon,
              color:
                  selected ? OptikMemberTokens.blue : OptikMemberTokens.inkMuted,
              size: m.navIconSize,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: m.navLabelSize,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? OptikMemberTokens.blue
                    : OptikMemberTokens.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  const _OrdersTab();

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final pad = m.pagePadding;

    return MemberPremiumScaffold(
      title: 'Pesanan',
      subtitle: 'Status · riwayat · garansi',
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 12, pad, 100),
        children: [
          MemberLayout.constrain(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MemberSectionLabel('Pesanan'),
                if (m.menuColumns > 1)
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.4,
                    children: [
                      MemberFeatureTile(
                        icon: Icons.local_shipping_outlined,
                        title: 'Status pesanan',
                        subtitle: 'Yang belum diambil + notifikasi perubahan',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MemberOrdersListPage(
                              title: 'Status pesanan',
                              onlyActive: true,
                            ),
                          ),
                        ),
                      ),
                      MemberFeatureTile(
                        icon: Icons.history_rounded,
                        title: 'Riwayat belanja',
                        subtitle: 'Semua transaksi',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MemberOrdersListPage(
                              title: 'Riwayat belanja',
                            ),
                          ),
                        ),
                      ),
                      MemberFeatureTile(
                        icon: Icons.verified_user_outlined,
                        title: 'Kartu garansi',
                        subtitle: 'Data asli sistem',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MemberWarrantyListPage(),
                          ),
                        ),
                      ),
                      MemberFeatureTile(
                        icon: Icons.storefront_outlined,
                        title: 'Klaim garansi',
                        subtitle: 'Wajib datang + bawa barang',
                        onTap: () => openMemberClaimPage(context),
                      ),
                    ],
                  )
                else ...[
                  MemberFeatureTile(
                    icon: Icons.local_shipping_outlined,
                    title: 'Status pesanan',
                    subtitle: 'Yang belum diambil + notifikasi perubahan',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MemberOrdersListPage(
                          title: 'Status pesanan',
                          onlyActive: true,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: m.isTablet ? 12 : 10),
                  MemberFeatureTile(
                    icon: Icons.history_rounded,
                    title: 'Riwayat belanja',
                    subtitle: 'Semua transaksi',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const MemberOrdersListPage(title: 'Riwayat belanja'),
                      ),
                    ),
                  ),
                  SizedBox(height: m.isTablet ? 12 : 10),
                  MemberFeatureTile(
                    icon: Icons.verified_user_outlined,
                    title: 'Kartu garansi',
                    subtitle: 'Data asli sistem',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MemberWarrantyListPage(),
                      ),
                    ),
                  ),
                  SizedBox(height: m.isTablet ? 12 : 10),
                  MemberFeatureTile(
                    icon: Icons.storefront_outlined,
                    title: 'Klaim garansi',
                    subtitle: 'Wajib datang + bawa barang',
                    onTap: () => openMemberClaimPage(context),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
