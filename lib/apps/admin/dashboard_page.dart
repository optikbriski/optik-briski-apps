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
import 'request_order_page.dart';
import 'invoice_config_page.dart';
import 'attendance_monitor_page.dart';
import 'attendance_qr_page.dart';
import 'jadwal_kerja_page.dart';
import 'monthly_export_page.dart';
import 'garansi_page.dart';
import '../../shared/qr/universal_qr_host.dart';
import '../../shared/qr/universal_qr_nav.dart';

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
      await TrainingMode.instance.enter(profile);
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
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
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
                      ? const Color(0xFFB45309)
                      : Colors.white70,
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
                color: Colors.redAccent, size: 22),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTodayStats,
        color: Colors.blueAccent,
        backgroundColor: const Color(0xFF1E293B),
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
                    backgroundColor: Colors.blueAccent.withOpacity(0.1),
                    backgroundImage: _fotoProfileUrl != null
                        ? NetworkImage(_fotoProfileUrl!)
                        : null,
                    child: _fotoProfileUrl == null
                        ? const Icon(Icons.person_rounded,
                            color: Colors.blueAccent, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("dash_selamat_bekerja".tr(),
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11)),
                        Text(
                          "${(widget.profile['role'] ?? 'default_admin'.tr()).toString().toUpperCase()} - ${widget.profile['toko_id'] == 'CABANG-PUSAT' ? 'nama_toko_pusat'.tr() : widget.profile['toko_id']}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),

              // --- SECTION KARTU KINERJA OMZET ---
              _buildOmzetCard(),
              const SizedBox(height: 35),

              Text("dash_navigasi_menu".tr(),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5)),
              const SizedBox(height: 15),

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
                          if (!training &&
                              widget.profile['toko_id'] == 'PUSAT')
                            _menuCard(
                              context,
                              "dash_menu_management".tr(),
                              Icons.verified_user_rounded,
                              Colors.blueAccent,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => AdminApprovalPage(
                                    roleAdmin: widget.profile['role']
                                            ?.toString() ??
                                        '',
                                    cabangAdmin: widget.profile['toko_id']
                                            ?.toString() ??
                                        '',
                                  ),
                                ),
                              ),
                            ),

                          if (!training)
                            _menuCard(
                              context,
                              "hr_tab_absen".tr(),
                              Icons.face_retouching_natural_rounded,
                              Colors.purpleAccent,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AttendanceMonitorPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (!training)
                            _menuCard(
                              context,
                              'dash_menu_attendance_qr'.tr(),
                              Icons.qr_code_2_rounded,
                              Colors.deepPurpleAccent,
                              () => Navigator.push(
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
                            _menuCard(
                              context,
                              'Jadwal Kerja',
                              Icons.calendar_month_rounded,
                              Colors.indigoAccent,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => JadwalKerjaPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (TrainingCurriculum.allows('pos'))
                            _menuCard(
                              context,
                              "POS Cashier",
                              Icons.point_of_sale_rounded,
                              Colors.greenAccent,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) =>
                                      SalesPage(profile: widget.profile),
                                ),
                              ),
                            ),

                          // Live: separate RO tile. Training: RO via Logistics hub.
                          if (!training)
                            _menuCard(
                              context,
                              "Request Order",
                              Icons.local_shipping_rounded,
                              Colors.orangeAccent,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => RequestOrderPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (TrainingCurriculum.allows('history_dp'))
                            _menuCard(
                              context,
                              "History & Down Payment",
                              Icons.history_edu,
                              Colors.orangeAccent,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => RiwayatTransaksiPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (TrainingCurriculum.allows('logistics'))
                            _menuCard(
                              context,
                              "dash_menu_logistik".tr(),
                              Icons.local_shipping_rounded,
                              Colors.amber,
                              () {
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
                            _menuCard(
                              context,
                              "dash_menu_master".tr(),
                              Icons.dataset_rounded,
                              Colors.indigoAccent,
                              () {
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
                            _menuCard(
                              context,
                              "dash_menu_keuangan".tr(),
                              Icons.account_balance_wallet_rounded,
                              Colors.tealAccent,
                              () => Navigator.push(
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
                            _menuCard(
                              context,
                              "Adjust Invoice",
                              Icons.note_alt_rounded,
                              Colors.pinkAccent,
                              () {
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

                          if (!training)
                            _menuCard(
                              context,
                              'dash_menu_export'.tr(),
                              Icons.picture_as_pdf_rounded,
                              Colors.cyanAccent,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MonthlyExportPage(
                                    profile: widget.profile,
                                  ),
                                ),
                              ),
                            ),

                          if (TrainingCurriculum.allows('warranty'))
                            _menuCard(
                              context,
                              'dash_menu_garansi'.tr(),
                              Icons.verified_rounded,
                              Colors.lightGreenAccent,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      GaransiPage(profile: widget.profile),
                                ),
                              ),
                            ),

                          if (!training)
                            _menuCard(
                              context,
                              'scan_qr'.tr(),
                              Icons.qr_code_scanner_rounded,
                              Colors.deepOrangeAccent,
                              () => UniversalQrNav.open(
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
              Text(
                'training_sec_title'.tr(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              ListenableBuilder(
                listenable: TrainingMode.instance,
                builder: (context, _) {
                  final active = TrainingMode.instance.isActive;
                  return Material(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: _trainingBusy ? null : _toggleTrainingMode,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: active
                                ? const Color(0xFFB45309)
                                : Colors.white.withOpacity(0.06),
                            width: active ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB45309)
                                    .withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.school_rounded,
                                color: active
                                    ? const Color(0xFFB45309)
                                    : Colors.orangeAccent,
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
                                          ? const Color(0xFFFBBF24)
                                          : Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    active
                                        ? 'training_menu_exit_desc'.tr()
                                        : 'training_menu_enter_desc'.tr(),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.55),
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
                                  color: Color(0xFFB45309),
                                ),
                              )
                            else
                              Icon(
                                active
                                    ? Icons.logout_rounded
                                    : Icons.chevron_right_rounded,
                                color: Colors.white38,
                                size: 20,
                              ),
                          ],
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

  // WIDGET PEMBANTU: KARTU OMZET HARI INI
  Widget _buildOmzetCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("dash_penjualan_hari_ini".tr(),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              Icon(Icons.trending_up,
                  color: Colors.white.withOpacity(0.5), size: 18),
            ],
          ),
          const SizedBox(height: 10),
          isStatsLoading
              ? const SizedBox(
                  height: 30,
                  width: 30,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(_formatRupiah(_omzetHariIni),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // WIDGET PEMBANTU: KARTU MENU NAVIGASI DENGAN PROTEKSI TEXT OVERFLOW
  Widget _menuCard(BuildContext context, String title, IconData icon,
      Color color, VoidCallback onTap) {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFF1E293B),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
