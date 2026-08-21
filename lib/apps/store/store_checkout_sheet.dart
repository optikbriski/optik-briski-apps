import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/widgets/rekasa_surface.dart';

Future<T?> showRekasaSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: RekasaTokens.paper,
    barrierColor: RekasaTokens.inkDeep.withOpacity(0.48),
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: builder,
  );
}

class RekasaSheetScaffold extends StatelessWidget {
  const RekasaSheetScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.child,
    this.price,
    this.caption,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel = 'Batal',
    this.onSecondary,
  });

  final String eyebrow;
  final String title;
  final Widget child;
  final String? price;
  final String? caption;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: RekasaTokens.sky,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                children: [
                  RekasaEyebrow(eyebrow),
                  const SizedBox(height: 14),
                  Text(title, style: Theme.of(context).textTheme.headlineMedium),
                  if (price != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      price!,
                      style: GoogleFonts.plusJakartaSans(
                        color: RekasaTokens.inkSoft,
                        fontWeight: FontWeight.w800,
                        fontSize: 34,
                        letterSpacing: -1.1,
                        height: 1,
                      ),
                    ),
                  ],
                  if (caption != null) ...[
                    const SizedBox(height: 10),
                    Text(caption!, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 22),
                  child,
                ],
              ),
            ),
            if (primaryLabel != null)
              Material(
                color: RekasaTokens.paper,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: onSecondary ?? () => Navigator.pop(context),
                        child: Text(secondaryLabel),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: onPrimary,
                          child: Text(primaryLabel!),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
