import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/member/member_cart.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_shop_order_detail_page.dart';

class MemberCartPage extends StatefulWidget {
  const MemberCartPage({super.key, this.embedded = false});

  /// true = tab di dalam MemberShopShell (tanpa app bar sendiri).
  final bool embedded;

  @override
  State<MemberCartPage> createState() => _MemberCartPageState();
}

class _MemberCartPageState extends State<MemberCartPage> {
  final _cart = MemberCart.instance;
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _cart.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _cart.addListener(_onCart);
  }

  @override
  void dispose() {
    _cart.removeListener(_onCart);
    super.dispose();
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  Widget get _empty {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Keranjang masih kosong.\nTambah produk dari tab Belanja.',
          textAlign: TextAlign.center,
          style: TextStyle(color: OptikMemberTokens.inkMuted, height: 1.4),
        ),
      ),
    );
  }

  Widget get _content {
    if (_cart.isEmpty) return _empty;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: _cart.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final it = _cart.items[i];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OptikMemberTokens.white,
                  borderRadius:
                      BorderRadius.circular(OptikMemberTokens.radiusMd),
                  border: Border.all(color: OptikMemberTokens.lineSoft),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: it.imageUrl.trim().isEmpty
                            ? Container(
                                color: OptikMemberTokens.blueMist,
                                child: const Icon(
                                  Icons.visibility_outlined,
                                  color: OptikMemberTokens.blue,
                                ),
                              )
                            : Image.network(
                                it.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: OptikMemberTokens.blueMist,
                                  child: const Icon(
                                      Icons.broken_image_outlined),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            it.nama,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: OptikMemberTokens.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _money.format(it.harga),
                            style: const TextStyle(
                              color: OptikMemberTokens.blue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _qtyBtn(
                                Icons.remove_rounded,
                                () => _cart.setQty(it.sku, it.qty - 1),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  '${it.qty}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              _qtyBtn(
                                Icons.add_rounded,
                                () => _cart.setQty(it.sku, it.qty + 1),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () => _cart.remove(it.sku),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: OptikMemberTokens.danger,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            14 +
                (widget.embedded
                    ? 0
                    : MediaQuery.paddingOf(context).bottom),
          ),
          decoration: BoxDecoration(
            color: OptikMemberTokens.white,
            border: Border(
              top: BorderSide(color: OptikMemberTokens.lineSoft),
            ),
            boxShadow: OptikMemberTokens.cardShadow,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'Subtotal',
                    style: TextStyle(color: OptikMemberTokens.inkMuted),
                  ),
                  const Spacer(),
                  Text(
                    _money.format(_cart.subtotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: OptikMemberTokens.blueDeep,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: OptikMemberTokens.blueDeep,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MemberShopOrderDetailPage(),
                      ),
                    );
                  },
                  child: const Text(
                    'Lanjut detail pesanan',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return ColoredBox(
        color: OptikMemberTokens.canvas,
        child: _content,
      );
    }
    return MemberPremiumScaffold(
      title: 'Keranjang',
      body: _content,
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: OptikMemberTokens.blueMist,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: OptikMemberTokens.blueDeep),
      ),
    );
  }
}
