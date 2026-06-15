import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'admin_approval_page.dart';
import '../karyawan/register_karyawan_page.dart';
import '../karyawan/login_karyawan_page.dart';
import '../karyawan/main_karyawan.dart';
import '../main.dart';

class LivenessCameraPage extends StatefulWidget {
  const LivenessCameraPage({super.key});

  @override
  State<LivenessCameraPage> createState() => _LivenessCameraPageState();
}

class _LivenessCameraPageState extends State<LivenessCameraPage> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isBusy = false;
  bool _isFaceDetected = false;
  late String _livenessStatus;
  Color _statusColor = Colors.orangeAccent;

  @override
  void initState() {
    super.initState();
    // 1. Inisialisasi Mesin Deteksi Wajah (Penting: Nyalakan Klasifikasi untuk baca Senyum/Mata)
    _livenessStatus = "liveness_mencari_wajah".tr();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _initializeCamera();
  }

  // 2. Fungsi Menyalakan Kamera Depan
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      // Cari kamera depan (front)
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {});
      // Mulai membaca gambar secara live (Stream)
      _cameraController!.startImageStream(_processCameraImage);
    } catch (e) {
      debugPrint("Error Kamera: $e");
    }
  }

  // 3. Fungsi AI Membaca Wajah secara Live (Setiap Frame)
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      // Konversi format kamera bawaan ke format yang bisa dibaca Google ML Kit
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.values.firstWhere(
            (r) =>
                r.rawValue == _cameraController!.description.sensorOrientation,
            orElse: () => InputImageRotation.rotation0deg,
          ),
          format: InputImageFormat.nv21, // Format standar Android
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      // Tembakkan ke AI Face Detector
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (_isFaceDetected) {
          if (mounted) {
            setState(() {
              _isFaceDetected = false;
              _livenessStatus = "liveness_wajah_tidak_terlihat".tr();
              _statusColor = Colors.redAccent;
            });
          }
        }
      } else {
        _isFaceDetected = true;
        final face = faces.first;

        //--- LOGIKA ANTI-TIPU (LIVENESS)
        // Karyawan WAJIB tersenyum lebar agar AI tahu dia manusia hidup
        if (face.smilingProbability != null) {
          if (face.smilingProbability! > 0.7) {
            // LIVENESS TEMBUS! (Berhasil absen)
            if (mounted) {
              setState(() {
                _livenessStatus = "liveness_sukses".tr();
                _statusColor = Colors.green;
              });
            }
            _berhasilAbsen(); // Matikan kamera dan simpan data
          } else {
            if (mounted) {
              setState(() {
                _livenessStatus = "liveness_senyum".tr();
                _statusColor = Colors.blueAccent;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error ML Kit: $e");
    } finally {
      _isBusy = false;
    }
  }

  // 4. FUNGSI BERHASIL ABSEN
  Future<void> _berhasilAbsen() async {
    // Hentikan proses deteksi wajah agar tidak berjalan berulang kali
    _cameraController?.stopImageStream();

    // Tunggu sebentar biar pengguna bisa membaca status "Sukses!" di layar
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      // Kembali ke halaman sebelumnya dengan membawa status TRUE (Berhasil)
      Navigator.pop(context, true);
    }
  }

  // 5. BERSIHKAN MEMORI SAAT HALAMAN DITUTUP
  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  // ==========================================================
  // WIDGET UTAMA (ANTARMUKA KAMERA LIVENESS)
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    // Tampilkan loading jika kamera belum siap
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body:
            Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Latar gelap Slate Premium
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "liveness_title".tr(),
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // TEKS STATUS INSTRUKSI (Dinamis berubah warna & teks)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              // PERBAIKAN DI SINI: Menggunakan Border.all dengan format yang benar
              border: Border.all(color: _statusColor, width: 1.5),
            ),
            child: Text(
              _livenessStatus,
              style: TextStyle(
                color: _statusColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 40),
          // FRAME KAMERA MELINGKAR (Lebih Premium)
          Expanded(
            child: Center(
              child: Container(
                width: 300,
                height: 400,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(200),
                  // PERBAIKAN DI SINI: Menggunakan Border.all
                  border: Border.all(color: _statusColor, width: 4.0),
                  boxShadow: [
                    BoxShadow(
                      color: _statusColor.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(200),
                  child: OverflowBox(
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        // Membalik nilai width & height karena orientasi sensor Portrait
                        width: _cameraController!.value.previewSize!.height,
                        height: _cameraController!.value.previewSize!.width,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          // TEKS INSTRUKSI TAMBAHAN DI BAWAH
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "liveness_instruksi".tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}
