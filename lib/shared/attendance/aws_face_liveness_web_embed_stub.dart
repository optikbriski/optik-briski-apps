import 'aws_face_liveness_service.dart';

/// Stub non-web.
class AwsFaceLivenessWebEmbed {
  AwsFaceLivenessWebEmbed({
    required this.viewType,
    required this.uiUrl,
    required this.session,
    required this.onEvent,
  });

  final String viewType;
  final String uiUrl;
  final AwsLivenessSession session;
  final void Function(Map<String, dynamic> event) onEvent;

  void register() {}

  void dispose() {}
}
