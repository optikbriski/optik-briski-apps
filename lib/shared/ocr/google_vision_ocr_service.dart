import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'vision_receipt_draft.dart';
import 'vision_table_grid.dart';

/// Client ke Edge Function `google-vision-ocr`.
/// KTP/IKD jangan lewat sini — tetap OCR on-device.
class GoogleVisionOcrService {
  GoogleVisionOcrService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const functionName = 'google-vision-ocr';
  static const memberFunctionName = 'member-vision-ocr';
  static const maxBytes = 2500000;

  final SupabaseClient _client;

  Future<VisionReceiptDraft> readReceipt(Uint8List jpegBytes) {
    return readDocument(bytes: jpegBytes, kind: 'receipt');
  }

  Future<VisionReceiptDraft> readDocument({
    required Uint8List bytes,
    String kind = 'receipt',
    String? memberId,
    String? phone,
  }) async {
    final blocked = kind.trim().toLowerCase();
    if (blocked == 'ktp' || blocked == 'ikd' || blocked == 'e-ktp') {
      throw 'KTP/IKD tidak dikirim ke Cloud Vision.';
    }
    if (bytes.length < 800) {
      throw 'Foto terlalu kecil / rusak.';
    }
    if (bytes.length > maxBytes) {
      throw 'Foto terlalu besar. Ambil ulang lebih dekat.';
    }

    try {
      final asMember = (memberId ?? '').trim().isNotEmpty;
      final res = await _client.functions.invoke(
        asMember ? memberFunctionName : functionName,
        body: {
          'kind': kind,
          'image_base64': base64Encode(bytes),
          if ((memberId ?? '').trim().isNotEmpty) 'member_id': memberId!.trim(),
          if ((phone ?? '').trim().isNotEmpty) 'phone': phone!.trim(),
        },
      );
      final data = _asMap(res.data);
      if (data['ok'] == true || (data['text']?.toString().isNotEmpty ?? false)) {
        return VisionReceiptDraft.parse(
          data['text']?.toString() ?? '',
        ).withTokens(VisionOcrToken.parseList(data['tokens']));
      }
      throw (data['error'] ?? 'OCR gagal.').toString();
    } on FunctionException catch (e) {
      throw _extractError(e);
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw 'Respons OCR tidak valid.';
  }

  String _extractError(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
    if (details is String && details.isNotEmpty) return details;
    if (e.reasonPhrase != null && e.reasonPhrase!.isNotEmpty) {
      return e.reasonPhrase!;
    }
    return 'OCR gagal (${e.status}).';
  }
}
