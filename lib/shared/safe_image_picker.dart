import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// `image_picker` only supports [ImageSource.camera] on Android/iOS.
/// Desktop/web need a `cameraDelegate` or they throw [StateError].
bool get imagePickerSupportsCamera {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

/// Prefer camera on Android/iOS; on desktop/web use gallery.
/// Also catches [StateError] (missing cameraDelegate) and retries gallery.
Future<XFile?> pickImageSafe({
  ImagePicker? picker,
  int? imageQuality,
  double? maxWidth,
  double? maxHeight,
  CameraDevice preferredCameraDevice = CameraDevice.rear,
  BuildContext? context,
}) async {
  final p = picker ?? ImagePicker();

  Future<XFile?> fromGallery() => p.pickImage(
        source: ImageSource.gallery,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );

  void notifyDesktopFallback() {
    final ctx = context;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Kamera tidak tersedia di desktop, pilih dari galeri',
        ),
      ),
    );
  }

  if (!imagePickerSupportsCamera) {
    notifyDesktopFallback();
    return fromGallery();
  }

  try {
    return await p.pickImage(
      source: ImageSource.camera,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      preferredCameraDevice: preferredCameraDevice,
    );
  } on StateError {
    notifyDesktopFallback();
    return fromGallery();
  }
}
