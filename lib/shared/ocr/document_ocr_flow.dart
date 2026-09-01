import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../member/member_session.dart';
import 'deskew_document_capture.dart';
import 'google_vision_ocr_service.dart';
import 'vision_receipt_draft.dart';

/// Scan (luruskan) + Cloud Vision. Batal → null. Error dilempar ke pemanggil.
Future<VisionReceiptDraft?> scanDocumentOcr({
  required BuildContext context,
  String kind = 'document',
  String? cropTitle,
  bool asMember = false,
}) async {
  final bytes = await captureDeskewedBytes(
    context: context,
    cropTitle: cropTitle,
  );
  if (bytes == null || bytes.length < 800) return null;
  return GoogleVisionOcrService().readDocument(
    bytes: bytes,
    kind: kind,
    memberId: asMember ? MemberSession.instance.memberId : null,
    phone: asMember ? MemberSession.instance.phoneForQuery : null,
  );
}

Future<Uint8List?> scanDocumentPreviewBytes({
  required BuildContext context,
  String? cropTitle,
}) {
  return captureDeskewedBytes(context: context, cropTitle: cropTitle);
}
