import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bootstrap.dart';
import 'tenant_service.dart';

/// Tagihan Rekasa → UMKM + kontrak online. Bukan nota POS toko.
class TenantBilling {
  TenantBilling._();

  static String formatRp(dynamic raw) {
    final n = int.tryParse('$raw'.split('.').first) ?? 0;
    final s = n.abs().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return n < 0 ? 'Rp -$s' : 'Rp $s';
  }

  /// `?kontrak=` atau `/kontrak/<token>` di web Admin.
  static String? tokenFromUri(Uri uri) {
    final q = (uri.queryParameters['kontrak'] ??
            uri.queryParameters['contract'] ??
            '')
        .trim();
    if (q.isNotEmpty) return q;
    final segs = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
    if (segs.length >= 2 &&
        (segs.first == 'kontrak' || segs.first == 'contract')) {
      final t = segs[1].trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  static String publicSignUrl(String token, {String? origin}) {
    final t = token.trim();
    final base = (origin ??
            (kIsWeb ? Uri.base.origin : 'https://admin.rekasakarya.id'))
        .replaceAll(RegExp(r'/$'), '');
    return '$base/?kontrak=$t';
  }

  static String waShareText({
    required String storeName,
    required String url,
  }) {
    return 'Halo $storeName, mohon baca dan tandatangani kontrak langganan Rekasa secara online:\n$url';
  }
}

class TenantAccessSnapshot {
  const TenantAccessSnapshot({
    required this.ok,
    this.platform = false,
    this.reason,
    this.status,
    this.error,
    this.displayName,
    this.slug,
    this.unsignedContractToken,
    this.invoices = const [],
  });

  final bool ok;
  final bool platform;
  final String? reason;
  final String? status;
  final String? error;
  final String? displayName;
  final String? slug;
  final String? unsignedContractToken;
  final List<Map<String, dynamic>> invoices;

  bool get isSuspended => reason == 'suspend' || status == 'suspend';

  String get lockTitle => isSuspended
      ? 'Langganan ditangguhkan'
      : 'Usaha belum aktif';

  String get lockBody => (error ?? '').trim().isNotEmpty
      ? error!
      : TenantService.suspendedMessage;

  factory TenantAccessSnapshot.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const TenantAccessSnapshot(ok: true, reason: 'unknown');
    }
    final map = Map<String, dynamic>.from(raw);
    final invoices = <Map<String, dynamic>>[];
    final inv = map['invoices'];
    if (inv is List) {
      for (final e in inv) {
        if (e is Map) invoices.add(Map<String, dynamic>.from(e));
      }
    }
    return TenantAccessSnapshot(
      ok: map['ok'] == true,
      platform: map['platform'] == true,
      reason: map['reason']?.toString(),
      status: map['status']?.toString(),
      error: map['error']?.toString(),
      displayName: map['display_name']?.toString(),
      slug: map['slug']?.toString(),
      unsignedContractToken: map['unsigned_contract_token']?.toString(),
      invoices: invoices,
    );
  }
}

/// Cek akses tenant. RPC belum ada (migrasi 000008 belum) = jangan kunci Optik.
class TenantAccess {
  TenantAccess._();

  static Future<TenantAccessSnapshot> load({SupabaseClient? client}) async {
    try {
      final raw = await (client ?? supabase).rpc('my_tenant_access');
      return TenantAccessSnapshot.fromRpc(raw);
    } catch (e) {
      debugPrint('my_tenant_access: $e');
      return const TenantAccessSnapshot(ok: true, reason: 'rpc_missing');
    }
  }
}
