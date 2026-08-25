import 'shift_auto_assign.dart';

/// Skor SOP harian Front/Back (±25) — murni, tanpa DB.
///
/// `poin_sop = round(25 * (2 * p - 1))`
/// Fatal: aktif + 0 story → −25 (override).
/// Libur / tidak aktif → 0.
class SopScoreInput {
  const SopScoreInput({
    required this.layer,
    required this.isPagi,
    required this.isAktif,
    required this.isLibur,
    required this.storyCount,
    required this.displayDone,
    required this.displayRequired,
    required this.stokDone,
    required this.sapuDone,
  });

  final OfficeLayer layer;
  final bool isPagi;
  final bool isAktif;
  final bool isLibur;

  /// Total story cabang hari itu (shared).
  final int storyCount;
  final int displayDone;
  final int displayRequired;
  final bool stokDone;
  final bool sapuDone;
}

class SopScoreResult {
  const SopScoreResult({
    required this.poin,
    required this.p,
    required this.sStory,
    required this.sCore,
    required this.sSapu,
    required this.fatalStory,
    required this.liburOrInactive,
  });

  final int poin;
  final double p;
  final double sStory;
  final double sCore;
  final double sSapu;
  final bool fatalStory;
  final bool liburOrInactive;
}

class SopScore {
  static const storyTarget = 8;
  static const displaySlotsDefault = 3;
  static const poinEnvelope = 25;

  /// Jam masuk &lt; 14 → pagi (bobot sapu aktif).
  static bool isPagiShift({String? jamMasuk, String? shiftLabel}) {
    final label = (shiftLabel ?? '').toLowerCase().trim();
    if (label.contains('siang') ||
        label.contains('sore') ||
        label.contains('malam') ||
        label.contains('evening')) {
      return false;
    }
    if (label.contains('pagi') || label.contains('morning')) {
      return true;
    }
    final raw = (jamMasuk ?? '').trim();
    if (raw.isEmpty) return true;
    final m = RegExp(r'^(\d{1,2})').firstMatch(raw);
    if (m == null) return true;
    final h = int.tryParse(m.group(1)!);
    if (h == null) return true;
    return h < 14;
  }

  static double clamp01(double v) {
    if (v.isNaN) return 0;
    if (v < 0) return 0;
    if (v > 1) return 1;
    return v;
  }

  static SopScoreResult compute(SopScoreInput input) {
    if (!input.isAktif || input.isLibur) {
      return const SopScoreResult(
        poin: 0,
        p: 0,
        sStory: 0,
        sCore: 0,
        sSapu: 0,
        fatalStory: false,
        liburOrInactive: true,
      );
    }

    final story = input.storyCount < 0 ? 0 : input.storyCount;
    final sStory = clamp01(story / storyTarget);
    final req = input.displayRequired <= 0
        ? displaySlotsDefault
        : input.displayRequired;
    final done = input.displayDone < 0 ? 0 : input.displayDone;
    final sDisplay = clamp01(done / req);
    final sStok = input.stokDone ? 1.0 : 0.0;
    final sSapu = input.sapuDone ? 1.0 : 0.0;
    final sCore =
        input.layer == OfficeLayer.front ? sDisplay : sStok;

    if (story == 0) {
      return SopScoreResult(
        poin: -poinEnvelope,
        p: 0,
        sStory: 0,
        sCore: sCore,
        sSapu: input.isPagi ? sSapu : 0,
        fatalStory: true,
        liburOrInactive: false,
      );
    }

    late final double p;
    if (input.layer == OfficeLayer.front) {
      p = input.isPagi
          ? 0.50 * sStory + 0.35 * sDisplay + 0.15 * sSapu
          : 0.50 * sStory + 0.50 * sDisplay;
    } else {
      p = input.isPagi
          ? 0.50 * sStory + 0.35 * sStok + 0.15 * sSapu
          : 0.50 * sStory + 0.50 * sStok;
    }

    final pClamped = clamp01(p);
    final poin = (poinEnvelope * (2 * pClamped - 1)).round();
    return SopScoreResult(
      poin: poin,
      p: pClamped,
      sStory: sStory,
      sCore: sCore,
      sSapu: input.isPagi ? sSapu : 0,
      fatalStory: false,
      liburOrInactive: false,
    );
  }
}
