import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/indonesia_major_cities.dart';
import 'package:optik_b_riski/shared/logistics/logistics_route_cities.dart';
import 'package:optik_b_riski/shared/logistics/logistics_status_timeline.dart';

void main() {
  final batang = kIndonesiaMajorCities.firstWhere((c) => c.name == 'Batang');
  final cimahi = kIndonesiaMajorCities.firstWhere((c) => c.name == 'Cimahi');

  List<LogisticsRouteStop> jalur() => LogisticsRouteCities.along(
        fromLat: batang.lat,
        fromLng: batang.lng,
        toLat: cimahi.lat,
        toLng: cimahi.lng,
        fromName: 'Batang',
        toName: 'Cimahi',
      );

  test('TRANSIT: terbaru di atas, kota besar di dalam pengiriman', () {
    final move = {
      'status': 'TRANSIT',
      'created_at': '2026-08-23T01:14:00Z',
      'product_name': 'DO-10556438',
      'dari_lokasi': 'PUSAT',
      'ke_lokasi': 'CABANG-CIMAHI',
      'kurir_nama': 'E2E Blok18 Kurir',
    };
    final nodes = LogisticsStatusTimeline.build(
      move: move,
      stops: jalur(),
      tripSameCity: [move],
    );
    expect(nodes.first.key, 'jalan');
    expect(nodes.first.current, isTrue);
    expect(nodes.first.title, 'Sedang dalam pengiriman');
    final kota = nodes.first.children.map((c) => c.title).toList();
    expect(kota.first, contains('Cimahi'));
    expect(kota, contains('Melewati Cirebon'));
    expect(kota, contains('Melewati Tegal'));
    expect(kota.join(), isNot(contains('Pekalongan')));
    expect(nodes.any((n) => n.key == 'berangkat'), isTrue);
    expect(nodes.last.title, 'Menyiapkan pengiriman');
  });

  test('SUCCESS: Diterima hijau di puncak, foto URL dipakai', () {
    final move = {
      'status': 'SUCCESS',
      'created_at': '2026-08-23T01:00:00Z',
      'verified_at': '2026-08-23T14:02:00Z',
      'verified_by_name': 'Fahmi',
      'product_name': 'DO-1',
      'dari_lokasi': 'PUSAT',
      'ke_lokasi': 'CABANG-CIMAHI',
      'bukti_foto_penerima': 'https://example.com/bukti.jpg',
    };
    final nodes = LogisticsStatusTimeline.build(
      move: move,
      stops: jalur(),
      tripSameCity: [move],
    );
    expect(nodes.first.key, 'diterima');
    expect(nodes.first.current, isTrue);
    expect(nodes.first.photoUrl, 'https://example.com/bukti.jpg');
    expect(nodes.where((n) => n.current).length, 1);
    expect(nodes.any((n) => n.key == 'jalan'), isTrue);
  });
}
