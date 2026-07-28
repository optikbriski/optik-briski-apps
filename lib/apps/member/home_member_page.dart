import 'package:flutter/material.dart';

import '../../shared/invoice/invoice_hub_service.dart';
import '../../shared/member/member_repository.dart';
import '../../shared/member/member_session.dart';
import '../../shared/theme.dart';
import 'member_rating_page.dart';
import 'pages/member_booking_page.dart';
import 'pages/member_care_page.dart';
import 'pages/member_catalog_page.dart';
import 'pages/member_feature_pages.dart';
import 'pages/member_invoice_hub_page.dart';
import 'pages/member_orders_list_page.dart';
import 'pages/member_points_page.dart';
import 'pages/member_reorder_page.dart';
import 'pages/member_warranty_list_page.dart';

/// Beranda Member — pola Janji Jiwa + GoPay:
/// highlight info penting, pengingat actionable, aksi cepat (putih–biru).
class HomeMemberPage extends StatefulWidget {
  const HomeMemberPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<HomeMemberPage> createState() => _HomeMemberPageState();
}

class _HomeMemberPageState extends State<HomeMemberPage> {
  final _repo = MemberRepository();
  bool _loading = true;
  int _points = 0;
  int _activeOrders = 0;
  int _garansiCount = 0;
  List<_HomeReminder> _reminders = const [];
  String? _highlightToko;
  Map<String, dynamic>? _homeContent;

  @override
  void initState() {
    super.initState();
    MemberSession.instance.addListener(_onSession);
    _load();
  }

  @override
  void dispose() {
    MemberSession.instance.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    _load();
  }

  Future<void> _load() async {
    final session = MemberSession.instance;
    final content = await _repo.homeContent();

    if (!session.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _points = 0;
        _activeOrders = 0;
        _garansiCount = 0;
        _reminders = const [];
        _highlightToko = null;
        _homeContent = content;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final phone = session.phoneForQuery;
      final sales = await _repo.listSales(phone);
      final garansi = await _repo.listGaransi(phone);
      final bookings = await _repo.listBookings(phone);
      final pts = (session.memberId == null || session.memberId!.isEmpty)
          ? 0
          : await _repo.pointsBalance(session.memberId!);

      final active = <Map<String, dynamic>>[];
      final reminders = <_HomeReminder>[];

      for (final s in sales) {
        final diambil = s['diambil_at'] != null ||
            (s['tracking_status']?.toString().toUpperCase() == 'DIAMBIL');
        if (!diambil) active.add(s);

        final label = InvoiceHubService.statusLabel({
          'tracking_status': s['tracking_status'],
          'diambil_at': s['diambil_at'],
        });
        final inv = s['no_invoice']?.toString() ?? '';
        final st = (s['tracking_status'] ?? '').toString().toUpperCase();
        final sisa = int.tryParse('${s['sisa_tagihan'] ?? 0}') ?? 0;

        if (st == 'SIAP_DIAMBIL' || st == 'CLEAR') {
          reminders.add(_HomeReminder(
            title: 'Siap diambil',
            body: '$inv · $label',
            accent: OptikMemberTokens.success,
            cta: 'Lihat nota',
            onTap: () => _open(MemberInvoiceHubPage(noInvoice: inv)),
          ));
        } else if (!diambil && sisa > 0) {
          reminders.add(_HomeReminder(
            title: 'Masih DP',
            body: '$inv · lunasi dulu sebelum ambil',
            accent: OptikMemberTokens.warning,
            cta: 'Detail',
            onTap: () => _open(MemberInvoiceHubPage(noInvoice: inv)),
          ));
        } else if (!diambil) {
          reminders.add(_HomeReminder(
            title: 'Dalam proses',
            body: '$inv · $label',
            accent: OptikMemberTokens.blue,
            cta: 'Lacak',
            onTap: () => _open(MemberInvoiceHubPage(noInvoice: inv)),
          ));
        }
      }

      final now = DateTime.now();
      for (final b in bookings) {
        if ((b['status'] ?? '') != 'booked') continue;
        final at = DateTime.tryParse('${b['scheduled_at']}');
        if (at == null) continue;
        final local = at.toLocal();
        if (local.isBefore(now.subtract(const Duration(hours: 2)))) continue;
        reminders.insert(
          0,
          _HomeReminder(
            title: 'Janji kontrol',
            body: '${b['toko_id']} · ${_fmtWhen(local)}',
            accent: OptikMemberTokens.blueDeep,
            cta: 'Jadwal',
            onTap: () => _open(const MemberBookingPage()),
          ),
        );
      }

      // Prioritas: siap diambil dulu, max 4
      reminders.sort((a, b) {
        int rank(_HomeReminder r) {
          if (r.title.contains('Siap')) return 0;
          if (r.title.contains('Janji')) return 1;
          if (r.title.contains('DP')) return 2;
          return 3;
        }

        return rank(a).compareTo(rank(b));
      });

      String? toko;
      if (active.isNotEmpty) {
        toko = active.first['toko_id']?.toString();
      } else if (sales.isNotEmpty) {
        toko = sales.first['toko_id']?.toString();
      }

      if (!mounted) return;
      setState(() {
        _points = pts;
        _activeOrders = active.length;
        _garansiCount = garansi.length;
        _reminders = reminders.take(4).toList();
        _highlightToko = toko;
        _homeContent = content;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _homeContent = content;
        _loading = false;
      });
    }
  }

