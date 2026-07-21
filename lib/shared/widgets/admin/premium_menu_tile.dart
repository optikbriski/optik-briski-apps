import 'package:flutter/material.dart';
import '../../theme.dart';

/// Dashboard / navigation tile with press scale and icon glow.
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
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          child: Ink(
            decoration: BoxDecoration(
              color: OptikAdminTokens.card.withOpacity(0.92),
              borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
              border: Border.all(color: OptikAdminTokens.line),
              gradient: OptikAdminTokens.cardSheen,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withOpacity(0.12),
                      boxShadow: OptikAdminTokens.glow(widget.color),
                      border: Border.all(
                        color: widget.color.withOpacity(0.22),
                      ),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 22),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OptikAdminTokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
