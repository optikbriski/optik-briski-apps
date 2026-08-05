import 'package:flutter/material.dart';
import '../../theme.dart';

/// Refined nav tile — soft ice mark, navy type, quiet chevron.
class PremiumMenuTile extends StatefulWidget {
  const PremiumMenuTile({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<PremiumMenuTile> createState() => _PremiumMenuTileState();
}

class _PremiumMenuTileState extends State<PremiumMenuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -1.5 : 0, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: OptikAdminTokens.card,
                border: Border.all(
                  color: _hover
                      ? OptikAdminTokens.ice
                      : OptikAdminTokens.ice.withOpacity(0.35),
                ),
                boxShadow: _hover
                    ? OptikAdminTokens.cardShadowHover
                    : OptikAdminTokens.cardShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                child: Row(
                  children: [
                    Builder(
                      builder: (_) {
                        final c = widget.color;
                        final isIce = c == OptikAdminTokens.ice ||
                            c == OptikAdminTokens.accentSoft ||
                            c == OptikAdminTokens.accentDeep ||
                            c == OptikAdminTokens.slate ||
                            c == OptikAdminTokens.navy;
                        final wash = isIce ? OptikAdminTokens.ice : c;
                        return Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            color: wash.withOpacity(isIce ? 0.32 : 0.16),
                            border: Border.all(
                              color: wash.withOpacity(isIce ? 0.9 : 0.85),
                            ),
                          ),
                          child: Icon(
                            widget.icon,
                            color: isIce ? OptikAdminTokens.navy : c,
                            size: 18,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          letterSpacing: -0.15,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: OptikAdminTokens.slate.withOpacity(
                        _hover ? 0.75 : 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
