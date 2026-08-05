import 'package:supabase_flutter/supabase_flutter.dart';

import 'invoice_status_footer.dart';

/// Konfigurasi layout nota per cabang (`invoice_settings`).
class InvoiceSettings {
  const InvoiceSettings({
    required this.tokoId,
    required this.shopName,
    required this.address,
    required this.phone,
    required this.logoUrl,
    required this.statusFooters,
    required this.googleReviewUrl,
    required this.headerAlignment,
    required this.fontSizeHeader,
    required this.fontSizeBody,
    required this.showQrInvoice,
  });

  final String tokoId;
  final String shopName;
  final String address;
  final String phone;
  final String logoUrl;
  final InvoiceStatusFooters statusFooters;
  final String googleReviewUrl;
  final String headerAlignment; // CENTER | LEFT
  final double fontSizeHeader;
  final double fontSizeBody;
  final bool showQrInvoice;

  bool get isCenter => headerAlignment.toUpperCase() != 'LEFT';
  bool get hasLogo => logoUrl.trim().isNotEmpty;

  /// Fallback teks (bukan JSON) bila pemanggil belum resolve per status.
  String get footerText => statusFooters.pending;

  InvoiceSettings copyWith({
    String? tokoId,
    String? shopName,
    String? address,
    String? phone,
    String? logoUrl,
    InvoiceStatusFooters? statusFooters,
    String? googleReviewUrl,
    String? headerAlignment,
    double? fontSizeHeader,
    double? fontSizeBody,
    bool? showQrInvoice,
  }) {
    return InvoiceSettings(
      tokoId: tokoId ?? this.tokoId,
      shopName: shopName ?? this.shopName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      logoUrl: logoUrl ?? this.logoUrl,
      statusFooters: statusFooters ?? this.statusFooters,
      googleReviewUrl: googleReviewUrl ?? this.googleReviewUrl,
      headerAlignment: headerAlignment ?? this.headerAlignment,
      fontSizeHeader: fontSizeHeader ?? this.fontSizeHeader,
      fontSizeBody: fontSizeBody ?? this.fontSizeBody,
      showQrInvoice: showQrInvoice ?? this.showQrInvoice,
    );
  }

  Map<String, dynamic> toMap() => {
        'toko_id': tokoId,
        'shop_name': shopName,
        'address': address,
        'phone': phone,
        // Jangan kirim null — upsert null bisa menghapus nilai lama / gagal diam-diam.
        'logo_url': logoUrl.trim(),
        'footer_text': statusFooters.encode(),
        'google_review_url': googleReviewUrl.trim(),
        'header_alignment': isCenter ? 'CENTER' : 'LEFT',
        'font_size_header': fontSizeHeader.round(),
        'font_size_body': fontSizeBody.round(),
        'show_qr_invoice': showQrInvoice,
      };

  /// Kompatibel dengan konsumen lama yang masih pakai Map config.
  Map<String, dynamic> toLegacyConfigMap() => {
        'toko_id': tokoId,
        'shop_name': shopName,
        'address': address,
        'phone': phone,
        'logo_url': logoUrl,
        'footer_text': footerText,
        'footer_by_status': {
          'dp': statusFooters.dp,
          'pending': statusFooters.pending,
          'ready': statusFooters.ready,
          'clear': statusFooters.clear,
        },
        'google_review_url': googleReviewUrl,
        'header_alignment': isCenter ? 'CENTER' : 'LEFT',
        'font_size_header': fontSizeHeader.round(),
        'font_size_body': fontSizeBody.round(),
        'show_qr_invoice': showQrInvoice,
      };

