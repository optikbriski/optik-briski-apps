import 'package:flutter/material.dart';

import '../../../shared/face_shape/face_shape.dart';
import '../../../shared/theme.dart';
import '../member_layout.dart';
import '../member_widgets.dart';

/// Referensi bentuk wajah + rekomendasi frame (tanpa kamera / AI).
class MemberFaceShapePage extends StatelessWidget {
  const MemberFaceShapePage({super.key});

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    return MemberPremiumScaffold(
      title: 'Bentuk',
      body: MemberLayout.constrain(
        context,
        ListView(
          padding: EdgeInsets.all(m.pagePadding),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    OptikMemberTokens.blueDeep,
                    OptikMemberTokens.blueMid,
                  ],
                ),
                borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Referensi bentuk wajah',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lihat foto model referensi dulu, lalu geser untuk contoh '
                    'frame rekomendasi. Panduan gaya optik — bukan diagnosis medis.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: m.sectionGap),
            Text(
              'Cara cek cepat',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: OptikMemberTokens.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '1) Rambut disingkap dari dahi & rahang.\n'
              '2) Foto / cermin lurus dari depan.\n'
              '3) Cocokkan dengan model, lalu geser contoh frame.',
              style: TextStyle(
                color: OptikMemberTokens.ink.withOpacity(0.78),
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: m.sectionGap),
            for (final shape in FaceShapeType.values) ...[
              _ShapeCard(shape: shape),
              SizedBox(height: m.sectionGap * 0.85),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OptikMemberTokens.lineSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sumber referensi',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: OptikMemberTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final s in FaceShapeFrameGuide.sources)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '•  ',
                            style: TextStyle(
                              color: OptikMemberTokens.blue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              s,
                              style: TextStyle(
                                color: OptikMemberTokens.ink.withOpacity(0.75),
                                height: 1.35,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ShapeCard extends StatefulWidget {
  const _ShapeCard({required this.shape});

  final FaceShapeType shape;

  @override
  State<_ShapeCard> createState() => _ShapeCardState();
}

class _ShapeCardState extends State<_ShapeCard> {
  late final PageController _pageController;
  int _page = 0;

  FaceShapeType get shape => widget.shape;

  /// Slide 0 = model saja; 1..n = frame rekomendasi (tanpa item "hindari").
  int get _slideCount {
    final frames = FaceShapeFrameGuide.recommendedFor(shape);
    final frameSlides = frames.isEmpty ? 0 : frames.length.clamp(1, 2);
    return 1 + frameSlides;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = FaceShapeFrameGuide.forShape(shape);
    final recommended = FaceShapeFrameGuide.recommendedFor(shape);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
        border: Border.all(color: OptikMemberTokens.lineSoft),
        boxShadow: [
          BoxShadow(
            color: OptikMemberTokens.blueDeep.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shape.labelId,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: OptikMemberTokens.blueDeep,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            shape.blurbId,
            style: TextStyle(
              color: OptikMemberTokens.ink.withOpacity(0.7),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OptikMemberTokens.lineSoft),
            ),
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slideCount,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _SlidePane(
                          caption: 'Model bentuk ${shape.labelId}',
                          hint: recommended.isEmpty
                              ? 'Bandingkan dengan foto / cermin Anda'
                              : 'Geser untuk lihat frame rekomendasi →',
                          child: FaceShapePhoto(
                            shape: shape,
                            size: 168,
                            showFrame: false,
                          ),
                        );
                      }
                      final variant = index - 1;
                      final suggestion = recommended[variant];
                      return _SlidePane(
                        caption: suggestion.title,
                        hint: suggestion.why,
                        child: FaceShapePhoto(
                          shape: shape,
                          size: 168,
                          showFrame: true,
                          frameVariant: variant,
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _slideCount; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: _page == i ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _page == i
                                ? OptikMemberTokens.blue
                                : OptikMemberTokens.blue.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Ciri khas',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: OptikMemberTokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            FaceShapeFrameGuide.howToSpot(shape),
            style: TextStyle(
              color: OptikMemberTokens.ink.withOpacity(0.78),
              height: 1.4,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cocoknya frame',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: OptikMemberTokens.ink,
            ),
          ),
          const SizedBox(height: 8),
          for (final f in frames)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (f.isAvoid
                              ? OptikMemberTokens.danger
                              : OptikMemberTokens.blue)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Icon(
                      f.isAvoid
                          ? Icons.block_outlined
                          : Icons.visibility_outlined,
                      size: 14,
                      color: f.isAvoid
                          ? OptikMemberTokens.danger
                          : OptikMemberTokens.blue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: OptikMemberTokens.ink,
                          ),
                        ),
                        Text(
                          f.why,
                          style: TextStyle(
                            color: OptikMemberTokens.ink.withOpacity(0.68),
                            height: 1.35,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SlidePane extends StatelessWidget {
  const _SlidePane({
    required this.caption,
    required this.hint,
    required this.child,
  });

  final String caption;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          Expanded(child: Center(child: child)),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: OptikMemberTokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.3,
              color: OptikMemberTokens.ink.withOpacity(0.62),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
