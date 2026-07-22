// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'detail_pribadi_page.dart';
import 'pengaturan_akun_karyawan.dart';
import 'bantuan_page.dart';
import 'pengaduan_page.dart';
import 'pengingat_page.dart';
import 'package:image_picker/image_picker.dart';
import 'software_update_page.dart';
import 'absensi_page.dart';
import 'pengajuan_jadwal_page.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../shared/attendance/attendance_service.dart';
import '../../shared/attendance/geofence_exit_monitor.dart';
import '../../shared/karyawan/karyawan_home_service.dart';
import '../../shared/app_update_service.dart';
import '../../shared/responsive.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/qr/qr_route.dart';
import '../../shared/qr/universal_qr_host.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/qr/universal_qr_scan_page.dart';
import '../../shared/scanner_penerimaan_page.dart';

// VARIABEL GLOBAL UNTUK MENYIMPAN FOTO
Uint8List? fotoKaryawanGlobal;

class KaryawanPage extends StatefulWidget {
  const KaryawanPage({super.key});

  @override
  State<KaryawanPage> createState() => KaryawanPageState();
}

String? _fotoProfileUrl;

class KaryawanPageState extends State<KaryawanPage>
    with WidgetsBindingObserver {
  final _homeService = KaryawanHomeService();

  // 1. WADAH DATA DINAMIS
  late String _namaKaryawan;
  String _jabatanKaryawan = "...";
  String _cabangKaryawan = "...";
  String? _karyawanId;
  String? _tokoId;
  bool _isLoading = true;

  // 2. JADWAL MINGGUAN (dari Supabase)
  List<Map<String, String>> _jadwalMingguIni = [];

  // Wadah List SOP
  List<Map<String, dynamic>> _daftarSOPTugas = [];

  double _securityScore = 0;

  // MESIN NAVIGASI BAWAH
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _namaKaryawan = 'memuat'.tr();
    _bindQrHost();
    _tarikDataProfil();
    _cekUpdateApkSilent();
    _cekHasilInstallSetelahResume();
  }

  void _bindQrHost() {
    UniversalQrHost.bind(
      callerRole: UniversalQrCallerRole.karyawan,
      cabangKaryawan: _cabangKaryawan,
      karyawanId: _karyawanId,
      karyawanNama: _namaKaryawan,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UniversalQrHost.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cekHasilInstallSetelahResume();
      _syncGeofenceMonitorIfOpenShift();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Auto-unduh di background saat app di-minimize (install tetap konfirmasi).
      _mulaiAutoDownloadUpdate(silent: true);
    }
  }

  /// Resume / cold start: pantau geofence lagi jika shift OPEN masih ada.
  /// [askPermissions]: true hanya di cold start profil (hindari dialog tiap resume).
  Future<void> _syncGeofenceMonitorIfOpenShift({
    bool askPermissions = false,
  }) async {
    if (kIsWeb) return;
    final kid = _karyawanId;
    final tid = _tokoId;
    if (kid == null || kid.isEmpty || tid == null || tid.isEmpty) return;
    try {
      final shift = await AttendanceService().fetchOpenShift(kid);
      await GeofenceExitMonitor.instance.syncFromOpenShift(
        karyawanId: kid,
        tokoId: tid,
        hasOpenShift: shift != null,
        permissionContext:
            askPermissions && mounted ? context : null,
      );
    } catch (e) {
      debugPrint('sync geofence monitor: $e');
    }
  }

  /// Setelah user selesai/cancel installer, pastikan app lama tetap sehat
  /// dan tampilkan sukses jika versi sudah naik.
  Future<void> _cekHasilInstallSetelahResume() async {
    try {
      final outcome = await _updateService.checkPendingInstallResult();
      if (!mounted) return;
      if (outcome.updated) {
        setState(() => _adaUpdateBaru = false);
        _showPremiumSnackbar(
          'Update berhasil',
          'Aplikasi sekarang versi ${outcome.localVersion}. Siap dipakai.',
          Colors.green,
        );
      }
    } catch (e) {
      debugPrint('cek hasil install: $e');
    }
  }

  bool _autoDownloadRunning = false;
  bool _installConfirmShown = false;
  bool _storageDialogShown = false;

  Future<void> _mulaiAutoDownloadUpdate({bool silent = false}) async {
    if (kIsWeb || _autoDownloadRunning) return;
    final autoOn = await _updateService.isAutoUpdateEnabled();
    if (!autoOn) return;

    _autoDownloadRunning = true;
    try {
      final result = await _updateService.downloadInBackground(
        appFlavor: 'karyawan',
      );
      if (!mounted) return;

      switch (result.status) {
        case BackgroundDownloadStatus.readyToInstall:
          setState(() => _adaUpdateBaru = true);
          await _tampilkanKonfirmasiInstall(result);
        case BackgroundDownloadStatus.insufficientStorage:
          setState(() => _adaUpdateBaru = true);
          await _tampilkanDialogStorageKurang(result);
        case BackgroundDownloadStatus.downloading:
          if (!silent) {
            _showPremiumSnackbar(
              'Mengunduh update',
              'Update diunduh di belakang. App tetap bisa dipakai.',
              Colors.blueAccent,
            );
          }
        case BackgroundDownloadStatus.failed:
          if (!silent && (result.message ?? '').isNotEmpty) {
            _showPremiumSnackbar(
              'Unduh update gagal',
              result.message!,
              Colors.orange,
            );
          }
        case BackgroundDownloadStatus.skipped:
          break;
      }
    } catch (e) {
      debugPrint('auto download update: $e');
    } finally {
      _autoDownloadRunning = false;
    }
  }

  Future<void> _tampilkanDialogStorageKurang(
      BackgroundDownloadResult result) async {
    if (_storageDialogShown || !mounted) return;
    _storageDialogShown = true;
    final st = result.storage;
    final butuh = st?.requiredLabel ?? 'beberapa puluh MB';
    final sisa = st?.freeLabel ?? '-';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Penyimpanan kurang',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Storage internal HP tidak cukup untuk mengunduh update.\n\n'
          'Dibutuhkan sekitar $butuh (tersedia $sisa).\n\n'
          'Kosongkan foto, cache, atau file lain di penyimpanan internal, '
          'lalu buka lagi aplikasi — unduhan akan dilanjutkan otomatis.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti',
                style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _storageDialogShown = false;
              _mulaiAutoDownloadUpdate();
            },
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
    _storageDialogShown = false;
  }

  Future<void> _tampilkanKonfirmasiInstall(
      BackgroundDownloadResult result) async {
    if (_installConfirmShown || !mounted) return;
    final path = result.apkPath;
    final info = result.info;
    if (path == null || info == null) return;

    _installConfirmShown = true;
    final hardForce = info.forceUpdate;

    await showDialog<void>(
      context: context,
      barrierDismissible: !hardForce,
      builder: (ctx) => PopScope(
        canPop: !hardForce,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            hardForce ? 'Update wajib siap dipasang' : 'Update siap dipasang',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Versi ${info.serverVersion} sudah diunduh.\n'
            'Pasang sekarang? App lama tetap aman sampai instalasi selesai.\n\n'
            '${info.notes ?? ''}',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            if (!hardForce)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Nanti',
                    style: TextStyle(color: Colors.white54)),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _updateService.confirmAndOpenInstaller(
                    apkPath: path,
                    expectedVersion: info.serverVersion,
                  );
                  if (!mounted) return;
                  _showPremiumSnackbar(
                    'Installer dibuka',
                    'Konfirmasi di layar sistem untuk memasang update.',
                    Colors.green,
                  );
                } catch (e) {
                  if (!mounted) return;
                  final pesan = e.toString().replaceAll('Exception: ', '');
                  if (pesan.contains('REQUEST_INSTALL_PACKAGES')) {
                    _showPremiumSnackbar(
                      'Izin instalasi diperlukan',
                      'Aktifkan “Instal aplikasi tidak dikenal” untuk Optik B. Riski di Pengaturan.',
                      Colors.orange,
                    );
                  } else {
                    _showPremiumSnackbar('Gagal buka installer', pesan, Colors.red);
                  }
                }
              },
              child: const Text('Pasang sekarang'),
            ),
          ],
        ),
      ),
    );
    _installConfirmShown = false;
  }

  double _fabBottomPad(BuildContext context) =>
      100 + MediaQuery.paddingOf(context).bottom;

  // MESIN POP-UP PILIHAN BAHASA
  void _tampilkanDialogBahasa(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return R.constrainedDialog(
          context: context,
          child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "pilihan_bahasa_judul".tr(),
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOpsiBahasaItem(context, "lang_id".tr(), const Locale('id')),
              _buildOpsiBahasaItem(context, "lang_en".tr(), const Locale('en')),
              _buildOpsiBahasaItem(context, "lang_ms".tr(), const Locale('ms')),
              _buildOpsiBahasaItem(context, "lang_zh".tr(), const Locale('zh')),
              _buildOpsiBahasaItem(context, "lang_ja".tr(), const Locale('ja')),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _buildOpsiBahasaItem(
      BuildContext context, String label, Locale locale) {
    bool isSelected = context.locale == locale;
    return ListTile(
      title: Text(label,
          style: TextStyle(
              color: isSelected ? Colors.blueAccent.shade100 : Colors.white70,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded, color: Colors.blueAccent)
          : null,
      onTap: () {
        context.setLocale(locale);
        Navigator.pop(context);
        _showPremiumSnackbar("notif_sukses_judul".tr(),
            "notif_bahasa_sukses".tr(), Colors.green);
      },
    );
  }

  // MESIN UPDATE APK (in-app, tanpa kirim link)
  bool _adaUpdateBaru = false;
  final _updateService = AppUpdateService();
  bool _updateDialogShown = false;

  Future<void> _cekUpdateApkSilent() async {
    try {
      final info =
          await _updateService.checkForUpdate(appFlavor: 'karyawan');
      if (!info.hasUpdate || !mounted) return;

      setState(() => _adaUpdateBaru = true);

      // Prefer auto-unduh; install tetap minta konfirmasi karyawan.
      final autoOn = await _updateService.isAutoUpdateEnabled();
      if (autoOn && info.urlReachable) {
        await _mulaiAutoDownloadUpdate();
        return;
      }

      if (_updateDialogShown) return;
      _updateDialogShown = true;

      final hardForce = info.forceUpdate && info.urlReachable;

      await showDialog<void>(
        context: context,
        barrierDismissible: !hardForce,
        builder: (ctx) => PopScope(
          canPop: !hardForce,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              hardForce ? 'Update wajib' : 'Update tersedia',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Versi baru ${info.serverVersion} siap '
              '(saat ini ${info.localVersion}).\n'
              'Unduh bisa otomatis; pemasangan tetap butuh konfirmasi Anda.\n\n'
              '${!info.urlReachable ? '⚠️ Link unduhan belum siap. Anda tetap bisa pakai app.\n\n' : ''}'
              '${info.notes ?? ''}',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              if (!hardForce)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Nanti',
                      style: TextStyle(color: Colors.white54)),
                ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SoftwareUpdatePage(
                        autoStartDownload: info.urlReachable,
                      ),
                    ),
                  );
                },
                child: Text(
                    info.urlReachable ? 'Unduh update' : 'Cek update'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      // Jangan ganggu pemakaian app jika cek update gagal.
      debugPrint("Gagal cek update: $e");
    }
  }

  // MESIN PENARIK DATA
  Future<void> _tarikDataProfil() async {
    try {
      final snap = await _homeService.loadHome();
      if (snap == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        _karyawanId = snap.karyawan['id']?.toString();
        _tokoId = snap.karyawan['toko_id']?.toString();
        _namaKaryawan =
            snap.karyawan['nama']?.toString() ?? 'default_karyawan'.tr();
        _jabatanKaryawan =
            snap.karyawan['jabatan']?.toString() ?? 'default_staff'.tr();
        _cabangKaryawan = snap.karyawan['cabang']?.toString() ??
            snap.karyawan['toko_id']?.toString() ??
            '-';
        _fotoProfileUrl = snap.karyawan['foto_profile']?.toString();
        _jadwalMingguIni = snap.jadwalMinggu;
        _daftarSOPTugas = snap.sopTasks;
        totalPoinBulanIni = snap.totalPoinBulan;
        currentStreakHari = snap.streakHari;
        isStreakBonusActive = snap.streakHari >= 3;
        _sudahKlaimPoinHariIni = snap.sudahKlaimHariIni;
        _riwayat30HariCache = snap.riwayat30Hari;
        _securityScore = snap.securityScore;
        _isLoading = false;
      });
      _bindQrHost();

      if (_karyawanId != null) {
        await _homeService.ensureTodayReminders(
          karyawanId: _karyawanId!,
          jadwalMinggu: _jadwalMingguIni,
          sopTasks: _daftarSOPTugas,
        );
      }
      unawaited(_syncGeofenceMonitorIfOpenShift(askPermissions: true));
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Gagal menarik data profil: $e");
    }
  }

  int totalPoinBulanIni = 0;
  int currentStreakHari = 0;
  bool isStreakBonusActive = false;
  bool _sudahKlaimPoinHariIni = false;
  List<int> _riwayat30HariCache = List<int>.filled(30, 0);

  final ImagePicker picker = ImagePicker();

  Future<void> _persistSopDone(
    int index, {
    String? buktiText,
    Uint8List? buktiBytes,
  }) async {
    if (_karyawanId == null) {
      _showPremiumSnackbar(
          "sop_error_judul".tr(), 'Data karyawan belum siap.', Colors.red);
      return;
    }
    final task = _daftarSOPTugas[index];
    if ((task['id']?.toString() ?? '').isEmpty) {
      _showPremiumSnackbar(
        "sop_error_judul".tr(),
        'Template SOP belum tersedia di database. Jalankan migration dulu.',
        Colors.orange,
      );
      return;
    }
    try {
      await _homeService.completeSopTask(
        karyawanId: _karyawanId!,
        task: task,
        buktiText: buktiText,
        buktiBytes: buktiBytes,
      );
      setState(() => _daftarSOPTugas[index]['selesai'] = true);
      _showPremiumSnackbar(
          "sop_bukti_sah".tr(), "sop foto sukses".tr(), Colors.green);
    } catch (e) {
      _showPremiumSnackbar("sop_error_judul".tr(), '$e', Colors.redAccent);
    }
  }

  void _toggleTugas(int index) async {
    if (_daftarSOPTugas[index]['selesai']) {
      _showPremiumSnackbar("sop_terkunci_judul".tr(), "sop_terkunci_desc".tr(),
          Colors.redAccent);
      return;
    }

    String jenisBukti = _daftarSOPTugas[index]['jenis_bukti'] ?? 'foto';

    if (jenisBukti == 'foto') {
      final XFile? foto = await pickImageSafe(
        picker: picker,
        context: context,
        imageQuality: 50,
      );

      if (foto != null) {
        final bytes = await foto.readAsBytes();
        await _persistSopDone(index, buktiBytes: bytes);
      } else {
        _showPremiumSnackbar(
            "sop_batal".tr(), "sop_foto_batal".tr(), Colors.orange);
      }
    } else if (jenisBukti == 'scan') {
      // Pakai scanner universal yang sama (bukan menu scanner terpisah).
      final routed = await UniversalQrScanPage.scanRouted(
        context,
        allowedTypes: {QrPayloadType.receiveStock},
      );
      if (routed == null || !mounted) {
        _showPremiumSnackbar(
            "sop_batal".tr(), "sop_scan_batal_msg".tr(), Colors.orange);
        return;
      }
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScannerPenerimaanPage(
            cabangKaryawan: _cabangKaryawan,
            karyawanId: _karyawanId,
            karyawanNama: _namaKaryawan,
            initialQr: routed.raw,
          ),
        ),
      );

      if (result != null) {
        await _persistSopDone(index, buktiText: result.toString());
      } else {
        _showPremiumSnackbar(
            "sop_batal".tr(), "sop_scan_batal_msg".tr(), Colors.orange);
      }
    } else {
      _tampilkanDialogInputManual(index);
    }
  }

  void _tampilkanDialogInputManual(int index) {
    TextEditingController inputController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return R.constrainedDialog(
          context: context,
          child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("sop_input_aktual".tr(), textAlign: TextAlign.center),
          content: TextField(
            controller: inputController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                hintText: "sop_hint_aktual".tr(),
                border: const OutlineInputBorder()),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("sop_batal".tr(),
                    style: const TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.bold))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () async {
                if (inputController.text.isNotEmpty) {
                  Navigator.pop(context);
                  await _persistSopDone(index,
                      buktiText: inputController.text.trim());
                  _showPremiumSnackbar("sop_terkonfirmasi".tr(),
                      "sop_aktual_tersimpan".tr(), Colors.green);
                } else {
                  _showPremiumSnackbar("sop_error_judul".tr(),
                      "sop_error_kosong".tr(), Colors.red);
                }
              },
              child: Text("sop_btn_konfirmasi".tr(),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        );
      },
    );
  }

  void _tampilkanDetailJadwal(Map<String, String> jadwal) {
    final catatan = jadwal['catatan']?.trim();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${jadwal['hari']} • ${jadwal['tanggal']}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Shift: ${jadwal['shift']}',
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
            if (catatan != null && catatan.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Catatan: $catatan',
                  style: const TextStyle(color: Colors.white54)),
            ],
            const SizedBox(height: 16),
            const Text(
              'Butuh ijin / cuti / tukar jadwal? Ajukan lewat tombol di bawah. '
              'Admin cabang yang menyetujui.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PengajuanJadwalPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: const Text('Ajukan ijin / tukar jadwal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // POP-UP RIWAYAT POIN 30 HARI
  void _tampilkanRiwayatPoin() {
    final riwayat30Hari = _riwayat30HariCache.isEmpty
        ? List<int>.filled(30, 0)
        : List<int>.from(_riwayat30HariCache);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          padding: const EdgeInsets.all(25),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 25),
              Text("poin_riwayat_judul".tr(),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B))),
              const SizedBox(height: 5),
              Text("poin_riwayat_desc".tr(),
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 25),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildLegendItem(Colors.green, "poin sempurna".tr()),
                  _buildLegendItem(Colors.amber, "poin_parsial".tr()),
                  _buildLegendItem(Colors.redAccent, "poin_bolong".tr()),
                ],
              ),
              const SizedBox(height: 25),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12),
                  itemCount: 30,
                  itemBuilder: (context, index) {
                    int status = riwayat30Hari[index];
                    Color warnaCard;
                    IconData iconCard;

                    if (status == 2) {
                      warnaCard = Colors.green;
                      iconCard = Icons.check_circle_rounded;
                    } else if (status == 1) {
                      warnaCard = Colors.amber;
                      iconCard = Icons.warning_rounded;
                    } else if (status == 0) {
                      warnaCard = Colors.redAccent;
                      iconCard = Icons.cancel_rounded;
                    } else {
                      warnaCard = Colors.grey.shade200;
                      iconCard = Icons.hourglass_empty;
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: status == 3
                            ? Colors.grey.shade100
                            : warnaCard.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: status == 3 ? Colors.transparent : warnaCard,
                            width: 2),
                      ),
                      child: Center(
                        child: status == 3
                            ? Text("${index + 1}",
                                style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))
                            : Icon(iconCard, color: warnaCard, size: 20),
                      ),
                    );
                  },
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B))),
        ),
      ],
    );
  }

  void _showPremiumSnackbar(String title, String message, Color color) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.fixed,
        backgroundColor: color,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 4),
            ],
            Text(message,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildDashboardTab(),
      _buildTodoTab(),
      _buildProfilTab(),
    ];

    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            gradient: _currentIndex == 2
                ? const LinearGradient(
                    colors: [Color(0xFF0A1628), Color(0xFF132F4C)],
                  )
                : null,
            color: _currentIndex == 2 ? null : Colors.white,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A1628).withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: AppBar(
            title: Column(
              children: [
                Text(
                  _currentIndex == 0
                      ? "halaman utama".tr()
                      : _currentIndex == 1
                          ? "daftar_tugas_sop".tr()
                          : "pengaturan_akun_judul".tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 0.3,
                    color: _currentIndex == 2
                        ? Colors.white
                        : const Color(0xFF0A1628),
                  ),
                ),
                Text(
                  'OPTIK B. RISKI',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w600,
                    color: _currentIndex == 2
                        ? const Color(0xFFD4AF37)
                        : const Color(0xFFC4A35A),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.transparent,
            foregroundColor:
                _currentIndex == 2 ? Colors.white : const Color(0xFF0A1628),
            elevation: 0,
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E3C72)))
          : pages[_currentIndex],
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF1E3C72), Color(0xFF0A1628)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E3C72).withOpacity(0.4),
              blurRadius: 14,
              offset: const Offset(0, 6),
            )
          ],
          border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.55), width: 1.5),
        ),
        child: FloatingActionButton(
          tooltip: 'scan_qr'.tr(),
          onPressed: () {
            UniversalQrNav.open(
              context,
              callerRole: UniversalQrCallerRole.karyawan,
              cabangKaryawan: _cabangKaryawan,
              karyawanId: _karyawanId,
              karyawanNama: _namaKaryawan,
            );
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.qr_code_scanner_rounded,
              color: Colors.white, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          elevation: 16,
          shadowColor: const Color(0xFF0A1628).withOpacity(0.12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                    child: _buildNavItem(
                        Icons.home_rounded, "nav_beranda".tr(), 0)),
                Expanded(
                    child: _buildNavItem(
                        Icons.fact_check_rounded, "nav sop".tr(), 1)),
                const SizedBox(width: 50),
                Expanded(
                    child: _buildNavItem(
                        Icons.headset_mic_rounded, "nav bantuan".tr(), 3)),
                Expanded(
                    child: _buildNavItem(
                        Icons.person_rounded, "nav_profil".tr(), 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    int targetPage = index == 3 ? index : index;
    bool isSelected = _currentIndex == targetPage && index != 3;
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () {
        if (index == 3) {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const BantuanPage()));
          return;
        }
        setState(() => _currentIndex = targetPage);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: _adaUpdateBaru && label == "nav_profil".tr(),
              backgroundColor: Colors.redAccent,
              smallSize: 10,
              child: Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF1E3C72)
                    : Colors.grey.shade400,
                size: isSelected ? 28 : 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF1E3C72)
                    : Colors.grey.shade400,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + _fabBottomPad(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.blue.withOpacity(0.3), blurRadius: 10)
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFF1E293B),
                    // Jika URL foto dari database ada, pasang!
                    backgroundImage: _fotoProfileUrl != null
                        ? NetworkImage(_fotoProfileUrl!)
                        : null,
                    child: _fotoProfileUrl == null
                        ? const Icon(Icons.person_rounded,
                            size: 35, color: Colors.white70)
                        : null,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${'dash_halo'.tr().trim()} $_namaKaryawan",
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(_jabatanKaryawan.tr(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.storefront_rounded,
                                color: Colors.blueAccent, size: 14),
                            const SizedBox(width: 6),
                            Text(_cabangKaryawan,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _tampilkanRiwayatPoin(),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.orange.withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 8))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.stars_rounded,
                            color: Colors.white, size: 28),
                        const SizedBox(height: 10),
                        Text("poin_total_judul".tr(),
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        Text("$totalPoinBulanIni / 1000",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.local_fire_department_rounded,
                          color: Colors.white, size: 28),
                      const SizedBox(height: 10),
                      Text("poin_streak_judul".tr(),
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text("$currentStreakHari ${'poin hari'.tr()}",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 35),
          Row(
            children: [
              Expanded(
                child: Text("jadwal_mingguan_judul".tr(),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B))),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PengajuanJadwalPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                label: const Text('Ijin / Tukar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: ListView.builder(
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              itemCount: _jadwalMingguIni.length,
              itemBuilder: (context, index) {
                final jadwal = _jadwalMingguIni[index];
                final shift = jadwal['shift'] ?? '-';
                final isLibur = shift.toLowerCase().contains('libur') ||
                    shift.contains("shift_libur".tr());
                final isEmpty = shift.contains('Belum');
                return Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 15, bottom: 10),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isLibur ? const Color(0xFFFEF2F2) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          isLibur ? Colors.red.shade100 : Colors.blue.shade50,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(jadwal['hari']!,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: isLibur
                                  ? Colors.red.shade700
                                  : const Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(jadwal['tanggal']!,
                              style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                          GestureDetector(
                            onTap: () => _tampilkanDetailJadwal(jadwal),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6)),
                              child: Icon(
                                  isEmpty
                                      ? Icons.info_outline_rounded
                                      : Icons.event_note_rounded,
                                  size: 14,
                                  color: Colors.blueAccent),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isLibur
                              ? Colors.red.shade100
                              : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(jadwal['shift']!,
                            style: TextStyle(
                                color: isLibur
                                    ? Colors.red.shade700
                                    : const Color(0xFF2563EB),
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoTab() {
    int tugasSelesai =
        _daftarSOPTugas.where((e) => e['selesai'] == true).length;
    double progress =
        _daftarSOPTugas.isEmpty ? 0 : tugasSelesai / _daftarSOPTugas.length;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + _fabBottomPad(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.stars_rounded,
                          color: Colors.white, size: 28),
                      const SizedBox(height: 10),
                      Text("poin_total_judul".tr(),
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text("$totalPoinBulanIni / 1000",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.local_fire_department_rounded,
                          color: Colors.white, size: 28),
                      const SizedBox(height: 10),
                      Text("poin_streak_judul".tr(),
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text("$currentStreakHari ${'poin hari'.tr()}",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("sop_progres_harian".tr(),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B))),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: progress == 1.0
                      ? Colors.green.shade100
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "$tugasSelesai / ${_daftarSOPTugas.length} ${'sop_selesai'.tr()}",
                  style: TextStyle(
                      color: progress == 1.0
                          ? Colors.green.shade700
                          : Colors.blueAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              color: progress == 1.0 ? Colors.green : Colors.blueAccent,
            ),
          ),
          const SizedBox(height: 25),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _daftarSOPTugas.length,
            itemBuilder: (context, index) {
              final tugas = _daftarSOPTugas[index];
              final isSelesai = tugas['selesai'];
              return GestureDetector(
                onTap: () => _toggleTugas(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: isSelesai ? const Color(0xFFF0FDF4) : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isSelesai
                          ? Colors.green.shade300
                          : Colors.grey.shade200,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: isSelesai ? Colors.green : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isSelesai ? Colors.green : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: isSelesai
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 16)
                            : null,
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          tugas['tugas'],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isSelesai ? FontWeight.w700 : FontWeight.w600,
                            color: isSelesai
                                ? Colors.green.shade700
                                : const Color(0xFF1E293B),
                            decoration: isSelesai
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            decorationColor: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 30),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8))
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: () async {
                  if (_karyawanId == null) return;
                  if (_sudahKlaimPoinHariIni) {
                    _showPremiumSnackbar("sop_sudah_disimpan_judul".tr(),
                        "sop_sudah_disimpan_desc".tr(), Colors.blueAccent);
                    return;
                  }
                  try {
                    final claimed = await _homeService.claimDailySopPoints(
                      karyawanId: _karyawanId!,
                      tasks: _daftarSOPTugas,
                      streakHari: currentStreakHari,
                    );
                    setState(() {
                      _sudahKlaimPoinHariIni = true;
                      totalPoinBulanIni += claimed;
                      isStreakBonusActive = currentStreakHari >= 3;
                    });
                    if (isStreakBonusActive) {
                      _showPremiumSnackbar(
                          "poin_streak_bonus_judul".tr(),
                          "${'poin_streak_bonus_msg'.tr()} $currentStreakHari",
                          Colors.orange.shade700);
                    } else {
                      _showPremiumSnackbar("poin_selesai_judul".tr(),
                          "poin_selesai_msg".tr(), Colors.green);
                    }
                  } catch (e) {
                    _showPremiumSnackbar(
                        "sop_error_judul".tr(), '$e', Colors.orange);
                  }
                },
                icon:
                    const Icon(Icons.cloud_upload_rounded, color: Colors.white),
                label: Text("sop_btn_simpan".tr(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilTab() {
    return Container(
      color: const Color(0xFF0F172A),
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + _fabBottomPad(context)),
        children: [
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF334155)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              border:
                  Border.all(color: Colors.white.withOpacity(0.05), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("profil_perlindungan_akun".tr(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.security_rounded,
                          color: Colors.greenAccent.shade400, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                    '${(_securityScore * 100).round()}% aman',
                    style: TextStyle(
                        color: _securityScore >= 0.9
                            ? Colors.greenAccent.shade400
                            : Colors.orangeAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _securityScore,
                    backgroundColor: Colors.grey.shade800,
                    color: _securityScore >= 0.9
                        ? Colors.greenAccent.shade400
                        : Colors.orangeAccent,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 15),
                Text("profil_enkripsi".tr(),
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 13, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 10),
            child: Text("menu utama label".tr(),
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                _buildMenuProfil(Icons.person_rounded,
                    "menu_detail profil".tr(), "sub_detail_profil".tr(), true),
                _buildMenuProfil(
                    Icons.face_retouching_natural_rounded,
                    'Absensi',
                    'Masuk/pulang: GPS toko + AWS Face Liveness + wajah',
                    true),
                _buildMenuProfil(
                    Icons.settings_rounded,
                    "menu_pengaturan_akun".tr(),
                    "sub_pengaturan_akun".tr(),
                    true),
                _buildMenuProfil(Icons.headset_mic_rounded,
                    "menu pusat bantuan".tr(), "sub_pusat_bantuan".tr(), true),
                _buildMenuProfil(Icons.warning_rounded, "menu pengaduan".tr(),
                    "sub_pengaduan".tr(), true),
                _buildMenuProfil(Icons.notifications_active_rounded,
                    "menu_pengingat".tr(), "sub_pengingat".tr(), true),
                _buildMenuProfil(Icons.system_update_rounded,
                    "menu_update".tr(), "sub update".tr(), true),
                _buildMenuProfil(Icons.translate_rounded,
                    "menu_ganti bahasa".tr(), "sub_ganti_bahasa".tr(), false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuProfil(
      IconData icon, String title, String subtitle, bool showDivider) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            highlightColor: Colors.white.withOpacity(0.05),
            splashColor: Colors.white.withOpacity(0.1),
            onTap: () {
              if (title == "menu_detail profil".tr()) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const DetailDataPribadiPage()));
              } else if (title == 'Absensi') {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AbsensiPage()));
              } else if (title == "menu_pengaturan_akun".tr()) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const PengaturanAkunPage()));
              } else if (title == "menu pusat bantuan".tr()) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const BantuanPage()));
              } else if (title == "menu pengaduan".tr()) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const PengaduanPage()));
              } else if (title == "menu_pengingat".tr()) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const PengingatPage()));
              } else if (title == "menu_update".tr()) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SoftwareUpdatePage()));
              } else if (title == "menu_ganti bahasa".tr()) {
                _tampilkanDialogBahasa(context);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.blueAccent.withOpacity(0.3), width: 1),
                    ),
                    child:
                        Icon(icon, color: Colors.blueAccent.shade100, size: 22),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withOpacity(0.2), size: 16),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
              color: Colors.white.withOpacity(0.05),
              height: 1,
              indent: 70,
              endIndent: 20),
      ],
    );
  }
}
