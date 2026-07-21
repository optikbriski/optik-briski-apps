import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../apps/admin/attendance_monitor_page.dart';
import 'ktp/ktp_approval_review_page.dart';
import 'liveness_camera_page.dart';
import 'responsive.dart';

class AdminApprovalPage extends StatefulWidget {
  final String roleAdmin;
  final String cabangAdmin;

  /// Used for attendance monitor (toko/role scope).
  final Map<String, dynamic>? profile;

  const AdminApprovalPage({
    super.key,
    this.roleAdmin = '',
    this.cabangAdmin = '',
    this.profile,
  });

  @override
  State<AdminApprovalPage> createState() => _AdminApprovalPageState();
}

class _AdminApprovalPageState extends State<AdminApprovalPage> {
  final supabase = Supabase.instance.client;
  List<dynamic> _listKaryawanAktif = [];
  List<dynamic> _listKaryawanPending = [];
  bool _isLoading = true;

  static const _pendingStatuses = [
    'Pending',
    'Menunggu OTP',
    'Menunggu Persetujuan',
  ];

  // Cek apakah admin pusat atau owner agar bisa memantau seluruh cabang
  bool get _isPusat {
    final cabang = widget.cabangAdmin.toUpperCase();
    return cabang == 'PUSAT' ||
        cabang == 'CABANG-PUSAT' ||
        widget.roleAdmin == 'owner' ||
        widget.roleAdmin == 'admin_pusat';
  }

  @override
  void initState() {
    super.initState();
    _tarikDataKaryawan();
  }

  // 1. FUNGSI TARIK DATA (OPTIMAL & HEMAT BUNDLE DATA)
  Future<void> _tarikDataKaryawan() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // ✅ FIX 1: Mengubah .in_ menjadi .inFilter agar kompatibel dengan versi SDK Supabase terbaru lo
      var query = supabase
          .from('karyawan')
          .select()
          .inFilter('status_approval', ['Aktif', ..._pendingStatuses]);

      if (!_isPusat && widget.cabangAdmin.isNotEmpty) {
        query = query.eq('toko_id', widget.cabangAdmin);
      }

      final data = await query.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _listKaryawanAktif =
              data.where((e) => e['status_approval'] == 'Aktif').toList();