  List<Map<String, String>> get _heroSlides {
    final raw = _homeContent?['slides'];
    final out = <Map<String, String>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final title = (e['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        out.add({
          'title': title,
          'subtitle': (e['subtitle'] ?? '').toString(),
          'image_url': (e['image_url'] ?? '').toString(),
        });
      }
    }
    if (out.isEmpty) {
      return const [
        {
          'title': 'Kacamata siap?\nLangsung tahu di sini',
          'subtitle': 'Pantau status pesanan & ambil tanpa ribet',
          'image_url': '',
        },
        {
          'title': 'Garansi digital\nOptik B. Riski',
          'subtitle': 'Data asli sistem · klaim wajib cek di toko',
          'image_url': '',
        },
      ];
    }
    return out;
  }

  List<Map<String, dynamic>> get _orderedSections {
    const fallback = [
      {'key': 'hero', 'visible': true, 'order': 0},
      {'key': 'greeting', 'visible': true, 'order': 1},
      {'key': 'promo', 'visible': true, 'order': 2},
      {'key': 'reminders', 'visible': true, 'order': 3},
      {'key': 'store', 'visible': true, 'order': 4},
      {'key': 'services_main', 'visible': true, 'order': 5},
      {'key': 'services_other', 'visible': true, 'order': 6},
    ];
    final raw = _homeContent?['sections'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    }
    final src = list.isEmpty ? fallback : list;
    final sorted = [...src]..sort((a, b) =>
        ((a['order'] as num?)?.toInt() ?? 0)
            .compareTo((b['order'] as num?)?.toInt() ?? 0));
    return sorted.where((s) => s['visible'] != false).toList();
  }

  bool _flag(String key) {
    final f = _homeContent?['feature_flags'];
    if (f is Map && f.containsKey(key)) return f[key] != false;
    return true;
  }

  String _fmtWhen(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final session = MemberSession.instance;
    final name = (session.nama ?? '').trim();
    final guestHello = (_homeContent?['greeting_guest'] ?? 'Hi, Teman Optik!')
        .toString();
    final guestSub = (_homeContent?['greeting_subtitle_guest'] ??
            'Login untuk lihat pesanan & garansi')
        .toString();
    final hello = name.isEmpty ? guestHello : 'Hi, $name!';
    final slides = _heroSlides;
    final brand =
        (_homeContent?['brand_label'] ?? 'OPTIK B. RISKI').toString();
    final promoTitle =
        (_homeContent?['promo_title'] ?? 'Promo & poin').toString();
    final promoSub = (_homeContent?['promo_subtitle'] ??
            'Voucher dan saldo poin kamu')
        .toString();
    final top = MediaQuery.paddingOf(context).top;
    const overlap = 32.0;
    final sections = _orderedSections;
    final showHero = sections.any((s) => s['key'] == 'hero');
    final showGreeting = sections.any((s) => s['key'] == 'greeting');
    final bodySections = sections.where((s) => s['key'] != 'hero').toList();

    Widget sectionGap() => const SizedBox(height: 14);

    final bodyChildren = <Widget>[];
    for (final section in bodySections) {
      final key = (section['key'] ?? '').toString();
      if (key == 'greeting') {
        bodyChildren.add(_GreetingCard(
          hello: hello,
          loggedIn: session.isLoggedIn,
          phone: session.phoneRaw ?? session.phoneE164,
          guestSubtitle: guestSub,
          loading: _loading,
          points: _points,
          activeOrders: _activeOrders,
          garansiCount: _garansiCount,
          onLogin: () => Navigator.of(context).pushNamed('/login'),
          onPoints: () => _open(const MemberPointsPage()),
          onOrders: () => _open(
            const MemberOrdersListPage(
              title: 'Status pesanan',
              onlyActive: true,
            ),
          ),
          onGaransi: () => _open(const MemberWarrantyListPage()),
        ));
        bodyChildren.add(
          (showHero && showGreeting)
              ? const SizedBox(height: overlap)
              : sectionGap(),
        );
      } else if (key == 'promo') {
        bodyChildren.add(_MiniActionCard(
          icon: Icons.local_offer_outlined,
          title: promoTitle,
          subtitle: promoSub,
          onTap: () => _open(const MemberPointsPage()),
        ));
        bodyChildren.add(sectionGap());
      } else if (key == 'reminders') {
        bodyChildren.add(_RemindersBlock(
          reminders: _reminders,
          loggedIn: session.isLoggedIn,
          onSeeAll: () =>
              _open(const MemberOrdersListPage(title: 'Pesanan saya')),
          onLogin: () => Navigator.of(context).pushNamed('/login'),
        ));
        bodyChildren.add(sectionGap());
      } else if (key == 'store') {
        if (_highlightToko != null && _highlightToko!.isNotEmpty) {
          bodyChildren.add(const Text(
            'Cabang terkait',
            style: TextStyle(
              color: OptikMemberTokens.ink,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ));
          bodyChildren.add(const SizedBox(height: 8));
          bodyChildren.add(_StoreChip(
            tokoId: _highlightToko!,
            onChange: () => _open(const MemberStoresPage()),
          ));
          bodyChildren.add(sectionGap());
        }
      } else if (key == 'services_main') {
        final mainItems = <Widget>[];
        if (_flag('katalog')) {
          mainItems.add(Expanded(
            child: _BigServiceButton(
              icon: Icons.visibility_outlined,
              label: 'Katalog\nproduk',
              onTap: () => _open(const MemberCatalogPage()),
            ),
          ));
        }
        if (_flag('janji_kontrol')) {
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
          bodyChildren.add(const Text(
            'Layanan utama',
            style: TextStyle(
              color: OptikMemberTokens.ink,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ));
          bodyChildren.add(const SizedBox(height: 8));
          bodyChildren.add(Row(children: mainItems));
          bodyChildren.add(sectionGap());
        }
      } else if (key == 'services_other') {
        final grid = <_GridItem>[
          if (_flag('resep'))
            _GridItem(Icons.history_edu_outlined, 'Resep',
                () => _open(const MemberReorderPage())),
          if (_flag('rating'))
            _GridItem(Icons.star_rate_rounded, 'Rating',
                () => _open(const MemberRatingPage())),
          if (_flag('notif'))
            _GridItem(Icons.notifications_active_outlined, 'Notif',
                () => _open(const MemberNotificationsPage())),
          if (_flag('perawatan'))
            _GridItem(Icons.menu_book_outlined, 'Perawatan',
                () => _open(const MemberCarePage())),
        ];
        if (grid.isNotEmpty) {
          bodyChildren.add(const Text(
            'Lainnya',
            style: TextStyle(
              color: OptikMemberTokens.ink,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ));
          bodyChildren.add(const SizedBox(height: 10));
          bodyChildren.add(_ServiceGrid(items: grid));
        }
      }
    }

    final body = RefreshIndicator(
      color: OptikMemberTokens.blue,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHero)
              SizedBox(
                height: 168 + top,
                width: double.infinity,
                child: _HeroBanner(
                  topInset: top,
                  brandLabel: brand,
                  slides: slides,
                ),
              ),
            Transform.translate(
              offset: (showHero && showGreeting)
                  ? const Offset(0, -overlap)
                  : Offset.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: bodyChildren,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return ColoredBox(color: OptikMemberTokens.canvas, child: body);
    }
    return Scaffold(backgroundColor: OptikMemberTokens.canvas, body: body);
  }
}

class _HomeReminder {
  const _HomeReminder({
    required this.title,
    required this.body,
    required this.accent,
    required this.cta,
    required this.onTap,
  });

  final String title;
  final String body;
  final Color accent;
  final String cta;
  final VoidCallback onTap;
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
              Text(
                widget.brandLabel,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontSize: 12.5,
                  height: 1.35,
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
                      loggedIn
                          ? (phone ?? 'Akun terhubung')
                          : guestSubtitle,
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

class _MiniActionCard extends StatelessWidget {
  const _MiniActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OptikMemberTokens.white,
      borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
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
                    Text(subtitle,
                        style: const TextStyle(
                            color: OptikMemberTokens.inkMuted, fontSize: 11.5)),
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
                child: Icon(icon, color: OptikMemberTokens.blue, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemindersBlock extends StatelessWidget {
  const _RemindersBlock({
    required this.reminders,
    required this.loggedIn,
    required this.onSeeAll,
    required this.onLogin,
  });

  final List<_HomeReminder> reminders;
  final bool loggedIn;
  final VoidCallback onSeeAll;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
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
          else
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
                      onPressed: r.onTap,
                      child: Text(r.cta, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StoreChip extends StatelessWidget {
  const _StoreChip({required this.tokoId, required this.onChange});

  final String tokoId;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final label = tokoId.toUpperCase() == 'PUSAT'
        ? 'Pusat'
        : tokoId.replaceFirst(RegExp(r'^CABANG-', caseSensitive: false), '');
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
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: OptikMemberTokens.blueDeep,
              ),
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Ubah')),
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
    // Row manual — hindari GridView yang meregang di IndexedStack.
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
