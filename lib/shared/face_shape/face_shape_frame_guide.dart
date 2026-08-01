import 'face_shape_type.dart';

class FrameSuggestion {
  const FrameSuggestion({
    required this.title,
    required this.why,
  });

  final String title;
  final String why;
}

/// Referensi bentuk wajah + rekomendasi frame (panduan optik klasik).
///
/// Sumber industri yang umum dipakai optician/stylist (bukan diagnosis medis):
/// - The Vision Council — consumer eyewear fit guidance
/// - AAO (American Academy of Ophthalmology) — tips memilih kacamata
/// - Panduan fitting klasik: contrast principle (soft vs angular frames)
abstract final class FaceShapeFrameGuide {
  static const sources = <String>[
    'The Vision Council — eyewear & face shape fit guidance',
    'American Academy of Ophthalmology — choosing eyeglasses tips',
    'Prinsip fitting klasik: soft frames untuk wajah angular, angular frames untuk wajah lembut',
  ];

  /// Cara mengenali bentuk (self-check di cermin / foto depan).
  static String howToSpot(FaceShapeType shape) {
    switch (shape) {
      case FaceShapeType.oval:
        return 'Tinggi wajah sedikit lebih besar dari lebar; dahi, pipi, dan rahang proporsional; dagu membulat lembut.';
      case FaceShapeType.round:
        return 'Lebar ≈ tinggi; pipi penuh; sudut dahi & rahang lembut (hampir melingkar).';
      case FaceShapeType.square:
        return 'Dahi, tulang pipi, dan rahang hampir sama lebar; garis rahang tegas/bersudut.';
      case FaceShapeType.heart:
        return 'Dahi atau tulang pipi lebih lebar; menyempit ke dagu yang lebih runcing.';
      case FaceShapeType.diamond:
        return 'Tulang pipi paling lebar; dahi dan rahang lebih sempit; dagu sering runcing.';
      case FaceShapeType.oblong:
        return 'Wajah jelas lebih panjang dari lebar; dahi, pipi, rahang relatif sejajar; dagu memanjang.';
    }
  }

  static List<FrameSuggestion> forShape(FaceShapeType shape) {
    switch (shape) {
      case FaceShapeType.oval:
        return const [
          FrameSuggestion(
            title: 'Hampir semua gaya',
            why:
                'Proporsi seimbang — rectangle, wayfarer, round, dan cat-eye umumnya aman.',
          ),
          FrameSuggestion(
            title: 'Hindari oversize ekstrem',
            why: 'Frame terlalu besar bisa menutupi proporsi alami wajah.',
          ),
        ];
      case FaceShapeType.round:
        return const [
          FrameSuggestion(
            title: 'Rectangle / square',
            why: 'Sudut tegas menambah struktur pada wajah yang membulat.',
          ),
          FrameSuggestion(
            title: 'Wayfarer / browline',
            why: 'Garis atas kuat memperpanjang kesan wajah.',
          ),
          FrameSuggestion(
            title: 'Hindari round kecil',
            why: 'Bisa membuat wajah terlihat lebih bulat.',
          ),
        ];
      case FaceShapeType.square:
        return const [
          FrameSuggestion(
            title: 'Round / oval',
            why: 'Lengkungan melembutkan sudut rahang yang tegas.',
          ),
          FrameSuggestion(
            title: 'Cat-eye lembut',
            why: 'Mengangkat perhatian visual ke atas.',
          ),
          FrameSuggestion(
            title: 'Hindari square boxy',
            why: 'Bisa memperkuat kesan sudut berlebih.',
          ),
        ];
      case FaceShapeType.heart:
        return const [
          FrameSuggestion(
            title: 'Aviator / bottom-heavy',
            why: 'Menambah volume di bagian bawah wajah.',
          ),
          FrameSuggestion(
            title: 'Round ringan / oval',
            why: 'Menyeimbangkan dahi yang lebih lebar.',
          ),
          FrameSuggestion(
            title: 'Hindari top-heavy tebal',
            why: 'Bisa membuat dahi terlihat lebih dominan.',
          ),
        ];
      case FaceShapeType.diamond:
        return const [
          FrameSuggestion(
            title: 'Cat-eye / oval',
            why: 'Melebar di atas untuk menyeimbangkan tulang pipi.',
          ),
          FrameSuggestion(
            title: 'Rimless / thin metal',
            why: 'Tidak bertabrakan dengan pipi yang menonjol.',
          ),
          FrameSuggestion(
            title: 'Hindari sempit di tengah',
            why: 'Bisa menekankan lebar pipi.',
          ),
        ];
      case FaceShapeType.oblong:
        return const [
          FrameSuggestion(
            title: 'Oversize / wide',
            why: 'Menambah lebar visual pada wajah yang panjang.',
          ),
          FrameSuggestion(
            title: 'Wayfarer / square pendek',
            why: 'Memotong garis vertikal wajah.',
          ),
          FrameSuggestion(
            title: 'Hindari narrow tinggi',
            why: 'Bisa membuat wajah terlihat lebih panjang.',
          ),
        ];
    }
  }
}
