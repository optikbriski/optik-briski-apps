import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/member/member_cart.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/theme.dart';
import 'member_cart_snackbar.dart';

/// Opens the same Member product detail bottom sheet used in the catalog
/// (browse-only). Loads identity + price from PUSAT catalog by [sku];
/// [tokoId] scopes available_qty when provided.
Future<void> openMemberProductDetailBySku(
  BuildContext context, {
  required String sku,
  String? tokoId,
  bool browseOnly = true,
  VoidCallback? onOpenCart,
}) async {
  final want = sku.trim().toUpperCase();
  if (want.isEmpty) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    ),
  );

  Map<String, dynamic>? product;
  try {
    final rows = await MemberRepository().listCatalog(
      search: want,
      limit: 12,
      tokoId: tokoId,
    );
    for (final r in rows) {
      final s = (r['sku'] ?? '').toString().trim().toUpperCase();
      if (s == want) {
        product = r;
        break;
      }
    }
  } catch (_) {
    product = null;
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // loading dialog

  if (product == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('member_help_product_not_found'.tr())),
    );
    return;
  }

  await showMemberProductDetailSheet(
    context,
    product: product,
    browseOnly: browseOnly,
    onOpenCart: onOpenCart,
  );
}

Future<void> showMemberProductDetailSheet(
  BuildContext context, {
  required Map<String, dynamic> product,
  bool browseOnly = true,
  VoidCallback? onOpenCart,
}) {
  final money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format;

  final nama = (product['nama'] ?? '-').toString();
  final kat = (product['kategori'] ?? '-').toString();
  final sub = (product['sub_kategori'] ?? '').toString();
  final warna = (product['warna'] ?? '-').toString();
  final sku = (product['sku'] ?? '-').toString();
  final barcode = (product['barcode'] ?? '-').toString();
  final lensa = (product['jenis_lensa'] ?? '').toString();
  final img = (product['image_url'] ?? '').toString().trim();
  final harga = int.tryParse('${product['harga'] ?? 0}') ?? 0;
  final asliRaw = int.tryParse('${product['harga_asli'] ?? ''}');
  final asli = (asliRaw != null && asliRaw > harga) ? asliRaw : null;
  final avail = int.tryParse('${product['available_qty'] ?? ''}');
  final outOfStock = avail != null && avail <= 0;
  final blocked = MemberCart.isOnlineBlocked(product);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: OptikMemberTokens.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final bottomPad = MediaQuery.paddingOf(ctx).bottom;
      final maxH = MediaQuery.sizeOf(ctx).height * 0.9;
      // Cap image so portrait frames never dominate short viewports.
      final imgH = (MediaQuery.sizeOf(ctx).height * 0.28).clamp(160.0, 220.0);

      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.lineSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (img.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            OptikMemberTokens.radiusMd,
                          ),
                          child: SizedBox(
                            height: imgH,
                            width: double.infinity,
                            child: Image.network(
                              img,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFF3F3F3),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.visibility_outlined,
                                  size: 48,
                                  color: OptikMemberTokens.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F3F3),
                            borderRadius: BorderRadius.circular(
                              OptikMemberTokens.radiusMd,
                            ),
                          ),
                          child: const Icon(
                            Icons.visibility_outlined,
                            size: 48,
                            color: OptikMemberTokens.inkMuted,
                          ),
                        ),
                      const SizedBox(height: 14),
                      Text(
                        nama,
                        style: const TextStyle(
                          color: OptikMemberTokens.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          if (asli != null)
                            Text(
                              money(asli),
                              style: const TextStyle(
                                color: OptikMemberTokens.inkMuted,
                                fontSize: 14,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          Text(
                            money(harga),
                            style: TextStyle(
                              color: asli != null
                                  ? const Color(0xFFC45C4A)
                                  : OptikMemberTokens.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _kv('Kategori', sub.isEmpty ? kat : '$kat · $sub'),
                      _kv('Warna', warna),
                      if (lensa.isNotEmpty) _kv('Jenis lensa', lensa),
                      _kv('SKU', sku),
                      _kv('Barcode', barcode),
                      const SizedBox(height: 8),
                      if (avail != null && !blocked)
                        _kv(
                          'Stok',
                          outOfStock
                              ? 'Habis — bisa pre-order'
                              : 'Tersedia ($avail)',
                        ),
                      if (!browseOnly && blocked) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4E8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFE8C9A0),
                            ),
                          ),
                          child: const Text(
                            kMemberOnlineBlockedLensaMessage,
                            style: TextStyle(
                              color: OptikMemberTokens.ink,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        browseOnly
                            ? 'Harga referensi dari katalog pusat (master data). '
                                'Untuk membeli, buka Belanja Online.'
                            : blocked
                                ? 'Lensa hanya tersedia lewat cabang (WhatsApp / booking).'
                                : 'Harga & stok dari master data pusat. '
                                    'Stok cabang dicek ulang saat checkout.',
                        style: const TextStyle(
                          color: OptikMemberTokens.inkMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (browseOnly)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Tutup'),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Tutup'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: blocked
                            ? null
                            : () async {
                                if (outOfStock) {
                                  final yes =
                                      await _confirmPreOrder(ctx, nama);
                                  if (!yes || !ctx.mounted) return;
                                }
                                final err = await MemberCart.instance
                                    .addProduct(product);
                                if (!ctx.mounted) return;
                                if (err != null) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(err)),
                                  );
                                  return;
                                }
                                Navigator.pop(ctx);
                                if (!context.mounted) return;
                                // Parent/shop context (not sheet) so timeout
                                // runs on the shop shell ScaffoldMessenger.
                                showMemberAddedToCartSnackBar(
                                  context,
                                  preOrder: outOfStock,
                                  onOpenCart: onOpenCart,
                                );
                              },
                        icon: Icon(
                          blocked
                              ? Icons.storefront_outlined
                              : Icons.shopping_bag_outlined,
                        ),
                        label: Text(
                          blocked
                              ? 'Hanya di toko / WA'
                              : outOfStock
                                  ? 'Pre-order'
                                  : 'Ke keranjang',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<bool> _confirmPreOrder(BuildContext context, String nama) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Stok habis'),
      content: Text(
        '“$nama” stoknya habis.\n\n'
        'Tetap bisa dipesan sebagai pre-order.\n'
        'Estimasi tiba 5–7 hari kerja setelah pembayaran lunas.\n\n'
        'Lanjutkan pre-order, atau cari produk lain?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cari produk lain'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Lanjutkan pre-order'),
        ),
      ],
    ),
  );
  return ok == true;
}

Widget _kv(String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            k,
            style: const TextStyle(
              color: OptikMemberTokens.inkMuted,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              color: OptikMemberTokens.ink,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}
