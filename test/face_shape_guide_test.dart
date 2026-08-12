import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/face_shape/face_shape.dart';

void main() {
  group('FaceShapeType.tryParse', () {
    test('parses id and aliases', () {
      expect(FaceShapeTypeX.tryParse('oval'), FaceShapeType.oval);
      expect(FaceShapeTypeX.tryParse('Round'), FaceShapeType.round);
      expect(FaceShapeTypeX.tryParse('rectangle'), FaceShapeType.oblong);
      expect(FaceShapeTypeX.tryParse('inverted_triangle'), FaceShapeType.heart);
      expect(FaceShapeTypeX.tryParse(''), isNull);
      expect(FaceShapeTypeX.tryParse(null), isNull);
    });
  });

  group('FaceShapeFrameGuide', () {
    test('every shape has recommended frames and optional avoid', () {
      for (final shape in FaceShapeType.values) {
        final all = FaceShapeFrameGuide.forShape(shape);
        final rec = FaceShapeFrameGuide.recommendedFor(shape);
        expect(all, isNotEmpty, reason: shape.id);
        expect(rec, isNotEmpty, reason: shape.id);
        expect(rec.every((f) => !f.isAvoid), isTrue);
        expect(rec.length, lessThanOrEqualTo(all.length));
        expect(all.where((f) => f.isAvoid), isNotEmpty, reason: shape.id);
      }
    });

    test('carousel-safe: at least one recommended per shape', () {
      for (final shape in FaceShapeType.values) {
        final rec = FaceShapeFrameGuide.recommendedFor(shape);
        expect(rec.length.clamp(1, 2), inInclusiveRange(1, 2));
      }
    });

    test('asset paths exist for all shapes', () {
      for (final shape in FaceShapeType.values) {
        final path = FaceShapePhoto.assetFor(shape);
        expect(path, contains('face_${shape.id}.png'));
      }
    });
  });
}
