import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/member/member_cart.dart';
import '../../shared/member/member_home_controller.dart';
import '../../shared/member/member_home_models.dart';
import '../../shared/member/member_session.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/optik_brand_logo.dart';
import 'member_rating_page.dart';
import 'pages/member_booking_page.dart';
import 'pages/member_care_page.dart';
import 'pages/member_face_shape_page.dart';
import 'pages/member_feature_pages.dart';
import 'pages/member_invoice_hub_page.dart';
import 'pages/member_online_order_page.dart';
import 'pages/member_orders_list_page.dart';
import 'pages/member_points_page.dart';
import 'pages/member_reorder_page.dart';
import 'pages/member_shop_shell.dart';
import 'pages/member_warranty_list_page.dart';

/// Beranda Member — CMS + data live lewat [MemberHomeController].
class HomeMemberPage extends StatefulWidget {
  const HomeMemberPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<HomeMemberPage> createState() => _HomeMemberPageState();
}

class _HomeMemberPageState extends State<HomeMemberPage> {
  final _home = MemberHomeController.instance;

  @override
  void initState() {
    super.initState();
    _home.addListener(_onHome);
    MemberCart.instance.addListener(_onCart);
    MemberCart.instance.ensureLoaded();
    _home.ensureLoaded();
  }

  @override
  void dispose() {
    _home.removeListener(_onHome);
    MemberCart.instance.removeListener(_onCart);
    super.dispose();
  }

