// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'detail_pribadi_page.dart';
import 'pengaturan_akun_karyawan.dart';
import 'bantuan_page.dart';
import 'pengaduan_page.dart';
import 'pengingat_page.dart';
import 'contribution_rekap_page.dart';
import 'package:image_picker/image_picker.dart';
import 'software_update_page.dart';
import 'absensi_page.dart';
import 'admin_login_code_page.dart';
import 'pengajuan_jadwal_page.dart';
import 'toko_antrian_page.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../shared/attendance/attendance_service.dart';
import '../../shared/attendance/geofence_exit_monitor.dart';
import '../../shared/karyawan/karyawan_home_service.dart';
import '../../shared/karyawan/karyawan_i18n_display.dart';
import '../../shared/karyawan/karyawan_jabatan.dart';
import '../../shared/karyawan/kpi_fire_service.dart';
import '../../shared/karyawan/karyawan_ops_watch.dart';
import '../../shared/karyawan/lab_job_service.dart';
import '../../shared/karyawan/shift_auto_assign.dart';
import '../../shared/karyawan/sop_daily_service.dart';
import '../../shared/karyawan/sop_score.dart';
import '../../shared/karyawan/sop_score_panel.dart';
import '../../shared/karyawan/streak_fire_level.dart';
import '../../shared/karyawan/toko_antrian_realtime.dart';
import '../../shared/karyawan/toko_antrian_service.dart';
import '../../shared/app_update_service.dart';
import '../../shared/responsive.dart';
import '../../shared/safe_image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/sync/client_force_sync.dart';
import '../../shared/theme.dart';
import '../../shared/whatsapp_launcher.dart';
import '../../shared/widgets/app_brand_mark.dart';
import '../../shared/qr/qr_route.dart';
import '../../shared/qr/universal_qr_host.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/qr/universal_qr_scan_page.dart';
import '../../shared/scanner_penerimaan_page.dart';
import '../member/pages/member_face_shape_page.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/tenant/tenant_modules.dart';

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
  final _labService = LabJobService();

  // 1. WADAH DATA DINAMIS
  late String _namaKaryawan;
  String _jabatanKaryawan = "...";
  String _cabangKaryawan = "...";
  String? _karyawanId;
  String? _tokoId;
  String? _nikKaryawan;
  bool _isLoading = true;
  List<Map<String, dynamic>> _labOpenJobs = [];
  List<Map<String, dynamic>> _labMineJobs = [];
  bool _labBusy = false;
  final _sopDaily = SopDailyService();
  SopBranchState? _sopBranch;
  SopScoreResult? _sopScore;
  bool _sopBusy = false;
  bool _sopIsPagi = true;
  final GlobalKey _labSectionKey = GlobalKey();
  final GlobalKey _sopSectionKey = GlobalKey();
  final GlobalKey _todayPanelKey = GlobalKey();
  final GlobalKey _antrianSectionKey = GlobalKey();
  final _antrianService = TokoAntrianService();
  List<TokoAntrianItem> _antrianItems = [];
  TokoAntrianRealtimeSubscription? _antrianRt;
  Timer? _antrianPoll;

  // 2. JADWAL MINGGUAN (dari Supabase)
  List<Map<String, String>> _jadwalMingguIni = [];

  // Wadah List SOP
  List<Map<String, dynamic>> _daftarSOPTugas = [];

  Map<String, String>? _jadwalHariIni;
  String _absenStatus = 'belum_masuk';
  DateTime? _absenMasukAt;
  DateTime? _absenPulangAt;
  List<Map<String, dynamic>> _pengajuanTerbaru = [];
  List<Map<String, dynamic>> _pengumuman = [];

  double _securityScore = 0;

  // MESIN NAVIGASI BAWAH
  int _currentIndex = 0;

  /// PUSAT: Admin/Owner. Cabang: Kepala Toko/Kepala Area. Front/Back: tidak.
  bool get _canShowAdminLoginCode => KaryawanJabatan.canShowAdminLoginCode(
        tokoId: _tokoId,
        jabatan: _jabatanKaryawan,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _namaKaryawan = 'memuat'.tr();
    _bindQrHost();
    _tarikDataProfil();
    _cekUpdateApkSilent();
    _cekHasilInstallSetelahResume();
    unawaited(_bindForceSync());
  }

  Future<void> _bindForceSync() async {
    await ClientForceSync.bindFromTenantService(
      localTokoId: _tokoId,
      onRemote: (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('client_force_sync_remote_ok'.tr()),
            backgroundColor: OptikAdminTokens.navy,
          ),
        );
        unawaited(_tarikDataProfil());
        unawaited(_loadTokoAntrian());
      },
    );
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
    _antrianPoll?.cancel();
    unawaited(_antrianRt?.dispose() ?? Future<void>.value());
    WidgetsBinding.instance.removeObserver(this);
    UniversalQrHost.clear();
    unawaited(ClientForceSync.unbind());
    unawaited(KaryawanOpsWatch.instance.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cekHasilInstallSetelahResume();
      _syncGeofenceMonitorIfOpenShift();
      // Tarik ulang poin/SOP agar Valid/Curang dari Admin langsung terlihat.
      unawaited(_tarikDataProfil());
      unawaited(_loadTokoAntrian());
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
      final outcome = await _updateService.checkPendingInstallResult(
        appFlavor: 'karyawan',
      );
      if (!mounted) return;
      if (outcome.updated) {
        setState(() => _adaUpdateBaru = false);
        _showPremiumSnackbar(
          'Update berhasil',
          'Aplikasi sekarang versi ${outcome.localVersion}. Siap dipakai.',
          OptikKaryawanTokens.seasideMid,
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
    final autoOn =
        await _updateService.isAutoUpdateEnabled(appFlavor: 'karyawan');
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
              OptikKaryawanTokens.gold,
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
        backgroundColor: OptikKaryawanTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: OptikKaryawanTokens.border),
        ),
        title: const Text(
          'Penyimpanan kurang',
          style: TextStyle(color: OptikKaryawanTokens.ink, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Storage internal HP tidak cukup untuk mengunduh update.\n\n'
          'Dibutuhkan sekitar $butuh (tersedia $sisa).\n\n'
          'Kosongkan foto, cache, atau file lain di penyimpanan internal, '
          'lalu buka lagi aplikasi — unduhan akan dilanjutkan otomatis.',
          style: const TextStyle(color: OptikKaryawanTokens.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('btn_mengerti'.tr(),
                style: TextStyle(color: OptikKaryawanTokens.muted)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _storageDialogShown = false;
              _mulaiAutoDownloadUpdate();
            },
            child: Text('btn_coba_lagi'.tr()),
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
          backgroundColor: OptikKaryawanTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: OptikKaryawanTokens.border),
          ),
          title: Text(
            hardForce ? 'Update wajib siap dipasang' : 'Update siap dipasang',
            style: const TextStyle(
                color: OptikKaryawanTokens.ink, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Versi ${info.serverVersion} sudah diunduh.\n'
            'Pasang sekarang? App lama tetap aman sampai instalasi selesai.\n\n'
            '${info.notes ?? ''}',
            style: const TextStyle(color: OptikKaryawanTokens.muted, height: 1.4),
          ),
          actions: [
            if (!hardForce)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('btn_nanti'.tr(),
                    style: TextStyle(color: OptikKaryawanTokens.muted)),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _updateService.confirmAndOpenInstaller(
                    apkPath: path,
                    expectedVersion: info.serverVersion,
                    appFlavor: 'karyawan',
                  );
                  if (!mounted) return;
                  _showPremiumSnackbar(
                    'Installer dibuka',
                    'Konfirmasi di layar sistem untuk memasang update.',
                    OptikKaryawanTokens.seasideMid,
                  );
                } catch (e) {
                  if (!mounted) return;
                  final pesan = e.toString().replaceAll('Exception: ', '');
                  if (pesan.contains('REQUEST_INSTALL_PACKAGES')) {
                    _showPremiumSnackbar(
                      'Izin instalasi diperlukan',
                      'Aktifkan “Instal aplikasi tidak dikenal” untuk ${BrandService.name} di Pengaturan.',
                      Colors.orange,
                    );
                  } else {
                    _showPremiumSnackbar('Gagal buka installer', pesan, Colors.red);
                  }
                }
              },
              child: Text('btn_pasang_sekarang'.tr()),
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
    final code = context.locale.languageCode;
    if (code != 'id' && code != 'en') {
      context.setLocale(const Locale('id'));
    }
    showDialog(
      context: context,
      builder: (context) {
        return R.constrainedDialog(
          context: context,
          child: AlertDialog(
          backgroundColor: OptikKaryawanTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: OptikKaryawanTokens.border),
          ),
          title: Text(
            "pilihan_bahasa_judul".tr(),
            style: const TextStyle(
                color: OptikKaryawanTokens.ink, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOpsiBahasaItem(context, "lang_id".tr(), const Locale('id')),
              _buildOpsiBahasaItem(context, "lang_en".tr(), const Locale('en')),
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
              color: isSelected ? OptikKaryawanTokens.seasideMid : OptikKaryawanTokens.ink,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded, color: OptikKaryawanTokens.gold)
          : null,
      onTap: () {
        context.setLocale(locale);
        Navigator.pop(context);
        _showPremiumSnackbar("notif_sukses_judul".tr(),
            "notif_bahasa_sukses".tr(), OptikKaryawanTokens.seasideMid);
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
      final autoOn =
          await _updateService.isAutoUpdateEnabled(appFlavor: 'karyawan');
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
            backgroundColor: OptikKaryawanTokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: OptikKaryawanTokens.border),
            ),
            title: Text(
              hardForce ? 'Update wajib' : 'Update tersedia',
              style: const TextStyle(
                  color: OptikKaryawanTokens.ink, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Versi baru ${info.serverVersion} siap '
              '(saat ini ${info.localVersion}).\n'
              'Unduh bisa otomatis; pemasangan tetap butuh konfirmasi Anda.\n\n'
              '${!info.urlReachable ? '⚠️ Link unduhan belum siap. Anda tetap bisa pakai app.\n\n' : ''}'
              '${info.notes ?? ''}',
              style: const TextStyle(color: OptikKaryawanTokens.muted, height: 1.4),
            ),
            actions: [
              if (!hardForce)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('btn_nanti'.tr(),
                      style: TextStyle(color: OptikKaryawanTokens.muted)),
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
        _nikKaryawan = snap.karyawan['nik']?.toString();
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
        _jadwalHariIni = snap.jadwalHariIni;
        _absenStatus = snap.absenStatus;
        _absenMasukAt = snap.absenMasukAt;
        _absenPulangAt = snap.absenPulangAt;
        _pengajuanTerbaru = snap.pengajuanTerbaru;
        _pengumuman = snap.pengumuman;
        currentStreakHari = snap.streakHari;
        // Paksa 1 sumber: level/progres selalu dari total poin bulan.
        _kpiFire = snap.kpiFire;
        _kpiYearHistory = snap.kpiYearHistory;
        _applyPoinBulan(snap.totalPoinBulan);
        isStreakBonusActive = snap.streakHari >= 3;
        _sudahKlaimPoinHariIni = snap.sudahKlaimHariIni;
        _securityScore = snap.securityScore;
        _isLoading = false;
      });
      _bindQrHost();
      unawaited(_bindForceSync());

      if (_karyawanId != null) {
        await _homeService.ensureTodayReminders(
          karyawanId: _karyawanId!,
          jadwalMinggu: _jadwalMingguIni,
          sopTasks: _daftarSOPTugas,
        );
      }
      unawaited(_loadLabQueue());
      unawaited(_loadTokoAntrian());
      unawaited(_bindTokoAntrianRealtime());
      unawaited(_loadSopScore());
      unawaited(_syncGeofenceMonitorIfOpenShift(askPermissions: true));
      final tokoOps = (_tokoId ?? _cabangKaryawan).trim();
      final kidOps = (_karyawanId ?? '').trim();
      if (tokoOps.isNotEmpty && kidOps.isNotEmpty) {
        unawaited(KaryawanOpsWatch.instance.start(
          tokoId: tokoOps,
          karyawanId: kidOps,
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Gagal menarik data profil: $e");
    }
  }

  bool get _showLabQueue =>
      _labService.isBackOffice(_jabatanKaryawan) &&
      (_absenStatus == 'sedang_bekerja' ||
          _labOpenJobs.isNotEmpty ||
          _labMineJobs.isNotEmpty);

  Future<void> _loadLabQueue() async {
    final kid = _karyawanId;
    final toko = _tokoId;
    if (kid == null ||
        toko == null ||
        !_labService.isBackOffice(_jabatanKaryawan)) {
      if (mounted) {
        setState(() {
          _labOpenJobs = [];
          _labMineJobs = [];
        });
      }
      return;
    }
    try {
      final q = await _labService.listHomeQueue(
        tokoId: toko,
        karyawanId: kid,
      );
      if (!mounted) return;
      setState(() {
        _labOpenJobs = q.open;
        _labMineJobs = q.mine;
      });
    } catch (e) {
      debugPrint('lab queue: $e');
    }
  }

  Future<void> _loadTokoAntrian() async {
    final toko = (_tokoId ?? '').trim();
    if (toko.isEmpty) {
      if (mounted) setState(() => _antrianItems = []);
      return;
    }
    try {
      final res = await _antrianService.loadDetailed(tokoId: toko);
      if (!mounted) return;
      setState(() => _antrianItems = res.items);
      if (res.hasErrors && res.items.isEmpty) {
        debugPrint('toko antrian errors: ${res.errors.join(' · ')}');
      }
    } catch (e) {
      debugPrint('toko antrian: $e');
    }
  }

  Future<void> _bindTokoAntrianRealtime() async {
    final toko = (_tokoId ?? '').trim();
    await _antrianRt?.dispose();
    _antrianRt = null;
    _antrianPoll?.cancel();
    _antrianPoll = null;
    if (toko.isEmpty) return;
    _antrianRt = TokoAntrianRealtime.subscribeToko(
      tokoId: toko,
      onChanged: () {
        if (mounted) unawaited(_loadTokoAntrian());
      },
    );
    _antrianPoll = Timer.periodic(const Duration(seconds: 40), (_) {
      if (mounted) unawaited(_loadTokoAntrian());
    });
  }

  void _openTokoAntrianPage() {
    final toko = (_tokoId ?? _cabangKaryawan).trim();
    final kid = (_karyawanId ?? '').trim();
    if (toko.isEmpty || kid.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TokoAntrianPage(
          tokoId: toko,
          karyawanId: kid,
          karyawanNama: _namaKaryawan,
          karyawanNik: (_nikKaryawan ?? '').trim(),
          initialItems: _antrianItems,
        ),
      ),
    ).then((_) {
      if (mounted) unawaited(_loadTokoAntrian());
    });
  }

  Future<void> _claimLabJob(Map<String, dynamic> job) async {
    final id = job['id']?.toString() ?? '';
    if (id.isEmpty || _labBusy) return;
    setState(() => _labBusy = true);
    try {
      final res = await _labService.claim(id);
      if (!mounted) return;
      final nama = res['nama']?.toString() ?? _namaKaryawan;
      final inv = res['no_invoice']?.toString() ??
          job['no_invoice']?.toString() ??
          '-';
      _showPremiumSnackbar(
        'lab_claim_ok_judul'.tr(),
        'lab_claim_ok_msg'.tr(args: [inv, nama]),
        OptikKaryawanTokens.success,
      );
      await _loadLabQueue();
      unawaited(_loadTokoAntrian());
    } catch (e) {
      if (!mounted) return;
      _showPremiumSnackbar(
        'lab_claim_gagal_judul'.tr(),
        '$e',
        OptikKaryawanTokens.danger,
      );
      await _loadLabQueue();
    } finally {
      if (mounted) setState(() => _labBusy = false);
    }
  }

  Future<void> _completeLabJob(Map<String, dynamic> job) async {
    final id = job['id']?.toString() ?? '';
    final inv = job['no_invoice']?.toString() ?? '-';
    final qty = job['unit_qty']?.toString() ?? '1';
    if (id.isEmpty || _labBusy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('lab_complete_confirm_judul'.tr()),
        content: Text(
          'lab_complete_confirm_msg'.tr(namedArgs: {
            'invoice': inv,
            'qty': qty,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('sop_batal'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('lab_queue_btn_selesai'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _labBusy = true);
    try {
      final res = await _labService.complete(jobId: id);
      if (!mounted) return;
      final track = (res['tracking_status'] ?? '').toString().toUpperCase();
      final isDp = res['is_dp'] == true;
      final pendingLeft = (res['pending_left'] is num)
          ? (res['pending_left'] as num).toInt()
          : int.tryParse('${res['pending_left'] ?? ''}') ?? 0;
      final okMsg = pendingLeft > 0
          ? 'lab_complete_ok_partial'.tr(namedArgs: {
              'invoice': inv,
              'left': '$pendingLeft',
            })
          : isDp
              ? 'lab_complete_ok_dp'.tr(namedArgs: {'invoice': inv})
              : 'lab_complete_ok_lunas'.tr(namedArgs: {
                  'invoice': inv,
                  'track': track.isEmpty ? 'SIAP_DIAMBIL' : track,
                });
      _showPremiumSnackbar(
        'lab_complete_ok_judul'.tr(),
        okMsg,
        OptikKaryawanTokens.success,
      );
      await _loadLabQueue();
      unawaited(_loadTokoAntrian());
    } catch (e) {
      if (!mounted) return;
      _showPremiumSnackbar(
        'lab_complete_gagal_judul'.tr(),
        '$e',
        OptikKaryawanTokens.danger,
      );
      await _loadLabQueue();
    } finally {
      if (mounted) setState(() => _labBusy = false);
    }
  }

  int totalPoinBulanIni = 0;
  int currentStreakHari = 0;
  KpiFireSnapshot _kpiFire = KpiFireSnapshot.empty();
  List<KpiMonthHistoryRecord> _kpiYearHistory = const [];
  bool isStreakBonusActive = false;

  bool _sudahKlaimPoinHariIni = false;

  /// Satu pintu update poin bulan → level/progres api ikut sinkron.
  void _applyPoinBulan(int poin) {
    totalPoinBulanIni = poin;
    _kpiFire = _kpiFire.syncedWithPoints(poin);
    _syncCurrentMonthInYearHistory();
  }

  void _syncCurrentMonthInYearHistory() {
    if (_kpiYearHistory.isEmpty) return;
    final cur = _kpiYearHistory.first;
    final now = DateTime.now();
    if (cur.year != now.year || cur.month != now.month) return;
    _kpiYearHistory = [
      KpiMonthHistoryRecord(
        year: cur.year,
        month: cur.month,
        totalPoin: _kpiFire.totalPoin,
        pointTarget: _kpiFire.pointTarget,
        workDays: cur.workDays,
        progress: _kpiFire.progress,
        fire: _kpiFire.fire,
      ),
      ..._kpiYearHistory.skip(1),
    ];
  }

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
          "sop_bukti_sah".tr(), "sop_foto_sukses".tr(), OptikKaryawanTokens.seasideMid);
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
      // Scanner universal — isi QR yang menentukan; bukti SOP hanya jika surat jalan.
      final routed = await UniversalQrScanPage.scanRouted(
        context,
        hintKey: 'universal_qr_scan_hint',
      );
      if (routed == null || !mounted) {
        _showPremiumSnackbar(
            "sop_batal".tr(), "sop_scan_batal_msg".tr(), Colors.orange);
        return;
      }
      if (routed.type != QrPayloadType.receiveStock) {
        await UniversalQrNav.dispatch(
          context,
          routed,
          callerRole: UniversalQrCallerRole.karyawan,
          cabangKaryawan: _cabangKaryawan,
          karyawanId: _karyawanId,
          karyawanNama: _namaKaryawan,
          profile: {
            'toko_id': _tokoId ?? _cabangKaryawan,
            'role': 'karyawan',
            'id': _karyawanId,
            'nama': _namaKaryawan,
            'nik': _nikKaryawan,
          },
        );
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
                  ElevatedButton.styleFrom(backgroundColor: OptikKaryawanTokens.gold),
              onPressed: () async {
                if (inputController.text.isNotEmpty) {
                  Navigator.pop(context);
                  await _persistSopDone(index,
                      buktiText: inputController.text.trim());
                  _showPremiumSnackbar("sop_terkonfirmasi".tr(),
                      "sop_aktual_tersimpan".tr(), OptikKaryawanTokens.seasideMid);
                } else {
                  _showPremiumSnackbar("sop_error_judul".tr(),
                      "sop_error_kosong".tr(), Colors.red);
                }
              },
              child: Text("sop_btn_konfirmasi".tr(),
                  style: const TextStyle(
                      color: OptikKaryawanTokens.ink, fontWeight: FontWeight.bold)),
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
        decoration: BoxDecoration(
          color: OptikKaryawanTokens.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: OptikKaryawanTokens.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${KaryawanI18nDisplay.hariLabel(jadwal['hari'] ?? '')} • ${KaryawanI18nDisplay.tanggalLabel(dateKey: jadwal['date_key'], fallback: jadwal['tanggal'], locale: context.locale)}',
              style: const TextStyle(
                color: OptikKaryawanTokens.ink,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'jadwal_shift_label'.tr(
                namedArgs: {
                  'shift': KaryawanI18nDisplay.shiftLabel(
                    jadwal['shift'] ?? '-',
                  ),
                },
              ),
              style: const TextStyle(
                color: OptikKaryawanTokens.muted,
                fontSize: 15,
              ),
            ),
            if (catatan != null && catatan.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'jadwal_catatan_label'.tr(namedArgs: {'note': catatan}),
                style: const TextStyle(color: OptikKaryawanTokens.muted),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'jadwal_ajukan_hint'.tr(),
              style: const TextStyle(
                color: OptikKaryawanTokens.muted,
                fontSize: 12,
                height: 1.4,
              ),
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
                label: Text('home_ajukan_ijin_tukar'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OptikKaryawanTokens.gold,
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

  // POP-UP detail Api KPI (progres poin).
  void _tampilkanRiwayatPoin() {
    _showFireHistorySheet();
  }

  /// Wash solid halaman detail — ikut tier api (bukan putih polos / glass).
  ({List<Color> wash, Color orb, Color band}) _kpiDetailPageAtmosphere(int lv) {
    switch (lv.clamp(0, 5)) {
      case 1:
        return (
          wash: const [
            Color(0xFFFFF3EF),
            Color(0xFFFFE4DC),
            Color(0xFFF8FBFC),
          ],
          orb: const Color(0xFFFFC9BA),
          band: const Color(0xFFFFD2C4),
        );
      case 2:
        return (
          wash: const [
            Color(0xFFFFF0E0),
            Color(0xFFFFD9A8),
            Color(0xFFFFF8F0),
          ],
          orb: const Color(0xFFFFB74D),
          band: const Color(0xFFFFCC80),
        );
      case 3:
        return (
          wash: const [
            Color(0xFFFFF3C4),
            Color(0xFFE8C45A),
            Color(0xFFFFF8E8),
          ],
          orb: const Color(0xFFFFE082),
          band: const Color(0xFFD4A017),
        );
      case 4:
        return (
          wash: const [
            Color(0xFFFFE8F0),
            Color(0xFFE8A0C0),
            Color(0xFFFFF5F8),
          ],
          orb: const Color(0xFFFF80AB),
          band: const Color(0xFFC2185B),
        );
      case 5:
        return (
          wash: const [
            Color(0xFFEFE0FF),
            Color(0xFFB48CFF),
            Color(0xFFF7F2FF),
          ],
          orb: const Color(0xFFD2B4FF),
          band: const Color(0xFF7E57C2),
        );
      default:
        return (
          wash: const [
            Color(0xFFF4F8F9),
            Color(0xFFE8EEF0),
            Color(0xFFFAFCFD),
          ],
          orb: const Color(0xFFCFD8DC),
          band: OptikKaryawanTokens.border,
        );
    }
  }

  Widget _buildKpiDetailPageShell({
    required ScrollController? scrollController,
    required List<Widget> children,
  }) {
    final lv = _kpiFire.fire.level.clamp(0, 5);
    final atm = _kpiDetailPageAtmosphere(lv);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: atm.wash,
          stops: const [0.0, 0.28, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: OptikKaryawanTokens.ink.withOpacity(0.14),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Ornamen solid atas — depth premium
          Positioned(
            right: -48,
            top: -56,
            child: IgnorePointer(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      atm.orb,
                      Color.lerp(atm.orb, atm.wash.last, 0.85)!,
                      atm.wash.last,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -70,
            top: 120,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(atm.orb, atm.wash[1], 0.55)!,
                ),
              ),
            ),
          ),
          // Pita aksen metal di atas
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 6,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.lerp(atm.band, Colors.white, 0.35)!,
                      atm.band,
                      Color.lerp(atm.band, atm.wash[1], 0.4)!,
                    ],
                  ),
                ),
              ),
            ),
          ),
          ListView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Color.lerp(atm.band, Colors.white, 0.45)!,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ],
      ),
    );
  }

  /// Material tier hero detail — selaras banner (solid, bukan glass).
  ({
    List<Color> body,
    Color border,
    Color fillBar,
    Color track,
    bool lit,
    String? badge,
    List<Color>? badgeGrad,
    Color badgeText,
  }) _kpiDetailTier(int lv) {
    switch (lv.clamp(0, 5)) {
      case 1:
        return (
          body: const [Color(0xFFFFF1EE), Color(0xFFFFD2C8), Color(0xFFF2A89A)],
          border: const Color(0xFFC62828),
          fillBar: const Color(0xFFD32F2F),
          track: const Color(0xFFFFF8F6),
          lit: false,
          badge: null,
          badgeGrad: null,
          badgeText: OptikKaryawanTokens.ink,
        );
      case 2:
        return (
          body: const [Color(0xFFFF9800), Color(0xFFEF6C00)],
          border: const Color(0xFFFFCC80),
          fillBar: const Color(0xFFFFE0B2),
          track: const Color(0xFFBF360C),
          lit: true,
          badge: null,
          badgeGrad: null,
          badgeText: Colors.white,
        );
      case 3:
        return (
          body: const [Color(0xFFFFE082), Color(0xFFC9A227), Color(0xFF4A3608)],
          border: const Color(0xFFFFE082),
          fillBar: const Color(0xFFFFECB3),
          track: const Color(0xFF3A2808),
          lit: true,
          badge: 'kpi_badge_gold',
          badgeGrad: const [
            Color(0xFFFFF8E1),
            Color(0xFFE0B43A),
            Color(0xFF8A6410),
          ],
          badgeText: const Color(0xFF3A2808),
        );
      case 4:
        return (
          body: const [Color(0xFF9C1258), Color(0xFF5A0A36), Color(0xFF1A0612)],
          border: const Color(0xFFF8BBD0),
          fillBar: const Color(0xFFF8BBD0),
          track: const Color(0xFF2A0618),
          lit: true,
          badge: 'kpi_badge_elite',
          badgeGrad: const [Color(0xFFFFE0EC), Color(0xFFFF80AB)],
          badgeText: const Color(0xFF4A0A28),
        );
      case 5:
        return (
          body: const [Color(0xFF4A2080), Color(0xFF2A1058), Color(0xFF0E061C)],
          border: const Color(0xFFE0C8FF),
          fillBar: const Color(0xFFE8D4FF),
          track: const Color(0xFF140828),
          lit: true,
          badge: 'kpi_badge_max',
          badgeGrad: const [Color(0xFFF0E0FF), Color(0xFFB48CFF)],
          badgeText: const Color(0xFF2A1058),
        );
      default:
        return (
          body: const [Color(0xFFF5FAFB), Color(0xFFE8EEF0)],
          border: OptikKaryawanTokens.border,
          fillBar: OptikKaryawanTokens.muted,
          track: const Color(0xFFE0E6E8),
          lit: false,
          badge: null,
          badgeGrad: null,
          badgeText: OptikKaryawanTokens.ink,
        );
    }
  }

  /// Konten detail Api KPI — dipakai sheet banner & riwayat.
  List<Widget> _buildKpiDetailSections() {
    final fire = _kpiFire.fire;
    final pct = (_kpiFire.progress * 100).round();
    final lv = fire.level.clamp(0, 5);
    final tier = _kpiDetailTier(lv);
    final nextLv = lv >= 5 ? 5 : (lv <= 0 ? 1 : lv + 1);
    final needPts = _kpiFire.pointsToNextLevel();
    final perLevel = KpiFireSnapshot.pointsPerLevel(_kpiFire.pointTarget);
    final monthLabel = DateFormat.yMMMM(context.locale.toString())
        .format(DateTime.now());
    final titleC = tier.lit ? Colors.white : OptikKaryawanTokens.ink;
    final metaC = tier.lit
        ? Colors.white.withOpacity(0.78)
        : OptikKaryawanTokens.ink.withOpacity(0.62);
    final nextLine = lv >= 5
        ? 'kpi_next_level_max'.tr()
        : 'kpi_next_level_pts'.tr(args: ['$needPts', '$nextLv']);

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'kpi_api_sheet_title'.tr(),
              style: GoogleFonts.fraunces(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: OptikKaryawanTokens.ink,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5F6),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: OptikKaryawanTokens.border),
            ),
            child: Text(
              monthLabel.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: OptikKaryawanTokens.muted,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'kpi_api_sheet_sub'.tr(args: ['${_kpiFire.pointTarget}']),
        style: TextStyle(
          color: OptikKaryawanTokens.muted,
          fontSize: 13.5,
          height: 1.45,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _kpiFormulaChip(
            '${_kpiFire.totalPoin}',
            'kpi_banner_pts'.tr(),
          ),
          _kpiFormulaChip(
            '${_kpiFire.pointTarget}',
            'kpi_target_bulan'.tr(),
          ),
          _kpiFormulaChip(
            '+$perLevel',
            'kpi_per_level'.tr(),
          ),
        ],
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _showKpiYearHistorySheet,
          icon: const Icon(Icons.calendar_month_rounded, size: 18),
          label: Text(
            'kpi_year_history_btn'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: OptikKaryawanTokens.ink,
            side: BorderSide(color: OptikKaryawanTokens.border),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      // HERO — material tier sama banner
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tier.body,
          ),
          border: Border.all(color: tier.border, width: lv >= 3 ? 1.6 : 1.2),
          boxShadow: [
            BoxShadow(
              color: Color.lerp(
                Colors.transparent,
                tier.body.last,
                lv >= 3 ? 0.45 : 0.22,
              )!,
              blurRadius: lv >= 3 ? 28 : 18,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: OptikKaryawanTokens.ink.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (lv >= 3)
              Positioned(
                right: -36,
                top: -40,
                child: IgnorePointer(
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(lv == 3 ? 0.38 : 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (lv >= 4)
              Positioned(
                left: -28,
                bottom: -36,
                child: IgnorePointer(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(0.12),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (tier.badge != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: tier.badgeGrad!,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            tier.badge!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: tier.badgeText,
                            ),
                          ),
                        ),
                        const Spacer(),
                      ] else
                        const Spacer(),
                      Text(
                        'kpi_fire_level'.tr(args: ['${lv <= 0 ? 0 : lv}']),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: metaC,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: tier.border,
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.16),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: StreakFireFlame(
                            fire: fire,
                            size: 36,
                            solid: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          fire.labelKey.tr(),
                          style: GoogleFonts.fraunces(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: titleC,
                            height: 1.1,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$pct%',
                            style: GoogleFonts.fraunces(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: titleC,
                              height: 1,
                              letterSpacing: -1.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'kpi_banner_pts'.tr().toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: metaC,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  StreakFireProgressBar(
                    progress: _kpiFire.progress,
                    height: 8,
                    compact: true,
                    trackColor: tier.track,
                    fillColor: tier.fillBar,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: tier.lit
                          ? Color.lerp(tier.body.last, Colors.black, 0.28)!
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: tier.lit
                            ? Color.lerp(tier.border, tier.body.last, 0.35)!
                            : tier.border,
                      ),
                    ),
                    child: Text(
                      nextLine,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: titleC,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      Text(
        'kpi_detail_ringkas'.tr(),
        style: GoogleFonts.fraunces(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: OptikKaryawanTokens.ink,
          letterSpacing: -0.3,
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _kpiStatTile(
              label: 'kpi_breakdown_tetap'.tr(),
              value: '${(_kpiFire.sTetap * 100).round()}%',
              accent: const Color(0xFF1B6B6A),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _kpiStatTile(
              label: 'kpi_breakdown_toko'.tr(),
              value: '${(_kpiFire.sToko * 100).round()}%',
              accent: const Color(0xFFC9A227),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OptikKaryawanTokens.border),
          boxShadow: [
            BoxShadow(
              color: OptikKaryawanTokens.ink.withOpacity(0.035),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            _kpiBreakdownTile(
              'kpi_breakdown_fair'.tr(),
              '${(_kpiFire.aktualPct * 100).round()}% / ${(_kpiFire.fairShare * 100).round()}%',
              showDivider: true,
            ),
            _kpiBreakdownTile(
              'kpi_breakdown_unit'.tr(),
              '${_kpiFire.unitOrang} / ${_kpiFire.unitTim}',
              showDivider: true,
            ),
            _kpiBreakdownTile(
              'kpi_breakdown_hari'.tr(),
              '${_kpiFire.hariValid}',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            final toko = (_tokoId ?? _cabangKaryawan).trim();
            if (toko.isEmpty) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ContributionRekapPage(
                  tokoId: toko,
                  jabatan: _jabatanKaryawan,
                  highlightKaryawanId: _karyawanId,
                ),
              ),
            );
          },
          icon: const Icon(Icons.groups_rounded, size: 18),
          label: Text('rekap_kontribusi_buka'.tr()),
        ),
      ),
      const SizedBox(height: 28),
      Text(
        'kpi_detail_peta'.tr(),
        style: GoogleFonts.fraunces(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: OptikKaryawanTokens.ink,
          letterSpacing: -0.3,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'kpi_level_ladder_sub'.tr(args: ['${_kpiFire.pointTarget}']),
        style: TextStyle(
          fontSize: 13,
          color: OptikKaryawanTokens.muted,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 14),
      _buildKpiLevelLadder(),
      const SizedBox(height: 8),
    ];
  }

  Widget _kpiFormulaChip(String weight, String label) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F8),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: OptikKaryawanTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            weight,
            style: GoogleFonts.fraunces(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: OptikKaryawanTokens.ink,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: OptikKaryawanTokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiStatTile({
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OptikKaryawanTokens.border),
        boxShadow: [
          BoxShadow(
            color: OptikKaryawanTokens.ink.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.fraunces(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: OptikKaryawanTokens.ink,
              height: 1,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: OptikKaryawanTokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  /// Ladder 5 level — syarat naik dari rentang poin bulan ini.
  Widget _buildKpiLevelLadder() {
    final current = _kpiFire.fire.level.clamp(0, 5);
    final target = _kpiFire.pointTarget;
    return Column(
      children: [
        for (var level = 1; level <= 5; level++) ...[
          if (level > 1) const SizedBox(height: 10),
          Builder(
            builder: (context) {
              final reached = current >= level;
              final active = current == level;
              final band =
                  KpiFireSnapshot.pointBandForLevel(level, target);
              final pal = StreakFireFlame.levelPalette(level);
              final fire = StreakFireLevel.previewLevel(level);
              final statusColor = active
                  ? tipColorForLevel(level)
                  : (reached
                      ? OptikKaryawanTokens.success
                      : OptikKaryawanTokens.muted);
              final statusLabel = active
                  ? 'kpi_level_current'.tr()
                  : (reached
                      ? 'kpi_level_reached'.tr()
                      : 'kpi_level_locked'.tr());
              final tier = _kpiDetailTier(level);
              final useDark = active && tier.lit;
              final bg = active
                  ? null
                  : (reached
                      ? Color.lerp(Colors.white, pal.bottom, 0.55)!
                      : const Color(0xFFF5F8F9));
              final border = active ? tier.border : OptikKaryawanTokens.border;
              final ink = useDark ? Colors.white : OptikKaryawanTokens.ink;
              final mute = useDark
                  ? Colors.white.withOpacity(0.75)
                  : OptikKaryawanTokens.muted;
              return Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: bg,
                  gradient: active
                      ? LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: tier.body,
                        )
                      : null,
                  border: Border.all(
                    color: border,
                    width: active ? 1.5 : 1.0,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Color.lerp(
                              Colors.transparent,
                              tier.body.last,
                              0.35,
                            )!,
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      if (active)
                        Container(
                          width: 5,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: reached || active
                                        ? Color.lerp(
                                            pal.top, Colors.white, 0.35)!
                                        : OptikKaryawanTokens.border,
                                  ),
                                ),
                                child: Center(
                                  child: StreakFireFlame(
                                    fire: fire,
                                    size: 24,
                                    solid: true,
                                    muted: !reached && !active,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'kpi_fire_level'.tr(args: ['$level']),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                        color: reached || active
                                            ? ink
                                            : OptikKaryawanTokens.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      fire.labelKey.tr(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: useDark
                                            ? Colors.white.withOpacity(0.92)
                                            : (reached
                                                ? pal.top
                                                : OptikKaryawanTokens.muted),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                        color: useDark
                                            ? Colors.white.withOpacity(0.85)
                                            : statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'kpi_level_band_pts'.tr(args: [
                                      '${band.lo}',
                                      '${band.hi}',
                                    ]),
                                    style: GoogleFonts.fraunces(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: reached || active
                                          ? (useDark
                                              ? Colors.white
                                              : pal.top)
                                          : mute,
                                      letterSpacing: -0.4,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'kpi_level_band'.tr(args: [
                                      '${(level - 1) * 20}',
                                      '${level * 20}',
                                    ]),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: useDark
                                          ? Colors.white.withOpacity(0.72)
                                          : mute,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Color tipColorForLevel(int level) =>
      StreakFireFlame.levelPalette(level.clamp(1, 5)).top;

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
                      color: OptikKaryawanTokens.ink,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 4),
            ],
            Text(message,
                style: const TextStyle(
                    color: OptikKaryawanTokens.ink, fontSize: 12)),
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
      backgroundColor: OptikKaryawanTokens.bgMid,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Container(
          decoration: BoxDecoration(
            color: OptikKaryawanTokens.snow.withOpacity(0.96),
            border: Border(
              bottom: BorderSide(
                color: OptikKaryawanTokens.cyan.withOpacity(0.22),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: OptikKaryawanTokens.cyan.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: AppBar(
            title: _currentIndex == 0
                ? const AppBrandMark(height: 22)
                : Text(
                    _currentIndex == 1
                        ? "daftar_tugas_sop".tr()
                        : "pengaturan_akun_judul".tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.2,
                      color: OptikKaryawanTokens.ink,
                    ),
                  ),
            backgroundColor: Colors.transparent,
            foregroundColor: OptikKaryawanTokens.ink,
            elevation: 0,
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  tooltip: 'nav_keluar'.tr(),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        OptikKaryawanTokens.cyan.withOpacity(0.12),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: OptikKaryawanTokens.cyan))
          : pages[_currentIndex],
      floatingActionButton: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: OptikKaryawanTokens.accentGradient,
          boxShadow: [
            BoxShadow(
              color: OptikKaryawanTokens.cyan.withOpacity(0.42),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: OptikKaryawanTokens.snow.withOpacity(0.9),
            width: 2.5,
          ),
        ),
        child: FloatingActionButton(
          // Universal: absensi, penerimaan DO/RO, pickup LUNAS, dll (tanpa filter tipe).
          tooltip: 'scan_qr_universal'.tr(),
          onPressed: () async {
            await UniversalQrNav.open(
              context,
              callerRole: UniversalQrCallerRole.karyawan,
              cabangKaryawan: _cabangKaryawan,
              karyawanId: _karyawanId,
              karyawanNama: _namaKaryawan,
              hintKey: 'universal_qr_scan_hint',
              profile: {
                'toko_id': _tokoId ?? _cabangKaryawan,
                'role': 'karyawan',
                'id': _karyawanId,
                'nama': _namaKaryawan,
                'nik': _nikKaryawan,
              },
            );
            if (mounted) unawaited(_loadTokoAntrian());
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.qr_code_scanner_rounded,
              color: OptikKaryawanTokens.ink, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 9,
          color: OptikKaryawanTokens.snow,
          elevation: 18,
          shadowColor: OptikKaryawanTokens.ink.withOpacity(0.10),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 72,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                    child: _buildNavItem(
                        Icons.home_rounded, "nav_beranda".tr(), 0)),
                Expanded(
                    child: _buildNavItem(
                        Icons.fact_check_rounded, "nav_sop".tr(), 1)),
                const SizedBox(width: 54),
                Expanded(
                    child: _buildNavItem(
                        Icons.headset_mic_rounded, "nav_bantuan".tr(), 3)),
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
    final targetPage = index == 3 ? index : index;
    final isSelected = _currentIndex == targetPage && index != 3;
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
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isSelected
              ? OptikKaryawanTokens.cyan.withOpacity(0.12)
              : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: _adaUpdateBaru && label == "nav_profil".tr(),
              backgroundColor: OptikKaryawanTokens.danger,
              smallSize: 10,
              child: Icon(
                icon,
                color: isSelected
                    ? OptikKaryawanTokens.cyan
                    : OptikKaryawanTokens.muted.withOpacity(0.55),
                size: isSelected ? 26 : 22,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected
                    ? OptikKaryawanTokens.ink
                    : OptikKaryawanTokens.muted.withOpacity(0.55),
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: OptikKaryawanTokens.authBgGradient,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -110,
            right: -70,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      OptikKaryawanTokens.cyan.withOpacity(0.36),
                      OptikKaryawanTokens.cyan.withOpacity(0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 260,
            left: -90,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikKaryawanTokens.pale.withOpacity(0.48),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikKaryawanTokens.cyan.withOpacity(0.10),
                ),
              ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      20, 10, 20, 28 + _fabBottomPad(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 520),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 14 * (1 - t)),
                            child: child,
                          ),
                        ),
                        child: _buildHomeHero(),
                      ),
                      const SizedBox(height: 18),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 640),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 18 * (1 - t)),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: _todayPanelKey,
                          child: _buildTodayCommandPanel(),
                        ),
                      ),
                      if (_pengumuman.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildPengumumanBanner(),
                      ],
                      const SizedBox(height: 22),
                      _buildQuickShortcuts(),
                      const SizedBox(height: 22),
                      KeyedSubtree(
                        key: _antrianSectionKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel('antrian_home_judul'.tr()),
                            const SizedBox(height: 10),
                            _buildTokoAntrianCard(),
                          ],
                        ),
                      ),
                      if (_showLabQueue) ...[
                        const SizedBox(height: 22),
                        KeyedSubtree(
                          key: _labSectionKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('lab_queue_judul'.tr()),
                              const SizedBox(height: 10),
                              _buildLabQueueCard(),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      KeyedSubtree(
                        key: _sopSectionKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel('home_sop_judul'.tr()),
                            const SizedBox(height: 10),
                            _buildSopHariIniCard(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _sectionLabel('home_pengajuan_judul'.tr()),
                      const SizedBox(height: 10),
                      _buildPengajuanCard(),
                      if (_showChecklistBukaTutup) ...[
                        const SizedBox(height: 18),
                        _sectionLabel('home_checklist_judul'.tr()),
                        const SizedBox(height: 10),
                        _buildChecklistBukaTutupCard(),
                      ],
                      const SizedBox(height: 22),
                      _buildMetricTwinRow(),
                      const SizedBox(height: 22),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('jadwal_mingguan_judul'.tr()),
                          const SizedBox(height: 2),
                          Text(
                            'home_shift_minggu_ini'.tr(),
                            style: TextStyle(
                              fontSize: 12,
                              color: OptikKaryawanTokens.muted
                                  .withOpacity(0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 132,
                        child: ListView.builder(
                          clipBehavior: Clip.none,
                          scrollDirection: Axis.horizontal,
                          itemCount: _jadwalMingguIni.length,
                          itemBuilder: (context, index) {
                            final jadwal = _jadwalMingguIni[index];
                            final shiftRaw = jadwal['shift'] ?? '-';
                            final shift =
                                KaryawanI18nDisplay.shiftLabel(shiftRaw);
                            final isLibur =
                                shiftRaw.toLowerCase().contains('libur') ||
                                    shiftRaw.contains("shift_libur".tr()) ||
                                    shift == 'jadwal_libur'.tr();
                            final isToday =
                                jadwal['date_key'] ==
                                    _jadwalHariIni?['date_key'];
                            return GestureDetector(
                              onTap: () => _tampilkanDetailJadwal(jadwal),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: 118,
                                margin: const EdgeInsets.only(
                                    right: 10, bottom: 4),
                                padding: const EdgeInsets.all(
                                    OptikKaryawanTokens.spaceMd),
                                decoration: BoxDecoration(
                                  color: isLibur
                                      ? const Color(0xFFFFF5F5)
                                      : isToday
                                          ? OptikKaryawanTokens.cyan
                                              .withOpacity(0.14)
                                          : OptikKaryawanTokens.snow
                                              .withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(
                                      OptikKaryawanTokens.radiusLg),
                                  border: Border.all(
                                    color: isLibur
                                        ? Colors.red.shade100
                                        : isToday
                                            ? OptikKaryawanTokens.cyan
                                                .withOpacity(0.50)
                                            : OptikKaryawanTokens.cyan
                                                .withOpacity(0.18),
                                    width: isToday ? 1.3 : 1,
                                  ),
                                  boxShadow: OptikKaryawanTokens.cardShadow,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      KaryawanI18nDisplay.hariLabel(
                                        jadwal['hari'] ?? '',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: isLibur
                                            ? Colors.red.shade700
                                            : OptikKaryawanTokens.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      KaryawanI18nDisplay.tanggalLabel(
                                        dateKey: jadwal['date_key'],
                                        fallback: jadwal['tanggal'],
                                        locale: context.locale,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: OptikKaryawanTokens.muted
                                            .withOpacity(0.9),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      shift,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isLibur
                                            ? Colors.red.shade700
                                            : OptikKaryawanTokens.ink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===== Home HP helpers (fitur 1–7) — premium mobile layout =====

  bool get _showChecklistBukaTutup {
    final j = KaryawanJabatan.normalize(_jabatanKaryawan);
    return j == 'frontliner' ||
        j == 'backliner' ||
        j == 'kepala toko' ||
        j == 'kepala area' ||
        j == 'kasir';
  }

  List<Map<String, dynamic>> get _checklistBukaTutup {
    bool match(String judul) {
      final t = judul.toLowerCase();
      return t.contains('buka') ||
          t.contains('tutup') ||
          t.contains('pagi') ||
          t.contains('malam') ||
          t.contains('etalase') ||
          t.contains('briefing');
    }

    final matched =
        _daftarSOPTugas.where((e) => match('${e['tugas']}')).toList();
    if (matched.isNotEmpty) return matched.take(4).toList();
    return _daftarSOPTugas.take(4).toList();
  }

  Future<void> _bukaPengajuanJadwal() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PengajuanJadwalPage()),
    );
    if (mounted) unawaited(_tarikDataProfil());
  }

  Future<void> _bukaAbsensi() async {
    if (!TenantModules.instance.allows('attendance')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('absensi_modul_off'.tr()),
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AbsensiPage()),
    );
    if (mounted) unawaited(_tarikDataProfil());
  }

  Future<void> _bukaPengaduan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PengaduanPage()),
    );
  }

  Future<void> _bukaPengingat() async {
    final result = await Navigator.push<PengingatNavResult>(
      context,
      MaterialPageRoute(builder: (_) => const PengingatPage()),
    );
    if (!mounted || result == null) return;
    await _applyPengingatNav(result);
  }

  Future<void> _applyPengingatNav(PengingatNavResult result) async {
    setState(() => _currentIndex = 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    switch (result.dest) {
      case PengingatDest.lab:
        await _loadLabQueue();
        if (!mounted) return;
        _scrollToKey(_labSectionKey);
        break;
      case PengingatDest.sop:
        _scrollToKey(_sopSectionKey);
        break;
      case PengingatDest.shift:
        _scrollToKey(_todayPanelKey);
        final j = _jadwalHariIni;
        if (j != null) {
          await Future<void>.delayed(const Duration(milliseconds: 280));
          if (!mounted) return;
          _tampilkanDetailJadwal(j);
        }
        break;
      case PengingatDest.home:
        break;
    }
  }

  void _scrollToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _bukaDetailPribadi() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DetailDataPribadiPage()),
    );
  }

  Future<void> _hubungiPusat() async {
    try {
      await openAdminWhatsApp(
        client: Supabase.instance.client,
        message:
            'Halo Admin ${BrandService.name}, saya $_namaKaryawan ($_cabangKaryawan) butuh bantuan.',
      );
    } catch (e) {
      if (!mounted) return;
      _showPremiumSnackbar('WhatsApp', '$e', Colors.redAccent);
    }
  }

  String _fmtJam(DateTime? dt) {
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _labelAbsenStatus() {
    switch (_absenStatus) {
      case 'sedang_bekerja':
        return 'home_absen_sedang'.tr();
      case 'selesai':
        return 'home_absen_selesai'.tr();
      case 'libur':
        return 'home_absen_libur'.tr();
      default:
        return 'home_absen_belum'.tr();
    }
  }

  Color _warnaAbsenStatus() {
    switch (_absenStatus) {
      case 'sedang_bekerja':
        return OptikKaryawanTokens.cyan;
      case 'selesai':
        return OptikKaryawanTokens.success;
      case 'libur':
        return Colors.orange.shade700;
      default:
        return OptikKaryawanTokens.ink;
    }
  }

  String _labelPengajuanStatus(String raw) {
    switch (raw.toUpperCase()) {
      case 'APPROVED':
        return 'home_pengajuan_ok'.tr();
      case 'REJECTED':
        return 'home_pengajuan_tolak'.tr();
      case 'CANCELLED':
        return 'home_pengajuan_batal'.tr();
      default:
        return 'home_pengajuan_tunggu'.tr();
    }
  }

  String _shiftCountdownText() {
    final shift = (_jadwalHariIni?['shift'] ?? '').trim();
    if (shift.toLowerCase().contains('libur')) {
      return 'home_absen_libur_desc'.tr();
    }
    if (shift.isEmpty || shift.contains('Belum')) {
      return 'home_shift_kosong'.tr();
    }
    final parts = shift.split('-');
    if (parts.length < 2) return shift;
    final startParts = parts[0].split(':');
    if (startParts.length < 2) return shift;
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
      int.tryParse(startParts[0]) ?? 0,
      int.tryParse(startParts[1]) ?? 0,
    );
    final endParts = parts[1].split(':');
    final end = DateTime(
      now.year,
      now.month,
      now.day,
      int.tryParse(endParts.isNotEmpty ? endParts[0] : '0') ?? 0,
      int.tryParse(endParts.length > 1 ? endParts[1] : '0') ?? 0,
    );
    if (_absenStatus == 'selesai' || now.isAfter(end)) {
      return 'home_shift_selesai_hari'.tr();
    }
    if (now.isBefore(start)) {
      final m = start.difference(now).inMinutes;
      if (m >= 60) {
        return 'home_shift_mulai_jam'.tr(args: ['${m ~/ 60}', '${m % 60}']);
      }
      return 'home_shift_mulai_menit'.tr(args: ['$m']);
    }
    return 'home_shift_berjalan'.tr();
  }

  Widget _sectionLabel(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: OptikKaryawanTokens.ink,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _softSurface({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(OptikKaryawanTokens.spaceMd),
    VoidCallback? onTap,
    bool emphasize = false,
  }) {
    final radius = BorderRadius.circular(
      emphasize ? OptikKaryawanTokens.radiusXl : OptikKaryawanTokens.radiusLg,
    );
    final body = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                OptikKaryawanTokens.snow.withOpacity(emphasize ? 0.96 : 0.92),
                OptikKaryawanTokens.cyan.withOpacity(emphasize ? 0.12 : 0.07),
                OptikKaryawanTokens.snow.withOpacity(0.94),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            border: Border.all(
              color: OptikKaryawanTokens.cyan
                  .withOpacity(emphasize ? 0.32 : 0.18),
            ),
            boxShadow: OptikKaryawanTokens.cardShadow,
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: body,
      ),
    );
  }

  Widget _buildHomeHero() {
    final firstName = _namaKaryawan.split(' ').first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: OptikKaryawanTokens.cyan.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: OptikKaryawanTokens.cyan.withOpacity(0.28),
                  ),
                ),
                child: Text(
                  'home_employee_desk'.tr(),
                  style: TextStyle(
                    color: OptikKaryawanTokens.ink.withOpacity(0.78),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                // Translations already include trailing punctuation (e.g. "Halo, ").
                "${'dash_halo'.tr()}$firstName",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: OptikKaryawanTokens.muted.withOpacity(0.95),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _jabatanKaryawan.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  color: OptikKaryawanTokens.ink,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.9,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.storefront_rounded,
                      size: 14,
                      color: OptikKaryawanTokens.cyan.withOpacity(0.95)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _cabangKaryawan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: OptikKaryawanTokens.ink.withOpacity(0.72),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: OptikKaryawanTokens.accentGradient,
            boxShadow: [
              BoxShadow(
                color: OptikKaryawanTokens.cyan.withOpacity(0.34),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 30,
            backgroundColor: OptikKaryawanTokens.pale,
            backgroundImage: _fotoProfileUrl != null
                ? NetworkImage(_fotoProfileUrl!)
                : null,
            child: _fotoProfileUrl == null
                ? const Icon(Icons.person_rounded,
                    size: 30, color: OptikKaryawanTokens.ink)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildTodayCommandPanel() {
    final shiftRaw = (_jadwalHariIni?['shift'] ?? '').trim();
    final shift = shiftRaw.isEmpty
        ? 'home_shift_kosong'.tr()
        : KaryawanI18nDisplay.shiftLabel(shiftRaw);
    final isLibur = shiftRaw.toLowerCase().contains('libur');
    final hariRaw = (_jadwalHariIni?['hari'] ?? '').trim();
    final hari = hariRaw.isEmpty
        ? 'home_hari_ini'.tr()
        : KaryawanI18nDisplay.hariLabel(hariRaw);
    final tgl = KaryawanI18nDisplay.tanggalLabel(
      dateKey: _jadwalHariIni?['date_key'],
      fallback: _jadwalHariIni?['tanggal'] ?? '',
      locale: context.locale,
    );
    final hasOpenAbsen = _absenStatus == 'sedang_bekerja';
    final ctaLabel = isLibur && !hasOpenAbsen
        ? 'home_cta_lihat_absen'.tr()
        : _absenStatus == 'belum_masuk'
            ? 'home_cta_absen_masuk'.tr()
            : _absenStatus == 'sedang_bekerja'
                ? 'home_cta_absen_pulang'.tr()
                : 'home_cta_lihat_absen'.tr();

    return _softSurface(
      emphasize: true,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isLibur ? Colors.red : OptikKaryawanTokens.cyan)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'home_shift_hari_ini'.tr().toUpperCase(),
                  style: TextStyle(
                    color: isLibur
                        ? Colors.red.shade700
                        : OptikKaryawanTokens.ink.withOpacity(0.78),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.15,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$hari${tgl.isEmpty ? '' : ' · $tgl'}',
                style: TextStyle(
                  color: OptikKaryawanTokens.muted.withOpacity(0.9),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            isLibur ? 'home_absen_libur'.tr() : shift,
            style: GoogleFonts.fraunces(
              color: isLibur ? const Color(0xFFC62828) : OptikKaryawanTokens.ink,
              fontSize: isLibur ? 38 : 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.2,
              height: 1.02,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isLibur
                ? 'home_absen_libur_desc'.tr()
                : _shiftCountdownText(),
            style: TextStyle(
              color: OptikKaryawanTokens.muted.withOpacity(0.95),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (!isLibur || hasOpenAbsen) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: OptikKaryawanTokens.snow.withOpacity(0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: OptikKaryawanTokens.cyan.withOpacity(0.14),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          OptikKaryawanTokens.cyan.withOpacity(0.28),
                          OptikKaryawanTokens.cyan.withOpacity(0.10),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.fingerprint_rounded,
                      color: _warnaAbsenStatus(),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _labelAbsenStatus(),
                          style: TextStyle(
                            color: _warnaAbsenStatus(),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${'home_absen_masuk'.tr()} ${_fmtJam(_absenMasukAt)}  ·  ${'home_absen_pulang'.tr()} ${_fmtJam(_absenPulangAt)}',
                          style: TextStyle(
                            color: OptikKaryawanTokens.muted.withOpacity(0.9),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: OptikKaryawanTokens.accentGradient,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: OptikKaryawanTokens.cyan.withOpacity(0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: _bukaAbsensi,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: OptikKaryawanTokens.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  ctaLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPengumumanBanner() {
    final p = _pengumuman.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: OptikKaryawanTokens.cyan.withOpacity(0.10),
            border: Border.all(
              color: OptikKaryawanTokens.cyan.withOpacity(0.22),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: OptikKaryawanTokens.cyan.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.campaign_rounded,
                    size: 17, color: OptikKaryawanTokens.ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home_pengumuman'.tr(),
                      style: TextStyle(
                        color: OptikKaryawanTokens.muted.withOpacity(0.95),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      KaryawanI18nDisplay.pengumumanJudul(
                        p['judul']?.toString(),
                      ),
                      style: const TextStyle(
                        color: OptikKaryawanTokens.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      KaryawanI18nDisplay.pengumumanIsi(p['isi']?.toString()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: OptikKaryawanTokens.ink.withOpacity(0.72),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSopHariIniCard() {
    final sc = _sopScore;
    final branch = _sopBranch;
    final poin = sc?.poin;
    final story = branch?.storyCount ?? 0;
    final fatal = sc?.fatalStory == true;
    return _softSurface(
      onTap: () => setState(() => _currentIndex = 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  poin == null
                      ? 'home_sop_kosong'.tr()
                      : 'home_sop_score'.tr(namedArgs: {
                          'poin': poin >= 0 ? '+$poin' : '$poin',
                          'story': '$story',
                          'target': '${SopScore.storyTarget}',
                        }),
                  style: const TextStyle(
                    color: OptikKaryawanTokens.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: OptikKaryawanTokens.muted.withOpacity(0.7)),
            ],
          ),
          if (fatal) ...[
            const SizedBox(height: 8),
            Text(
              'sop_score_fatal'.tr(),
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPengajuanCard() {
    final pending = _pengajuanTerbaru
        .where((e) => '${e['status']}'.toUpperCase() == 'PENDING')
        .length;
    final rows = _pengajuanTerbaru.take(2).toList();
    return _softSurface(
      onTap: _bukaPengajuanJadwal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rows.isEmpty
                      ? 'home_pengajuan_kosong'.tr()
                      : 'home_pengajuan_judul'.tr(),
                  style: const TextStyle(
                    color: OptikKaryawanTokens.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (pending > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'home_pengajuan_badge'.tr(args: ['$pending']),
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...rows.map((r) {
              final status = '${r['status'] ?? 'PENDING'}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${KaryawanI18nDisplay.pengajuanTipe(r['tipe']?.toString())} · ${r['tanggal'] ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: OptikKaryawanTokens.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _labelPengajuanStatus(status),
                      style: TextStyle(
                        color: status.toUpperCase() == 'APPROVED'
                            ? OptikKaryawanTokens.success
                            : status.toUpperCase() == 'REJECTED'
                                ? Colors.redAccent
                                : Colors.orange.shade800,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildTokoAntrianCard() {
    final n = _antrianItems.length;
    final preview = _antrianItems.take(3).toList();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusXl),
        onTap: _openTokoAntrianPage,
        child: _softSurface(
          emphasize: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: OptikKaryawanTokens.navyGradient,
                      borderRadius:
                          BorderRadius.circular(OptikKaryawanTokens.radiusSm),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: OptikKaryawanTokens.ink,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      n == 0
                          ? 'antrian_home_kosong'.tr()
                          : 'antrian_home_count'
                              .tr(namedArgs: {'count': '$n'}),
                      style: GoogleFonts.fraunces(
                        color: OptikKaryawanTokens.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (n > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: OptikKaryawanTokens.ink,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$n',
                        style: const TextStyle(
                          color: OptikKaryawanTokens.snow,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: OptikKaryawanTokens.muted.withOpacity(0.7),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'antrian_home_desc'.tr(),
                style: TextStyle(
                  color: OptikKaryawanTokens.muted.withOpacity(0.95),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...preview.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: OptikKaryawanTokens.cyan,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: OptikKaryawanTokens.ink.withOpacity(0.88),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    UniversalQrNav.open(
                      context,
                      callerRole: UniversalQrCallerRole.karyawan,
                      cabangKaryawan: _cabangKaryawan,
                      karyawanId: _karyawanId,
                      karyawanNama: _namaKaryawan,
                      profile: {
                        'toko_id': _tokoId ?? _cabangKaryawan,
                        'role': 'karyawan',
                        'id': _karyawanId,
                        'nama': _namaKaryawan,
                        'nik': _nikKaryawan,
                      },
                    ).then((_) {
                      if (mounted) unawaited(_loadTokoAntrian());
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OptikKaryawanTokens.ink,
                    side: BorderSide(
                      color: OptikKaryawanTokens.cyan.withOpacity(0.55),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(OptikKaryawanTokens.radiusMd),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(
                    'scan_qr_universal'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabQueueCard() {
    final open = _labOpenJobs.take(4).toList();
    final mine = _labMineJobs.take(3).toList();
    if (open.isEmpty && mine.isEmpty) {
      return _softSurface(
        child: Text(
          'lab_queue_kosong'.tr(),
          style: TextStyle(
            color: OptikKaryawanTokens.muted.withOpacity(0.95),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return _softSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'lab_queue_desc'.tr(),
            style: TextStyle(
              color: OptikKaryawanTokens.muted.withOpacity(0.95),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (mine.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'lab_queue_mine'.tr(),
              style: const TextStyle(
                color: OptikKaryawanTokens.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            ...mine.map((j) => _labJobTile(j, mine: true)),
          ],
          if (open.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'lab_queue_open'.tr(args: ['${_labOpenJobs.length}']),
              style: const TextStyle(
                color: OptikKaryawanTokens.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            ...open.map((j) => _labJobTile(j, mine: false)),
          ],
        ],
      ),
    );
  }

  Widget _labJobTile(Map<String, dynamic> job, {required bool mine}) {
    final inv = job['no_invoice']?.toString() ?? '-';
    final qty = job['unit_qty']?.toString() ?? '1';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inv,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: OptikKaryawanTokens.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mine
                      ? 'lab_queue_mine_sub'.tr(args: [qty])
                      : 'lab_queue_open_sub'.tr(args: [qty]),
                  style: TextStyle(
                    color: OptikKaryawanTokens.muted.withOpacity(0.95),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!mine)
            FilledButton(
              onPressed: _labBusy ? null : () => _claimLabJob(job),
              style: FilledButton.styleFrom(
                backgroundColor: OptikKaryawanTokens.cyan,
                foregroundColor: OptikKaryawanTokens.ink,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(OptikKaryawanTokens.radiusSm),
                ),
              ),
              child: Text(
                'lab_queue_btn_kerjakan'.tr(),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            FilledButton(
              onPressed: _labBusy ? null : () => _completeLabJob(job),
              style: FilledButton.styleFrom(
                backgroundColor: OptikKaryawanTokens.seasideMid,
                foregroundColor: OptikKaryawanTokens.ink,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(OptikKaryawanTokens.radiusSm),
                ),
              ),
              child: Text(
                'lab_queue_btn_selesai'.tr(),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickShortcuts() {
    final items = [
      (Icons.warning_amber_rounded, 'home_shortcut_pengaduan'.tr(),
          _bukaPengaduan),
      (Icons.support_agent_rounded, 'home_shortcut_hubungi'.tr(),
          _hubungiPusat),
      (Icons.notifications_active_rounded, 'home_shortcut_pengingat'.tr(),
          _bukaPengingat),
      (Icons.badge_outlined, 'home_shortcut_profil'.tr(), _bukaDetailPribadi),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('home_shortcut_judul'.tr()),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                        OptikKaryawanTokens.radiusLg),
                    onTap: items[i].$3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                          OptikKaryawanTokens.radiusLg),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Ink(
                          height: 78,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                OptikKaryawanTokens.radiusLg),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                OptikKaryawanTokens.snow.withOpacity(0.94),
                                OptikKaryawanTokens.cyan.withOpacity(0.12),
                              ],
                            ),
                            border: Border.all(
                              color:
                                  OptikKaryawanTokens.cyan.withOpacity(0.20),
                            ),
                            boxShadow: OptikKaryawanTokens.cardShadow,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: OptikKaryawanTokens.cyan
                                      .withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(
                                      OptikKaryawanTokens.radiusSm),
                                ),
                                child: Icon(items[i].$1,
                                    color: OptikKaryawanTokens.ink, size: 18),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                items[i].$2,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: OptikKaryawanTokens.ink,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildChecklistBukaTutupCard() {
    final items = _checklistBukaTutup;
    return _softSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'home_checklist_desc'.tr(),
                  style: TextStyle(
                    color: OptikKaryawanTokens.muted.withOpacity(0.95),
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentIndex = 1),
                style: TextButton.styleFrom(
                  foregroundColor: OptikKaryawanTokens.ink,
                  backgroundColor: OptikKaryawanTokens.cyan.withOpacity(0.14),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'home_checklist_buka_sop'.tr(),
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              'home_checklist_kosong'.tr(),
              style: TextStyle(
                color: OptikKaryawanTokens.muted.withOpacity(0.9),
                fontSize: 12.5,
              ),
            )
          else
            ...items.map((t) {
              final done = t['selesai'] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 18,
                      color: done
                          ? OptikKaryawanTokens.cyan
                          : OptikKaryawanTokens.muted.withOpacity(0.65),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        KaryawanI18nDisplay.sopTugas(t['tugas']?.toString()),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: OptikKaryawanTokens.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Banner KPI — eskalasi premium per level.
  /// L1 matte → L2 clean → L3 gold → L4 elite → L5 max. Api PNG solid.
  Widget _buildMetricTwinRow() {
    final fire = _kpiFire.fire;
    final progress = _kpiFire.progress;
    final lv = fire.level.clamp(0, 5);

    final pal = StreakFireFlame.levelPalette(lv <= 0 ? 1 : lv);
    final tip = lv <= 0 ? const Color(0xFF8AA0A8) : pal.top;
    final tipDeep = Color.lerp(tip, const Color(0xFF0C0408), 0.38) ?? tip;

    final kpiPct = (progress * 100).round();
    final fairPct = (_kpiFire.fairShare * 100).round();
    final aktualPct = (_kpiFire.aktualPct * 100).round();
    final layerLabel = _kpiFire.layer == OfficeLayer.back
        ? 'kpi_layer_back'.tr()
        : 'kpi_layer_front'.tr();
    final fairLine = _kpiFire.peerCount > 0
        ? 'kpi_balance_sub'.tr(args: ['$aktualPct', '$fairPct', layerLabel])
        : 'kpi_balance_sub_empty'.tr();
    final fireLine = fire.level == 0
        ? fire.labelKey.tr()
        : '${fire.labelKey.tr()} · ${'kpi_fire_level'.tr(args: ['${fire.fifth}'])}';

    const ink = OptikKaryawanTokens.ink;
    final snow = OptikKaryawanTokens.snow;
    // L1 soft-light (teks gelap) · L2+ saturated (teks terang).
    final lit = lv >= 2;

    // Identitas beda per tier (L1 & L5 sudah OK — jangan digoyang).
    // L2: clean mid · L3: gold jewelry · L4: pre-peak night · L5: MAX
    final showSheen = lv >= 3;
    final showOrbLeft = lv >= 3;
    final showOrbRight = lv >= 4;
    final showRail = lv >= 3;
    final showOuterRing = lv >= 4;
    final showPeakBadge = lv >= 5;
    final showEliteBadge = lv == 4; // penanda kelas sebelum MAX
    final showGoldMark = lv == 3;
    final showInnerStroke = lv >= 3;
    final cornerR = switch (lv) {
      1 => 18.0,
      2 => 20.0,
      3 => 22.0,
      4 => 25.0,
      5 => 28.0,
      _ => 18.0,
    };
    final radius = BorderRadius.circular(cornerR);
    final borderW = switch (lv) {
      1 => 1.0,
      2 => 1.15,
      3 => 1.55,
      4 => 1.7,
      5 => 1.8,
      _ => 1.0,
    };
    final railW = switch (lv) {
      3 => 4.0,
      4 => 4.6,
      5 => 5.0,
      _ => 0.0,
    };
    final flameSize = switch (lv) {
      1 => 26.0,
      2 => 27.0,
      3 => 30.0,
      4 => 31.5,
      5 => 32.0,
      _ => 26.0,
    };
    final ptsSize = switch (lv) {
      1 => 26.0,
      2 => 27.0,
      3 => 30.0,
      4 => 32.0,
      5 => 33.0,
      _ => 26.0,
    };
    final barH = switch (lv) {
      1 => 5.0,
      2 => 5.5,
      3 => 6.5,
      4 => 7.2,
      5 => 7.5,
      _ => 5.0,
    };
    final shadowDepth = switch (lv) {
      1 => 0.05,
      2 => 0.07,
      3 => 0.14,
      4 => 0.20,
      5 => 0.22,
      _ => 0.05,
    };
    final glowStr = switch (lv) {
      1 => 0.0,
      2 => 0.06,
      3 => 0.24,
      4 => 0.34,
      5 => 0.38,
      _ => 0.0,
    };

    late final List<Color> bodyColors;
    late final Color borderColor;
    late final Color orbA;
    late final Color orbB;
    late final Color fillBar;
    switch (lv) {
      case 1: // Soft matte — sudah OK
        bodyColors = const [
          Color(0xFFFFF1EE),
          Color(0xFFFFD2C8),
          Color(0xFFF2A89A),
        ];
        borderColor = const Color(0x55C62828);
        orbA = const Color(0xFFE57373);
        orbB = orbA;
        fillBar = const Color(0xFFD32F2F);
      case 2: // Clean mid — flat 2-tone, tanpa ornament mewah
        bodyColors = const [
          Color(0xFFFF9800),
          Color(0xFFEF6C00),
        ];
        borderColor = const Color(0x66FFFFFF);
        orbA = const Color(0xFFFFB74D);
        orbB = orbA;
        fillBar = const Color(0xFFFFE0B2);
      case 3: // Gold jewelry — metal dalam, beda jelas dari L2
        bodyColors = const [
          Color(0xFFFFE082),
          Color(0xFFC9A227),
          Color(0xFF4A3608),
        ];
        borderColor = const Color(0xEEFFE082);
        orbA = const Color(0xFFFFF59D);
        orbB = const Color(0xFFFFF8E1);
        fillBar = const Color(0xFFFFECB3);
      case 4: // Pre-peak night magenta — gelap, hampir L5
        bodyColors = const [
          Color(0xFF9C1258),
          Color(0xFF5A0A36),
          Color(0xFF1A0612),
        ];
        borderColor = const Color(0xDDF8BBD0);
        orbA = const Color(0xFFFF80AB);
        orbB = const Color(0xFFFFCDD2);
        fillBar = const Color(0xFFF8BBD0);
      case 5: // Peak night — sudah OK, jangan diubah
        bodyColors = const [
          Color(0xFF4A2080),
          Color(0xFF2A1058),
          Color(0xFF0E061C),
        ];
        borderColor = const Color(0xE6E0C8FF);
        orbA = const Color(0xFFD2B4FF);
        orbB = const Color(0xFFF0E0FF);
        fillBar = const Color(0xFFE8D4FF);
      default:
        bodyColors = [snow, const Color(0xFFF5FAFB)];
        borderColor = OptikKaryawanTokens.lineStrong;
        orbA = tip;
        orbB = tip;
        fillBar = tip;
    }

    final titleC = !lit
        ? ink.withOpacity(lv <= 1 ? 0.48 : 0.55)
        : Colors.white.withOpacity(lv == 2 ? 0.72 : 0.78);
    final valueC = !lit ? ink : Colors.white;
    final metaC = !lit
        ? ink.withOpacity(0.62)
        : Colors.white.withOpacity(0.82);
    final historyC = !lit
        ? ink.withOpacity(0.38)
        : Colors.white.withOpacity(0.52);
    final trackC = !lit
        ? ink.withOpacity(0.08)
        : Colors.white.withOpacity(lv == 2 ? 0.16 : 0.20);

    return Material(
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        splashColor: Colors.white.withOpacity(0.08),
        highlightColor: Colors.transparent,
        onTap: _showFireHistorySheet,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: bodyColors,
              stops: bodyColors.length == 2
                  ? const [0.0, 1.0]
                  : const [0.0, 0.46, 1.0],
            ),
            border: Border.all(color: borderColor, width: borderW),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(shadowDepth),
                blurRadius: 12.0 + lv * 4,
                spreadRadius: -3,
                offset: Offset(0, 6.0 + lv * 1.2),
              ),
              if (glowStr > 0)
                BoxShadow(
                  color: orbA.withOpacity(glowStr),
                  blurRadius: 16.0 + lv * 5,
                  spreadRadius: -6,
                  offset: Offset(0, 8.0 + lv),
                ),
              if (lv >= 5)
                BoxShadow(
                  color: const Color(0xFFB388FF).withOpacity(0.35),
                  blurRadius: 36,
                  spreadRadius: -4,
                  offset: const Offset(0, 14),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                if (showInnerStroke)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(cornerR - 3),
                            border: Border.all(
                              color: Colors.white.withOpacity(
                                  lv >= 5 ? 0.22 : 0.14),
                              width: lv >= 5 ? 1.1 : 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showSheen)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 28.0 + lv * 4,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.06 + lv * 0.025),
                              Colors.white.withOpacity(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showOrbLeft)
                  Positioned(
                    left: -30,
                    top: -34,
                    child: IgnorePointer(
                      child: Container(
                        width: 100 + lv * 12,
                        height: 100 + lv * 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              orbA.withOpacity(0.20 + lv * 0.05),
                              orbA.withOpacity(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showOrbRight)
                  Positioned(
                    right: -32,
                    bottom: -40,
                    child: IgnorePointer(
                      child: Container(
                        width: 130 + lv * 8,
                        height: 130 + lv * 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              orbB.withOpacity(lv >= 5 ? 0.32 : 0.20),
                              orbB.withOpacity(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showRail)
                  Positioned(
                    left: 0,
                    top: 14,
                    bottom: 14,
                    width: railW,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(99),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: lv == 3
                                ? const [
                                    Color(0xFFFFF6D0),
                                    Color(0xFFE0B43A),
                                    Color(0xFF6B4E0E),
                                  ]
                                : lv >= 5
                                    ? const [
                                        Color(0xFFF0E0FF),
                                        Color(0xFFB48CFF),
                                        Color(0xFF3A1870),
                                      ]
                                    : [
                                        Colors.white.withOpacity(0.70),
                                        orbA,
                                        tipDeep,
                                      ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14 + (showRail ? railW : 0),
                    15,
                    10,
                    14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 52 + lv * 1.5,
                            height: 52 + lv * 1.5,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (showOuterRing)
                                  IgnorePointer(
                                    child: Container(
                                      width: 50 + lv.toDouble(),
                                      height: 50 + lv.toDouble(),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withOpacity(
                                              lv >= 5 ? 0.35 : 0.22),
                                          width: lv >= 5 ? 1.4 : 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (lv >= 2)
                                  IgnorePointer(
                                    child: Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(
                                          colors: [
                                            orbA.withOpacity(
                                                0.18 + lv * 0.05),
                                            orbA.withOpacity(0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                IgnorePointer(
                                  child: Container(
                                    width: lv <= 1 ? 40 : 42,
                                    height: lv <= 1 ? 40 : 42,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: !lit
                                          ? snow.withOpacity(0.85)
                                          : Colors.white.withOpacity(0.12),
                                      border: Border.all(
                                        color: !lit
                                            ? tip.withOpacity(0.35)
                                            : Colors.white.withOpacity(0.42),
                                        width: lv <= 1 ? 1.0 : 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                                StreakFireFlame(
                                  fire: fire,
                                  size: flameSize,
                                  solid: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'kpi_banner_judul'.tr().toUpperCase(),
                                        style: TextStyle(
                                          color: titleC,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: switch (lv) {
                                            2 => 0.7,
                                            3 => 1.0,
                                            4 => 1.15,
                                            5 => 1.25,
                                            _ => 0.6,
                                          },
                                        ),
                                      ),
                                    ),
                                    if (showGoldMark)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFFFF8E1),
                                              Color(0xFFE0B43A),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(99),
                                          border: Border.all(
                                            color: const Color(0xFFFFF59D)
                                                .withOpacity(0.8),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFE0B43A)
                                                  .withOpacity(0.40),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          'kpi_badge_gold'.tr(),
                                          style: const TextStyle(
                                            color: Color(0xFF3A2808),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.7,
                                          ),
                                        ),
                                      ),
                                    if (showEliteBadge)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFFFE0EC),
                                              Color(0xFFFF80AB),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(99),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFF80AB)
                                                  .withOpacity(0.45),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          'kpi_badge_elite'.tr(),
                                          style: const TextStyle(
                                            color: Color(0xFF4A0A28),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.7,
                                          ),
                                        ),
                                      ),
                                    if (showPeakBadge)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFF0E0FF),
                                              Color(0xFFB48CFF),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(99),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFB48CFF)
                                                  .withOpacity(0.45),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          'kpi_badge_max'.tr(),
                                          style: const TextStyle(
                                            color: Color(0xFF2A1058),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                // Poin & level 1 sumber: _kpiFire.totalPoin.
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${_kpiFire.totalPoin}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.fraunces(
                                          color: valueC,
                                          fontSize: ptsSize,
                                          fontWeight: FontWeight.w700,
                                          height: 1.0,
                                          letterSpacing: -1.0,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 3),
                                      child: Text(
                                        'kpi_banner_pts'.tr(),
                                        style: TextStyle(
                                          color: metaC,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: lv <= 1
                                            ? tip.withOpacity(0.14)
                                            : Colors.white.withOpacity(0.22),
                                        borderRadius:
                                            BorderRadius.circular(99),
                                        border: Border.all(
                                          color: lv <= 1
                                              ? tip.withOpacity(0.40)
                                              : Colors.white
                                                  .withOpacity(0.40),
                                        ),
                                      ),
                                      child: Text(
                                        '$kpiPct%',
                                        style: TextStyle(
                                          color: switch (lv) {
                                            1 => tipDeep,
                                            3 => const Color(0xFF3A2808),
                                            4 => const Color(0xFF3E0A28),
                                            5 => const Color(0xFF2A1058),
                                            _ => Colors.white,
                                          },
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            tooltip: 'poin_riwayat_judul'.tr(),
                            onPressed: _tampilkanRiwayatPoin,
                            icon: Icon(
                              Icons.history_rounded,
                              size: 18 + (lv >= 4 ? 2 : 0),
                              color: historyC,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: lv >= 4 ? 13 : 11),
                      Text(
                        fairLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: metaC,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            width: lv >= 4 ? 8 : 6,
                            height: lv >= 4 ? 8 : 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: fillBar,
                              boxShadow: lv >= 3
                                  ? [
                                      BoxShadow(
                                        color: orbA.withOpacity(0.55),
                                        blurRadius: 7,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fireLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: valueC,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (fire.level > 0)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: lv >= 4 ? 9 : 7,
                                vertical: lv >= 4 ? 4 : 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(
                                    lv <= 1 ? 0.10 : 0.14),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: Colors.white.withOpacity(
                                      lv <= 1 ? 0.18 : 0.30),
                                  width: lv >= 5 ? 1.2 : 1.0,
                                ),
                              ),
                              child: Text(
                                '${fire.fifth}/5',
                                style: TextStyle(
                                  color: valueC,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: lv >= 4 ? 13 : 11),
                      StreakFireProgressBar(
                        progress: progress,
                        height: barH,
                        compact: true,
                        trackColor: trackC,
                        fillColor: fillBar,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiBreakdownTile(
    String label,
    String value, {
    bool showDivider = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: OptikKaryawanTokens.border.withOpacity(0.9),
                ),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: OptikKaryawanTokens.muted,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              color: OptikKaryawanTokens.ink,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  void _showFireHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.94,
          minChildSize: 0.5,
          maxChildSize: 0.98,
          builder: (context, scrollController) {
            return _buildKpiDetailPageShell(
              scrollController: scrollController,
              children: _buildKpiDetailSections(),
            );
          },
        );
      },
    );
  }

  void _showKpiYearHistorySheet() {
    final history = _kpiYearHistory;
    final now = DateTime.now();
    final byKey = {
      for (final r in history) r.monthKey: r,
    };
    final minYear = history.isEmpty
        ? now.year
        : history.map((e) => e.year).reduce((a, b) => a < b ? a : b);
    final maxYear = now.year;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var viewYear = maxYear;
        KpiMonthHistoryRecord? selected;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 0.98,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheet) {
                Widget monthCell(int month) {
                  final key =
                      '$viewYear-${month.toString().padLeft(2, '0')}';
                  final rec = byKey[key];
                  final isFuture = viewYear > now.year ||
                      (viewYear == now.year && month > now.month);
                  final isCurrent =
                      viewYear == now.year && month == now.month;
                  final isSelected = selected?.monthKey == key;
                  final fire = rec?.fire ??
                      StreakFireLevel.forKpiProgress(0);
                  final lv = fire.level.clamp(1, 5);
                  final pal = StreakFireFlame.levelPalette(lv);
                  final monthName = DateFormat.MMM(context.locale.toString())
                      .format(DateTime(viewYear, month));
                  final pct = ((rec?.progress ?? 0) * 100).round();

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: isFuture
                          ? null
                          : () => setSheet(() {
                                selected = rec ??
                                    KpiMonthHistoryRecord(
                                      year: viewYear,
                                      month: month,
                                      totalPoin: 0,
                                      pointTarget:
                                          KpiFireSnapshot.monthlyPointTarget,
                                      workDays:
                                          KpiFireSnapshot.fallbackWorkDays,
                                      progress: 0,
                                      fire: fire,
                                    );
                              }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                        decoration: BoxDecoration(
                          color: isFuture
                              ? const Color(0xFFF3F6F7)
                              : (isCurrent || isSelected
                                  ? Color.lerp(
                                      Colors.white, pal.bottom, 0.62)!
                                  : const Color(0xFFF8FBFC)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected || isCurrent
                                ? Color.lerp(pal.top, Colors.white, 0.3)!
                                : OptikKaryawanTokens.border,
                            width: isSelected || isCurrent ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              monthName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isFuture
                                    ? OptikKaryawanTokens.muted
                                        .withOpacity(0.55)
                                    : OptikKaryawanTokens.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Opacity(
                              opacity: isFuture ? 0.28 : 1,
                              child: StreakFireFlame(
                                fire: fire,
                                size: 28,
                                solid: true,
                                muted: isFuture ||
                                    ((rec?.isEmptyMonth ?? true) &&
                                        !isCurrent),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isFuture
                                  ? '—'
                                  : 'kpi_fire_level'.tr(args: ['$lv']),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isFuture
                                    ? OptikKaryawanTokens.muted
                                        .withOpacity(0.5)
                                    : pal.top,
                              ),
                            ),
                            Text(
                              isFuture ? '' : '$pct%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: OptikKaryawanTokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: OptikKaryawanTokens.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'kpi_year_history_title'.tr(),
                        style: GoogleFonts.fraunces(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: OptikKaryawanTokens.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'kpi_year_history_sub'.tr(),
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: OptikKaryawanTokens.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Navigasi tahun
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F7F8),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: OptikKaryawanTokens.border),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: viewYear <= minYear
                                  ? null
                                  : () => setSheet(() {
                                        viewYear -= 1;
                                        selected = null;
                                      }),
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            Expanded(
                              child: Text(
                                '$viewYear',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.fraunces(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: OptikKaryawanTokens.ink,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: viewYear >= maxYear
                                  ? null
                                  : () => setSheet(() {
                                        viewYear += 1;
                                        selected = null;
                                      }),
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Grid kalender 3×4 (Jan–Des)
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.92,
                        children: [
                          for (var m = 1; m <= 12; m++) monthCell(m),
                        ],
                      ),
                      if (selected != null) ...[
                        const SizedBox(height: 16),
                        Builder(
                          builder: (context) {
                            final rec = selected!;
                            final lv = rec.fire.level.clamp(1, 5);
                            final pal =
                                StreakFireFlame.levelPalette(lv);
                            final pct = (rec.progress * 100).round();
                            final label = DateFormat.yMMMM(
                                    context.locale.toString())
                                .format(
                                    DateTime(rec.year, rec.month));
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Color.lerp(
                                    Colors.white, pal.bottom, 0.45)!,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Color.lerp(
                                      pal.top, Colors.white, 0.35)!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  StreakFireFlame(
                                    fire: rec.fire,
                                    size: 34,
                                    solid: true,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          label,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color: OptikKaryawanTokens.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${rec.fire.labelKey.tr()} · ${'kpi_fire_level'.tr(args: ['$lv'])}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: pal.top,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${rec.totalPoin} / ${rec.pointTarget} ${'kpi_banner_pts'.tr()} · $pct%',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                OptikKaryawanTokens.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _loadSopScore() async {
    final kid = (_karyawanId ?? '').trim();
    final toko = (_tokoId ?? '').trim();
    if (kid.isEmpty || toko.isEmpty) return;
    try {
      final jam = _jadwalHariIni?['jam_masuk']?.toString();
      final shift = _jadwalHariIni?['shift']?.toString() ??
          _jadwalHariIni?['keterangan']?.toString();
      final isLibur = (_jadwalHariIni?['status'] ?? '')
              .toString()
              .toLowerCase()
              .contains('libur') ||
          '${_jadwalHariIni?['is_libur']}'.toLowerCase() == 'true' ||
          _absenStatus == 'libur';
      final isAktif = _absenStatus == 'sedang_bekerja' ||
          _absenStatus == 'sudah_pulang' ||
          _absenStatus == 'belum_absen';
      final isPagi = SopScore.isPagiShift(jamMasuk: jam, shiftLabel: shift);
      final branch = await _sopDaily.fetchBranchState(tokoId: toko);
      final score = SopScore.compute(
        SopScoreInput(
          layer: officeLayerOf(_jabatanKaryawan),
          isPagi: isPagi,
          isAktif: isAktif && !isLibur,
          isLibur: isLibur,
          storyCount: branch.storyCount,
          displayDone: branch.displayDone,
          displayRequired: branch.displayRequired,
          stokDone: branch.stokDone,
          sapuDone: branch.sapuDone,
        ),
      );
      if (!mounted) return;
      setState(() {
        _sopBranch = branch;
        _sopScore = score;
        _sopIsPagi = isPagi;
      });
    } catch (e) {
      debugPrint('sop score: $e');
    }
  }

  Future<void> _runSopAction(Future<void> Function() action) async {
    if (_sopBusy) return;
    setState(() => _sopBusy = true);
    try {
      await action();
      await _loadSopScore();
      final kid = (_karyawanId ?? '').trim();
      final sc = _sopScore;
      if (kid.isNotEmpty && sc != null) {
        await _sopDaily.syncMyPoin(karyawanId: kid, score: sc);
        if (mounted) {
          setState(() => _sudahKlaimPoinHariIni = true);
          _showPremiumSnackbar(
            'sop_score_sync_ok_judul'.tr(),
            'sop_score_sync_ok_msg'.tr(namedArgs: {
              'poin': sc.poin >= 0 ? '+${sc.poin}' : '${sc.poin}',
            }),
            OptikKaryawanTokens.success,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showPremiumSnackbar(
          'sop_error_judul'.tr(),
          '$e',
          OptikKaryawanTokens.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _sopBusy = false);
    }
  }

  Widget _buildTodoTab() {
    int tugasSelesai =
        _daftarSOPTugas.where((e) => e['selesai'] == true).length;
    double progress =
        _daftarSOPTugas.isEmpty ? 0 : tugasSelesai / _daftarSOPTugas.length;
    final layer = officeLayerOf(_jabatanKaryawan);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + _fabBottomPad(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetricTwinRow(),
          const SizedBox(height: 22),
          SopScorePanel(
            state: _sopBranch,
            score: _sopScore,
            layer: layer,
            isPagi: _sopIsPagi,
            busy: _sopBusy,
            onAddStory: () => _runSopAction(() async {
              final kid = _karyawanId!;
              final toko = _tokoId!;
              await _sopDaily.addStoryPost(tokoId: toko, karyawanId: kid);
            }),
            onCompleteDisplay: (slot) => _runSopAction(() async {
              await _sopDaily.completeDisplaySlot(
                tokoId: _tokoId!,
                karyawanId: _karyawanId!,
                slotIndex: slot,
              );
            }),
            onClaimSapu: () => _runSopAction(() async {
              await _sopDaily.claimSapu(
                tokoId: _tokoId!,
                karyawanId: _karyawanId!,
              );
            }),
            onClaimStok: () => _runSopAction(() async {
              await _sopDaily.claimStokCheck(
                tokoId: _tokoId!,
                karyawanId: _karyawanId!,
              );
            }),
            onSync: () => _runSopAction(() async {}),
          ),
          const SizedBox(height: 28),
          Text(
            'sop_bukti_tambahan'.tr(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: OptikKaryawanTokens.navyDeep,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'sop_bukti_tambahan_desc'.tr(),
            style: TextStyle(
              color: OptikKaryawanTokens.muted.withOpacity(0.95),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("sop_progres_harian".tr(),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: OptikKaryawanTokens.navyDeep)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: progress == 1.0
                      ? OptikKaryawanTokens.seasideWash
                      : OptikKaryawanTokens.gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "$tugasSelesai / ${_daftarSOPTugas.length} ${'sop_selesai'.tr()}",
                  style: TextStyle(
                      color: progress == 1.0
                          ? OptikKaryawanTokens.ink
                          : OptikKaryawanTokens.gold,
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
              color: progress == 1.0
                  ? OptikKaryawanTokens.seasideMid
                  : OptikKaryawanTokens.gold,
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
                    color: isSelesai
                        ? OptikKaryawanTokens.seasideWash
                        : OptikKaryawanTokens.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelesai
                          ? OptikKaryawanTokens.seasideMid.withOpacity(0.45)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelesai
                              ? OptikKaryawanTokens.seasideMid
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelesai
                                ? OptikKaryawanTokens.seasideMid
                                : Colors.grey.shade400,
                          ),
                        ),
                        child: isSelesai
                            ? const Icon(Icons.check,
                                size: 16, color: OptikKaryawanTokens.ink)
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          KaryawanI18nDisplay.sopTugas(
                            tugas['tugas']?.toString(),
                          ),
                          style: TextStyle(
                            fontWeight:
                                isSelesai ? FontWeight.w700 : FontWeight.w600,
                            color: isSelesai
                                ? OptikKaryawanTokens.ink
                                : OptikKaryawanTokens.ink.withOpacity(0.85),
                            decoration: isSelesai
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfilTab() {
    return Container(
      color: OptikKaryawanTokens.darkBg,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + _fabBottomPad(context)),
        children: [
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  OptikKaryawanTokens.seasideWash,
                  OptikKaryawanTokens.seasidePale,
                  OptikKaryawanTokens.seasideMid,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: OptikKaryawanTokens.border, width: 1),
              boxShadow: [
                BoxShadow(
                  color: OptikKaryawanTokens.seasideMid.withOpacity(0.18),
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
                            color: OptikKaryawanTokens.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: OptikKaryawanTokens.seasidePale.withOpacity(0.75),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.security_rounded,
                          color: OptikKaryawanTokens.seasideMid, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                    '${(_securityScore * 100).round()}% aman',
                    style: TextStyle(
                        color: _securityScore >= 0.9
                            ? OptikKaryawanTokens.success
                            : OptikKaryawanTokens.warning,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _securityScore,
                    backgroundColor: OptikKaryawanTokens.seasidePale,
                    color: _securityScore >= 0.9
                        ? OptikKaryawanTokens.success
                        : OptikKaryawanTokens.warning,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 15),
                Text("profil_enkripsi".tr(),
                    style: const TextStyle(
                        color: OptikKaryawanTokens.muted, fontSize: 13, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 10),
            child: Text("menu_utama_label".tr(),
                style: const TextStyle(
                    color: OptikKaryawanTokens.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
          ),
          Container(
            decoration: BoxDecoration(
              color: OptikKaryawanTokens.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: OptikKaryawanTokens.border),
              boxShadow: OptikKaryawanTokens.cardShadow,
            ),
            child: Column(
              children: [
                _buildMenuProfil(
                  Icons.person_rounded,
                  "menu_detail_profil".tr(),
                  "sub_detail_profil".tr(),
                  true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DetailDataPribadiPage(),
                      ),
                    );
                  },
                ),
                if (TenantModules.instance.allows('attendance'))
                  _buildMenuProfil(
                    Icons.face_retouching_natural_rounded,
                    'menu_absensi'.tr(),
                    'sub_absensi'.tr(),
                    true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AbsensiPage(),
                        ),
                      );
                    },
                  ),
                _buildMenuProfil(
                  Icons.face_outlined,
                  'menu_bentuk_wajah'.tr(),
                  'sub_bentuk_wajah'.tr(),
                  true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MemberFaceShapePage(),
                      ),
                    );
                  },
                ),
                _buildMenuProfil(
                  Icons.settings_rounded,
                  "menu_pengaturan_akun".tr(),
                  "sub_pengaturan_akun".tr(),
                  true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PengaturanAkunPage(),
                      ),
                    );
                  },
                ),
                if (_canShowAdminLoginCode)
                  _buildMenuProfil(
                    Icons.phonelink_lock_rounded,
                    'menu_kode_login_admin'.tr(),
                    (_tokoId ?? '').trim().toUpperCase() == 'PUSAT'
                        ? 'sub_kode_login_admin_pusat'.tr()
                        : 'sub_kode_login_admin_cabang'.tr(),
                    true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminLoginCodePage(),
                        ),
                      );
                    },
                  ),
                _buildMenuProfil(
                  Icons.headset_mic_rounded,
                  "menu_pusat_bantuan".tr(),
                  "sub_pusat_bantuan".tr(),
                  true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BantuanPage(),
                      ),
                    );
                  },
                ),
                _buildMenuProfil(
                  Icons.warning_rounded,
                  "menu_pengaduan".tr(),
                  "sub_pengaduan".tr(),
                  true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PengaduanPage(),
                      ),
                    );
                  },
                ),
                _buildMenuProfil(
                  Icons.notifications_active_rounded,
                  "menu_pengingat".tr(),
                  "sub_pengingat".tr(),
                  true,
                  onTap: () {
                    Navigator.push<PengingatNavResult>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PengingatPage(),
                      ),
                    ).then((result) {
                      if (result != null && mounted) {
                        unawaited(_applyPengingatNav(result));
                      }
                    });
                  },
                ),
                _buildMenuProfil(
                  Icons.system_update_rounded,
                  "menu_update".tr(),
                  "sub_update".tr(),
                  true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SoftwareUpdatePage(),
                      ),
                    );
                  },
                ),
                _buildMenuProfil(
                  Icons.translate_rounded,
                  "menu_ganti_bahasa".tr(),
                  "sub_ganti_bahasa".tr(),
                  false,
                  onTap: () => _tampilkanDialogBahasa(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuProfil(
    IconData icon,
    String title,
    String subtitle,
    bool showDivider, {
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            highlightColor: OptikKaryawanTokens.seasideWash.withOpacity(0.55),
            splashColor: OptikKaryawanTokens.seasidePale.withOpacity(0.45),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OptikKaryawanTokens.gold.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: OptikKaryawanTokens.gold.withOpacity(0.3),
                          width: 1),
                    ),
                    child:
                        Icon(icon, color: OptikKaryawanTokens.seasideMid, size: 22),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: OptikKaryawanTokens.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: const TextStyle(
                                color: OptikKaryawanTokens.muted,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      color: OptikKaryawanTokens.muted.withOpacity(0.45),
                      size: 16),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(
              color: OptikKaryawanTokens.border,
              height: 1,
              indent: 70,
              endIndent: 20),
      ],
    );
  }
}
