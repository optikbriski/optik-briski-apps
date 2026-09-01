import 'dart:typed_data';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import 'google_vision_ocr_service.dart';

/// Sumber yang dipilih user sebelum OCR.
enum DocumentCaptureSource {
  camera,
  gallery,
  file,
}

bool documentBytesLookLikePdf(Uint8List bytes) {
  if (bytes.length < 5) return false;
  return bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}

bool get _nativeDocScanner {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

/// Pilih dulu: kamera, galeri, atau file — baru ambil gambar.
Future<Uint8List?> captureDeskewedBytes({
  required BuildContext context,
  String? cropTitle,
}) async {
  final source = await pickDocumentCaptureSource(context);
  if (source == null || !context.mounted) return null;
  return captureDeskewedBytesFrom(
    context: context,
    source: source,
    cropTitle: cropTitle,
  );
}

Future<DocumentCaptureSource?> pickDocumentCaptureSource(
  BuildContext context,
) {
  return showModalBottomSheet<DocumentCaptureSource>(
    context: context,
    showDragHandle: true,
    backgroundColor: OptikAdminTokens.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ocr_source_title'.tr(),
                style: TextStyle(
                  color: OptikAdminTokens.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ocr_source_hint'.tr(),
                style: TextStyle(
                  color: OptikAdminTokens.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              _SourceTile(
                icon: Icons.photo_camera_outlined,
                title: 'ocr_source_camera'.tr(),
                subtitle: 'ocr_source_camera_sub'.tr(),
                onTap: () => Navigator.pop(ctx, DocumentCaptureSource.camera),
              ),
              _SourceTile(
                icon: Icons.photo_library_outlined,
                title: 'ocr_source_gallery'.tr(),
                subtitle: 'ocr_source_gallery_sub'.tr(),
                onTap: () => Navigator.pop(ctx, DocumentCaptureSource.gallery),
              ),
              _SourceTile(
                icon: Icons.upload_file_outlined,
                title: 'ocr_source_file'.tr(),
                subtitle: 'ocr_source_file_sub'.tr(),
                onTap: () => Navigator.pop(ctx, DocumentCaptureSource.file),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<Uint8List?> captureDeskewedBytesFrom({
  required BuildContext context,
  required DocumentCaptureSource source,
  String? cropTitle,
}) async {
  final title = (cropTitle ?? 'ocr_crop_title'.tr()).trim();

  if (source == DocumentCaptureSource.file) {
    return _pickFileThenCrop(context, title);
  }

  if (_nativeDocScanner) {
    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        scannerSource: source == DocumentCaptureSource.camera
            ? ScannerSource.camera
            : ScannerSource.gallery,
        androidScannerMode: AndroidScannerMode.full,
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.7,
        ),
      );
      if (paths == null || paths.isEmpty) return null;
      final bytes = await XFile(paths.first).readAsBytes();
      if (bytes.length >= 800) return Uint8List.fromList(bytes);
    } on CunningDocumentScannerException catch (e) {
      if (e.code == 'permission_denied') rethrow;
    } on MissingPluginException {
      // Fallback ImagePicker di bawah.
    }
  }

  if (!context.mounted) return null;
  return _pickImageThenCrop(
    context,
    title,
    source == DocumentCaptureSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
  );
}

Future<Uint8List?> _pickImageThenCrop(
  BuildContext context,
  String title,
  ImageSource source,
) async {
  final picker = ImagePicker();
  XFile? picked;
  try {
    picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 2000,
      preferredCameraDevice: CameraDevice.rear,
    );
  } on StateError {
    if (source == ImageSource.camera && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('ocr_camera_unavailable'.tr())),
      );
    }
    return null;
  } catch (e) {
    if (source == ImageSource.camera && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('ocr_camera_unavailable'.tr())),
      );
    }
    return null;
  }
  if (picked == null || !context.mounted) return null;
  return _cropOrRead(context, title, picked);
}

Future<Uint8List?> _pickFileThenCrop(BuildContext context, String title) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const [
      'jpg',
      'jpeg',
      'png',
      'webp',
      'gif',
      'bmp',
      'heic',
      'heif',
      'pdf',
    ],
    withData: true,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  final name = (file.name).toLowerCase();
  var bytes = file.bytes;
  if (bytes == null && file.path != null && file.path!.isNotEmpty) {
    bytes = await XFile(file.path!).readAsBytes();
  }
  if (bytes == null || bytes.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('ocr_file_invalid'.tr())),
      );
    }
    return null;
  }
  final raw = Uint8List.fromList(bytes);
  if (name.endsWith('.pdf') || documentBytesLookLikePdf(raw)) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('ocr_pdf_unsupported'.tr())),
      );
    }
    return null;
  }
  if (raw.length < 800) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('ocr_file_invalid'.tr())),
      );
    }
    return null;
  }
  if (raw.length > GoogleVisionOcrService.maxBytes) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('ocr_file_too_big'.tr())),
      );
    }
    return null;
  }
  if (!context.mounted) return null;
  if (file.path != null && file.path!.isNotEmpty) {
    return _cropOrRead(context, title, XFile(file.path!));
  }
  return _cropOrRead(
    context,
    title,
    XFile.fromData(raw, mimeType: _mimeForName(name), name: file.name),
    fallbackBytes: raw,
  );
}

String _mimeForName(String name) {
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  if (name.endsWith('.gif')) return 'image/gif';
  if (name.endsWith('.bmp')) return 'image/bmp';
  return 'image/jpeg';
}

Future<Uint8List?> _cropOrRead(
  BuildContext context,
  String title,
  XFile picked, {
  Uint8List? fallbackBytes,
}) async {
  try {
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      maxWidth: 1600,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 70,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: title,
          toolbarColor: OptikKaryawanTokens.seasideMid,
          toolbarWidgetColor: OptikKaryawanTokens.ink,
          lockAspectRatio: false,
          hideBottomControls: false,
          cropStyle: CropStyle.rectangle,
        ),
        IOSUiSettings(
          title: title,
          aspectRatioLockEnabled: false,
          rotateButtonsHidden: false,
        ),
        if (kIsWeb)
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
            barrierColor: Colors.black54,
          ),
      ],
    );
    if (cropped == null) return null;
    return Uint8List.fromList(await cropped.readAsBytes());
  } catch (_) {
    if (fallbackBytes != null && fallbackBytes.length >= 800) {
      return fallbackBytes;
    }
    return Uint8List.fromList(await picked.readAsBytes());
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OptikAdminTokens.lineStrong),
              color: OptikAdminTokens.ice.withOpacity(
                OptikAdminTokens.isDark ? 0.08 : 0.45,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: OptikAdminTokens.navy, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: OptikAdminTokens.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: OptikAdminTokens.navy.withOpacity(0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
