import 'dart:math' as math;

import 'indonesia_major_cities.dart';
import 'logistics_live_map_rules.dart';
import 'logistics_tracking_service.dart';

/// Satu titik di list jalur (gudang, kota besar, tujuan).
class LogisticsRouteStop {
  const LogisticsRouteStop({
    required this.name,
    required this.origin,
    required this.dest,
    required this.kmFromOrigin,
  });

  final String name;
  final bool origin;
  final bool dest;
  final double kmFromOrigin;
}

/// Baris list: hari/jam + status di titik itu.
class LogisticsRouteEvent {
  const LogisticsRouteEvent({
    required this.tempat,
    required this.aksi,
    this.at,
    required this.done,
    required this.current,
  });

  final String tempat;
  final String aksi;
  final DateTime? at;
  final bool done;
  final bool current;
}

/// Kota besar di koridor gudang → tujuan. Kabupaten kecil tidak dihitung.
abstract final class LogisticsRouteCities {
  static const _corridorKm = 48.0;
  static const _minGapKm = 55.0;
  static const _endClearKm = 28.0;
  static const _snapKm = 22.0;

  static DateTime? parseTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final t = '$raw'.trim();
    if (t.isEmpty || t == 'null') return null;
    return DateTime.tryParse(t);
  }

  static String _st(Map<String, dynamic> move) =>
      (move['status'] ?? '').toString().toUpperCase();

  static bool sudahBerangkat(Map<String, dynamic> move) {
    switch (_st(move)) {
      case 'TRANSIT':
      case 'PENDING':
      case 'SUCCESS':
        return true;
      default:
        return false;
    }
  }

  static DateTime? berangkatAt(Map<String, dynamic> move) {
    final stamped = parseTime(move['berangkat_at']);
    if (stamped != null) return stamped;
    if (!sudahBerangkat(move)) return null;
    return parseTime(move['created_at']);
  }

  static DateTime? dibuatAt(Map<String, dynamic> move) =>
      parseTime(move['created_at']);

  static DateTime? tibaTujuanAt(Map<String, dynamic> move) {
    final tiba = parseTime(move['tiba_kota_at']);
    if (tiba != null) return tiba;
    final st = _st(move);
    if (st == 'SUCCESS') return parseTime(move['verified_at']);
    return null;
  }

  static String normalizeTokoName(String? raw) {
    var t = (raw ?? '').trim().toUpperCase();
    if (t.startsWith('CABANG-')) t = t.substring(7);
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  static IndonesiaCity? cityByName(String? raw) {
    final key = normalizeTokoName(raw);
    if (key.isEmpty || key == 'PUSAT') return null;
    for (final c in kIndonesiaMajorCities) {
      if (c.name.toUpperCase() == key) return c;
    }
    for (final c in kIndonesiaMajorCities) {
      final n = c.name.toUpperCase();
      if (key.contains(n) || n.contains(key)) return c;
    }
    return null;
  }

  static IndonesiaCity? nearestCity(
    double lat,
    double lng, {
    bool besarOnly = false,
    double maxKm = _snapKm,
  }) {
    IndonesiaCity? best;
    var bestKm = maxKm;
    for (final c in kIndonesiaMajorCities) {
      if (besarOnly && !c.besar) continue;
      final d = kmBetween(lat, lng, c.lat, c.lng);
      if (d <= bestKm) {
        bestKm = d;
        best = c;
      }
    }
    return best;
  }

  static ({double lat, double lng, String name})? resolveEnd({
    double? lat,
    double? lng,
    String? tokoId,
    String? fallbackLabel,
  }) {
    final has = lat != null &&
        lng != null &&
        lat.abs() > 0.0001 &&
        lng.abs() > 0.0001;
    if (has) {
      final snap = nearestCity(lat, lng);
      final label = snap?.name ??
          (fallbackLabel?.trim().isNotEmpty == true
              ? fallbackLabel!.trim()
              : LogisticsTrackingService.tokoLabel(tokoId));
      return (lat: lat, lng: lng, name: label);
    }
    final named = cityByName(tokoId) ?? cityByName(fallbackLabel);
    if (named != null) {
      return (lat: named.lat, lng: named.lng, name: named.name);
    }
    return null;
  }

  static double kmBetween(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0;
    final p1 = aLat * math.pi / 180;
    final p2 = bLat * math.pi / 180;
    final dLat = (bLat - aLat) * math.pi / 180;
    final dLng = (bLng - aLng) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }

  static ({double x, double y}) _xy(
    double lat,
    double lng,
    double lat0,
    double lng0,
  ) {
    final x = (lng - lng0) * math.cos(lat0 * math.pi / 180) * 111.32;
    final y = (lat - lat0) * 110.574;
    return (x: x, y: y);
  }

  /// Jarak titik ke garis gudang→tujuan (km) + progres 0..1.
  static ({double distKm, double t}) _toSegment({
    required double lat,
    required double lng,
    required double aLat,
    required double aLng,
    required double bLat,
    required double bLng,
  }) {
    final a = _xy(aLat, aLng, aLat, aLng);
    final b = _xy(bLat, bLng, aLat, aLng);
    final p = _xy(lat, lng, aLat, aLng);
    final vx = b.x - a.x;
    final vy = b.y - a.y;
    final len2 = vx * vx + vy * vy;
    if (len2 < 0.01) {
      return (distKm: math.sqrt(p.x * p.x + p.y * p.y), t: 0);
    }
    var t = ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2;
    final tc = t.clamp(0.0, 1.0);
    final dx = p.x - (a.x + tc * vx);
    final dy = p.y - (a.y + tc * vy);
    return (distKm: math.sqrt(dx * dx + dy * dy), t: t);
  }

  /// Kota besar di koridor. Asal/tujuan selalu ikut (boleh kota kecil).
  static List<LogisticsRouteStop> along({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String? fromName,
    String? toName,
  }) {
    final tripKm = kmBetween(fromLat, fromLng, toLat, toLng);
    final originName = (fromName ?? '').trim().isEmpty
        ? (nearestCity(fromLat, fromLng)?.name ?? 'Asal')
        : fromName!.trim();
    final destName = (toName ?? '').trim().isEmpty
        ? (nearestCity(toLat, toLng)?.name ?? 'Tujuan')
        : toName!.trim();

    final origin = LogisticsRouteStop(
      name: originName,
      origin: true,
      dest: tripKm < 8 && originName.toUpperCase() == destName.toUpperCase(),
      kmFromOrigin: 0,
    );
    if (tripKm < 18) {
      if (origin.dest) return [origin];
      return [
        origin,
        LogisticsRouteStop(
          name: destName,
          origin: false,
          dest: true,
          kmFromOrigin: tripKm,
        ),
      ];
    }

    final hits = <({IndonesiaCity city, double t, double km})>[];
    for (final c in kIndonesiaMajorCities) {
      if (!c.besar) continue;
      final seg = _toSegment(
        lat: c.lat,
        lng: c.lng,
        aLat: fromLat,
        aLng: fromLng,
        bLat: toLat,
        bLng: toLng,
      );
      if (seg.t <= 0.04 || seg.t >= 0.96) continue;
      if (seg.distKm > _corridorKm) continue;
      final km = kmBetween(fromLat, fromLng, c.lat, c.lng);
      if (km < _endClearKm) continue;
      if (kmBetween(c.lat, c.lng, toLat, toLng) < _endClearKm) continue;
      hits.add((city: c, t: seg.t, km: km));
    }
    hits.sort((a, b) => a.t.compareTo(b.t));

    final picked = <LogisticsRouteStop>[origin];
    for (final h in hits) {
      final last = picked.last;
      if (h.city.name.toUpperCase() == last.name.toUpperCase()) continue;
      if (h.city.name.toUpperCase() == destName.toUpperCase()) continue;
      if (h.km - last.kmFromOrigin < _minGapKm) continue;
      picked.add(LogisticsRouteStop(
        name: h.city.name,
        origin: false,
        dest: false,
        kmFromOrigin: h.km,
      ));
    }
    if (picked.last.name.toUpperCase() != destName.toUpperCase()) {
      picked.add(LogisticsRouteStop(
        name: destName,
        origin: false,
        dest: true,
        kmFromOrigin: tripKm,
      ));
    }
    return picked;
  }

  static String jalurRingkas(List<LogisticsRouteStop> stops) {
    if (stops.isEmpty) return '';
    return stops.map((s) => s.name).join(' → ');
  }

  static List<LogisticsRouteEvent> events({
    required Map<String, dynamic> move,
    required List<LogisticsRouteStop> stops,
    required List<Map<String, dynamic>> tripSameCity,
  }) {
    final left = sudahBerangkat(move);
    final berangkat = berangkatAt(move);
    final tiba = tibaTujuanAt(move);
    final arrived = LogisticsLiveMapRules.arrivedInDestCity(
      move: move,
      tripSameCity: tripSameCity,
    );
    final st = _st(move);
    final destDone = st == 'SUCCESS';
    final destNow = st == 'PENDING' || (st == 'TRANSIT' && arrived);

    if (stops.isEmpty) {
      return [
        LogisticsRouteEvent(
          tempat: LogisticsTrackingService.tokoLabel(
            move['dari_lokasi']?.toString(),
          ),
          aksi: left ? 'Berangkat' : 'Belum berangkat',
          at: left ? berangkat : dibuatAt(move),
          done: left,
          current: !left,
        ),
        LogisticsRouteEvent(
          tempat: LogisticsTrackingService.tokoLabel(
            move['ke_lokasi']?.toString(),
          ),
          aksi: destDone
              ? 'Diterima'
              : (destNow ? 'Tiba' : (left ? 'Belum tiba' : 'Tujuan')),
          at: destDone || destNow ? tiba : null,
          done: destDone,
          current: destNow && !destDone,
        ),
      ];
    }

    return [
      for (var i = 0; i < stops.length; i++)
        _eventForStop(
          stop: stops[i],
          left: left,
          berangkat: berangkat,
          dibuat: dibuatAt(move),
          tiba: tiba,
          destDone: destDone,
          destNow: destNow,
        ),
    ];
  }

  static LogisticsRouteEvent _eventForStop({
    required LogisticsRouteStop stop,
    required bool left,
    required DateTime? berangkat,
    required DateTime? dibuat,
    required DateTime? tiba,
    required bool destDone,
    required bool destNow,
  }) {
    if (stop.origin) {
      return LogisticsRouteEvent(
        tempat: stop.name,
        aksi: left ? 'Berangkat' : 'Belum berangkat',
        at: left ? berangkat : dibuat,
        done: left,
        current: !left,
      );
    }
    if (stop.dest) {
      return LogisticsRouteEvent(
        tempat: stop.name,
        aksi: destDone
            ? 'Diterima'
            : (destNow ? 'Tiba' : (left ? 'Belum tiba' : 'Tujuan')),
        at: destDone ? tiba : (destNow ? tiba : null),
        done: destDone,
        current: destNow && !destDone,
      );
    }
    return LogisticsRouteEvent(
      tempat: stop.name,
      aksi: 'Lewat jalur',
      done: false,
      current: false,
    );
  }
}
