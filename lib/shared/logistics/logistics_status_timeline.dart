import 'logistics_live_map_rules.dart';
import 'logistics_route_cities.dart';
import 'logistics_tracking_service.dart';

class LogisticsTimelineLine {
  const LogisticsTimelineLine({
    required this.title,
    this.detail,
    this.at,
  });

  final String title;
  final String? detail;
  final DateTime? at;
}

class LogisticsTimelineNode {
  const LogisticsTimelineNode({
    required this.key,
    required this.title,
    this.detail,
    this.at,
    this.current = false,
    this.photoUrl,
    this.children = const [],
  });

  final String key;
  final String title;
  final String? detail;
  final DateTime? at;
  final bool current;
  final String? photoUrl;
  final List<LogisticsTimelineLine> children;
}

/// Timeline gaya resi: terbaru di atas, kota besar di dalam “pengiriman”.
abstract final class LogisticsStatusTimeline {
  static String? fotoUrl(Map<String, dynamic> move) {
    for (final k in [
      'bukti_foto_penerima',
      'bukti_foto_penerim',
      'bukti_foto_kurir',
      'bukti_foto_pengirim',
    ]) {
      final s = '${move[k] ?? ''}'.trim();
      if (s.isEmpty || s == '-' || s == 'null') continue;
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
    }
    return null;
  }

  static List<LogisticsTimelineNode> build({
    required Map<String, dynamic> move,
    required List<LogisticsRouteStop> stops,
    required List<Map<String, dynamic>> tripSameCity,
  }) {
    final st = (move['status'] ?? '').toString().toUpperCase();
    final left = LogisticsRouteCities.sudahBerangkat(move);
    final berangkat = LogisticsRouteCities.berangkatAt(move);
    final dibuat = LogisticsRouteCities.dibuatAt(move);
    final tiba = LogisticsRouteCities.tibaTujuanAt(move);
    final arrived = LogisticsLiveMapRules.arrivedInDestCity(
      move: move,
      tripSameCity: tripSameCity,
    );
    final tujuan = _tujuanName(move, stops);
    final asal = _asalName(move, stops);
    final kurir = '${move['kurir_nama'] ?? ''}'.trim();
    final verified = '${move['verified_by_name'] ?? ''}'.trim();
    final nodes = <LogisticsTimelineNode>[];

    if (st == 'SUCCESS') {
      nodes.add(LogisticsTimelineNode(
        key: 'diterima',
        title: 'Diterima',
        detail: verified.isEmpty
            ? 'Paket telah terkirim di $tujuan.'
            : 'Paket telah terkirim di $tujuan. Diterima $verified.',
        at: tiba ?? LogisticsRouteCities.parseTime(move['verified_at']),
        current: true,
        photoUrl: fotoUrl(move),
      ));
    } else if (st == 'PENDING') {
      nodes.add(LogisticsTimelineNode(
        key: 'verifikasi',
        title: 'Menunggu verifikasi',
        detail: 'Paket tiba di $tujuan. Menunggu konfirmasi toko.',
        at: tiba,
        current: true,
      ));
    } else if (st == 'TRANSIT') {
      nodes.add(_pengiriman(
        current: true,
        tujuan: tujuan,
        at: berangkat,
        arrived: arrived,
        stops: stops,
      ));
    } else if (st == 'WAITING') {
      nodes.add(LogisticsTimelineNode(
        key: 'jemput',
        title: 'Siap dijemput',
        detail: kurir.isEmpty
            ? 'Paket siap dijemput kurir dari $asal.'
            : 'Menunggu $kurir menjemput paket di $asal.',
        at: dibuat,
        current: true,
        children: _rencana(stops),
      ));
    } else if (st == 'BATAL' || st == 'REJECTED') {
      nodes.add(LogisticsTimelineNode(
        key: 'batal',
        title: st == 'REJECTED' ? 'Ditolak' : 'Dibatalkan',
        detail: 'Pengiriman tidak dilanjutkan.',
        at: LogisticsRouteCities.parseTime(move['verified_at']) ?? dibuat,
        current: true,
      ));
    } else {
      nodes.add(LogisticsTimelineNode(
        key: 'siap',
        title: 'Menyiapkan pengiriman',
        detail: 'Paket sedang disiapkan di $asal.',
        at: dibuat,
        current: true,
        children: _rencana(stops),
      ));
    }

    if (st == 'SUCCESS' || st == 'PENDING') {
      nodes.add(_pengiriman(
        current: false,
        tujuan: tujuan,
        at: berangkat,
        arrived: true,
        stops: stops,
      ));
    }

    if (left && st != 'TRANSIT') {
      nodes.add(LogisticsTimelineNode(
        key: 'berangkat',
        title: 'Paket sudah berangkat',
        detail: kurir.isEmpty
            ? 'Paket di-pick-up dari $asal.'
            : 'Paket di-pick-up $kurir dari $asal.',
        at: berangkat,
      ));
    } else if (left && st == 'TRANSIT') {
      nodes.add(LogisticsTimelineNode(
        key: 'berangkat',
        title: 'Paket sudah berangkat',
        detail: kurir.isEmpty
            ? 'Paket di-pick-up dari $asal.'
            : 'Paket di-pick-up $kurir dari $asal.',
        at: berangkat,
      ));
    }

    if (st != 'PREPARING' && st != 'WAITING' && st != 'QUEUED') {
      nodes.add(LogisticsTimelineNode(
        key: 'siap',
        title: 'Menyiapkan pengiriman',
        detail: 'Paket sedang disiapkan di $asal.',
        at: dibuat,
      ));
    }

    if (dibuat != null &&
        (st == 'PREPARING' || st == 'WAITING' || st == 'QUEUED')) {
      nodes.add(LogisticsTimelineNode(
        key: 'dibuat',
        title: 'Surat jalan dibuat',
        detail: 'Nomor ${move['product_name'] ?? '-'} dicatat gudang.',
        at: dibuat,
      ));
    }

    return nodes;
  }

