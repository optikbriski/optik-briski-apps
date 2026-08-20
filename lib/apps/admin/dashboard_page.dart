import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'sales_page.dart';
import 'inventory.dart';
import 'product_master.dart';
import 'buku_besar.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/admin_approval_page.dart';
import '../../shared/training/training_banner.dart';
import '../../shared/training/training_curriculum.dart';
import '../../shared/training/training_mode.dart';
import '../../shared/widgets/optik_brand_logo.dart';
import 'riwayat_transaksi_page.dart';
import 'invoice_config_page.dart';
import 'member_home_content_page.dart';
import 'online_orders_page.dart';
import 'absensi_toko_page.dart';
import 'attendance_monitor_page.dart';
import 'jadwal_kerja_page.dart';
import 'monthly_export_page.dart';
import 'garansi_page.dart';
import 'toko_geofence_page.dart';
import 'tinjauan_mencurigakan_page.dart';
import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/qr/universal_qr_host.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'owner_provision_page.dart';
import 'owner_finance_ops_page.dart';
import 'tenant_admin_page.dart';

class DashboardPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const DashboardPage({super.key, required this.profile});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _omzetHariIni = 0;
  bool isStatsLoading = true;
  String? _fotoProfileUrl;
  bool _trainingBusy = false;

  @override
  void initState() {
    super.initState();
    UniversalQrHost.bind(
      callerRole: UniversalQrCallerRole.admin,
      profile: widget.profile,
    );
    _fetchTodayStats();
    _fetchFotoProfil();
  }

  @override
  void dispose() {
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
  String _formatRupiah(dynamic angka) {
    if (angka == null) return "rp_0".tr();
    try {
      int val = int.tryParse(angka.toString().split('.')[0]) ?? 0;
      return "Rp ${val.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}";
    } catch (e) {
      return "rp_0".tr();
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
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
        _snack('training_msg_exited'.tr(), OptikAdminTokens.slate);
        setState(() {});
      } catch (e) {
        _snack('training_msg_error'.tr().replaceAll('{}', '$e'), OptikAdminTokens.danger);
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
      _snack('training_msg_entered'.tr(), OptikAdminTokens.training);
      setState(() {});
    } catch (e) {
      _snack('training_msg_error'.tr().replaceAll('{}', '$e'), OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _trainingBusy = false);
    }
  }

  // 3. AMBIL STATISTIK JURNAL OMZET TOKO HARI INI
  Future<void> _fetchTodayStats() async {
    if (!mounted) return;
    setState(() => isStatsLoading = true);
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final res = await Supabase.instance.client
          .from('sales')
          .select('total_harga')
          .eq('toko_id', widget.profile['toko_id'] ?? 'KOSONG')
          .gte('created_at', '${today}T00:00:00')
          .lte('created_at', '${today}T23:59:59');

      int total = 0;
      for (var item in res) {
        total += (item['total_harga'] ?? 0) as int;
      }

      if (mounted) {
        setState(() {
          _omzetHariIni = total;
          isStatsLoading = false;
        });
      }
    } catch (e) {
      debugPrint("${'gagal_tarik_omzet'.tr()} $e");
      if (mounted) {
        setState(() => isStatsLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const OptikBrandLogo.color(height: 34),
        actions: [
          ListenableBuilder(
            listenable: TrainingMode.instance,
            builder: (context, _) {
              final active = TrainingMode.instance.isActive;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _HeaderIconButton(
                  tooltip: active
                      ? 'training_menu_exit'.tr()
                      : 'training_menu_enter'.tr(),
                  onPressed: _trainingBusy ? null : _toggleTrainingMode,
                  icon: Icons.school_rounded,
                  emphasized: active,
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _HeaderIconButton(
              tooltip: 'Logout',
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
              },
              icon: Icons.logout_rounded,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTodayStats,
        color: OptikAdminTokens.navy,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PremiumPanel(
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
                        color: OptikAdminTokens.ice.withOpacity(0.35),
                        border: Border.all(color: OptikAdminTokens.ice),
                        image: _fotoProfileUrl != null
                            ? DecorationImage(
                                image: NetworkImage(_fotoProfileUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _fotoProfileUrl == null
                          ? const Icon(Icons.person_rounded,
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
                              final role = (widget.profile['role'] ??
                                      'default_admin'.tr())
                                  .toString()
                                  .toUpperCase();
                              final toko = widget.profile['toko_id'] ==
                                      'CABANG-PUSAT'
                                  ? 'nama_toko_pusat'.brandTr()
                                  : widget.profile['toko_id'];
                              final via = (widget.profile[
                                          'login_via_karyawan_nama'] ??
                                      '')
                                  .toString()
                                  .trim();
                              if (via.isEmpty) return '$role · $toko';
                              return '$role · $toko · via $via';
                            }(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
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
              ),
              const SizedBox(height: 12),

              _buildOmzetCard(),
              const SizedBox(height: 28),

              PremiumSectionHeader(label: "dash_navigasi_menu".tr()),

              ListenableBuilder(
                listenable: TrainingMode.instance,
                builder: (context, _) {
                  final training = TrainingCurriculum.isActive;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final cols = w < 420 ? 2 : (w < 900 ? 3 : 4);
                      final ratio = w < 420 ? 2.55 : (w < 900 ? 2.75 : 2.95);
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: cols,
                        crossAxisSpacing: 11,
                        mainAxisSpacing: 11,
                        childAspectRatio: ratio,
                        children: [
                          // Manajemen Karyawan: pusat / owner / admin_pusat (standalone).
                          if (!training &&
                              (widget.profile['toko_id'] == 'PUSAT' ||
                                  widget.profile['toko_id'] ==
                                      'CABANG-PUSAT' ||
                                  widget.profile['role'] == 'owner' ||
                                  widget.profile['role'] == 'admin_pusat'))
                            PremiumMenuTile(
                              title: "dash_menu_management".tr(),
                              icon: Icons.verified_user_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => AdminApprovalPage(
                                    roleAdmin: widget.profile['role']
                                            ?.toString() ??
                                        '',
                                    cabangAdmin: widget.profile['toko_id']
                                            ?.toString() ??
                                        '',
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          // Buat Owner (franchise) — provision only.
                          if (!training &&
                              (widget.profile['toko_id'] == 'PUSAT' ||
                                  widget.profile['toko_id'] ==
                                      'CABANG-PUSAT' ||
                                  widget.profile['role'] == 'owner' ||
                                  widget.profile['role'] == 'admin_pusat' ||
                                  widget.profile['role'] == 'super_admin'))
                            PremiumMenuTile(
                              title: 'Buat Owner',
                              icon: Icons.workspace_premium_rounded,
                              color: OptikAdminTokens.navy,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OwnerProvisionPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (!training &&
                              (widget.profile['is_platform'] == true ||
                                  widget.profile['is_platform'] == 'true' ||
                                  widget.profile['role'] == 'platform'))
                            PremiumMenuTile(
                              title: 'UMKM / Tenant',
                              icon: Icons.apartment_rounded,
                              color: OptikAdminTokens.navy,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TenantAdminPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          // Payroll period + mutasi saldo pusat↔toko (Owner monitor sync).
                          if (!training &&
                              (widget.profile['toko_id'] == 'PUSAT' ||
                                  widget.profile['toko_id'] ==
                                      'CABANG-PUSAT' ||
                                  widget.profile['role'] == 'owner' ||
                                  widget.profile['role'] == 'admin_pusat' ||
                                  widget.profile['role'] == 'super_admin'))
                            PremiumMenuTile(
                              title: 'Payroll & Saldo Owner',
                              icon: Icons.account_balance_wallet_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OwnerFinanceOpsPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          // Monitor Absensi (tile sendiri): admin_pusat cabang + owner semua.
                          if (!training &&
                              AttendanceAdminScope.canOpenStoreMonitor(
                                  widget.profile))
                            PremiumMenuTile(
                              title: 'dash_menu_monitor_absensi'.tr(),
                              icon: Icons.fact_check_rounded,
                              color: OptikAdminTokens.slate,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AttendanceMonitorPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          // Absensi kiosk (QR→geo→face):
                          // - admin_toko cabang → Absensi (toko sendiri)
                          // - owner / admin_pusat → Absensi Pusat (perangkat Pusat)
                          if (!training &&
                              AttendanceAdminScope.canOpenStoreKiosk(
                                  widget.profile))
                            PremiumMenuTile(
                              title: AttendanceAdminScope.isPusatKioskLabel(
                                      widget.profile)
                                  ? 'dash_menu_absensi_pusat_kiosk'.tr()
                                  : 'dash_menu_absensi_kiosk'.tr(),
                              icon: Icons.face_retouching_natural_rounded,
                              color: OptikAdminTokens.slate,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AbsensiTokoPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          // Antrean tinjauan lanjut — hanya role yang boleh monitor.
                          if (!training &&
                              AttendanceAdminScope.canOpenStoreMonitor(
                                  widget.profile))
                            PremiumMenuTile(
                              title: 'dash_menu_tinjauan_mencurigakan'.tr(),
                              icon: Icons.warning_amber_rounded,
                              color: OptikAdminTokens.warning,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TinjauanMencurigakanPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          // Geofence: owner + admin_pusat saja (bukan cabang).
                          if (!training &&
                              AttendanceAdminScope.canManageGeofence(
                                  widget.profile))
                            PremiumMenuTile(
                              title: 'Geofence Toko',
                              icon: Icons.radar_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TokoGeofencePage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (!training &&
                              (widget.profile['toko_id'] == 'PUSAT' ||
                                  widget.profile['toko_id'] ==
                                      'CABANG-PUSAT' ||
                                  widget.profile['role'] == 'owner' ||
                                  widget.profile['role'] == 'admin_pusat' ||
                                  widget.profile['role'] == 'admin_toko'))
                            PremiumMenuTile(
                              title: 'Jadwal Kerja',
                              icon: Icons.calendar_month_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => JadwalKerjaPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (TrainingCurriculum.allows('pos'))
                            PremiumMenuTile(
                              title: "POS Cashier",
                              icon: Icons.point_of_sale_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) =>
                                      SalesPage(profile: widget.profile),
                                ),
                              ),
                            ),

                          // Request Order: only via Logistics hub (not a dashboard tile).

                          if (TrainingCurriculum.allows('history_dp'))
                            PremiumMenuTile(
                              title: "DP · PENDING · READY · CLEAR",
                              icon: Icons.history_edu,
                              color: OptikAdminTokens.slate,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => RiwayatTransaksiPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (TrainingCurriculum.allows('logistics'))
                            PremiumMenuTile(
                              title: "dash_menu_logistik".tr(),
                              icon: Icons.local_shipping_rounded,
                              color: OptikAdminTokens.slate,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (c) => InventoryOverview(
                                      profile: widget.profile,
                                    ),
                                  ),
                                );
                              },
                            ),

                          if (TrainingCurriculum.allows('master_data') &&
                              (training ||
                                  widget.profile['role'] == 'owner' ||
                                  widget.profile['role'] == 'admin_pusat' ||
                                  widget.profile['role'] == 'admin_toko' ||
                                  widget.profile['toko_id'] == 'PUSAT'))
                            PremiumMenuTile(
                              title: "dash_menu_master".tr(),
                              icon: Icons.dataset_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (c) => ProductMasterPage(
                                      profile: widget.profile,
                                    ),
                                  ),
                                );
                              },
                            ),

                          if (TrainingCurriculum.allows('finance'))
                            PremiumMenuTile(
                              title: "dash_menu_keuangan".tr(),
                              icon: Icons.account_balance_wallet_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => BukuBesarPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (!training &&
                              (widget.profile['role'] == 'owner' ||
                                  widget.profile['role'] == 'admin_pusat'))
                            PremiumMenuTile(
                              title: "Adjust Invoice",
                              icon: Icons.note_alt_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (c) => InvoiceConfigPage(
                                      profile: widget.profile,
                                    ),
                                  ),
                                );
                              },
                            ),

                          if (!training &&
                              (widget.profile['role'] == 'owner' ||
                                  widget.profile['role'] == 'admin_pusat' ||
                                  widget.profile['role'] == 'super_admin'))
                            PremiumMenuTile(
                              title: 'Konten Home Member',
                              icon: Icons.phone_android_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (c) => MemberHomeContentPage(
                                      profile: widget.profile,
                                    ),
                                  ),
                                );
                              },
                            ),

                          if (!training)
                            PremiumMenuTile(
                              title: 'Pesanan Online',
                              icon: Icons.shopping_bag_outlined,
                              color: OptikAdminTokens.ice,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (c) => OnlineOrdersPage(
                                      profile: widget.profile,
                                    ),
                                  ),
                                );
                              },
                            ),

                          // PDF export: pusat / owner only (bukan cabang).
                          if (!training &&
                              (widget.profile['toko_id'] == 'PUSAT' ||
                                  widget.profile['toko_id'] ==
                                      'CABANG-PUSAT' ||
                                  widget.profile['role'] == 'owner' ||
                                  widget.profile['role'] == 'admin_pusat'))
                            PremiumMenuTile(
                              title: 'dash_menu_export'.tr(),
                              icon: Icons.picture_as_pdf_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MonthlyExportPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (TrainingCurriculum.allows('warranty'))
                            PremiumMenuTile(
                              title: 'dash_menu_garansi'.tr(),
                              icon: Icons.verified_rounded,
                              color: OptikAdminTokens.ice,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      GaransiPage(profile: widget.profile),
                                ),
                              ),
                            ),

                          if (!training)
                            PremiumMenuTile(
                              title: 'scan_qr'.tr(),
                              icon: Icons.qr_code_scanner_rounded,
                              color: OptikAdminTokens.slate,
                              onTap: () => UniversalQrNav.open(
                                context,
                                profile: widget.profile,
                                callerRole: UniversalQrCallerRole.admin,
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 28),

              PremiumSectionHeader(label: 'training_sec_title'.tr()),
              ListenableBuilder(
                listenable: TrainingMode.instance,
                builder: (context, _) {
                  final active = TrainingMode.instance.isActive;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _trainingBusy ? null : _toggleTrainingMode,
                      borderRadius: BorderRadius.circular(22),
                      child: PremiumPanel(
                        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                        borderRadius: 20,
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: active
                                    ? OptikAdminTokens.navy
                                    : OptikAdminTokens.ice,
                              ),
                              child: Icon(
                                Icons.school_rounded,
                                color: active
                                    ? OptikAdminTokens.snow
                                    : OptikAdminTokens.navy,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'training_enter_eyebrow'.tr(),
                                    style: const TextStyle(
                                      color: OptikAdminTokens.slate,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    active
                                        ? 'training_menu_exit'.tr()
                                        : 'training_menu_enter'.tr(),
                                    style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    active
                                        ? 'training_menu_exit_desc'.tr()
                                        : 'training_menu_enter_desc'.tr(),
                                    style: const TextStyle(
                                      color: OptikAdminTokens.slate,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_trainingBusy)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: OptikAdminTokens.navy,
                                ),
                              )
                            else
                              Icon(
                                active
                                    ? Icons.logout_rounded
                                    : Icons.chevron_right_rounded,
                                color: OptikAdminTokens.textMuted,
                                size: 22,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOmzetCard() {
    return PremiumStatCard(
      label: "dash_penjualan_hari_ini".tr(),
      value: _formatRupiah(_omzetHariIni),
      loading: isStatsLoading,
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
                ? OptikAdminTokens.ice.withOpacity(0.35)
                : OptikAdminTokens.card,
            border: Border.all(
              color: emphasized
                  ? OptikAdminTokens.navy
                  : OptikAdminTokens.ice.withOpacity(0.4),
            ),
            boxShadow: OptikAdminTokens.cardShadow,
          ),
          child: Icon(
            icon,
            size: 19,
            color: emphasized
                ? OptikAdminTokens.navy
                : OptikAdminTokens.slate,
          ),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}
