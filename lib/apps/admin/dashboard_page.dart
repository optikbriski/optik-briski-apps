import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../shared/admin_appearance.dart';
import '../../shared/admin/admin_nav_badge_service.dart';
import '../../shared/connectivity/connectivity_reload.dart';
import '../../shared/admin/admin_force_sync.dart';
import '../../shared/admin/admin_language.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/tenant/tenant_modules.dart';
import '../../shared/training/training_banner.dart';
import '../../shared/training/training_mode.dart';
import '../../shared/widgets/app_brand_mark.dart';
import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/qr/universal_qr_host.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/tenant_suspended_page.dart';
import 'admin_dash_nav.dart';
import 'admin_nav_sidebar.dart';

class DashboardPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const DashboardPage({super.key, required this.profile});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {
  static final Object _connectivityReloadOwner = Object();

  bool _trainingBusy = false;
  bool _forceSyncBusy = false;
  bool _sidebarOpen = true;
  bool _groupPicked = false;
  String? _openGroupId;
  String? _activeItemId = 'rangkuman_kerja';
  String? _fotoProfileUrl;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _paneNavKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AdminLanguage.ensureSupported(context);
    });
    UniversalQrHost.bind(
      callerRole: UniversalQrCallerRole.admin,
      profile: widget.profile,
    );
    _fetchTodayStats();
    _fetchFotoProfil();
    AdminNavBadgeService.instance.bindProfile(widget.profile);
    AdminNavBadgeService.instance.start();
    ConnectivityReload.bind(_connectivityReloadOwner, _reloadFromConnectivityBanner);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AdminNavBadgeService.instance.refresh());
    }
  }

  void _markNavItemUnread(String itemId) {
    unawaited(AdminNavBadgeService.instance.markScopeUnread(itemId));
  }

  Future<void> _reloadFromConnectivityBanner() async {
    await Future.wait<void>([
      _fetchTodayStats(),
      _fetchFotoProfil(),
      AdminNavBadgeService.instance.refresh(),
    ]);
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AdminNavBadgeService.instance.stop();
    ConnectivityReload.unbind(_connectivityReloadOwner);
    UniversalQrHost.clear();
    super.dispose();
  }

  // 1. FUNGSI TARIK FOTO PROFIL KARYAWAN REAL-TIME
  Future<void> _fetchFotoProfil() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Ambil URL foto dari tabel karyawan berdasarkan UID auth aktif
      final res = await supabase
          .from('karyawan')
          .select('foto_profile')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && res['foto_profile'] != null) {
        if (mounted) {
          setState(() {
            _fotoProfileUrl = res['foto_profile'].toString();
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal tarik foto profil untuk dashboard: $e");
    }
  }

  // 2. FORMATTER MATA UANG RUPIAH LOKAL
  void _snack(String msg, Color color, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  /// Paksa sinkron data cabang ini ke semua web/APK — bukan cek kebocoran.
  Future<void> _forceSync() async {
    if (_forceSyncBusy) return;
    setState(() => _forceSyncBusy = true);
    final toko = AdminForceSync.tokoFromProfile(widget.profile);
    final isPusat = AttendanceAdminScope.isPusatTokoId(toko);
    _snack(
      isPusat
          ? 'admin_force_sync_busy_pusat'.tr()
          : 'admin_force_sync_busy'.tr(namedArgs: {'toko': toko}),
      OptikAdminTokens.navy,
      duration: const Duration(seconds: 8),
    );
    try {
      // Pusat: reloadWeb false (di dalam AdminForceSync). Cabang: boleh reload.
      final result = await AdminForceSync.run(
        tokoId: toko,
        reloadWeb: !isPusat,
      );
      if (!mounted) return;
      // Web cabang mungkin sudah reload; Pusat tetap di halaman.
      if (result.reloadedWeb) return;
      // Matikan busy SEBELUM snack sukses — setState di finally menelan SnackBar.
      setState(() => _forceSyncBusy = false);
      _snack(
        result.pusatAllBranches
            ? 'admin_force_sync_ok_pusat'.tr(namedArgs: {
                'count': '${result.branchCount}',
              })
            : 'admin_force_sync_ok'.tr(namedArgs: {'toko': toko}),
        OptikAdminTokens.success,
        duration: const Duration(seconds: 6),
      );
      unawaited(_fetchTodayStats());
    } catch (e) {
      if (!mounted) return;
      setState(() => _forceSyncBusy = false);
      _snack(
        'admin_force_sync_fail'.tr(namedArgs: {'error': '$e'}),
        OptikAdminTokens.danger,
        duration: const Duration(seconds: 8),
      );
    } finally {
      if (mounted && _forceSyncBusy) {
        setState(() => _forceSyncBusy = false);
      }
    }
  }

  /// Enter/exit Training Mode — same full Admin menus; sandbox wipe on exit.
  Future<void> _toggleTrainingMode() async {
    if (_trainingBusy) return;
    if (TrainingMode.instance.isActive) {
      final ok = await TrainingModeDialogs.confirmExit(context);
      if (!ok || !mounted) return;
      setState(() => _trainingBusy = true);
      try {
        await TrainingMode.instance.exit();
        if (!mounted) return;
        _snack('admin_auto_8f01aad442'.tr(), OptikAdminTokens.slate);
        setState(() {});
      } catch (e) {
        _snack('admin_auto_3fdfb8b635'.tr().replaceAll('{}', '$e'),
            OptikAdminTokens.danger);
      } finally {
        if (mounted) setState(() => _trainingBusy = false);
      }
      return;
    }

    final ok = await TrainingModeDialogs.confirmEnter(context);
    if (!ok || !mounted) return;
    setState(() => _trainingBusy = true);
    try {
      // Lock to this account's toko + role (cabang stays cabang — no elevate).
      final profile = Map<String, dynamic>.from(widget.profile);
      if ((profile['toko_id'] ?? '').toString().trim().isEmpty) {
        throw 'training_err_no_admin_profile'.tr();
      }
      if ((profile['role'] ?? '').toString().trim().isEmpty) {
        throw 'training_err_no_admin_profile'.tr();
      }
      // Premium enter: ≥2s loading overlay while sandbox is prepared.
      await TrainingModeDialogs.runEnterWithLoading(
        context,
        () => TrainingMode.instance.enter(profile),
      );
      if (!mounted) return;
      _snack('admin_auto_73a6c032e3'.tr(), OptikAdminTokens.training);
      setState(() {});
    } catch (e) {
      _snack('admin_auto_3fdfb8b635'.tr().replaceAll('{}', '$e'),
          OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _trainingBusy = false);
    }
  }

  Future<void> _pickLook() async {
    final sel = await showAdminPicker<AdminAppearanceMode>(
      context: context,
      title: 'dash_look_title'.tr(),
      subtitle: 'dash_look_subtitle'.tr(),
      searchable: false,
      headerIcon: Icons.palette_outlined,
      selected: AdminAppearance.instance.mode,
      options: [
        AdminPickerOption(
          value: AdminAppearanceMode.frozenLake,
          label: 'dash_look_frozen'.tr(),
          subtitle: 'dash_look_frozen_sub'.tr(),
          icon: Icons.ac_unit_rounded,
        ),
        AdminPickerOption(
          value: AdminAppearanceMode.komboLight,
          label: 'dash_look_light'.tr(),
          subtitle: 'dash_look_light_sub'.tr(),
          icon: Icons.light_mode_rounded,
        ),
        AdminPickerOption(
          value: AdminAppearanceMode.komboDark,
          label: 'dash_look_dark'.tr(),
          subtitle: 'dash_look_dark_sub'.tr(),
          icon: Icons.dark_mode_rounded,
        ),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    await AdminAppearance.instance.setMode(sel.value!);
  }

  Future<void> _fetchTodayStats() async {
    try {
      await TenantModules.instance.load();
    } catch (e) {
      debugPrint("${'gagal_tarik_omzet'.tr()} $e");
    }
  }

  String? _resolvedGroupId(List<AdminDashNavGroup> groups) {
    final folders = groups.where((g) => !g.directItem).toList();
    if (folders.isEmpty) return null;
    if (_openGroupId != null && folders.any((g) => g.id == _openGroupId)) {
      return _openGroupId;
    }
    if (!_groupPicked) return folders.first.id;
    return null;
  }

  AdminDashNavItem? _itemById(List<AdminDashNavGroup> groups, String? id) {
    if (id == null) return null;
    for (final g in groups) {
      for (final item in g.items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  void _selectGroup(String id, {required String? currentlyOpen}) {
    setState(() {
      if (!_sidebarOpen) _sidebarOpen = true;
      _groupPicked = true;
      _openGroupId = currentlyOpen == id ? null : id;
    });
  }

  void _goHome() {
    setState(() => _activeItemId = 'rangkuman_kerja');
  }

  void _openNavItem(
    AdminDashNavItem item, {
    required List<AdminDashNavGroup> groups,
    required bool closeDrawer,
  }) {
    if (closeDrawer && _scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
    if (item.onOpen != null && item.buildPage == null) {
      item.onOpen!();
      return;
    }
    if (item.buildPage == null) return;

    String? groupId;
    for (final g in groups) {
      if (g.items.any((i) => i.id == item.id)) {
        groupId = g.id;
        break;
      }
    }
    setState(() {
      _groupPicked = true;
      if (groupId != null) _openGroupId = groupId;
      _activeItemId = item.id;
      if (!_sidebarOpen) _sidebarOpen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        TrainingMode.instance,
        TenantModules.instance,
        AdminAppearance.instance,
        AdminNavBadgeService.instance,
      ]),
      builder: (context, _) {
        final groups = buildAdminDashNavGroups(
          context: context,
          profile: widget.profile,
          onToggleTraining: _toggleTrainingMode,
        );
        final openId = _resolvedGroupId(groups);
        final active = _itemById(groups, _activeItemId);
        final badges = AdminNavBadgeService.instance.counts;

        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 900;
            return PopScope(
              canPop: _activeItemId == null ||
                  _activeItemId == 'rangkuman_kerja',
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _goHome();
              },
              child: PremiumScaffold(
                scaffoldKey: _scaffoldKey,
                drawer: narrow
                    ? Drawer(
                        backgroundColor: OptikAdminTokens.bgMid,
                        child: SafeArea(
                          child: AdminNavSidebar(
                            groups: groups,
                            openGroupId: openId,
                            selectedItemId: _activeItemId,
                            expanded: true,
                            badgeCounts: badges,
                            onClose: () => Navigator.of(context).pop(),
                            onSelectGroup: (id) => _selectGroup(
                              id,
                              currentlyOpen: openId,
                            ),
                            onOpenItem: (item) => _openNavItem(
                              item,
                              groups: groups,
                              closeDrawer: true,
                            ),
                            onMarkItemUnread: _markNavItemUnread,
                          ),
                        ),
                      )
                    : null,
                appBar: AppBar(
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  backgroundColor: OptikAdminTokens.bg,
                  surfaceTintColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  toolbarHeight: 64,
                  leadingWidth: 64,
                  flexibleSpace: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          OptikAdminTokens.isKombo ? OptikAdminTokens.bg : null,
                      gradient: OptikAdminTokens.isKombo
                          ? null
                          : LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.lerp(
                                  OptikAdminTokens.bgMid,
                                  OptikAdminTokens.ice,
                                  0.22,
                                )!,
                                OptikAdminTokens.bgMid,
                              ],
                            ),
                      border: Border(
                        bottom: BorderSide(
                          color: OptikAdminTokens.chromeEdge,
                          width: OptikAdminTokens.isKombo ? 1 : 1.2,
                        ),
                      ),
                    ),
                  ),
                  leading: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                    child: _HeaderIconButton(
                      tooltip: 'dash_nav_toggle'.tr(),
                      icon: Icons.menu_rounded,
                      emphasized: true,
                      onPressed: () {
                        if (narrow) {
                          _scaffoldKey.currentState?.openDrawer();
                        } else {
                          setState(() => _sidebarOpen = !_sidebarOpen);
                        }
                      },
                    ),
                  ),
                  centerTitle: false,
                  titleSpacing: 8,
                  title: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: _goHome,
                      behavior: HitTestBehavior.opaque,
                      child: AppBrandMark(
                        height: 34,
                        onDark: OptikAdminTokens.isDark,
                      ),
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 4, 12),
                      child: _HeaderIconButton(
                        tooltip: 'admin_menu_language'.tr(),
                        icon: Icons.translate_rounded,
                        onPressed: () => AdminLanguage.showPicker(context),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 4, 12),
                      child: _HeaderIconButton(
                        tooltip: 'dash_look_title'.tr(),
                        icon: Icons.palette_outlined,
                        onPressed: _pickLook,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 4, 12),
                      child: _HeaderIconButton(
                        tooltip: 'admin_force_sync_tooltip'.tr(),
                        onPressed: _forceSyncBusy ? null : _forceSync,
                        icon: _forceSyncBusy
                            ? Icons.hourglass_top_rounded
                            : Icons.sync_rounded,
                      ),
                    ),
                    ListenableBuilder(
                      listenable: TrainingMode.instance,
                      builder: (context, _) {
                        final active = TrainingMode.instance.isActive;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 4, 12),
                          child: _HeaderIconButton(
                            tooltip: active
                                ? 'training_menu_exit'.tr()
                                : 'training_menu_enter'.tr(),
                            onPressed:
                                _trainingBusy ? null : _toggleTrainingMode,
                            icon: Icons.school_rounded,
                            emphasized: active,
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                      child: _HeaderIconButton(
                        tooltip: 'admin_logout'.tr(),
                        onPressed: () async {
                          await signOutQuiet();
                        },
                        icon: Icons.logout_rounded,
                      ),
                    ),
                  ],
                ),
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!narrow)
                      AdminNavSidebar(
                        groups: groups,
                        openGroupId: openId,
                        selectedItemId: _activeItemId,
                        expanded: _sidebarOpen,
                        showHeader: _sidebarOpen,
                        badgeCounts: badges,
                        onSelectGroup: (id) => _selectGroup(
                          id,
                          currentlyOpen: openId,
                        ),
                        onOpenItem: (item) => _openNavItem(
                          item,
                          groups: groups,
                          closeDrawer: false,
                        ),
                        onMarkItemUnread: _markNavItemUnread,
                      ),
                    Expanded(
                      child: Navigator(
                        key: _paneNavKey,
                        onDidRemovePage: (page) {
                          if (page.name != _activeItemId) return;
                          setState(() => _activeItemId = null);
                        },
                        pages: [
                          MaterialPage<void>(
                            key: const ValueKey('admin-dash-home'),
                            name: 'home',
                            child: _buildHomePane(),
                          ),
                          if (active?.buildPage != null)
                            MaterialPage<void>(
                              key: ValueKey(active!.id),
                              name: active.id,
                              child: Builder(builder: active.buildPage!),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHomePane() {
    return RefreshIndicator(
      onRefresh: _fetchTodayStats,
      color: OptikAdminTokens.navy,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGreetingCard(),
            const SizedBox(height: 28),
            _buildRekasaWatermark(),
          ],
        ),
      ),
    );
  }

  Widget _buildGreetingCard() {
    return PremiumPanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
      borderRadius: 20,
      showAccentBar: true,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: OptikAdminTokens.ice.withOpacity(0.55),
              border: Border.all(color: OptikAdminTokens.ice),
              image: _fotoProfileUrl != null
                  ? DecorationImage(
                      image: NetworkImage(_fotoProfileUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _fotoProfileUrl == null
                ? Icon(Icons.person_rounded,
                    color: OptikAdminTokens.navy, size: 24)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "dash_selamat_bekerja".tr().toUpperCase(),
                  style: TextStyle(
                    color: OptikAdminTokens.slate.withOpacity(0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.9,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  () {
                    final role =
                        (widget.profile['role'] ?? 'default_admin'.tr())
                            .toString()
                            .toUpperCase();
                    final toko = widget.profile['toko_id'] == 'CABANG-PUSAT'
                        ? 'nama_toko_pusat'.brandTr()
                        : widget.profile['toko_id'];
                    final via =
                        (widget.profile['login_via_karyawan_nama'] ?? '')
                            .toString()
                            .trim();
                    if (via.isEmpty) return '$role · $toko';
                    return '$role · $toko · via $via';
                  }(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17.5,
                    height: 1.2,
                    letterSpacing: -0.3,
                    color: OptikAdminTokens.navy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRekasaWatermark() {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        '(by Rekasa)',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: OptikAdminTokens.slate.withOpacity(0.45),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.emphasized = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: emphasized
                ? (OptikAdminTokens.isKombo
                    ? OptikAdminTokens.navy
                    : OptikAdminTokens.ice.withOpacity(0.45))
                : OptikAdminTokens.card.withOpacity(0.85),
            border: Border.all(
              color: emphasized
                  ? OptikAdminTokens.navy
                  : OptikAdminTokens.chromeEdge,
            ),
            boxShadow: OptikAdminTokens.cardShadow,
          ),
          child: Icon(
            icon,
            size: 19,
            color: emphasized
                ? (OptikAdminTokens.isKombo
                    ? OptikAdminTokens.onHighlight
                    : OptikAdminTokens.navy)
                : OptikAdminTokens.slate,
          ),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}
