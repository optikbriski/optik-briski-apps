/// Pilih sumber hitungan story SOP: IG live, cache IG, atau tap honor.
///
/// IG gagal tanpa cache **tidak** boleh jadi 0 (fatal −25 di toko).
class SopStoryResolve {
  const SopStoryResolve({
    required this.count,
    required this.live,
    required this.fromIg,
  });

  final int count;

  /// Graph/cache hari ini valid — kunci tap honor.
  final bool live;

  final bool fromIg;

  static SopStoryResolve pick({
    required bool hasAccount,
    int? igCount,
    int? cacheCount,
    required int honorCount,
  }) {
    if (!hasAccount) {
      return SopStoryResolve(
        count: honorCount < 0 ? 0 : honorCount,
        live: false,
        fromIg: false,
      );
    }
    if (igCount != null) {
      final n = igCount < 0 ? 0 : igCount;
      return SopStoryResolve(count: n, live: true, fromIg: true);
    }
    if (cacheCount != null) {
      final n = cacheCount < 0 ? 0 : cacheCount;
      return SopStoryResolve(count: n, live: true, fromIg: true);
    }
    return SopStoryResolve(
      count: honorCount < 0 ? 0 : honorCount,
      live: false,
      fromIg: false,
    );
  }
}
