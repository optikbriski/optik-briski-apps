/// Pure math for Front/Back contribution fair-share rekap (rulebook ±10pp).
class ContributionPeer {
  const ContributionPeer({
    required this.karyawanId,
    required this.nama,
    required this.jabatan,
    required this.units,
    required this.aktualPct,
    required this.fairShare,
    required this.hariKerja,
    required this.targetHari,
  });

  final String karyawanId;
  final String nama;
  final String jabatan;
  final int units;
  final double aktualPct;
  final double fairShare;
  final int hariKerja;
  final int targetHari;

  /// Poin produksi/transaksi uncapped (+5 × unit).
  int get poin => units * 5;

  /// Delta vs fair share in percentage points.
  double get deltaPp => (aktualPct - fairShare) * 100;

  /// Toleransi rulebook ±10 persen poin.
  static const tolerancePp = 10.0;

  bool get isAboveFair => deltaPp > tolerancePp;
  bool get isBelowFair => deltaPp < -tolerancePp;
  bool get isBalanced => !isAboveFair && !isBelowFair;

  /// Flag jadwal timpang vs target bulan (~26–27).
  bool get scheduleImbalance {
    if (targetHari <= 0) return false;
    return (hariKerja - targetHari).abs() > 3;
  }
}

class ContributionRekap {
  const ContributionRekap({
    required this.layerLabel,
    required this.fairShare,
    required this.unitTim,
    required this.targetHari,
    required this.peers,
    required this.periodStart,
    required this.periodEnd,
  });

  final String layerLabel;
  final double fairShare;
  final int unitTim;
  final int targetHari;
  final List<ContributionPeer> peers;
  final DateTime periodStart;
  final DateTime periodEnd;

  bool get hasScheduleImbalance => peers.any((p) => p.scheduleImbalance);

  /// Build sorted peers (highest units first) from raw maps.
  static ContributionRekap build({
    required String layerLabel,
    required Map<String, int> unitsById,
    required Map<String, String> namaById,
    required Map<String, String> jabatanById,
    required Map<String, int> hariKerjaById,
    required int targetHari,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    final ids = unitsById.keys.toList();
    final n = ids.length;
    final fair = n > 0 ? 1.0 / n : 0.0;
    final unitTim = unitsById.values.fold<int>(0, (a, b) => a + b);

    final peers = <ContributionPeer>[
      for (final id in ids)
        ContributionPeer(
          karyawanId: id,
          nama: namaById[id] ?? '-',
          jabatan: jabatanById[id] ?? '',
          units: unitsById[id] ?? 0,
          aktualPct: unitTim > 0 ? (unitsById[id] ?? 0) / unitTim : 0.0,
          fairShare: fair,
          hariKerja: hariKerjaById[id] ?? 0,
          targetHari: targetHari,
        ),
    ]..sort((a, b) {
        final u = b.units.compareTo(a.units);
        if (u != 0) return u;
        return a.nama.toLowerCase().compareTo(b.nama.toLowerCase());
      });

    return ContributionRekap(
      layerLabel: layerLabel,
      fairShare: fair,
      unitTim: unitTim,
      targetHari: targetHari,
      peers: peers,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }
}
