import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-only: cek / minta pengecualian optimasi baterai agar foreground
/// service lokasi lebih tahan saat layar mati.
class AndroidBatteryOptimization {
  AndroidBatteryOptimization._();

  static const _channel = MethodChannel('optik.briski/battery_optimization');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// true jika sudah diizinkan "Tidak dioptimalkan" / ignore battery optimizations.
  static Future<bool> isIgnoring() async {
    if (!_isAndroid) return true;
    try {
      final v = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return v ?? false;
    } catch (e) {
      debugPrint('AndroidBatteryOptimization.isIgnoring: $e');
      return false;
    }
  }

  /// Tampilkan dialog sistem minta ignore battery optimizations.
  static Future<bool> requestIgnore() async {
    if (!_isAndroid) return false;
    try {
      final v =
          await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return v ?? false;
    } catch (e) {
      debugPrint('AndroidBatteryOptimization.requestIgnore: $e');
      return false;
    }
  }

  /// Buka daftar pengaturan optimasi baterai (fallback).
  static Future<bool> openSettings() async {
    if (!_isAndroid) return false;
    try {
      final v = await _channel.invokeMethod<bool>('openBatterySettings');
      return v ?? false;
    } catch (e) {
      debugPrint('AndroidBatteryOptimization.openSettings: $e');
      return false;
    }
  }
}
