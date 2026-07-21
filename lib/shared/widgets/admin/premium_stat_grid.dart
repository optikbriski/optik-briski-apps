import 'package:flutter/material.dart';
import '../../theme.dart';
import 'premium_panel.dart';

/// Equal-width KPI strip that fills available horizontal space.
/// Narrow: wrap 2-col. Wide: single row of Expanded cards (no left-clump gap).
class PremiumStatGrid extends StatelessWidget {
  const PremiumStatGrid({
    super.key,
    required this.items,
    this.spacing = OptikAdminTokens.spaceSm,
    this.narrowBreakpoint = 560,
    this.padding = EdgeInsets.zero,
  });

  final List<PremiumStatItem> items;
  final double spacing;
  final double narrowBreakpoint;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < narrowBreakpoint;
          if (narrow) {
            final half = (c.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in items)
                  SizedBox(
                    width: half,
                    child: _StatTile(item: item),
                  ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                Expanded(child: _StatTile(item: items[i])),
              ],
            ],
          );
        },
      ),
    );
  }
}

class PremiumStatItem {
  const PremiumStatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.item});

  final PremiumStatItem item;

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      borderRadius: 16,
      borderColor: item.color.withOpacity(0.28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.label.toUpperCase(),
            style: TextStyle(
              color: item.color.withOpacity(0.9),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            style: TextStyle(
              color: item.color,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
