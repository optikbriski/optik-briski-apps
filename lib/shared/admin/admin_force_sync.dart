import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../config.dart';
import '../sync/client_force_sync.dart';
import '../tenant/tenant_modules.dart';
import '../tenant/tenant_service.dart';
import 'admin_force_sync_reload_stub.dart'
    if (dart.library.html) 'admin_force_sync_reload_web.dart';

/// Paksa sinkron **cabang** dari Admin: lokal + broadcast ke semua web/APK.
///
/// - Cabang biasa: sinkron toko itu saja; web pengirim boleh reload.
/// - **Pusat**: seolah semua cabang force-sync bersamaan; **tanpa** reload web
///   (hanya sinyal belakang + soft-refresh sesi/modul).
///
/// **Bukan** jalur kebocoran stok.
class AdminForceSync {
  AdminForceSync._();

  static const allBranchesToko = '*';

  /// [tokoId] = cabang login. Jika Pusat → sync semua cabang, tanpa reload web.
  static Future<AdminForceSyncResult> run({
    required String tokoId,
    bool reloadWeb = true,
  }) async {
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession == null) {
      throw StateError('Belum login — sinkron dibatalkan.');
    }
    final toko = tokoId.trim().toUpperCase();
    if (toko.isEmpty) {
      throw StateError('Toko cabang kosong — sinkron dibatalkan.');
    }

    // Jangan refreshSession di sini: gagal refresh (blip jaringan) bisa
    // men-sign-out lewat onAuthStateChange → user balik ke Login Admin.
    try {
      await TenantModules.instance.load().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('AdminForceSync TenantModules: $e');
    }

    final tenantId = (TenantService.instance.id ?? '').trim();
    if (tenantId.isEmpty) {
      throw StateError('Tenant belum terikat — sinkron dibatalkan.');
    }

    final isPusat = AttendanceAdminScope.isPusatTokoId(toko);
    if (isPusat) {
      final cabang = await _listTenantTokoIds()
          .timeout(const Duration(seconds: 8), onTimeout: () {
        return const ['PUSAT', 'CABANG-PUSAT'];
      });
      // Satu sinyal "semua cabang" agar tiap perangkat terima.
      await ClientForceSync.publish(
        tenantId: tenantId,
        tokoId: allBranchesToko,
        source: 'admin_pusat_${currentFlavor.name}',
      );
      // Best-effort: bangunkan channel stok per toko di belakang layar.
      // Jangan blok snackbar sukses — client remote sudah terima `*` via publish.
      unawaited(
        ClientForceSync.pingStockChannels(
          cabang,
          concurrency: 6,
          timeBudget: const Duration(seconds: 12),
        ),
      );
      // Pusat: jangan reload web — cukup sistem belakang.
      return AdminForceSyncResult(
        tokoId: allBranchesToko,
        pusatAllBranches: true,
        branchCount: cabang.length,
        reloadedWeb: false,
      );
    }

    await ClientForceSync.publish(
      tenantId: tenantId,
      tokoId: toko,
      source: 'admin_${currentFlavor.name}',
    );
    await ClientForceSync.pingStockChannel(toko);

    final doReload = reloadWeb && kIsWeb;
    if (doReload) {
      reloadAdminPageImpl();
    }
    return AdminForceSyncResult(
      tokoId: toko,
      pusatAllBranches: false,
      branchCount: 1,
      reloadedWeb: doReload,
    );
  }

  static String tokoFromProfile(Map<String, dynamic> profile) {
    return AttendanceAdminScope.tokoOf(profile).toUpperCase();
  }

  static Future<List<String>> _listTenantTokoIds() async {
    try {
      final rows = await Supabase.instance.client.from('toko_id').select('id');
      final out = <String>{};
      for (final raw in rows as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['id'] ?? m['toko_id'] ?? '').toString().trim().toUpperCase();
        if (id.isNotEmpty) out.add(id);
      }
      if (out.isEmpty) {
        out.addAll(const ['PUSAT', 'CABANG-PUSAT']);
      }
      return out.toList()..sort();
    } catch (e) {
      debugPrint('AdminForceSync list toko: $e');
      return const ['PUSAT', 'CABANG-PUSAT'];
    }
  }
}

class AdminForceSyncResult {
  const AdminForceSyncResult({
    required this.tokoId,
    required this.pusatAllBranches,
    required this.branchCount,
    required this.reloadedWeb,
  });

  final String tokoId;
  final bool pusatAllBranches;
  final int branchCount;
  final bool reloadedWeb;
}
