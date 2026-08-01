/// Enam bentuk wajah standar optik + rekomendasi frame.
enum FaceShapeType {
  oval,
  round,
  square,
  heart,
  diamond,
  oblong,
}

extension FaceShapeTypeX on FaceShapeType {
  String get id => name;

  String get labelId {
    switch (this) {
      case FaceShapeType.oval:
        return 'Oval';
      case FaceShapeType.round:
        return 'Round';
      case FaceShapeType.square:
        return 'Square';
      case FaceShapeType.heart:
        return 'Heart';
      case FaceShapeType.diamond:
        return 'Diamond';
      case FaceShapeType.oblong:
        return 'Oblong';
    }
  }

  String get blurbId {
    switch (this) {
      case FaceShapeType.oval:
        return 'Proporsi seimbang — cocok hampir semua gaya frame.';
      case FaceShapeType.round:
        return 'Lebar ≈ tinggi, sudut lembut — butuh frame yang tegas.';
      case FaceShapeType.square:
        return 'Dahi & rahang kuat — lembutkan dengan frame melengkung.';
      case FaceShapeType.heart:
        return 'Dahi lebih lebar, dagu meruncing — seimbangkan bagian bawah.';
      case FaceShapeType.diamond:
        return 'Tulang pipi menonjol — frame yang melebar di atas/bawah.';
      case FaceShapeType.oblong:
        return 'Wajah lebih panjang — frame yang menambah lebar visual.';
    }
  }

  static FaceShapeType? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final key = raw.trim().toLowerCase();
    for (final v in FaceShapeType.values) {
      if (v.id == key || v.labelId.toLowerCase() == key) return v;
    }
    // Alias dataset publik
    switch (key) {
      case 'rectangle':
      case 'rectangular':
        return FaceShapeType.oblong;
      case 'triangle':
      case 'inverted_triangle':
        return FaceShapeType.heart;
      default:
        return null;
    }
  }
}
