import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keranjang belanja Member (persist lokal).
class MemberCart extends ChangeNotifier {
  MemberCart._();
  static final MemberCart instance = MemberCart._();

  static const _prefsKey = 'member_cart_v1';

  final List<MemberCartItem> _items = [];
  bool _loaded = false;

  List<MemberCartItem> get items => List.unmodifiable(_items);
  int get totalQty => _items.fold(0, (s, e) => s + e.qty);
  int get subtotal => _items.fold(0, (s, e) => s + e.lineTotal);
  bool get isEmpty => _items.isEmpty;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _items.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          if (e is Map) {
            _items.add(MemberCartItem.fromMap(Map<String, dynamic>.from(e)));
          }
        }
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_items.map((e) => e.toMap()).toList()),
    );
  }

  /// Lensa custom tidak dijual online.
  static bool isOnlineBlocked(Map<String, dynamic> product) {
    final kat = (product['kategori'] ?? '').toString().trim().toLowerCase();
    return kat == 'lensa';
  }

  Future<String?> addProduct(Map<String, dynamic> product, {int qty = 1}) async {
    await ensureLoaded();
    if (isOnlineBlocked(product)) {
      return 'Lensa custom tidak dijual online. Pesan lewat cabang / booking.';
    }
    final sku = (product['sku'] ?? '').toString().trim();
    if (sku.isEmpty) return 'Produk tanpa SKU tidak bisa dibeli online.';
    final harga = int.tryParse('${product['harga'] ?? 0}') ?? 0;
    if (harga <= 0) return 'Harga produk tidak valid.';
    // Stok cabang dicek di checkout; jika kurang → pre-order → RO cabang.

    final i = _items.indexWhere((e) => e.sku.toUpperCase() == sku.toUpperCase());
    final nextQty = (i >= 0 ? _items[i].qty : 0) + qty;
    if (i >= 0) {
      _items[i] = _items[i].copyWith(qty: nextQty);
    } else {
      _items.add(MemberCartItem(
        sku: sku,
        productId: (product['id'] ?? '').toString(),
        nama: (product['nama'] ?? sku).toString(),
        kategori: (product['kategori'] ?? '').toString(),
        harga: harga,
        qty: qty,
        imageUrl: (product['image_url'] ?? '').toString(),
      ));
    }
    await _persist();
    notifyListeners();
    return null;
  }

  Future<void> setQty(String sku, int qty) async {
    await ensureLoaded();
    final i = _items.indexWhere((e) => e.sku.toUpperCase() == sku.toUpperCase());
    if (i < 0) return;
    if (qty <= 0) {
      _items.removeAt(i);
    } else {
      _items[i] = _items[i].copyWith(qty: qty);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String sku) async {
    await setQty(sku, 0);
  }

  Future<void> clear() async {
    _items.clear();
    await _persist();
    notifyListeners();
  }

  List<Map<String, dynamic>> toCheckoutItems() =>
      _items.map((e) => e.toCheckoutMap()).toList();
}

class MemberCartItem {
  const MemberCartItem({
    required this.sku,
    required this.productId,
    required this.nama,
    required this.kategori,
    required this.harga,
    required this.qty,
    this.imageUrl = '',
  });

  final String sku;
  final String productId;
  final String nama;
  final String kategori;
  final int harga;
  final int qty;
  final String imageUrl;

  int get lineTotal => harga * qty;

  MemberCartItem copyWith({int? qty}) => MemberCartItem(
        sku: sku,
        productId: productId,
        nama: nama,
        kategori: kategori,
        harga: harga,
        qty: qty ?? this.qty,
        imageUrl: imageUrl,
      );

  Map<String, dynamic> toMap() => {
        'sku': sku,
        'product_id': productId,
        'nama': nama,
        'kategori': kategori,
        'harga': harga,
        'qty': qty,
        'image_url': imageUrl,
      };

  Map<String, dynamic> toCheckoutMap() => {
        'sku': sku,
        'qty': qty,
        'harga': harga,
        'nama': nama,
        'kategori': kategori,
      };

  factory MemberCartItem.fromMap(Map<String, dynamic> m) => MemberCartItem(
        sku: (m['sku'] ?? '').toString(),
        productId: (m['product_id'] ?? m['id'] ?? '').toString(),
        nama: (m['nama'] ?? '').toString(),
        kategori: (m['kategori'] ?? '').toString(),
        harga: int.tryParse('${m['harga'] ?? 0}') ?? 0,
        qty: int.tryParse('${m['qty'] ?? 1}') ?? 1,
        imageUrl: (m['image_url'] ?? '').toString(),
      );
}
