import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb; // Tambahan penting untuk deteksi platform
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
    _livenessStatus = "liveness_mencari_wajah".tr();

    // Inisialisasi ML Kit HANYA jika berjalan di HP/Mobile native
    if (!kIsWeb) {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
    }

    _initializeCamera();
  }

  // Fungsi Menyalakan Kamera Depan (Mendukung HP & Web)
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
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

      if (kIsWeb) {
        // Alur Web: startImageStream tidak didukung di web, gunakan alur interaktif browser
        _startWebLivenessFlow();
      } else {
        // Alur HP Native: Gunakan deteksi real-time stream ML Kit
        _cameraController!.startImageStream(_processCameraImage);
      }
    } catch (e) {
      debugPrint("Error Kamera: $e");
    }
  }

  // Alur khusus deteksi wajah interaktif untuk versi Web Browser
  void _startWebLivenessFlow() {
    // 1. Fase scan wajah awal di browser (2 detik)
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isFaceDetected = true;
        _livenessStatus = "liveness_senyum".tr();
        _statusColor = Colors.blueAccent;
      });

      // 2. Fase mendeteksi senyuman pengguna di browser (3 detik)
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _livenessStatus = "liveness_sukses".tr();
          _statusColor = Colors.green;
        });
        _berhasilAbsen();
      });
    });
  }

  // Fungsi AI Membaca Wajah secara Live (Hanya dieksekusi di HP Native)
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || kIsWeb) return;
    _isBusy = true;

    try {
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
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

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

        if (face.smilingProbability != null) {
          if (face.smilingProbability! > 0.7) {
            if (mounted) {
              setState(() {
                _livenessStatus = "liveness_sukses".tr();
                _statusColor = Colors.green;
              });
            }
            _berhasilAbsen();
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

  // FUNGSI BERHASIL ABSEN
  Future<void> _berhasilAbsen() async {
    if (!kIsWeb) {
      _cameraController?.stopImageStream();
    }
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  // BERSIHKAN MEMORI (Mencegah Kebocoran RAM di HP & Web)
  @override
  void dispose() {
    if (!kIsWeb) {
      _cameraController?.stopImageStream();
      _faceDetector.close();
    }
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body:
            Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      );
    }

    // Penyesuaian rasio aspek box preview kamera antara monitor web dan layar HP
    final previewSize = _cameraController!.value.previewSize!;
    final double viewWidth = kIsWeb ? previewSize.width : previewSize.height;
    final double viewHeight = kIsWeb ? previewSize.height : previewSize.width;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
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
          Expanded(
            child: Center(
              child: Container(
                width: 300,
                height: 400,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(200),
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
                        width: viewWidth,
                        height: viewHeight,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
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
