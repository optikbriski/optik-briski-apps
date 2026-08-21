import 'package:flutter/foundation.dart';

import '../bootstrap.dart';
import 'industry_catalog.dart';
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
    this.fromServer = false,
  });

  final int baseIdr;
  final int addOnIdr;
  final int whiteLabelIdr;
  final int amountIdr;
  final bool whiteLabel;
  final bool fromServer;

  factory StoreQuote.fromRpc(dynamic raw, {required StoreQuote fallback}) {
    if (raw is! Map || raw['ok'] != true) return fallback;
    int n(dynamic v, int d) => int.tryParse('$v'.split('.').first) ?? d;
    return StoreQuote(
      baseIdr: n(raw['base_idr'], fallback.baseIdr),
      addOnIdr: n(raw['add_on_idr'], fallback.addOnIdr),
      whiteLabelIdr: n(raw['white_label_idr'], fallback.whiteLabelIdr),
      amountIdr: n(raw['amount_idr'], fallback.amountIdr),
      whiteLabel: raw['white_label'] == true || fallback.whiteLabel,
      fromServer: true,
    );
  }
}

class StoreCatalog {
  StoreCatalog({
    required this.plans,
    required this.modules,
    this.industries = const [],
    this.industryKey,
    this.whiteLabelAddonIdr = 200000,
    this.fromServer = false,
  });

  final List<StorePlanDef> plans;
  final List<StoreModuleDef> modules;
  final List<StoreIndustryDef> industries;
  final String? industryKey;
  final int whiteLabelAddonIdr;
  final bool fromServer;

  StoreIndustryDef? get industry {
    for (final i in industries) {
      if (i.key == industryKey) return i;
    }
    return industryByKey(industryKey);
  }

  static StoreCatalog local([String? industryKey]) {
    final industries = List<StoreIndustryDef>.from(industryCatalog);
    final pack = industryByKey(industryKey);
    if (pack == null) {
      return StoreCatalog(plans: const [], modules: const [], industries: industries);
    }
    final prices = <String, int>{
      'paket_c': 250000,
      'paket_b': 450000,
      'paket_a': 750000,
    };
    final labels = <String, String>{
      'paket_c': 'Paket C — Starter',
      'paket_b': 'Paket B — Bisnis',
      'paket_a': 'Paket A — Pro',
    };
    final blurbs = <String, String>{
      'paket_c': 'Mulai jalan. Kulit Rekasa + kode usaha.',
      'paket_b': 'Operasional lebih lengkap. Masih kulit Rekasa.',
      'paket_a': 'Paket tertinggi: modul penuh bidang ini + merek sendiri.',
    };
    final highlights = <String, String>{
      'paket_c': 'Hemat',
      'paket_b': 'Laku',
      'paket_a': 'Tertinggi',
    };
    final modules = <StoreModuleDef>[];
    pack.copy.forEach((key, m) {
      final base = moduleCatalog.cast<StoreModuleDef?>().firstWhere(
            (e) => e!.key == key,
            orElse: () => null,
          );
      modules.add(
        StoreModuleDef(
          key: m.key,
          label: m.label,
          summary: m.summary,
          body: m.body,
          videoUrl: m.videoUrl ?? base?.videoUrl,
          addOnPriceIdr: m.addOnPriceIdr != 50000
              ? m.addOnPriceIdr
              : (base?.addOnPriceIdr ?? 50000),
        ),
      );
    });
    return StoreCatalog(
      industryKey: pack.key,
      industries: industries,
      modules: modules,
      plans: [
        for (final k in ['paket_c', 'paket_b', 'paket_a'])
          StorePlanDef(
            planKey: k,
            label: labels[k]!,
            priceIdr: prices[k]!,
            whiteLabel: k == 'paket_a',
            blurb: '${blurbs[k]} ${pack.blurb}',
            highlight: highlights[k]!,
            moduleKeys: pack.modulesFor(k),
          ),
      ],
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

  static Future<StoreCatalog> load([String? industryKey]) async {
    try {
      final raw = await supabase.rpc(
        'list_store_catalog',
        params: {'p_industry_key': industryKey},
      );
      if (raw is! Map || raw['ok'] != true) {
        return StoreCatalog.local(industryKey);
      }
      return fromRpc(Map<String, dynamic>.from(raw), fallbackIndustry: industryKey);
    } catch (e) {
      debugPrint('list_store_catalog: $e');
      try {
        final raw = await supabase.rpc('list_store_catalog');
        if (raw is Map && raw['ok'] == true) {
          return fromRpc(
            Map<String, dynamic>.from(raw),
            fallbackIndustry: industryKey,
          );
        }
      } catch (e2) {
        debugPrint('list_store_catalog fallback: $e2');
      }
      return StoreCatalog.local(industryKey);
    }
  }

  Future<StoreQuote> quoteRemote({
    required StorePlanDef plan,
    required Map<String, bool> enabled,
    required bool whiteLabel,
  }) async {
    final local = quote(plan: plan, enabled: enabled, whiteLabel: whiteLabel);
    Future<StoreQuote> call(Map<String, dynamic> params) async {
      final raw = await supabase.rpc('quote_store_order', params: params);
      return StoreQuote.fromRpc(raw, fallback: local);
    }

    try {
      return await call({
        'p_plan_key': plan.planKey,
        'p_modules': enabled,
        'p_white_label': whiteLabel,
        'p_industry_key': industryKey ?? 'umum',
      });
    } catch (e) {
      debugPrint('quote_store_order: $e');
      try {
        return await call({
          'p_plan_key': plan.planKey,
          'p_modules': enabled,
          'p_white_label': whiteLabel,
        });
      } catch (e2) {
        debugPrint('quote_store_order fallback: $e2');
        return local;
      }
    }
  }

  static StoreCatalog fromRpc(
    Map<String, dynamic> raw, {
    String? fallbackIndustry,
  }) {
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
    final industries = <StoreIndustryDef>[];
    final inds = raw['industries'];
    if (inds is List) {
      for (final e in inds) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final local = industryByKey('${m['key']}');
        industries.add(
          StoreIndustryDef(
            key: '${m['key']}',
            label: '${m['label'] ?? m['key']}',
            blurb: '${m['blurb'] ?? local?.blurb ?? ''}',
            planModules: local?.planModules ?? const {},
            copy: local?.copy ?? const {},
          ),
        );
      }
    }
    final selected = (raw['industry_key'] ?? fallbackIndustry)?.toString();
    if (plans.isEmpty || modules.isEmpty) {
      final local = StoreCatalog.local(selected);
      return StoreCatalog(
        plans: local.plans,
        modules: local.modules,
        industries: industries.isEmpty ? local.industries : industries,
        industryKey: selected,
        whiteLabelAddonIdr:
            int.tryParse('${raw['white_label_addon_idr']}') ?? 200000,
        fromServer: true,
      );
    }
    return StoreCatalog(
      plans: plans,
      modules: modules,
      industries: industries.isEmpty ? industryCatalog : industries,
      industryKey: selected,
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
