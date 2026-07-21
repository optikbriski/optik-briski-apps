import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'sales_page.dart';
import 'inventory.dart';
import 'product_master.dart';
import 'buku_besar.dart';
import '../../shared/admin_approval_page.dart';
import '../../shared/training/training_banner.dart';
import '../../shared/training/training_curriculum.dart';
import '../../shared/training/training_mode.dart';
import 'riwayat_transaksi_page.dart';
import 'invoice_config_page.dart';
import 'attendance_qr_page.dart';
import 'jadwal_kerja_page.dart';
import 'monthly_export_page.dart';
import 'garansi_page.dart';
import '../../shared/qr/universal_qr_host.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

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
        _snack('training_msg_exited'.tr(), Colors.blueGrey);
        setState(() {});
      } catch (e) {
        _snack('training_msg_error'.tr().replaceAll('{}', '$e'), Colors.red);
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
      _snack('training_msg_entered'.tr(), const Color(0xFFB45309));
      setState(() {});
    } catch (e) {
      _snack('training_msg_error'.tr().replaceAll('{}', '$e'), Colors.red);
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Image.asset(
          'assets/images/logo_briski.png',
          height: 35,
          fit: BoxFit.contain,
        ),
        actions: [
          ListenableBuilder(
            listenable: TrainingMode.instance,
            builder: (context, _) {
              final active = TrainingMode.instance.isActive;
              return IconButton(
                tooltip: active
                    ? 'training_menu_exit'.tr()
                    : 'training_menu_enter'.tr(),
                onPressed: _trainingBusy ? null : _toggleTrainingMode,
                icon: Icon(
                  Icons.school_rounded,
                  color: active
                      ? OptikAdminTokens.training
                      : OptikAdminTokens.textSecondary,
                  size: 22,
                ),
              );
            },
          ),
          IconButton(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              // AdminAuthWrapper akan otomatis kembali ke LoginPage
            },
            icon: const Icon(Icons.logout_rounded,
                color: OptikAdminTokens.danger, size: 22),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTodayStats,
        color: OptikAdminTokens.accentSoft,
        backgroundColor: OptikAdminTokens.card,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SECTION HEADER USER PROFILE ---
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: OptikAdminTokens.accent.withOpacity(0.12),
                    backgroundImage: _fotoProfileUrl != null
                        ? NetworkImage(_fotoProfileUrl!)
                        : null,
                    child: _fotoProfileUrl == null
                        ? const Icon(Icons.person_rounded,
                            color: OptikAdminTokens.accentSoft, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("dash_selamat_bekerja".tr(),
                            style: const TextStyle(
                                color: OptikAdminTokens.textMuted,
                                fontSize: 11)),
                        Text(
                          "${(widget.profile['role'] ?? 'default_admin'.tr()).toString().toUpperCase()} - ${widget.profile['toko_id'] == 'CABANG-PUSAT' ? 'nama_toko_pusat'.tr() : widget.profile['toko_id']}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: OptikAdminTokens.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),

              // --- SECTION KARTU KINERJA OMZET ---
              _buildOmzetCard(),
              const SizedBox(height: 32),

              PremiumSectionHeader(label: "dash_navigasi_menu".tr()),

              // --- GRID NAVIGASI RESPONSIF (HP / tablet / web) ---
              // Training: only POS, Logistics, History&DP, Warranty, Finance, Master Data.
              ListenableBuilder(
                listenable: TrainingMode.instance,
                builder: (context, _) {
                  final training = TrainingCurriculum.isActive;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final cols = w < 420 ? 2 : (w < 720 ? 3 : 4);
                      final ratio = w < 420 ? 1.05 : (w < 720 ? 1.1 : 1.15);
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: cols,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: ratio,
                        children: [
                          // Manajemen Karyawan (+ monitor absensi): pusat only.
                          if (!training &&
                              (widget.profile['toko_id'] == 'PUSAT' ||
                                  widget.profile['toko_id'] ==
                                      'CABANG-PUSAT' ||
                                  widget.profile['role'] == 'owner' ||
                                  widget.profile['role'] == 'admin_pusat'))
                            PremiumMenuTile(
                              title: "dash_menu_management".tr(),
                              icon: Icons.verified_user_rounded,
                              color: OptikAdminTokens.accentSoft,
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

                          // Satu pintu Absen: QR toko → karyawan scan → face di APK
                          if (!training)
                            PremiumMenuTile(
                              title: 'dash_menu_absen'.tr(),
                              icon: Icons.qr_code_2_rounded,
                              color: Colors.deepPurpleAccent,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AttendanceQrPage(
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
                              color: Colors.indigoAccent,
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
                              color: OptikAdminTokens.success,
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
                              title: "History & Down Payment",
                              icon: Icons.history_edu,
                              color: Colors.orangeAccent,
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
                              color: OptikAdminTokens.warning,
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
                              color: Colors.indigoAccent,
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
                              color: Colors.tealAccent,
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
                              color: Colors.pinkAccent,
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
                              color: Colors.cyanAccent,
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
                              color: Colors.lightGreenAccent,
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
                              color: Colors.deepOrangeAccent,
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

              // Mode Latihan — 6 modul kurikulum; sandbox sync; wipe on exit.
              PremiumSectionHeader(label: 'training_sec_title'.tr()),
              ListenableBuilder(
                listenable: TrainingMode.instance,
                builder: (context, _) {
                  final active = TrainingMode.instance.isActive;
                  return PremiumPanel(
                    padding: EdgeInsets.zero,
                    borderRadius: OptikAdminTokens.radiusMd,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _trainingBusy ? null : _toggleTrainingMode,
                        borderRadius:
                            BorderRadius.circular(OptikAdminTokens.radiusMd),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                OptikAdminTokens.radiusMd),
                            border: Border.all(
                              color: active
                                  ? OptikAdminTokens.training
                                  : OptikAdminTokens.line,
                              width: active ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: OptikAdminTokens.training
                                      .withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  boxShadow: active
                                      ? OptikAdminTokens.glow(
                                          OptikAdminTokens.trainingSoft)
                                      : null,
                                ),
                                child: Icon(
                                  Icons.school_rounded,
                                  color: active
                                      ? OptikAdminTokens.training
                                      : OptikAdminTokens.trainingSoft,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      active
                                          ? 'training_menu_exit'.tr()
                                          : 'training_menu_enter'.tr(),
                                      style: TextStyle(
                                        color: active
                                            ? OptikAdminTokens.warning
                                            : OptikAdminTokens.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      active
                                          ? 'training_menu_exit_desc'.tr()
                                          : 'training_menu_enter_desc'.tr(),
                                      style: const TextStyle(
                                        color: OptikAdminTokens.textMuted,
                                        fontSize: 11,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_trainingBusy)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: OptikAdminTokens.training,
                                  ),
                                )
                              else
                                Icon(
                                  active
                                      ? Icons.logout_rounded
                                      : Icons.chevron_right_rounded,
                                  color: OptikAdminTokens.textMuted,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
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
