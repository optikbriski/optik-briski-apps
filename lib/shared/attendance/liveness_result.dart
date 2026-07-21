import 'dart:typed_data';

/// Hasil capture dari halaman liveness (kompatibel: boleh dicek sebagai `== true`).
class LivenessCaptureResult {
  const LivenessCaptureResult({
    required this.success,
    this.photoBytes,
    this.faceTemplate,
    this.livenessProvider,
    this.livenessSessionId,
    this.livenessConfidence,
  });

  final bool success;
  final Uint8List? photoBytes;
  final List<double>? faceTemplate;

  /// `aws` | `local` | null
  final String? livenessProvider;
  final String? livenessSessionId;
  final double? livenessConfidence;

  @override
  bool operator ==(Object other) {
    if (other is bool) return success == other;
    return other is LivenessCaptureResult && other.success == success;
  }

  @override
  int get hashCode => success.hashCode;
}
