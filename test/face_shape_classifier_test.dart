import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/face_shape/face_shape.dart';

void main() {
  final clf = FaceShapeClassifier();

  FaceShapeFeatures feats(List<double> v) => FaceShapeFeatures(
        values: v,
        foreheadWidth: 100,
        cheekWidth: 110,
        jawWidth: 95,
        faceLength: 140,
        faceWidth: 110,
      );

  test('round-ish ratios prefer round', () {
    final p = clf.classify(
      feats([1.05, 0.97, 0.96, 1.01, 0.98, 0.04, 0.97, 1.04, 0.34, 0.64]),
    );
    expect(p.primary.shape, FaceShapeType.round);
    expect(p.primary.score, greaterThan(0.2));
    expect(p.ranked.length, FaceShapeType.values.length);
  });

  test('oblong-ish ratios prefer oblong', () {
    final p = clf.classify(
      feats([1.55, 0.97, 0.93, 1.04, 0.95, 0.07, 0.97, 1.07, 0.31, 0.60]),
    );
    expect(p.primary.shape, FaceShapeType.oblong);
  });

  test('heart-ish ratios prefer heart', () {
    final p = clf.classify(
      feats([1.30, 1.10, 0.80, 1.30, 0.94, 0.20, 1.10, 1.25, 0.33, 0.58]),
    );
    expect(p.primary.shape, FaceShapeType.heart);
  });
}
