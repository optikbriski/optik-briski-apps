import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'sales_page.dart';
import 'inventory.dart';
import 'product_master.dart';
import 'buku_besar.dart';
import '../../shared/admin_approval_page.dart';
import 'barcode_scanner.dart' hide RiwayatTransaksiPage;
import 'riwayat_transaksi_page.dart';
import 'request_order_page.dart';
import 'invoice_config_page.dart';
import 'attendance_monitor_page.dart';
import 'attendance_qr_page.dart';
import 'jadwal_kerja_page.dart';
import 'monthly_export_page.dart';
import 'garansi_page.dart';
import '../../shared/invoice/invoice_hub_page.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchTodayStats();
    _fetchFotoProfil();
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
              LayoutBuilder(
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
                  // 1. MENU PERSETUJUAN KARYAWAN (HANYA PUSAT)
                  if (widget.profile['toko_id'] == 'PUSAT')
                    _menuCard(
                        context,
                        "dash_menu_management".tr(),
                        Icons.verified_user_rounded,
                        Colors.blueAccent,
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (c) => AdminApprovalPage(
                                      roleAdmin:
                                          widget.profile['role']?.toString() ??
                                              '',
                                      cabangAdmin: widget.profile['toko_id']
                                              ?.toString() ??
                                          '',
                                    )))),

                  // 2. MENU ABSENSI — monitor shift/log (clock-in di APK Karyawan)
                  _menuCard(
                      context,
                      "hr_tab_absen".tr(),
                      Icons.face_retouching_natural_rounded,
                      Colors.purpleAccent,
                      () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AttendanceMonitorPage(
                                  profile: widget.profile),
                            ),
                          )),

                  // 2a. QR ABSENSI BERPUTAR — layar toko untuk clock-in karyawan
                  _menuCard(
                    context,
                    'dash_menu_attendance_qr'.tr(),
                    Icons.qr_code_2_rounded,
                    Colors.deepPurpleAccent,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AttendanceQrPage(profile: widget.profile),
                      ),
                    ),
                  ),

                  // 2b. JADWAL KERJA — pusat pilih cabang; toko atur cabangnya
                  if (widget.profile['toko_id'] == 'PUSAT' ||
                      widget.profile['toko_id'] == 'CABANG-PUSAT' ||
                      widget.profile['role'] == 'owner' ||
                      widget.profile['role'] == 'admin_pusat' ||
                      widget.profile['role'] == 'admin_toko')
                    _menuCard(
                      context,
                      'Jadwal Kerja',
                      Icons.calendar_month_rounded,
                      Colors.indigoAccent,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              JadwalKerjaPage(profile: widget.profile),
                        ),
                      ),
                    ),

// --- 3. MENU KASIR POS (Kembalikan ke SalesPage) ---
                  _menuCard(
                      context,
                      "POS Cashier", // Sesuai label di app Bos
                      Icons.point_of_sale_rounded,
                      Colors.greenAccent,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (c) =>
                                  SalesPage(profile: widget.profile)))),

                  // 4. MENU REQUEST ORDER (Logistik) ---
                  _menuCard(
                    context,
                    "Request Order", // Ganti ke "dash_request_order".tr() kalau sudah buat translate-nya
                    Icons.local_shipping_rounded,
                    Colors.orangeAccent,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) =>
                            RequestOrderPage(profile: widget.profile),
                      ),
                    ),
                  ),

// --- 5. MENU RIWAYAT TRANSAKSI & DP ---
                  _menuCard(
                      context,
                      "History & Down Payment", // Sesuai label di app Bos
                      Icons.history_edu,
                      Colors.orangeAccent,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (c) => RiwayatTransaksiPage(
                                  profile: widget
                                      .profile)))), // ✅ Ini baru arahkan ke RiwayatTransaksiPage!

                  // 6. MENU INVENTARIS & LOGISTIK (SEKARANG SUDAH AKTIF UNLOCKED)
                  _menuCard(
                    context,
                    "dash_menu_logistik".tr(),
                    Icons.local_shipping_rounded,
                    Colors.amber,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) =>
                              InventoryOverview(profile: widget.profile),
                        ),
                      );
                    },
                  ),

// 7. MENU MASTER DATA PRODUK (REVISI: UNLOCKED FOR OWNER & ALL BRANCHES)
                  if (widget.profile['role'] == 'owner' ||
                      widget.profile['role'] == 'admin_pusat' ||
                      widget.profile['role'] == 'admin_toko' ||
                      widget.profile['toko_id'] == 'PUSAT')
                    _menuCard(
                      context,
                      "dash_menu_master".tr(),
                      Icons.dataset_rounded,
                      Colors.indigoAccent,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) =>
                                ProductMasterPage(profile: widget.profile),
                          ),
                        );
                      },
                    ),

                  // 8. BUKU BESAR & KEUANGAN
                  _menuCard(
                      context,
                      "dash_menu_keuangan".tr(),
                      Icons.account_balance_wallet_rounded,
                      Colors.tealAccent,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (c) =>
                                  BukuBesarPage(profile: widget.profile)))),

                  // 🎯 MENU 9: ADJUST DESAIN INVOICE GLOBAL (HANYA OWNER & ADMIN PUSAT)
                  if (widget.profile['role'] == 'owner' ||
                      widget.profile['role'] == 'admin_pusat')
                    _menuCard(
                      context,
                      "Adjust Invoice", // <-- Nama menu di dashboard depan
                      Icons
                          .note_alt_rounded, // ✅ FIX: Karakter ilegal sudah dibuang bersih!
                      Colors
                          .pinkAccent, // Warna aksen pink biar kontras dan gampang dicari
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) =>
                                InvoiceConfigPage(profile: widget.profile),
                          ),
                        );
                      },
                    ),

                  // 10. LAPORAN EKSPOR OPERASIONAL (PDF)
                  _menuCard(
                    context,
                    'dash_menu_export'.tr(),
                    Icons.picture_as_pdf_rounded,
                    Colors.cyanAccent,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            MonthlyExportPage(profile: widget.profile),
                      ),
                    ),
                  ),

                  // 11. GARANSI FRAME + LENSA
                  _menuCard(
                    context,
                    'dash_menu_garansi'.tr(),
                    Icons.verified_rounded,
                    Colors.lightGreenAccent,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GaransiPage(profile: widget.profile),
                      ),
                    ),
                  ),

                  // 12. SCAN QR INVOICE HUB
                  _menuCard(
                    context,
                    'dash_menu_invoice_hub'.tr(),
                    Icons.qr_code_2_rounded,
                    Colors.deepOrangeAccent,
                    () => InvoiceHubPage.openScanner(
                      context,
                      profile: widget.profile,
                    ),
                  ),
                ],
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
