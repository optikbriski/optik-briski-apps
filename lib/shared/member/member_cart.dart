import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'member_catalog_kategori.dart';

/// Copy tunggal: Lensa tidak dijual online (cart / detail / checkout client).
const kMemberOnlineBlockedLensaMessage =
    'Lensa custom tidak dijual online. Pesan via WhatsApp cabang atau booking di toko.';

/// Batas qty per baris keranjang (UI +/- + addProduct).
const kMemberCartMaxQtyPerLine = 99;

/// Keranjang belanja Member (persist lokal).
///
/// **Badge / shell:** [totalQty] = jumlah qty **semua** baris (bukan hanya
/// tercentang). Selection hanya memengaruhi subtotal + checkout.
///
/// Selection (SKU tercentang) hidup di sesi in-memory — tidak di-persist.
/// Default: semua item tercentang saat load / item baru ditambah.
class MemberCart extends ChangeNotifier {
  MemberCart._();
  static final MemberCart instance = MemberCart._();

  static const _prefsKey = 'member_cart_v1';

  final List<MemberCartItem> _items = [];
  /// SKU (UPPER) yang ikut checkout.
  final Set<String> _selectedSkus = {};
  bool _loaded = false;
  Future<void>? _loading;
  /// Serialisasi mutasi supaya tap +/- cepat tidak race (qty ketinggalan).
  Future<void> _writeQueue = Future<void>.value();

  List<MemberCartItem> get items => List.unmodifiable(_items);

  /// Qty semua baris — dipakai badge shell / katalog (bukan selected-only).
  int get totalQty => _items.fold(0, (s, e) => s + e.qty);

  /// Subtotal semua baris (abaikan selection). Untuk debug / legacy.
  int get subtotal => _items.fold(0, (s, e) => s + e.lineTotal);
  bool get isEmpty => _items.isEmpty;

  List<MemberCartItem> get selectedItems => _items
      .where((e) => _selectedSkus.contains(e.sku.toUpperCase()))
      .toList(growable: false);

  int get selectedSubtotal =>
      selectedItems.fold(0, (s, e) => s + e.lineTotal);

  bool get hasSelection => selectedItems.isNotEmpty;

  bool get allSelected =>
      _items.isNotEmpty &&
      _items.every((e) => _selectedSkus.contains(e.sku.toUpperCase()));

  bool isSelected(String sku) =>
      _selectedSkus.contains(_skuKey(sku));

  static String _skuKey(String sku) => sku.trim().toUpperCase();

  static int clampQty(int qty) {
    if (qty <= 0) return 0;
    if (qty > kMemberCartMaxQtyPerLine) return kMemberCartMaxQtyPerLine;
    return qty;
  }

  void setSelected(String sku, bool selected) {
    final key = _skuKey(sku);
    if (key.isEmpty) return;
    final exists = _items.any((e) => e.sku.toUpperCase() == key);
    if (!exists) return;
    if (selected) {
      _selectedSkus.add(key);
    } else {
      _selectedSkus.remove(key);
    }
    notifyListeners();
  }

  void setAllSelected(bool selected) {
    _selectedSkus.clear();
    if (selected) {
      for (final e in _items) {
        final key = e.sku.toUpperCase();
        if (key.isNotEmpty) _selectedSkus.add(key);
      }
    }
    notifyListeners();
  }

  void _pruneSelection() {
    final present = _items.map((e) => e.sku.toUpperCase()).toSet();
    _selectedSkus.removeWhere((s) => !present.contains(s));
  }

