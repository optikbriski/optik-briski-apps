/// Tier Voucher Ongkir OBR (bukan gratis ongkir) berdasarkan subtotal belanja.
class ObrShippingVoucherTier {
  const ObrShippingVoucherTier({
    required this.id,
    required this.minSubtotal,
    required this.maxSubtotalExclusive,
    required this.maxDiscount,
    required this.allowedCategories,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final int minSubtotal;
  /// null = tanpa batas atas (≥ 1jt).
  final int? maxSubtotalExclusive;
  final int maxDiscount;
  final Set<String> allowedCategories;
  final String title;
  final String subtitle;

  static const all = <ObrShippingVoucherTier>[
    ObrShippingVoucherTier(
      id: 'obr_ship_0_150',
      minSubtotal: 0,
      maxSubtotalExclusive: 150000,
      maxDiscount: 2000,
      allowedCategories: {'nextday'},
      title: 'Voucher Ongkir OBR',
      subtitle: 'Diskon ongkir Rp 2.000 · OBR Next Day',
    ),
    ObrShippingVoucherTier(
      id: 'obr_ship_150_400',
      minSubtotal: 150000,
      maxSubtotalExclusive: 400000,
      maxDiscount: 6000,
      allowedCategories: {'nextday'},
      title: 'Voucher Ongkir OBR',
      subtitle: 'Diskon ongkir Rp 6.000 · OBR Next Day',
    ),
    ObrShippingVoucherTier(
      id: 'obr_ship_400_600',
      minSubtotal: 400000,
      maxSubtotalExclusive: 600000,
      maxDiscount: 8000,
      allowedCategories: {'nextday', 'sameday'},
      title: 'Voucher Ongkir OBR',
      subtitle: 'Diskon ongkir Rp 8.000 · OBR Next Day & Same Day',
    ),
    ObrShippingVoucherTier(
      id: 'obr_ship_600_1jt',
      minSubtotal: 600000,
      maxSubtotalExclusive: 1000000,
      maxDiscount: 16000,
      allowedCategories: {'nextday', 'sameday'},
      title: 'Voucher Ongkir OBR',
      subtitle: 'Diskon ongkir Rp 16.000 · OBR Next Day & Same Day',
    ),
    ObrShippingVoucherTier(
      id: 'obr_ship_1jt_plus',
      minSubtotal: 1000000,
      maxSubtotalExclusive: null,
      maxDiscount: 30000,
      allowedCategories: {'instant', 'sameday', 'nextday'},
      title: 'Voucher Ongkir OBR',
      subtitle: 'Diskon ongkir s.d. Rp 30.000 · semua OBR',
    ),
  ];

  static ObrShippingVoucherTier resolve(int subtotal) {
    final s = subtotal < 0 ? 0 : subtotal;
    for (final t in all) {
      final underMax = t.maxSubtotalExclusive == null ||
          s < t.maxSubtotalExclusive!;
      if (s >= t.minSubtotal && underMax) return t;
    }
    return all.last;
  }

  /// Tier berikutnya (untuk hint naik belanja), atau null jika sudah max.
  static ObrShippingVoucherTier? nextAfter(ObrShippingVoucherTier current) {
    final i = all.indexWhere((t) => t.id == current.id);
    if (i < 0 || i >= all.length - 1) return null;
    return all[i + 1];
  }

  String get minLabel {
    if (minSubtotal <= 0) return 'Rp 0';
    return _fmt(minSubtotal);
  }

  String get rangeLabel {
    if (maxSubtotalExclusive == null) {
      return 'Belanja ≥ ${_fmt(minSubtotal)}';
    }
    return 'Belanja $minLabel – ${_fmt(maxSubtotalExclusive! - 1)}';
  }

  String get categoriesLabel {
    final labels = <String>[];
    if (allowedCategories.contains('instant')) labels.add('Instant');
    if (allowedCategories.contains('sameday')) labels.add('Same Day');
    if (allowedCategories.contains('nextday')) labels.add('Next Day');
    return labels.join(' · ');
  }

  bool get isObrOnly => true;

  bool canApply({
    required bool isObr,
    required String? category,
    required int shippingFee,
  }) {
    if (!isObr) return false;
    if (shippingFee <= 0) return false;
    final cat = (category ?? '').trim().toLowerCase();
    if (cat.isEmpty) return false;
    return allowedCategories.contains(cat);
  }

  String? blockReason({
    required bool isObr,
    required String? category,
    required int shippingFee,
  }) {
    if (shippingFee <= 0) return 'Belum ada ongkir';
    if (!isObr) return 'Hanya untuk kurir OBR Delivery';
    final cat = (category ?? '').trim().toLowerCase();
    if (!allowedCategories.contains(cat)) {
      return 'Berlaku untuk OBR: $categoriesLabel';
    }
    return null;
  }

  int applyDiscount(int shippingFee) {
    if (shippingFee <= 0) return 0;
    final d = maxDiscount > shippingFee ? shippingFee : maxDiscount;
    return d < 0 ? 0 : d;
  }

  int feeAfterDiscount(int shippingFee) {
    final after = shippingFee - applyDiscount(shippingFee);
    return after < 0 ? 0 : after;
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return 'Rp $buf';
  }
}

/// Hitung diskon produk dari baris member_promos.
int productPromoDiscountRp(Map<String, dynamic> promo, int subtotal) {
  if (subtotal <= 0) return 0;
  final type = (promo['discount_type'] ?? 'nominal').toString().toLowerCase();
  final raw = int.tryParse('${promo['discount_value'] ?? 0}') ?? 0;
  if (raw <= 0 || type == 'info') return 0;
  if (type == 'percent') {
    final pct = raw > 100 ? 100 : raw;
    final d = (subtotal * pct / 100).floor();
    return d > subtotal ? subtotal : d;
  }
  // nominal
  return raw > subtotal ? subtotal : raw;
}

/// Hasil pilihan dari layar voucher.
class MemberVoucherSelection {
  const MemberVoucherSelection({
    this.useShippingVoucher = false,
    this.shippingTierId,
    this.productPromo,
  });

  final bool useShippingVoucher;
  final String? shippingTierId;
  final Map<String, dynamic>? productPromo;

  static const empty = MemberVoucherSelection();
}