  static LogisticsTimelineNode _pengiriman({
    required bool current,
    required String tujuan,
    required DateTime? at,
    required bool arrived,
    required List<LogisticsRouteStop> stops,
  }) {
    return LogisticsTimelineNode(
      key: 'jalan',
      title: 'Sedang dalam pengiriman',
      detail: arrived
          ? 'Paket tiba di kota tujuan $tujuan.'
          : 'Paket menuju $tujuan.',
      at: at,
      current: current,
      children: _kotaAnak(stops, arrived: arrived),
    );
  }

  static List<LogisticsTimelineLine> _kotaAnak(
    List<LogisticsRouteStop> stops, {
    required bool arrived,
  }) {
    final via = stops.where((s) => !s.origin).toList().reversed;
    return [
      for (final s in via)
        LogisticsTimelineLine(
          title: s.dest
              ? (arrived ? 'Tiba di ${s.name}' : 'Menuju ${s.name}')
              : 'Melewati ${s.name}',
          detail: s.dest
              ? (arrived ? 'Kota tujuan' : 'Belum tiba')
              : 'Kota besar di jalur',
        ),
    ];
  }

  static List<LogisticsTimelineLine> _rencana(List<LogisticsRouteStop> stops) {
    if (stops.length < 2) return const [];
    return [
      LogisticsTimelineLine(
        title: 'Rencana jalur',
        detail: LogisticsRouteCities.jalurRingkas(stops),
      ),
    ];
  }

  static String _tujuanName(
    Map<String, dynamic> move,
    List<LogisticsRouteStop> stops,
  ) {
    for (final s in stops) {
      if (s.dest) return s.name;
    }
    return LogisticsTrackingService.tokoLabel(move['ke_lokasi']?.toString());
  }

  static String _asalName(
    Map<String, dynamic> move,
    List<LogisticsRouteStop> stops,
  ) {
    for (final s in stops) {
      if (s.origin) return s.name;
    }
    return LogisticsTrackingService.tokoLabel(move['dari_lokasi']?.toString());
  }
}
