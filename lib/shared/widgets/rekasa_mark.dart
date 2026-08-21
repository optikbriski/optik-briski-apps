import 'package:flutter/material.dart';

/// Tanda Rekasa (bukan logo tenant Optik).
class RekasaMark extends StatelessWidget {
  const RekasaMark({
    super.key,
    this.height = 28,
    this.showWordmark = true,
  });

  final double height;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: height,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF0B3D8C),
        borderRadius: BorderRadius.circular(height * 0.22),
      ),
      child: Text(
        'R',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: height * 0.55,
          height: 1,
        ),
      ),
    );
    if (!showWordmark) return badge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        SizedBox(width: height * 0.32),
        Text(
          'Rekasa',
          style: TextStyle(
            color: const Color(0xFF0B3D8C),
            fontWeight: FontWeight.w800,
            fontSize: height * 0.72,
            letterSpacing: 0.2,
            height: 1,
          ),
        ),
      ],
    );
  }
}