          _listKaryawanPending = data
              .where((e) =>
                  _pendingStatuses.contains(e['status_approval']?.toString()))
              .toList();

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${'appr_err_umum'.tr()}$e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // WIDGET CARD KARYAWAN AKTIF
  Widget _buildCardKaryawanAktif(Map<String, dynamic> k) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(
          backgroundColor: Colors.greenAccent,
          child: Icon(Icons.person, color: Colors.black),
        ),
        title: Text(
          k['nama'] ?? '-',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text("${k['jabatan'] ?? '-'} - ${k['cabang'] ?? '-'}"),
        trailing: IconButton(
          icon:
              const Icon(Icons.info_outline_rounded, color: Colors.blueAccent),
          onPressed: () => _tampilkanDetailKaryawan(k),
        ),
      ),
    );
  }

  // UI PREMIUM & RESPONSIVE POP-UP (tanpa Flexible di scroll — hindari crash)
  void _tampilkanDetailKaryawan(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.9;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: R.dialogMaxWidth(ctx, 950),
              maxHeight: maxH,
            ),
            child: Material(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.badge_rounded,
                            color: Colors.blueAccent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "appr_detail_title".tr(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.redAccent),
                          onPressed: () => Navigator.pop(ctx),
                        )
                      ],
                    ),
                    const SizedBox(height: 25),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 750;
                        final detailBlocks = _buildDetailDataBlocks(data, isMobile);

                        if (isMobile) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildVirtualIDCard(data),
                              const SizedBox(height: 30),
                              detailBlocks,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildVirtualIDCard(data),
                            const SizedBox(width: 40),
                            Expanded(child: detailBlocks),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailDataBlocks(Map<String, dynamic> data, bool isMobile) {
    final pribadi = _buildDataSection("hr_data_pribadi".tr(), [
      _buildInfoRow("profil_label_nik".tr(), data['nik'] ?? '-'),
      _buildInfoRow("appr_email".tr(), data['email'] ?? '-'),
      _buildInfoRow("appr_nomor_wa".tr(), data['wa'] ?? '-',
          valColor: Colors.greenAccent),
      _buildInfoRow("appr_gender".tr(), data['gender'] ?? '-'),
      _buildInfoRow(
          "profil_label_umur".tr(),
          "appr_tahun".tr(args: [(data['umur'] ?? '-').toString()])),
      _buildInfoRow("appr_alamat".tr(), data['alamat_lengkap'] ?? '-'),
    ]);
    final kepegawaian = _buildDataSection("hr_kepegawaian".tr(), [
      _buildInfoRow(
          "appr_tgl_mulai".tr(),
          data['tanggal_mulai'] != null
              ? data['tanggal_mulai'].toString().split('T')[0]
              : '-'),
      if (_isPusat)
        _buildInfoRow("appr_pin_absensi".tr(),
            data['pin_absensi']?.toString() ?? '-',
            valColor: Colors.redAccent),
      _buildInfoRow("appr_status".tr(), data['status_approval'] ?? '-',
          valColor: Colors.greenAccent),
    ]);
    final payroll = _buildDataSection("appr_data_payroll".tr(), [
      _buildInfoRow("hr_reg_bank".tr(), data['nama_bank'] ?? 'BCA'),
      _buildInfoRow("appr_no_rekening".tr(), data['no_rekening'] ?? '-',
          valColor: Colors.blueAccent),
    ]);
    final darurat = _buildDataSection("hr_kontak_darurat".tr(), [
      _buildInfoRow("appr_nama_kontak".tr(), data['darurat_nama'] ?? '-'),
      if (_isPusat)
        _buildInfoRow("hr_reg_wa_darurat".tr(), data['darurat_wa'] ?? '-',
            valColor: Colors.orangeAccent),
    ]);

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pribadi,
          const SizedBox(height: 16),
          kepegawaian,
          const SizedBox(height: 16),
          payroll,
          const SizedBox(height: 16),
          darurat,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pribadi),
            const SizedBox(width: 20),
            Expanded(child: kepegawaian),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: payroll),
            const SizedBox(width: 20),
            Expanded(child: darurat),
          ],
        ),
      ],
    );
  }

  // WIDGET HELPER: ID CARD VIRTUAL
  Widget _buildVirtualIDCard(Map<String, dynamic> data) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A32),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            // ✅ FIX 2: Mengubah Maincenter menjadi MainAxisAlignment.center yang valid
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.remove_red_eye, color: Colors.amber, size: 24),
              const SizedBox(width: 8),
              Text(
                "judul_aplikasi".tr(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            "appr_id_card_pos".tr(),
            style: const TextStyle(
                color: Colors.white54, fontSize: 8, letterSpacing: 2),
          ),
          const SizedBox(height: 15),
          const Divider(color: Colors.white12, thickness: 1),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.amber, width: 2),
            ),
            child: const CircleAvatar(
              radius: 45,
              backgroundColor: Colors.white10,
              child: Icon(Icons.person, size: 50, color: Colors.white54),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            data['nama'] ?? '-',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            (data['jabatan'] ?? 'default_karyawan'.tr())
                .toString()
                .toUpperCase(),
            style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "${'hr_cabang'.tr()} ${(data['cabang']?.toString().toUpperCase() ?? 'appr_pusat'.tr())}",
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: SizedBox(
              height: 100,
              width: 100,
              child: BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: () {
                  final nik = data['nik']?.toString().trim() ?? '';
                  return nik.isEmpty ? '0000000000000000' : nik;
                }(),
                color: Colors.black,
                drawText: false,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            "appr_scan_barcode".tr(),
            style: const TextStyle(
                color: Colors.amber,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
              color: Colors.blueAccent,
              fontWeight: FontWeight.bold,
              fontSize: 14),
        ),
        const SizedBox(height: 8),
        const Divider(color: Colors.white12, thickness: 1),
        const SizedBox(height: 10),
        ...rows,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value,
      {Color valColor = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: valColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Satu pintu: buka HALAMAN DETAIL → pilih data valid → baru Tolak/Approve.
  Future<void> _bukaReviewVerifikasi(Map karyawan) async {
    try {
      final data = <String, dynamic>{
        for (final e in karyawan.entries) e.key.toString(): e.value,
      };
      final result = await Navigator.push<KtpReviewResult>(
        context,
        MaterialPageRoute(
          builder: (_) => KtpApprovalReviewPage(karyawan: data),
        ),
      );
      if (!mounted || result == null || result == KtpReviewResult.cancelled) {
        return;
      }
      final nama = data['nama']?.toString() ?? '-';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          result == KtpReviewResult.approved
              ? "appr_sukses_setuju".tr(args: [nama])
              : "appr_sukses_tolak".tr(args: [nama]),
        ),
        backgroundColor:
            result == KtpReviewResult.approved ? Colors.green : Colors.redAccent,
      ));
      await _tarikDataKaryawan();
    } catch (e, st) {
      debugPrint('Review verifikasi error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal buka detail verifikasi: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  // 5. WIDGET CARD KARYAWAN PENDING — tanpa Tolak/Approve di luar
  Widget _buildCardKaryawanPending(Map<String, dynamic> k) {
    final String nama = k['nama']?.toString() ?? '-';
    final hasKtp = (k['ktp_photo_url']?.toString() ?? '').isNotEmpty;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.amber.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _bukaReviewVerifikasi(Map<String, dynamic>.from(k)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.amber,
                    child: Icon(Icons.person_outline_rounded,
                        color: Colors.black),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nama,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 16)),
                        const SizedBox(height: 4),
                        Text("${k['jabatan'] ?? '-'} - ${k['cabang'] ?? '-'}",
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        Text(
                          hasKtp
                              ? 'Ada foto KTP + jejak OCR'
                              : 'Belum ada foto KTP',
                          style: TextStyle(
                            color:
                                hasKtp ? Colors.greenAccent : Colors.orange,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.blueAccent),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () =>
                      _bukaReviewVerifikasi(Map<String, dynamic>.from(k)),
                  icon: const Icon(Icons.fact_check_rounded, size: 18),
                  label: const Text(
                    'Buka detail & putuskan',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tolak / Approve hanya setelah review data di dalam detail.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 60, color: Colors.white24),
          ),
          const SizedBox(height: 20),
          Text(
            "appr_data_kosong".tr(),
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(message,
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "appr_title".tr(),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white),
              ),
              Text(
                _isPusat ? "appr_semua_cabang".tr() : widget.cabangAdmin,
                style: const TextStyle(fontSize: 11, color: Colors.blueAccent),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                final profile = widget.profile ??
                    <String, dynamic>{
                      'role': widget.roleAdmin,
                      'toko_id': widget.cabangAdmin,
                    };
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AttendanceMonitorPage(profile: profile),
                  ),
                );
              },
              icon: const Icon(Icons.fact_check_rounded, size: 18),
              label: Text('appr_monitor_absensi'.tr()),
              style: TextButton.styleFrom(
                foregroundColor: Colors.purpleAccent,
              ),
            ),
            IconButton(
              tooltip: "appr_tooltip_refresh".tr(),
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _tarikDataKaryawan,
            )
          ],
          bottom: TabBar(
            indicatorColor: Colors.blueAccent,
            indicatorWeight: 3,
            labelColor: Colors.blueAccent,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_alt_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text("appr_tab_aktif".tr()),
                    ],
                  ),
                ),
              ),
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.how_to_reg_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text("appr_tab_verifikasi".tr()),
                      if (_listKaryawanPending.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.redAccent, shape: BoxShape.circle),
                          child: Text(
                            _listKaryawanPending.length.toString(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        )
                      ]
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.blueAccent))
            : TabBarView(
                children: [
                  _listKaryawanAktif.isEmpty
                      ? _buildEmptyState(
                          "appr_aktif_kosong".tr(), Icons.group_off_rounded)
                      : RefreshIndicator(
                          onRefresh: _tarikDataKaryawan,
                          color: Colors.blueAccent,
                          backgroundColor: const Color(0xFF1E293B),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _listKaryawanAktif.length,
                            itemBuilder: (context, index) =>
                                _buildCardKaryawanAktif(
                                    _listKaryawanAktif[index]),
                          ),
                        ),
                  _listKaryawanPending.isEmpty
                      ? _buildEmptyState(
                          "appr_verifikasi_kosong".tr(), Icons.verified_rounded)
                      : RefreshIndicator(
                          onRefresh: _tarikDataKaryawan,
                          color: Colors.blueAccent,
                          backgroundColor: const Color(0xFF1E293B),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _listKaryawanPending.length,
                            itemBuilder: (context, index) =>
                                _buildCardKaryawanPending(
                                    _listKaryawanPending[index]),
                          ),
                        ),
                ],
              ),
      ),
    );
  }
}
