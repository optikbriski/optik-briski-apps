import 'package:flutter/material.dart';

import '../../shared/member/member_session.dart';
import '../../shared/member/member_status_watch.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/theme.dart';
import 'home_member_page.dart';
import 'member_widgets.dart';
import 'pages/member_claim_page.dart';
import 'pages/member_feature_pages.dart';
import 'pages/member_orders_list_page.dart';
import 'pages/member_warranty_list_page.dart';

class MemberShell extends StatefulWidget {
  const MemberShell({super.key});

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (MemberSession.instance.isLoggedIn) {
      MemberStatusWatch.instance.start();
    }
    MemberSession.instance.addListener(_onSession);
  }

  @override
  void dispose() {
    MemberSession.instance.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
    if (MemberSession.instance.isLoggedIn) {
      MemberStatusWatch.instance.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = MemberSession.instance.fontScale.clamp(0.9, 1.35);
    final pages = <Widget>[
      const HomeMemberPage(embedded: true),
      const _OrdersTab(),
      const MemberStoresPage(embedded: true),
      const MemberProfilePage(embedded: true),
    ];

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        backgroundColor: OptikMemberTokens.canvas,
        // Jangan IndexedStack: tinggi tab lain (Cabang/Akun) merenggangkan Beranda.
        body: pages[_index],
        floatingActionButton: FloatingActionButton(
          onPressed: () => UniversalQrNav.open(
            context,
            callerRole: UniversalQrCallerRole.member,
          ),
          tooltip: 'Scan QR',
          child: const Icon(Icons.qr_code_scanner_rounded),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          color: OptikMemberTokens.white,
          elevation: 0,
          notchMargin: 6,
          shape: const CircularNotchedRectangle(),
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                _navItem(0, Icons.home_outlined, Icons.home_rounded, 'Beranda'),
                _navItem(
                    1, Icons.receipt_long_outlined, Icons.receipt_long, 'Pesanan'),
                const SizedBox(width: 56),
                _navItem(2, Icons.storefront_outlined, Icons.storefront_rounded,
                    'Cabang'),
                _navItem(
                    3, Icons.person_outline_rounded, Icons.person_rounded, 'Akun'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, IconData iconActive, String label) {
    final selected = _index == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _index = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? iconActive : icon,
              color:
                  selected ? OptikMemberTokens.blue : OptikMemberTokens.inkMuted,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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
    return MemberPremiumScaffold(
      title: 'Pesanan',
      subtitle: 'Status · riwayat · garansi',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          const MemberSectionLabel('Pesanan'),
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
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          MemberFeatureTile(
            icon: Icons.verified_user_outlined,
            title: 'Kartu garansi',
            subtitle: 'Data asli sistem',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MemberWarrantyListPage()),
            ),
          ),
          const SizedBox(height: 10),
          MemberFeatureTile(
            icon: Icons.storefront_outlined,
            title: 'Klaim garansi',
            subtitle: 'Wajib datang + bawa barang',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MemberClaimPage()),
            ),
          ),
        ],
      ),
    );
  }
}
