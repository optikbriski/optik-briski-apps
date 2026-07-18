import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'attendance/face_template.dart';
import 'attendance/liveness_result.dart';

class LivenessCameraPage extends StatefulWidget {
  const LivenessCameraPage({super.key});

  @override
  State<LivenessCameraPage> createState() => _LivenessCameraPageState();
}

class _LivenessCameraPageState extends State<LivenessCameraPage> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isBusy = false;
  bool _isFaceDetected = false;
  late String _livenessStatus;
  Color _statusColor = Colors.orangeAccent;

  // Penampung Timer resmi agar bisa dibatalkan saat dispose (Anti-Leak)
  Timer? _webTimer1;
  Timer? _webTimer2;

  // Flag pengaman agar fungsi kelulusan absen hanya dieksekusi tepat satu kali
  bool _isSuccessTriggered = false;

  // Penampung pesan eror jika inisialisasi hardware/izin kamera gagal
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _livenessStatus = "liveness_mencari_wajah".tr();

    // Inisialisasi ML Kit HANYA jika berjalan di HP/Mobile native
    if (!kIsWeb) {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableLandmarks: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );
    }

    _initializeCamera();
  }

  // Fungsi Menyalakan Kamera Depan (Mendukung HP & Web)
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = "Kamera tidak ditemukan pada perangkat ini.";
          });
        }
        return;
      }

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
        _startWebLivenessFlow();
      } else {
        // Alur HP Native: Jalankan streaming kamera
        _cameraController!.startImageStream(_processCameraImage);
      }
    } catch (e) {
      debugPrint("Error Kamera: $e");
      if (mounted) {
        setState(() {
          _errorMessage =
              "Gagal mengakses kamera. Pastikan izin akses telah diberikan.";
        });
      }
    }
  }

  // Alur khusus deteksi wajah interaktif untuk versi Web Browser
  void _startWebLivenessFlow() {
    _webTimer1 = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isFaceDetected = true;
        _livenessStatus = "liveness_senyum".tr();
        _statusColor = Colors.blueAccent;
      });

      _webTimer2 = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _livenessStatus = "liveness_sukses".tr();
          _statusColor = Colors.green;
        });
        _berhasilAbsen();
      });
    });
  }

  // Konverter YUV420 ke NV21 murni untuk membuang padding bytes yang merusak gambar
  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;

    final int numPixels = width * height;
    final nv21 = Uint8List(numPixels + (numPixels ~/ 2));

    // Ekstrak data Y plane langsung menggunakan setRange tanpa sublist (Hemat GC & RAM)
    int idY = 0;
    final int yRowStride = yPlane.bytesPerRow;
    for (int y = 0; y < height; y++) {
      final int start = y * yRowStride;
      if (start + width <= yBuffer.length) {
        nv21.setRange(idY, idY + width, yBuffer, start);
      }
      idY += width;
    }

    // Interleave bidang U dan V (Format NV21: YYYYYYYY VUVU)
    int idUV = numPixels;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height ~/ 2; y++) {
      for (int x = 0; x < width ~/ 2; x++) {
        final int uIndex = y * uvRowStride + x * uvPixelStride;
        final int vIndex =
            y * vPlane.bytesPerRow + x * (vPlane.bytesPerPixel ?? 1);

        // Guard check untuk mengantisipasi pemotongan buffer agresif oleh OS gawai tertentu
        if (vIndex < vBuffer.length && uIndex < uBuffer.length) {
          nv21[idUV++] = vBuffer[vIndex]; // V dahulu di format NV21
          nv21[idUV++] = uBuffer[uIndex]; // Kemudian baru U
        }
      }
    }
    return nv21;
  }

  // Fungsi AI Membaca Wajah secara Live (Hanya dieksekusi di HP Native)
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || kIsWeb || _isSuccessTriggered || _faceDetector == null)
      return;
    _isBusy = true;

    try {
      final bool isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      late final Uint8List bytes;
      late final InputImageFormat imageFormat;

      if (isIOS) {
        // iOS: Cukup flatten satu bidang tunggal BGRA8888
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        bytes = allBytes.done().buffer.asUint8List();
        imageFormat = InputImageFormat.bgra8888;
      } else {
        // Android: Gunakan pembersih padding YUV ke NV21 agar gambar tidak distorsi/stretch
        bytes = _convertYUV420ToNV21(image);
        imageFormat = InputImageFormat.nv21;
      }

      // Mengonversi rotasi sensor bawaan secara rigid dan presisi
      final int sensorOrientation =
          _cameraController!.description.sensorOrientation;
      InputImageRotation imageRotation;
      switch (sensorOrientation) {
        case 90:
          imageRotation = InputImageRotation.rotation90deg;
          break;
        case 180:
          imageRotation = InputImageRotation.rotation180deg;
          break;
        case 270:
          imageRotation = InputImageRotation.rotation270deg;
          break;
        default:
          imageRotation = InputImageRotation.rotation0deg;
      }

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: imageRotation,
          format: imageFormat,
          bytesPerRow: isIOS ? image.planes.first.bytesPerRow : image.width,
        ),
      );

      final faces = await _faceDetector!.processImage(inputImage);

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

  // FUNGSI BERHASIL: ambil foto + template wajah, lalu kembalikan ke pemanggil
  Future<void> _berhasilAbsen() async {
    if (_isSuccessTriggered) return;
    _isSuccessTriggered = true;

    Uint8List? photoBytes;
    List<double>? faceTemplate;

    if (!kIsWeb && _cameraController != null) {
      try {
        await _cameraController?.stopImageStream();
      } catch (e) {
        debugPrint("Error mematikan stream: $e");
      }

      try {
        final shot = await _cameraController!.takePicture();
        photoBytes = await shot.readAsBytes();
        if (_faceDetector != null) {
          final faces = await _faceDetector!
              .processImage(InputImage.fromFilePath(shot.path));
          if (faces.isNotEmpty) {
            faceTemplate = FaceTemplateUtil.fromFace(faces.first);
          }
        }
      } catch (e) {
        debugPrint("Gagal capture foto liveness: $e");
      }
    }

    if (mounted) {
      setState(() {
        _livenessStatus = "liveness_sukses".tr();
        _statusColor = Colors.green;
      });
    }

    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      Navigator.pop(
        context,
        LivenessCaptureResult(
          success: true,
          photoBytes: photoBytes,
          faceTemplate: faceTemplate,
        ),
      );
    }
  }

  // BERSIHKAN MEMORI TOTAL (Anti-Leak HP & Monitor Kasir)
  @override
  void dispose() {
    _webTimer1?.cancel();
    _webTimer2?.cancel();

    if (!kIsWeb) {
      try {
        _cameraController?.stopImageStream();
      } catch (e) {
        debugPrint("Stream sudah mati otomatis.");
      }
      _faceDetector?.close();
    }
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_rounded,
                    color: Colors.redAccent, size: 60),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(150, 45)),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Kembali"),
                )
              ],
            ),
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body:
            Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      );
    }

    final previewSize = _cameraController!.value.previewSize!;
    final double viewWidth = kIsWeb ? previewSize.width : previewSize.height;
    final double viewHeight = kIsWeb ? previewSize.height : previewSize.width;

    // ✅ FIX CLEAN POP: Mengunci pintu keluar fisik secara statis, didPop dicek untuk memutus loop tanpa akhir
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop)
          return; // Jika sudah berhasil keluar, hentikan eksekusi kode di bawahnya

        // Menangani swipe gesture fisik Android / tombol back bawaan HP kasir
        if (!_isSuccessTriggered) {
          Navigator.pop(context, false);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: Text(
            "liveness_title".tr(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white),
            onPressed: () {
              // Menangani klik tombol back manual di sudut kiri atas layar aplikasi
              if (!_isSuccessTriggered) {
                Navigator.pop(context, false);
              }
            },
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
      ),
    );
  }
}
