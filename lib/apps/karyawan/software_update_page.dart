import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

class SoftwareUpdatePage extends StatefulWidget {
  const SoftwareUpdatePage({super.key});

  @override
  State<SoftwareUpdatePage> createState() => _SoftwareUpdatePageState();
}

class _SoftwareUpdatePageState extends State<SoftwareUpdatePage> {
  bool _isAutoUpdateOn = false;
  bool _isLoading = true;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  String _versiLokal = "";
  String _versiServer = "";
  String _urlDownload = "";
  bool _adaUpdate = false;

  @override
  void initState() {
    super.initState();
    _inisialisasiData();
  }

  Future<void> _inisialisasiData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _isAutoUpdateOn = prefs.getBool('auto_update_karyawan') ?? false;

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    _versiLokal = packageInfo.version;

    try {
      final data = await Supabase.instance.client
          .from('versi_app')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data != null) {
        _versiServer = data['versi_terbaru'] ?? _versiLokal;
        _urlDownload = data['url_download'] ?? "";

        if (_versiServer != _versiLokal && _urlDownload.isNotEmpty) {
          _adaUpdate = true;
        }
      }
    } catch (e) {
      debugPrint("${"update_debug_cek_versi".tr()} $e");
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadDanInstall() async {
    // 1. SENSOR PENJAGA WEB CHROME
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            "Format APK tidak bisa dipasang di Browser Web Chrome. Silakan uji coba fitur ini di HP Android asli atau Emulator!"),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ));
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      // 2. PASTIKAN SISTEM OPERASI ADALAH ANDROID
      if (!Platform.isAndroid) {
        throw Exception(
            "Fitur instalasi langsung hanya didukung pada perangkat Android.");
      }

      Dio dio = Dio();
      var dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      String savePath = "${dir.path}/Optik_B_Riski_Update.apk";

      // 3. PROSES UNDUH FILE APK
      await dio.download(
        _urlDownload,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );

      // 4. PROSES MENGEKSEKUSI PEMASANGAN APK KE SISTEM ANDROID
      final result = await OpenFile.open(savePath,
          type: "application/vnd.android.package-archive");

      // 5. NOTIFIKASI JIKA EKSEKUSI FILE GAGAL
      if (result.type != ResultType.done) {
        throw Exception(
            "Sistem menolak membuka installer. Alasan: ${result.message}");
      }
    } catch (e) {
      // 6. POP-UP NOTIFIKASI PINTAR UNTUK USER
      if (mounted) {
        String pesanError = e.toString();

        // Jika error disebabkan karena izin install apk belum dinyalakan di HP
        if (pesanError.contains("REQUEST_INSTALL_PACKAGES")) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              title: const Row(
                children: [
                  Icon(Icons.security_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 10),
                  Text("Izin Pemasangan Diperlukan"),
                ],
              ),
              content: const Text(
                "HP Anda memblokir instalasi otomatis. Mohon buka Pengaturan HP -> Akses Aplikasi Khusus -> Instal Aplikasi Tidak Dikenal -> Lalu aktifkan izin untuk aplikasi Optik B. Riski.",
                style: TextStyle(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Dimengerti",
                      style: TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        } else {
          // Jika error disebabkan hal lain (misal internet putus)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Gagal Memperbarui: ${pesanError.replaceAll('Exception:', '')}"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ));
        }
      }
    } finally {
      // 7. RESET STATE DOWNLOADING
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text("update_title".tr(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent))
          : Column(
              children: [
                Container(
                  color: const Color(0xFF1E293B),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("update_auto".tr(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16)),
                      Row(
                        children: [
                          Text(
                              _isAutoUpdateOn
                                  ? "update_on".tr()
                                  : "update_off".tr(),
                              style: TextStyle(
                                  color: _isAutoUpdateOn
                                      ? Colors.greenAccent
                                      : Colors.grey,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          CupertinoSwitch(
                            value: _isAutoUpdateOn,
                            activeColor: Colors.blueAccent,
                            onChanged: (val) async {
                              SharedPreferences prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool('auto_update_karyawan', val);
                              setState(() => _isAutoUpdateOn = val);
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!_adaUpdate) ...[
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                shape: BoxShape.circle),
                            child: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 45,
                                color: Colors.greenAccent),
                          ),
                          const SizedBox(height: 25),
                          Text("update_up_to_date".tr(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text("${"update_version".tr()} $_versiLokal",
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 14)),
                        ] else ...[
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.2),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.system_update_rounded,
                                size: 45, color: Colors.blueAccent),
                          ),
                          const SizedBox(height: 25),
                          Text("update_available".tr(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                              "${"update_version".tr()} $_versiServer ${"update_ready".tr()}",
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 14)),
                          const SizedBox(height: 40),
                          if (_isDownloading)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 50),
                              child: Column(
                                children: [
                                  LinearProgressIndicator(
                                      value: _downloadProgress,
                                      backgroundColor: Colors.grey.shade800,
                                      color: Colors.blueAccent,
                                      minHeight: 6,
                                      borderRadius: BorderRadius.circular(3)),
                                  const SizedBox(height: 12),
                                  Text(
                                      "${"update_downloading".tr()} ${(_downloadProgress * 100).toStringAsFixed(0)}%",
                                      style: TextStyle(
                                          color: Colors.grey.shade400)),
                                ],
                              ),
                            )
                          else
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 30, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20))),
                              onPressed: _downloadDanInstall,
                              child: Text("update_btn_download".tr(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
