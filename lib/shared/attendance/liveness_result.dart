import 'dart:typed_data';

/// Hasil capture dari halaman liveness (kompatibel: boleh dicek sebagai `== true`).
class LivenessCaptureResult {
  const LivenessCaptureResult({
    required this.success,
    this.photoBytes,
    this.faceTemplate,
  });

  final bool success;
  final Uint8List? photoBytes;
  final List<double>? faceTemplate;

  @override
  bool operator ==(Object other) {
    if (other is bool) return success == other;
    return other is LivenessCaptureResult && other.success == success;
  }

  @override
  int get hashCode => success.hashCode;
}
