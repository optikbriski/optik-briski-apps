import 'product_identity.dart';
import 'stock_mutation_service.dart';

/// Neraca kapitalisasi aset gudang — stok fisik × modal / jual.
/// Bukan jurnal GL 1201. Reserved tetap aset (barang masih di rak).
abstract final class WarehouseAssetRules {
  static ({int aset, int omzet, int margin, int volume}) fromProduct(
    Map<String, dynamic> product,
  ) {
    final stok = StockQty.realOf(product);
    if (stok <= 0) {
      return (aset: 0, omzet: 0, margin: 0, volume: 0);
    }
    final modal = ProductIdentity.modalPriceOf(product);
    final jual = ProductIdentity.sellPriceOf(product);
    final aset = stok * modal;
    final omzet = stok * jual;
    return (aset: aset, omzet: omzet, margin: omzet - aset, volume: stok);
  }

  static ({int aset, int omzet, int margin, int volume}) fromProducts(
    Iterable<Map<String, dynamic>> products,
  ) {
    var aset = 0;
    var omzet = 0;
    var volume = 0;
    for (final p in products) {
      final line = fromProduct(p);
      aset += line.aset;
      omzet += line.omzet;
      volume += line.volume;
    }
    return (aset: aset, omzet: omzet, margin: omzet - aset, volume: volume);
  }

  static ({int aset, int omzet, int margin, int volume})? fromRpc(
    dynamic raw,
  ) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final aset = StockQty.parseCount(m['aset_pokok']);
    final omzet = StockQty.parseCount(m['potensi_omzet']);
    final volume = StockQty.parseCount(m['volume']);
    final margin = m['proyeksi_margin'] == null
        ? omzet - aset
        : StockQty.parseCount(m['proyeksi_margin']);
    return (aset: aset, omzet: omzet, margin: margin, volume: volume);
  }
}
