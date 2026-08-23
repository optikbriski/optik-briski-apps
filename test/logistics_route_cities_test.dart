import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/indonesia_major_cities.dart';
import 'package:optik_b_riski/shared/logistics/logistics_route_cities.dart';

void main() {
  IndonesiaCity city(String name) =>
      kIndonesiaMajorCities.firstWhere((c) => c.name == name);

  test('Batang ke Cimahi: hanya kota besar di jalur pantura', () {
    final batang = city('Batang');
    final cimahi = city('Cimahi');
    final stops = LogisticsRouteCities.along(
      fromLat: batang.lat,
      fromLng: batang.lng,
      toLat: cimahi.lat,
      toLng: cimahi.lng,
      fromName: 'Batang',
      toName: 'Cimahi',
    );
    final names = stops.map((s) => s.name).toList();
    expect(names.first, 'Batang');
    expect(names.last, 'Cimahi');
    expect(names, containsAll(['Tegal', 'Cirebon']));
    expect(names, isNot(contains('Pekalongan')));
    expect(names, isNot(contains('Pemalang')));
    expect(names, isNot(contains('Brebes')));
    expect(names, isNot(contains('Surabaya')));
    expect(names, isNot(contains('Yogyakarta')));
    expect(names.length, lessThanOrEqualTo(5));
  });

  test('kota kecil tidak masuk jalur tengah', () {
    expect(
      kIndonesiaMajorCities.where((c) => c.name == 'Pekalongan').single.besar,
      isFalse,
    );
    expect(
      kIndonesiaMajorCities.where((c) => c.name == 'Tegal').single.besar,
      isTrue,
    );
  });

  test('CIMAHI di nama toko ketemu kota Cimahi', () {
    expect(LogisticsRouteCities.cityByName('CABANG-CIMAHI')?.name, 'Cimahi');
    expect(LogisticsRouteCities.cityByName('PUSAT'), isNull);
  });

  test('jam berangkat hanya setelah TRANSIT', () {
    final prep = {
      'status': 'PREPARING',
      'created_at': '2026-08-23T01:00:00Z',
    };
    expect(LogisticsRouteCities.berangkatAt(prep), isNull);
    expect(LogisticsRouteCities.sudahBerangkat(prep), isFalse);

    final transit = {
      'status': 'TRANSIT',
      'created_at': '2026-08-23T01:00:00Z',
    };
    expect(LogisticsRouteCities.berangkatAt(transit), isNotNull);
    expect(
      LogisticsRouteCities.berangkatAt({
        ...transit,
        'berangkat_at': '2026-08-23T08:14:00Z',
      })?.toUtc().hour,
      8,
    );
  });

  test('list event: berangkat Batang, lewat Cirebon, belum tiba Cimahi', () {
    final batang = city('Batang');
    final cimahi = city('Cimahi');
    final move = {
      'status': 'TRANSIT',
      'created_at': '2026-08-23T01:14:00Z',
      'dari_lokasi': 'PUSAT',
      'ke_lokasi': 'CABANG-CIMAHI',
    };
    final stops = LogisticsRouteCities.along(
      fromLat: batang.lat,
      fromLng: batang.lng,
      toLat: cimahi.lat,
      toLng: cimahi.lng,
      fromName: 'Batang',
      toName: 'Cimahi',
    );
    final ev = LogisticsRouteCities.events(
      move: move,
      stops: stops,
      tripSameCity: [move],
    );
    expect(ev.first.tempat, 'Batang');
    expect(ev.first.aksi, 'Berangkat');
    expect(ev.first.at, isNotNull);
    expect(ev.any((e) => e.tempat == 'Cirebon' && e.aksi == 'Lewat jalur'), isTrue);
    expect(ev.last.tempat, 'Cimahi');
    expect(ev.last.aksi, 'Belum tiba');
  });

  test('tujuan SUCCESS memakai jam verifikasi', () {
    final move = {
      'status': 'SUCCESS',
      'created_at': '2026-08-23T01:00:00Z',
      'verified_at': '2026-08-23T14:02:00Z',
      'dari_lokasi': 'PUSAT',
      'ke_lokasi': 'CABANG-CIMAHI',
    };
    final ev = LogisticsRouteCities.events(
      move: move,
      stops: const [
        LogisticsRouteStop(
          name: 'Batang',
          origin: true,
          dest: false,
          kmFromOrigin: 0,
        ),
        LogisticsRouteStop(
          name: 'Cimahi',
          origin: false,
          dest: true,
          kmFromOrigin: 240,
        ),
      ],
      tripSameCity: [move],
    );
    expect(ev.last.aksi, 'Diterima');
    expect(ev.last.at?.toUtc().hour, 14);
  });
}
