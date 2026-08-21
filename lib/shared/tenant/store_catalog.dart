import 'package:flutter/foundation.dart';

import '../bootstrap.dart';
import 'module_catalog.dart';

class StorePlanDef {
  const StorePlanDef({
    required this.planKey,
    required this.label,
    required this.priceIdr,
    required this.whiteLabel,
    required this.blurb,
    required this.highlight,
    required this.moduleKeys,
  });

  final String planKey;
  final String label;
  final int priceIdr;
  final bool whiteLabel;
  final String blurb;
  final String highlight;
  final List<String> moduleKeys;

  bool includes(String key) => moduleKeys.contains(key);
}

class StoreQuote {
  const StoreQuote({
    required this.baseIdr,
    required this.addOnIdr,
    required this.whiteLabelIdr,
    required this.amountIdr,
    required this.whiteLabel,
  });

  final int baseIdr;
  final int addOnIdr;
  final int whiteLabelIdr;
  final int amountIdr;
  final bool whiteLabel;
}

class StoreCatalog {
  StoreCatalog({
    required this.plans,
    required this.modules,
    this.whiteLabelAddonIdr = 200000,
    this.fromServer = false,
  });

  final List<StorePlanDef> plans;
  final List<StoreModuleDef> modules;
  final int whiteLabelAddonIdr;
  final bool fromServer;

  static StoreCatalog local() {
    return StoreCatalog(
      plans: const [
        StorePlanDef(
          planKey: 'paket_c',
          label: 'Paket C — Starter',
          priceIdr: 250000,
          whiteLabel: false,
          blurb:
              'Mulai jualan: kasir, master barang, aplikasi member. Kulit Rekasa + kode usaha.',
          highlight: 'Paling hemat',
          moduleKeys: ['pos', 'master_data', 'member_app'],
        ),
        StorePlanDef(
          planKey: 'paket_b',
          label: 'Paket B — Bisnis',
          priceIdr: 450000,
          whiteLabel: false,
          blurb:
              'Toko berkembang: stok antar cabang, garansi, absensi, riwayat DP. Masih kulit Rekasa.',
          highlight: 'Paling laku',
          moduleKeys: [
            'pos',
            'master_data',
            'member_app',
            'logistics',
            'warranty',
            'attendance',
            'history_dp',
          ],
        ),
        StorePlanDef(
          planKey: 'paket_a',
          label: 'Paket A — Pro',
          priceIdr: 750000,
          whiteLabel: true,
          blurb: 'Semua modul + APK & web nama+ikon merek sendiri. Paket tertinggi.',
          highlight: 'Tertinggi',
          moduleKeys: [
            'pos',
            'master_data',
            'member_app',
            'logistics',
            'warranty',
            'attendance',
            'history_dp',
            'finance',
            'online_orders',
          ],
        ),
      ],
      modules: List.of(moduleCatalog),
    );
  }

  StoreModuleDef? module(String key) {
    for (final m in modules) {
      if (m.key == key) return m;
    }
    return null;
  }

  StoreQuote quote({
    required StorePlanDef plan,
    required Map<String, bool> enabled,
    required bool whiteLabel,
  }) {
    var add = 0;
    enabled.forEach((key, on) {
      if (!on) return;
      if (plan.includes(key)) return;
      add += module(key)?.addOnPriceIdr ?? 50000;
    });
    final wl = whiteLabel && !plan.whiteLabel ? whiteLabelAddonIdr : 0;
    return StoreQuote(
      baseIdr: plan.priceIdr,
      addOnIdr: add,
      whiteLabelIdr: wl,
      amountIdr: plan.priceIdr + add + wl,
      whiteLabel: whiteLabel,
    );
  }

  static Future<StoreCatalog> load() async {
    try {
      final raw = await supabase.rpc('list_store_catalog');
      if (raw is! Map || raw['ok'] != true) return StoreCatalog.local();
      return fromRpc(Map<String, dynamic>.from(raw));
    } catch (e) {
      debugPrint('list_store_catalog: $e');
      return StoreCatalog.local();
    }
  }

  static StoreCatalog fromRpc(Map<String, dynamic> raw) {
    final plans = <StorePlanDef>[];
    final modules = <StoreModuleDef>[];
    final p = raw['plans'];
    if (p is List) {
      for (final e in p) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final keys = <String>[];
        final mods = m['modules'];
        if (mods is List) {
          for (final k in mods) {
            final s = '$k'.trim();
            if (s.isNotEmpty) keys.add(s);
          }
        }
        plans.add(
          StorePlanDef(
            planKey: '${m['plan_key']}',
            label: '${m['label'] ?? m['plan_key']}',
            priceIdr: int.tryParse('${m['price_idr']}') ?? 0,
            whiteLabel: m['white_label'] == true,
            blurb: '${m['blurb'] ?? ''}',
            highlight: '${m['highlight'] ?? ''}',
            moduleKeys: keys,
          ),
        );
      }
    }
    final mods = raw['modules'];
    if (mods is List) {
      for (final e in mods) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        modules.add(
          StoreModuleDef(
            key: '${m['key']}',
            label: '${m['label'] ?? m['key']}',
            summary: '${m['summary'] ?? ''}',
            body: '${m['body'] ?? ''}',
            videoUrl: (m['video_url'] ?? '').toString().trim().isEmpty
                ? null
                : '${m['video_url']}'.trim(),
            addOnPriceIdr: int.tryParse('${m['add_on_price_idr']}') ?? 50000,
          ),
        );
      }
    }
    if (plans.isEmpty || modules.isEmpty) return StoreCatalog.local();
    return StoreCatalog(
      plans: plans,
      modules: modules,
      whiteLabelAddonIdr:
          int.tryParse('${raw['white_label_addon_idr']}') ?? 200000,
      fromServer: true,
    );
  }
}

/// YouTube / tautan video → URL embed atau buka luar.
class StoreVideo {
  static String? youtubeId(String? raw) {
    final u = (raw ?? '').trim();
    if (u.isEmpty) return null;
    final uri = Uri.tryParse(u);
    if (uri == null) return null;
    final host = uri.host.replaceFirst('www.', '');
    if (host == 'youtu.be') {
      final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      return id.isEmpty ? null : id;
    }
    if (host.contains('youtube.com')) {
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
      final segs = uri.pathSegments;
      if (segs.length >= 2 &&
          (segs.first == 'embed' ||
              segs.first == 'shorts' ||
              segs.first == 'live')) {
        return segs[1];
      }
    }
    return null;
  }

  static String? embedUrl(String? raw) {
    final id = youtubeId(raw);
    if (id != null) {
      return 'https://www.youtube-nocookie.com/embed/$id?rel=0&modestbranding=1';
    }
    final u = (raw ?? '').trim();
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    return null;
  }
}
