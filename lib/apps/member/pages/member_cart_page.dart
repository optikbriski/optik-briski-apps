import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
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
    // Standalone push (bukan tab shell): pastikan snackbar "Ditambah…" hilang.
    // Tab shell sudah hide di MemberShopShell._goTab(2).
    if (!widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      });
    }
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

  void _continueToOrderDetail() {
    if (!_cart.hasSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('member_cart_none_selected'.tr())),
      );
      return;
    }
    final blockedErr = _cart.onlineBlockedSelectionError;
    if (blockedErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(blockedErr)),
      );
      unawaited(_cart.purgeOnlineBlocked());
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MemberShopOrderDetailPage(),
      ),
    );
  }

  Widget get _empty {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'member_cart_empty'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: OptikMemberTokens.inkMuted, height: 1.4),
        ),
      ),
    );
  }

  Widget get _content {
    if (_cart.isEmpty) return _empty;
    final canContinue = _cart.hasSelection;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  // null = sebagian tercentang (indeterminate).
                  value: _cart.allSelected
                      ? true
                      : (_cart.hasSelection ? null : false),
                  tristate: true,
                  activeColor: OptikMemberTokens.blueDeep,
                  side: const BorderSide(
                    color: OptikMemberTokens.inkMuted,
                    width: 1.4,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) =>
                      _cart.setAllSelected(!_cart.allSelected),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _cart.setAllSelected(!_cart.allSelected),
                  child: Text(
                    'member_cart_select_all'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: OptikMemberTokens.inkSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            itemCount: _cart.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final it = _cart.items[i];
              final checked = _cart.isSelected(it.sku);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OptikMemberTokens.white,
                  borderRadius:
                      BorderRadius.circular(OptikMemberTokens.radiusMd),
                  border: Border.all(color: OptikMemberTokens.lineSoft),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: checked,
                          activeColor: OptikMemberTokens.blueDeep,
                          side: const BorderSide(
                            color: OptikMemberTokens.inkMuted,
                            width: 1.4,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) =>
                              _cart.setSelected(it.sku, v ?? false),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: checked
                                  ? OptikMemberTokens.ink
                                  : OptikMemberTokens.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _money.format(it.harga),
                            style: TextStyle(
                              color: checked
                                  ? OptikMemberTokens.blue
                                  : OptikMemberTokens.inkMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _qtyBtn(
                                Icons.remove_rounded,
                                () => _cart.adjustQty(it.sku, -1),
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
                                it.qty >= kMemberCartMaxQtyPerLine
                                    ? null
                                    : () => _cart.adjustQty(it.sku, 1),
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
                  Text(
                    'member_cart_subtotal'.tr(),
                    style: const TextStyle(color: OptikMemberTokens.inkMuted),
                  ),
                  const Spacer(),
                  Text(
                    _money.format(_cart.selectedSubtotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: OptikMemberTokens.blueDeep,
                    ),
                  ),
                ],
              ),
              if (!canContinue) ...[
                const SizedBox(height: 8),
                Text(
                  'member_cart_none_selected'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: OptikMemberTokens.inkMuted,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: OptikMemberTokens.blueDeep,
                    disabledBackgroundColor:
                        OptikMemberTokens.blueDeep.withOpacity(0.35),
                    disabledForegroundColor: OptikMemberTokens.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: canContinue ? _continueToOrderDetail : null,
                  child: Text(
                    'member_cart_continue'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
      title: 'member_shop_tab_cart'.tr(),
      body: _content,
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: OptikMemberTokens.blueMist
              .withOpacity(enabled ? 1 : 0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? OptikMemberTokens.blueDeep
              : OptikMemberTokens.inkMuted,
        ),
      ),
    );
  }
}
