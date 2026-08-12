import 'package:flutter/material.dart';

import 'member_cart_page.dart';

/// Add-to-cart snackbar for Member shop.
///
/// Flutter 3.41+ defaults [SnackBar.persist] to `true` when [SnackBar.action]
/// is non-null. In that mode the duration [Timer] fires but returns without
/// calling [ScaffoldMessengerState.hideCurrentSnackBar] — so the bar stays
/// forever until the action / cart tab / close icon dismisses it.
///
/// We force `persist: false` + an explicit 3s duration so timeout works, and
/// still keep the "Lihat" action + dismiss-on-cart (shell tab) behavior.
void showMemberAddedToCartSnackBar(
  BuildContext context, {
  required bool preOrder,
  VoidCallback? onOpenCart,
}) {
  // Prefer the nearest messenger (shop shell wraps its own when present);
  // fall back to the ambient MaterialApp messenger.
  final messenger = ScaffoldMessenger.of(context);

  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 3),
      // Critical: override Flutter's action → persist:true default.
      persist: false,
      content: Text(
        preOrder ? 'Ditambah (pre-order)' : 'Ditambah ke keranjang',
      ),
      action: SnackBarAction(
        label: 'Lihat',
        onPressed: () {
          messenger.hideCurrentSnackBar();
          if (onOpenCart != null) {
            onOpenCart();
          } else if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MemberCartPage()),
            );
          }
        },
      ),
    ),
  );

  // Belt-and-suspenders: if framework timeout is ignored again (e.g. another
  // persist regression), force-hide only while this snackbar is still current.
  var stillCurrent = true;
  controller.closed.whenComplete(() => stillCurrent = false);
  Future<void>.delayed(const Duration(seconds: 3), () {
    if (!stillCurrent || !messenger.mounted) return;
    messenger.hideCurrentSnackBar();
  });
}