  void _onHome() {
    if (mounted) setState(() {});
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openShop({int tab = 0}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberShopShell(initialTab: tab)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickStore() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const MemberStoresPage(pickMode: true),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    await MemberSession.instance.setPreferredToko(picked);
  }

  void _openReminder(MemberHomeReminder r) {
    if (r.kind == MemberHomeReminderKind.booking) {
      _open(const MemberBookingPage());
      return;
    }
    final oid = (r.onlineOrderId ?? '').trim();
    if (oid.isNotEmpty) {
      _open(MemberOnlineOrderPage(onlineOrderId: oid));
      return;
    }
    final inv = r.noInvoice;
    if (inv != null && inv.isNotEmpty) {
      _open(MemberInvoiceHubPage(noInvoice: inv));
    }
  }

  Future<void> _copyPromoCode(Map<String, dynamic> promo) async {
    if (!mounted) return;
    final code = (promo['voucher_code'] ?? '').toString().trim();
    final messenger = ScaffoldMessenger.of(context);
    if (code.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Tunjukkan promo ini ke kasir.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Kode $code disalin')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = MemberSession.instance;
    final snap = _home.snapshot;
    final loading = _home.loading && snap == null;
    final refreshing = _home.loading && snap != null;
    final name = (session.nama ?? '').trim();
    final guestHello = snap?.greetingGuest() ?? 'Hi, Teman Optik!';
    final guestSub = snap?.greetingSubtitleGuest() ??
        'Login untuk lihat pesanan & garansi';
    final hello = name.isEmpty ? guestHello : 'Hi, $name!';
    final slides = snap?.heroSlides() ??
        const [
          {
            'title': 'Kacamata siap?\nLangsung tahu di sini',
            'subtitle': 'Pantau status pesanan & ambil tanpa ribet',
            'image_url': '',
          },
        ];
    final brand = snap?.brandLabel() ?? 'OPTIK B. RISKI';
    final promoTitle = snap?.promoTitle() ?? 'Promo & poin';
    final promoSub = snap?.promoSubtitle() ?? 'Voucher dan saldo poin kamu';
    final sections = snap?.orderedSections() ??
        const [
          {'key': 'hero', 'visible': true, 'order': 0},
          {'key': 'greeting', 'visible': true, 'order': 1},
          {'key': 'promo', 'visible': true, 'order': 2},
          {'key': 'reminders', 'visible': true, 'order': 3},
          {'key': 'store', 'visible': true, 'order': 4},
          {'key': 'services_main', 'visible': true, 'order': 5},
          {'key': 'services_other', 'visible': true, 'order': 6},
        ];
    final top = MediaQuery.paddingOf(context).top;
    const overlap = 32.0;
    final showHero = sections.any((s) => s['key'] == 'hero');
    final error = snap?.error ?? _home.lastError;
    final highlightToko = snap?.highlightToko;
    final promos = snap?.promos ?? const [];
    final reminders = snap?.reminders ?? const [];
    final totalReminders = snap?.totalReminders ?? 0;
    final points = snap?.points ?? 0;
    final activeOrders = snap?.activeOrders ?? 0;
    final garansiCount = snap?.garansiCount ?? 0;

    bool flag(String key) => snap?.flag(key) ?? true;

    Widget sectionGap() => const SizedBox(height: 14);

    final columnChildren = <Widget>[];

    if (error != null && error.isNotEmpty) {
      columnChildren.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _ErrorBanner(
          message: error,
          onRetry: () => _home.refresh(force: true),
        ),
      ));
      columnChildren.add(sectionGap());
    }

    for (var i = 0; i < sections.length; i++) {
      final key = (sections[i]['key'] ?? '').toString();
      final prevKey =
          i > 0 ? (sections[i - 1]['key'] ?? '').toString() : '';
      final heroThenGreeting = key == 'greeting' && prevKey == 'hero';
      final heroAtTop = key == 'hero' && i == 0 && error == null;

      if (key == 'hero') {
        columnChildren.add(SizedBox(
          height: (heroAtTop ? 168 + top : 140),
          width: double.infinity,
          child: _HeroBanner(
            topInset: heroAtTop ? top : 12,
            brandLabel: brand,
            slides: slides,
          ),
        ));
        continue;
      }

      Widget? block;
      if (key == 'greeting') {
        block = _GreetingCard(
          hello: hello,
          loggedIn: session.isLoggedIn,
          phone: session.phoneRaw ?? session.phoneE164,
          guestSubtitle: guestSub,
          loading: loading || refreshing,
          points: points,
          activeOrders: activeOrders,
          garansiCount: garansiCount,
          onLogin: () => Navigator.of(context).pushNamed('/login'),
          onPoints: () => _open(const MemberPointsPage()),
          onOrders: () => _open(
            const MemberOrdersListPage(
              title: 'Status pesanan',
              onlyActive: true,
            ),
          ),
          onGaransi: () => _open(const MemberWarrantyListPage()),
        );
      } else if (key == 'promo') {
        block = _PromoSection(
          title: promoTitle,
          subtitle: promoSub,
          points: points,
          promos: promos,
          loggedIn: session.isLoggedIn,
          onOpenPoints: () => _open(const MemberPointsPage()),
          onPromoTap: _copyPromoCode,
          onLogin: () => Navigator.of(context).pushNamed('/login'),
        );
      } else if (key == 'reminders') {
        block = _RemindersBlock(
          reminders: reminders,
          totalCount: totalReminders,
          loggedIn: session.isLoggedIn,
          onSeeAll: () =>
              _open(const MemberOrdersListPage(title: 'Pesanan saya')),
          onLogin: () => Navigator.of(context).pushNamed('/login'),
          onReminder: _openReminder,
        );
      } else if (key == 'store') {
        block = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cabang saya',
              style: TextStyle(
                color: OptikMemberTokens.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _StoreChip(tokoId: highlightToko, onChange: _pickStore),
          ],
        );
      } else if (key == 'services_main') {
        final mainItems = <Widget>[];
        if (flag('katalog')) {
          mainItems.add(Expanded(
            child: _BigServiceButton(
              icon: Icons.storefront_rounded,
              label: 'Belanja\nOnline',
              onTap: () => _openShop(),
            ),
          ));
        }
        if (flag('janji_kontrol')) {
          if (mainItems.isNotEmpty) {
            mainItems.add(const SizedBox(width: 10));
          }
          mainItems.add(Expanded(
            child: _BigServiceButton(
              icon: Icons.event_available_rounded,
              label: 'Janji\nKontrol',
              onTap: () => _open(const MemberBookingPage()),
            ),
          ));
        }
        if (mainItems.isNotEmpty) {
          block = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Layanan utama',
                style: TextStyle(
                  color: OptikMemberTokens.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Row(children: mainItems),
            ],
          );
        }
      } else if (key == 'services_other') {
        final grid = <_GridItem>[
          if (flag('resep'))
            _GridItem(Icons.history_edu_outlined, 'Resep',
                () => _open(const MemberReorderPage())),
          if (flag('rating'))
            _GridItem(Icons.star_rate_rounded, 'Rating',
                () => _open(const MemberRatingPage())),
          if (flag('notif'))
            _GridItem(Icons.notifications_active_outlined, 'Notif',
                () => _open(const MemberNotificationsPage())),
          if (flag('perawatan'))
            _GridItem(Icons.menu_book_outlined, 'Perawatan',
                () => _open(const MemberCarePage())),
          if (flag('bentuk_wajah'))
            _GridItem(Icons.face_retouching_natural_rounded, 'Bentuk\nWajah',
                () => _open(const MemberFaceShapePage())),
        ];
        if (grid.isNotEmpty) {
          block = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Lainnya',
                style: TextStyle(
                  color: OptikMemberTokens.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              _ServiceGrid(items: grid),
            ],
          );
        }
      }

      if (block == null) continue;

      columnChildren.add(
        Transform.translate(
          offset: heroThenGreeting ? const Offset(0, -overlap) : Offset.zero,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              heroThenGreeting ? 0 : (i == 0 ? 12 : 0),
              16,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                block,
                heroThenGreeting
                    ? const SizedBox(height: overlap)
                    : sectionGap(),
              ],
            ),
          ),
        ),
      );
    }

    if (loading && columnChildren.isEmpty) {
      columnChildren.add(const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: CircularProgressIndicator()),
      ));
    }

    final body = RefreshIndicator(
      color: OptikMemberTokens.blue,
      onRefresh: () => _home.refresh(force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: columnChildren,
        ),
      ),
    );

    final cartBtn = Positioned(
      top: top + 6,
      right: 12,
      child: Material(
        color: Colors.white.withOpacity(0.92),
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(
          tooltip: 'Keranjang',
          onPressed: () => _openShop(tab: 2),
          icon: Badge(
            isLabelVisible: MemberCart.instance.totalQty > 0,
            label: Text('${MemberCart.instance.totalQty}'),
            child: const Icon(Icons.shopping_cart_outlined,
                color: OptikMemberTokens.blueDeep),
          ),
        ),
      ),
    );

    if (widget.embedded) {
      return ColoredBox(
        color: OptikMemberTokens.canvas,
        child: Stack(children: [body, if (showHero) cartBtn]),
      );
    }
    return Scaffold(
      backgroundColor: OptikMemberTokens.canvas,
      body: Stack(children: [body, if (showHero) cartBtn]),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        border: Border.all(color: OptikMemberTokens.danger.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: OptikMemberTokens.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: OptikMemberTokens.danger,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatefulWidget {
  const _HeroBanner({
    required this.topInset,
    required this.brandLabel,
    required this.slides,
  });

  final double topInset;
  final String brandLabel;
  final List<Map<String, String>> slides;

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  final _controller = PageController();
  int _page = 0;

  @override
  void didUpdateWidget(covariant _HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slides.length != widget.slides.length && _page > 0) {
      _page = 0;
      if (_controller.hasClients) {
        _controller.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView(
          controller: _controller,
          onPageChanged: (i) => setState(() => _page = i),
          children: [
            for (final s in slides)
              _bannerSlide(
                title: s['title'] ?? '',
                subtitle: s['subtitle'] ?? '',
                imageUrl: s['image_url'] ?? '',
              ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 48,
          child: Row(
            children: List.generate(slides.length, (i) {
              final on = i == _page;
              return Container(
                margin: const EdgeInsets.only(left: 5),
                width: on ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(on ? 0.95 : 0.45),
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _bannerSlide({
    required String title,
    required String subtitle,
    required String imageUrl,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl.trim().isNotEmpty)
          Image.network(
            imageUrl.trim(),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    OptikMemberTokens.blueDeep,
                    OptikMemberTokens.blue,
                    Color(0xFF2E86DE),
                  ],
                ),
              ),
            ),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  OptikMemberTokens.blueDeep,
                  OptikMemberTokens.blue,
                  Color(0xFF2E86DE),
                ],
              ),
            ),
          ),
        if (imageUrl.trim().isNotEmpty)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x660F172A),
                  Color(0x990F172A),
                ],
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, widget.topInset + 14, 20, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const OptikBrandLogo.white(height: 26),
                  if (widget.brandLabel.trim().isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.brandLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.88),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.hello,
    required this.loggedIn,
    required this.phone,
    required this.guestSubtitle,
    required this.loading,
    required this.points,
    required this.activeOrders,
    required this.garansiCount,
    required this.onLogin,
    required this.onPoints,
    required this.onOrders,
    required this.onGaransi,
  });

  final String hello;
  final bool loggedIn;
  final String? phone;
  final String guestSubtitle;
  final bool loading;
  final int points;
  final int activeOrders;
  final int garansiCount;
  final VoidCallback onLogin;
  final VoidCallback onPoints;
  final VoidCallback onOrders;
  final VoidCallback onGaransi;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: OptikMemberTokens.white,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
        border: Border.all(color: OptikMemberTokens.lineSoft),
        boxShadow: OptikMemberTokens.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hello,
                      style: const TextStyle(
                        color: OptikMemberTokens.blueDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loggedIn ? (phone ?? 'Akun terhubung') : guestSubtitle,
                      style: const TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!loggedIn)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: onLogin,
                  child: const Text('Login'),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.blueSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Aktif',
                    style: TextStyle(
                      color: OptikMemberTokens.blueDeep,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RoundStat(
                  icon: Icons.loyalty_rounded,
                  label: 'Poin',
                  value: loading ? '…' : '$points',
                  onTap: onPoints,
                ),
              ),
              Expanded(
                child: _RoundStat(
                  icon: Icons.local_shipping_outlined,
                  label: 'Pesanan',
                  value: loading ? '…' : '$activeOrders aktif',
                  onTap: onOrders,
                ),
              ),
              Expanded(
                child: _RoundStat(
                  icon: Icons.verified_user_outlined,
                  label: 'Garansi',
                  value: loading ? '…' : '$garansiCount',
                  onTap: onGaransi,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundStat extends StatelessWidget {
  const _RoundStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: OptikMemberTokens.blueSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: OptikMemberTokens.blue),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: OptikMemberTokens.blueDeep,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoSection extends StatelessWidget {
  const _PromoSection({
    required this.title,
    required this.subtitle,
    required this.points,
    required this.promos,
    required this.loggedIn,
    required this.onOpenPoints,
    required this.onPromoTap,
    required this.onLogin,
  });

  final String title;
  final String subtitle;
  final int points;
  final List<Map<String, dynamic>> promos;
  final bool loggedIn;
  final VoidCallback onOpenPoints;
  final ValueChanged<Map<String, dynamic>> onPromoTap;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: OptikMemberTokens.white,
          borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
          child: InkWell(
            onTap: loggedIn ? onOpenPoints : onLogin,
            borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
                border: Border.all(color: OptikMemberTokens.lineSoft),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: OptikMemberTokens.blueDeep,
                                fontSize: 13.5)),
                        const SizedBox(height: 2),
                        Text(
                          loggedIn
                              ? '$subtitle · $points poin'
                              : 'Login untuk lihat voucher & tukar poin',
                          style: const TextStyle(
                              color: OptikMemberTokens.inkMuted,
                              fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.blueSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_offer_outlined,
                        color: OptikMemberTokens.blue, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (promos.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: promos.length.clamp(0, 12),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final p = promos[i];
                final label = MemberHomeSnapshot.promoDiscountLabel(p);
                final name = (p['title'] ?? 'Promo').toString();
                final code = (p['voucher_code'] ?? '').toString().trim();
                return Material(
                  color: OptikMemberTokens.white,
                  borderRadius:
                      BorderRadius.circular(OptikMemberTokens.radiusMd),
                  child: InkWell(
                    onTap: () => onPromoTap(p),
                    borderRadius:
                        BorderRadius.circular(OptikMemberTokens.radiusMd),
                    child: Container(
                      width: 168,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(OptikMemberTokens.radiusMd),
                        border: Border.all(color: OptikMemberTokens.lineSoft),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: OptikMemberTokens.blueDeep,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: OptikMemberTokens.inkMuted,
                              fontSize: 11.5,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            code.isEmpty ? 'Info kasir' : code,
                            style: TextStyle(
                              color: OptikMemberTokens.blue,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: code.isEmpty ? 0 : 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _RemindersBlock extends StatelessWidget {
  const _RemindersBlock({
    required this.reminders,
    required this.totalCount,
    required this.loggedIn,
    required this.onSeeAll,
    required this.onLogin,
    required this.onReminder,
  });

  final List<MemberHomeReminder> reminders;
  final int totalCount;
  final bool loggedIn;
  final VoidCallback onSeeAll;
  final VoidCallback onLogin;
  final ValueChanged<MemberHomeReminder> onReminder;

  @override
  Widget build(BuildContext context) {
    final extra = totalCount > reminders.length
        ? totalCount - reminders.length
        : 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OptikMemberTokens.white,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
        border: Border.all(color: OptikMemberTokens.lineSoft),
        boxShadow: OptikMemberTokens.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pengingat',
                  style: TextStyle(
                    color: OptikMemberTokens.blueDeep,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              TextButton(
                onPressed: loggedIn ? onSeeAll : onLogin,
                child: Text(loggedIn ? 'Lihat semua' : 'Login dulu'),
              ),
            ],
          ),
          if (!loggedIn)
            const Padding(
              padding: EdgeInsets.only(bottom: 4, top: 4),
              child: Text(
                'Login untuk melihat kacamata siap diambil, DP, dan jadwal kontrol.',
                style: TextStyle(
                  color: OptikMemberTokens.inkMuted,
                  height: 1.4,
                  fontSize: 13,
                ),
              ),
            )
          else if (reminders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Tidak ada pengingat penting saat ini.',
                style: TextStyle(color: OptikMemberTokens.inkMuted),
              ),
            )
          else ...[
            ...reminders.map(
              (r) => Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OptikMemberTokens.blueMist,
                  borderRadius:
                      BorderRadius.circular(OptikMemberTokens.radiusSm),
                  border: Border.all(color: OptikMemberTokens.lineSoft),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 40,
                      decoration: BoxDecoration(
                        color: r.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.title,
                            style: TextStyle(
                              color: r.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r.body,
                            style: const TextStyle(
                              color: OptikMemberTokens.inkSecondary,
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        backgroundColor: r.accent,
                      ),
                      onPressed: () => onReminder(r),
                      child: Text(r.cta, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
            if (extra > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onSeeAll,
                    child: Text('+$extra pengingat lain · lihat semua'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StoreChip extends StatelessWidget {
  const _StoreChip({required this.tokoId, required this.onChange});

  final String? tokoId;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final raw = (tokoId ?? '').trim();
    final label = raw.isEmpty
        ? 'Belum dipilih'
        : raw.toUpperCase() == 'PUSAT'
            ? 'Pusat'
            : raw.replaceFirst(RegExp(r'^CABANG-', caseSensitive: false), '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: OptikMemberTokens.white,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        border: Border.all(color: OptikMemberTokens.lineSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.store_mall_directory_outlined,
              color: OptikMemberTokens.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: raw.isEmpty
                        ? OptikMemberTokens.inkMuted
                        : OptikMemberTokens.blueDeep,
                  ),
                ),
                if (raw.isEmpty)
                  const Text(
                    'Pilih cabang untuk janji & pengingat',
                    style: TextStyle(
                      color: OptikMemberTokens.inkMuted,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: Text(raw.isEmpty ? 'Pilih' : 'Ubah'),
          ),
        ],
      ),
    );
  }
}

class _BigServiceButton extends StatelessWidget {
  const _BigServiceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OptikMemberTokens.blueDeep,
      borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: OptikMemberTokens.blue,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    fontSize: 14,
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

class _GridItem {
  const _GridItem(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({required this.items});
  final List<_GridItem> items;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 4) {
      final chunk = items.skip(i).take(4).toList();
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 4 < items.length ? 12 : 0),
          child: Row(
            children: [
              for (var j = 0; j < 4; j++)
                Expanded(
                  child: j < chunk.length
                      ? _ServiceGridCell(item: chunk[j])
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _ServiceGridCell extends StatelessWidget {
  const _ServiceGridCell({required this.item});
  final _GridItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: OptikMemberTokens.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OptikMemberTokens.lineSoft),
                boxShadow: OptikMemberTokens.cardShadow,
              ),
              child: Icon(item.icon, color: OptikMemberTokens.blue),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: OptikMemberTokens.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
