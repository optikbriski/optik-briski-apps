import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Nomor WA fallback jika invoice_settings.phone kosong.
const String defaultAdminWhatsApp = '6281288801697';

String normalizeWaNumber(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
  digits = digits.replaceAll('+', '');
  if (digits.startsWith('0')) {
    digits = '62${digits.substring(1)}';
  }
  return digits;
}

Future<String> resolveAdminWhatsApp({SupabaseClient? client}) async {
  final c = client ?? Supabase.instance.client;
  try {
    final row = await c
        .from('invoice_settings')
        .select('phone')
        .limit(1)
        .maybeSingle();
    final phone = row?['phone']?.toString() ?? '';
    if (phone.trim().isNotEmpty) {
      return normalizeWaNumber(phone);
    }
  } catch (_) {}
  return defaultAdminWhatsApp;
}

Future<void> openAdminWhatsApp({
  String? message,
  SupabaseClient? client,
}) async {
  final phone = await resolveAdminWhatsApp(client: client);
  final uri = Uri.parse(
    message == null || message.isEmpty
        ? 'https://wa.me/$phone'
        : 'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
  );
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    throw 'Tidak bisa membuka WhatsApp. Pastikan aplikasi terpasang.';
  }
}