  factory InvoiceSettings.fromRow(Map<String, dynamic> row, {String? tokoId}) {
    final id = InvoiceSettingsService.normalizeTokoId(
        tokoId ?? row['toko_id']?.toString());
    return InvoiceSettings(
      tokoId: id,
      shopName: (row['shop_name'] ??
              InvoiceSettingsService.defaultShopName(id))
          .toString(),
      address: (row['address'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      logoUrl: (row['logo_url'] ?? '').toString(),
      statusFooters:
          InvoiceStatusFooters.decode(row['footer_text']?.toString()),
      googleReviewUrl: (row['google_review_url'] ?? '').toString(),
      headerAlignment:
          (row['header_alignment'] ?? 'CENTER').toString().toUpperCase() ==
                  'LEFT'
              ? 'LEFT'
              : 'CENTER',
      fontSizeHeader:
          (num.tryParse('${row['font_size_header'] ?? 16}') ?? 16).toDouble(),
      fontSizeBody:
          (num.tryParse('${row['font_size_body'] ?? 12}') ?? 12).toDouble(),
      showQrInvoice: row['show_qr_invoice'] != false,
    );
  }

  /// Default tunggal — dipakai jika cabang & PUSAT belum punya setting.
  factory InvoiceSettings.defaults(String tokoId) {
    final id = InvoiceSettingsService.normalizeTokoId(tokoId);
    return InvoiceSettings(
      tokoId: id,
      shopName: InvoiceSettingsService.defaultShopName(id),
      address: id == 'PUSAT' ? '' : '',
      phone: '-',
      logoUrl: '',
      statusFooters: InvoiceStatusFooters.defaults(),
      googleReviewUrl: '',
      headerAlignment: 'CENTER',
      fontSizeHeader: 16,
      fontSizeBody: 12,
      showQrInvoice: true,
    );
  }
}

class InvoiceSettingsService {
  InvoiceSettingsService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static String normalizeTokoId(String? raw) {
    final t = (raw ?? '').trim().toUpperCase();
    return t.isEmpty ? 'PUSAT' : t;
  }

  /// Banner struk default per cabang: `OPTIK B. RISKI PUSAT` / `OPTIK B. RISKI CIKARANG`.
  static String defaultShopName(String? tokoId) {
    final id = normalizeTokoId(tokoId);
    if (id == 'PUSAT') return 'OPTIK B. RISKI PUSAT';
    var label = id;
    if (label.startsWith('CABANG-')) {
      label = label.substring('CABANG-'.length);
    } else if (label.startsWith('CABANG_')) {
      label = label.substring('CABANG_'.length);
    } else if (label.startsWith('CABANG ')) {
      label = label.substring('CABANG '.length);
    }
    label = label.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    while (label.contains('  ')) {
      label = label.replaceAll('  ', ' ');
    }
    if (label.isEmpty) label = id;
    return 'OPTIK B. RISKI $label';
  }

  /// Ganti nama toko generik/Pusat pada cabang → nama sesuai kode cabang.
  static InvoiceSettings withBranchShopName(InvoiceSettings settings) {
    final id = normalizeTokoId(settings.tokoId);
    final desired = defaultShopName(id);
    final current = settings.shopName.trim().toUpperCase();
    final looksGeneric = current.isEmpty ||
        current == 'OPTIK B. RISKI' ||
        current == 'OPTIK B. RISKI PUSAT' ||
        (id != 'PUSAT' && current.contains('PUSAT'));
    if (!looksGeneric) return settings;
    return settings.copyWith(shopName: desired);
  }

  /// Cabang dari master `toko_id`, selalu sertakan PUSAT.
  Future<List<String>> listCabang() async {
    final set = <String>{'PUSAT'};
    try {
      final rows = await _db.from('toko_id').select('id');
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final id = normalizeTokoId(row['id']?.toString());
        if (id.isNotEmpty) set.add(id);
      }
    } catch (_) {
      // Fallback: cabang yang sudah punya setting
      try {
        final rows = await _db.from('invoice_settings').select('toko_id');
        for (final row in List<Map<String, dynamic>>.from(rows as List)) {
          set.add(normalizeTokoId(row['toko_id']?.toString()));
        }
      } catch (_) {}
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<InvoiceSettings?> _fetchRow(String tokoId) async {
    try {
      final row = await _db
          .from('invoice_settings')
          .select()
          .eq('toko_id', tokoId)
          .maybeSingle();
      if (row == null) return null;
      return InvoiceSettings.fromRow(Map<String, dynamic>.from(row),
          tokoId: tokoId);
    } catch (_) {
      return null;
    }
  }

  /// Footer cabang yang masih inherit → teks selalu dari PUSAT.
  Future<InvoiceSettings> _resolveFooters(InvoiceSettings settings) async {
    final id = normalizeTokoId(settings.tokoId);
    if (id == 'PUSAT' || !settings.statusFooters.inheritFromPusat) {
      return id == 'PUSAT'
          ? settings.copyWith(
              statusFooters:
                  settings.statusFooters.copyWith(inheritFromPusat: false),
            )
          : settings;
    }
    final pusat = await _fetchRow('PUSAT') ?? InvoiceSettings.defaults('PUSAT');
    return settings.copyWith(
      statusFooters: InvoiceStatusFooters.inheritedFrom(pusat.statusFooters),
    );
  }

  /// Cabang → PUSAT → default tunggal.
  /// Footer cabang: awal wajib sama PUSAT (inherit), bisa di-adjust nanti.
  /// Nama toko cabang: `OPTIK B. RISKI {CABANG}`, bukan ikut teks PUSAT.
  Future<InvoiceSettings> fetchForToko(String? tokoId) async {
    final id = normalizeTokoId(tokoId);
    final own = await _fetchRow(id);
    if (own != null) {
      return withBranchShopName(await _resolveFooters(own));
    }

    if (id != 'PUSAT') {
      final pusat = await _fetchRow('PUSAT');
      if (pusat != null) {
        return withBranchShopName(
          pusat.copyWith(
            tokoId: id,
            shopName: defaultShopName(id),
            address: '',
            phone: pusat.phone.trim().isEmpty ? '-' : pusat.phone,
            statusFooters:
                InvoiceStatusFooters.inheritedFrom(pusat.statusFooters),
          ),
        );
      }
    }

    return InvoiceSettings.defaults(id);
  }

  /// Simpan semua kolom, lalu baca ulang dari DB (bukti tersimpan).
  Future<InvoiceSettings> save(InvoiceSettings settings) async {
    final id = normalizeTokoId(settings.tokoId);
    var toSave = settings.copyWith(tokoId: id);
    // Master PUSAT tidak pernah inherit.
    if (id == 'PUSAT') {
      toSave = toSave.copyWith(
        statusFooters:
            toSave.statusFooters.copyWith(inheritFromPusat: false),
      );
    } else if (toSave.statusFooters.inheritFromPusat) {
      // Cabang inherit: simpan flag + salinan teks Pusat saat ini.
      final pusat =
          await _fetchRow('PUSAT') ?? InvoiceSettings.defaults('PUSAT');
      toSave = toSave.copyWith(
        statusFooters: InvoiceStatusFooters.inheritedFrom(pusat.statusFooters),
      );
    }

    final payload = toSave.toMap();
    payload['updated_at'] = DateTime.now().toIso8601String();

    final saved = await _db
        .from('invoice_settings')
        .upsert(payload, onConflict: 'toko_id')
        .select()
        .single();

    return _resolveFooters(InvoiceSettings.fromRow(
      Map<String, dynamic>.from(saved),
      tokoId: id,
    ));
  }

  Future<void> deleteCabang(String tokoId) async {
    final id = normalizeTokoId(tokoId);
    if (id == 'PUSAT') {
      throw StateError('Setting PUSAT tidak boleh dihapus');
    }
    await _db.from('invoice_settings').delete().eq('toko_id', id);
  }

  /// Preview: sale terbaru cabang (boleh null).
  Future<({Map<String, dynamic>? sale, List<Map<String, dynamic>> items})>
      fetchPreviewSale(String tokoId) async {
    final id = normalizeTokoId(tokoId);
    final sale = await _db
        .from('sales')
        .select()
        .eq('toko_id', id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (sale == null) {
      return (sale: null, items: <Map<String, dynamic>>[]);
    }
    final items = await _db
        .from('sales_items')
        .select()
        .eq('sale_id', sale['id']);
    return (
      sale: Map<String, dynamic>.from(sale),
      items: List<Map<String, dynamic>>.from(items as List),
    );
  }
}