  void _selectAllPresent() {
    _selectedSkus
      ..clear()
      ..addAll(_items.map((e) => e.sku.toUpperCase()).where((s) => s.isNotEmpty));
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    if (_loading != null) {
      await _loading;
      return;
    }
    _loading = _loadFromPrefs();
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _loadFromPrefs() async {
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
    // Jangan biarkan Lensa / baris rusak tersisa dari prefs lama.
    final changed = _sanitizeUnlocked();
    _selectAllPresent();
    _loaded = true;
    if (changed) await _persist();
    notifyListeners();
  }

  /// Hapus lensa, SKU kosong, qty/harga invalid; merge SKU duplikat.
  /// Return true jika isi berubah.
  bool _sanitizeUnlocked() {
    final before = jsonEncode(_items.map((e) => e.toMap()).toList());
    final merged = <String, MemberCartItem>{};
    for (final e in _items) {
      final key = _skuKey(e.sku);
      if (key.isEmpty) continue;
      if (isOnlineBlockedKategori(e.kategori)) continue;
      final qty = clampQty(e.qty);
      if (qty <= 0) continue;
      if (e.harga <= 0) continue;
      final prev = merged[key];
      if (prev == null) {
        merged[key] = e.copyWith(qty: qty);
      } else {
        merged[key] = prev.copyWith(
          qty: clampQty(prev.qty + qty),
          // Prefer data baris belakangan (lebih baru di prefs).
          productId: e.productId.isNotEmpty ? e.productId : prev.productId,
          nama: e.nama.isNotEmpty ? e.nama : prev.nama,
          kategori: e.kategori.isNotEmpty ? e.kategori : prev.kategori,
          harga: e.harga > 0 ? e.harga : prev.harga,
          imageUrl: e.imageUrl.isNotEmpty ? e.imageUrl : prev.imageUrl,
        );
      }
    }
    _items
      ..clear()
      ..addAll(merged.values);
    final after = jsonEncode(_items.map((e) => e.toMap()).toList());
    return before != after;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_items.map((e) => e.toMap()).toList()),
    );
  }

  /// Lensa (semua alias case/trim) tidak dijual online.
  static bool isOnlineBlockedKategori(Object? kategori) =>
      normalizeMemberProductKategori(kategori) == 'lensa';

  /// Lensa custom tidak dijual online.
  static bool isOnlineBlocked(Map<String, dynamic> product) =>
      isOnlineBlockedKategori(product['kategori']);

  /// True jika ada baris tercentang yang diblokir online (Lensa).
  bool get hasOnlineBlockedSelection =>
      selectedItems.any((e) => isOnlineBlockedKategori(e.kategori));

  /// Pesan error bila selection mengandung Lensa; null jika aman.
  String? get onlineBlockedSelectionError =>
      hasOnlineBlockedSelection ? kMemberOnlineBlockedLensaMessage : null;

  /// Hapus semua baris Lensa dari keranjang (persist). Return jumlah dihapus.
  Future<int> purgeOnlineBlocked() => _enqueueWrite(() async {
        await ensureLoaded();
        final before = _items.length;
        if (!_purgeOnlineBlockedUnlocked()) return 0;
        _pruneSelection();
        await _persist();
        notifyListeners();
        return before - _items.length;
      });

  bool _purgeOnlineBlockedUnlocked() {
    final before = _items.length;
    _items.removeWhere((e) => isOnlineBlockedKategori(e.kategori));
    return _items.length != before;
  }

  Future<String?> addProduct(Map<String, dynamic> product, {int qty = 1}) =>
      _enqueueWrite(() async {
        await ensureLoaded();
        if (isOnlineBlocked(product)) {
          return kMemberOnlineBlockedLensaMessage;
        }
        final sku = (product['sku'] ?? '').toString().trim();
        if (sku.isEmpty) return 'Produk tanpa SKU tidak bisa dibeli online.';
        final harga = int.tryParse('${product['harga'] ?? 0}') ?? 0;
        if (harga <= 0) return 'Harga produk tidak valid.';
        // Stok cabang dicek di checkout; jika kurang → pre-order → RO cabang.

        final addQty = qty < 1 ? 1 : qty;
        final i =
            _items.indexWhere((e) => e.sku.toUpperCase() == sku.toUpperCase());
        final current = i >= 0 ? _items[i].qty : 0;
        if (current >= kMemberCartMaxQtyPerLine) {
          return 'Maksimal $kMemberCartMaxQtyPerLine pcs per produk.';
        }
        final nextQty = clampQty(current + addQty);
        final productId = (product['id'] ?? '').toString();
        final nama = (product['nama'] ?? sku).toString();
        final kategori = (product['kategori'] ?? '').toString();
        final imageUrl = (product['image_url'] ?? '').toString();
        if (i >= 0) {
          // Refresh nama/harga/gambar dari master saat qty bertambah.
          _items[i] = _items[i].copyWith(
            qty: nextQty,
            productId: productId.isNotEmpty ? productId : null,
            nama: nama,
            kategori: kategori,
            harga: harga,
            imageUrl: imageUrl,
          );
        } else {
          _items.add(MemberCartItem(
            sku: sku,
            productId: productId,
            nama: nama,
            kategori: kategori,
            harga: harga,
            qty: nextQty,
            imageUrl: imageUrl,
          ));
        }
        // Item baru / qty bertambah: tetap / jadi tercentang.
        _selectedSkus.add(sku.toUpperCase());
        await _persist();
        notifyListeners();
        return null;
      });

  Future<void> setQty(String sku, int qty) => _enqueueWrite(() async {
        await ensureLoaded();
        _setQtyUnlocked(sku, qty);
        await _persist();
        notifyListeners();
      });

  /// +/- dari UI: baca qty terkini di dalam antrian tulis (aman dari tap cepat).
  Future<void> adjustQty(String sku, int delta) => _enqueueWrite(() async {
        await ensureLoaded();
        final key = _skuKey(sku);
        if (key.isEmpty || delta == 0) return;
        final i = _items.indexWhere((e) => e.sku.toUpperCase() == key);
        if (i < 0) return;
        _setQtyUnlocked(sku, _items[i].qty + delta);
        await _persist();
        notifyListeners();
      });

  void _setQtyUnlocked(String sku, int qty) {
    final key = _skuKey(sku);
    if (key.isEmpty) return;
    final i = _items.indexWhere((e) => e.sku.toUpperCase() == key);
    if (i < 0) return;
    final next = clampQty(qty);
    if (next <= 0) {
      _items.removeAt(i);
      _selectedSkus.remove(key);
    } else {
      _items[i] = _items[i].copyWith(qty: next);
    }
    _pruneSelection();
  }

  Future<void> remove(String sku) async {
    await setQty(sku, 0);
  }

  Future<void> clear() => _enqueueWrite(() async {
        _items.clear();
        _selectedSkus.clear();
        await _persist();
        notifyListeners();
      });

  /// Hapus hanya item tercentang (setelah checkout sukses).
  Future<void> removeSelected() => _enqueueWrite(() async {
        await ensureLoaded();
        _items.removeWhere((e) => _selectedSkus.contains(e.sku.toUpperCase()));
        _selectedSkus.clear();
        await _persist();
        notifyListeners();
      });

  /// Item siap checkout = tercentang dan tidak diblokir online (Lensa).
  List<Map<String, dynamic>> toCheckoutItems() => selectedItems
      .where((e) => !isOnlineBlockedKategori(e.kategori))
      .map((e) => e.toCheckoutMap())
      .toList();

  /// Test-only: kosongkan state + izinkan [ensureLoaded] baca prefs lagi.
  @visibleForTesting
  Future<void> debugResetForTest() async {
    await _writeQueue.catchError((_) {});
    _writeQueue = Future<void>.value();
    _items.clear();
    _selectedSkus.clear();
    _loaded = false;
    _loading = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }
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

  MemberCartItem copyWith({
    int? qty,
    String? productId,
    String? nama,
    String? kategori,
    int? harga,
    String? imageUrl,
  }) =>
      MemberCartItem(
        sku: sku,
        productId: productId ?? this.productId,
        nama: nama ?? this.nama,
        kategori: kategori ?? this.kategori,
        harga: harga ?? this.harga,
        qty: qty ?? this.qty,
        imageUrl: imageUrl ?? this.imageUrl,
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
