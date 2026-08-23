import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/logistics_live_map_rules.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  Map<String, dynamic> move({
    required String ke,
    required String status,
    String kurir = 'k1',
    String created = '2026-08-23T10:00:00Z',
    Object? tibaKota,
  }) =>
      {
        'ke_lokasi': ke,
        'status': status,
        'kurir_karyawan_id': kurir,
        'created_at': created,
        if (tibaKota != null) 'tiba_kota_at': tibaKota,
      };

  test('transit antar kota: teks saja, belum Google', () {
    final a = move(ke: 'CABANG-A', status: 'TRANSIT', created: '2026-08-23T08:00:00Z');
    final b = move(ke: 'CABANG-B', status: 'TRANSIT', created: '2026-08-23T08:10:00Z');
    final trip = [a, b];
    expect(
      LogisticsLiveMapRules.arrivedInDestCity(move: a, tripSameCity: trip),
      isFalse,
    );
    expect(
      LogisticsLiveMapRules.bolehLihatPetaLive(
        profile: p('admin_toko', 'CABANG-A'),
        move: a,
        tripSameCity: trip,
      ),
      isFalse,
    );
    expect(
      LogisticsLiveMapRules.alasanTertutup(
        profile: p('admin_toko', 'CABANG-A'),
        move: a,
        tripSameCity: trip,
      ),
      contains('kota tujuan'),
    );
  });

  test('tiba Bandung: hanya toko A yang lihat Google', () {
    final a = move(
      ke: 'CABANG-A',
      status: 'TRANSIT',
      created: '2026-08-23T08:00:00Z',
      tibaKota: '2026-08-23T11:00:00Z',
    );
    final b = move(
      ke: 'CABANG-B',
      status: 'TRANSIT',
      created: '2026-08-23T08:10:00Z',
      tibaKota: '2026-08-23T11:00:00Z',
    );
    final c = move(
      ke: 'CABANG-C',
      status: 'TRANSIT',
      created: '2026-08-23T08:20:00Z',
      tibaKota: '2026-08-23T11:00:00Z',
    );
    final trip = [a, b, c];
    expect(
      LogisticsLiveMapRules.bolehLihatPetaLive(
        profile: p('admin_toko', 'CABANG-A'),
        move: a,
        tripSameCity: trip,
      ),
      isTrue,
    );
    expect(
      LogisticsLiveMapRules.bolehLihatPetaLive(
        profile: p('admin_toko', 'CABANG-B'),
        move: b,
        tripSameCity: trip,
      ),
      isFalse,
    );
    expect(
      LogisticsLiveMapRules.bolehLihatPetaLive(
        profile: p('admin_toko', 'CABANG-C'),
        move: c,
        tripSameCity: trip,
      ),
      isFalse,
    );
    expect(
      LogisticsLiveMapRules.bolehLihatPetaLive(
        profile: p('admin_pusat', 'PUSAT'),
        move: a,
        tripSameCity: trip,
      ),
      isTrue,
    );
    expect(
      LogisticsLiveMapRules.alasanTertutup(
        profile: p('admin_toko', 'CABANG-C'),
        move: c,
        tripSameCity: trip,
      ),
      contains('Giliran'),
    );
  });

  test('A sudah terima: A tutup, B buka, C masih tutup', () {
    final a = move(
      ke: 'CABANG-A',
      status: 'SUCCESS',
      created: '2026-08-23T08:00:00Z',
    );
    final b = move(
      ke: 'CABANG-B',
      status: 'TRANSIT',
      created: '2026-08-23T08:10:00Z',
    );
    final c = move(
      ke: 'CABANG-C',
      status: 'TRANSIT',
      created: '2026-08-23T08:20:00Z',
    );
    final trip = [a, b, c];
    expect(
      LogisticsLiveMapRules.arrivedInDestCity(move: b, tripSameCity: trip),
      isTrue,
    );
    expect(
      LogisticsLiveMapRules.bolehLihatPetaLive(
        profile: p('admin_toko', 'CABANG-A'),
        move: a,
        tripSameCity: trip,
      ),
      isFalse,
    );
    expect(
      LogisticsLiveMapRules.bolehLihatPetaLive(
        profile: p('admin_toko', 'CABANG-B'),
        move: b,
        tripSameCity: trip,
      ),
      isTrue,
    );
    expect(
      LogisticsLiveMapRules.bolehLihatPetaLive(
        profile: p('admin_toko', 'CABANG-C'),
        move: c,
        tripSameCity: trip,
      ),
      isFalse,
    );
    expect(
      LogisticsLiveMapRules.alasanTertutup(
        profile: p('admin_toko', 'CABANG-A'),
        move: a,
        tripSameCity: trip,
      ),
      contains('selesai'),
    );
  });

  test('kotaBucket mengelompokkan titik dekat', () {
    expect(
      LogisticsLiveMapRules.kotaBucket(-6.917, 107.619),
      LogisticsLiveMapRules.kotaBucket(-6.91, 107.61),
    );
    expect(
      LogisticsLiveMapRules.kotaBucket(-6.917, 107.619),
      isNot(LogisticsLiveMapRules.kotaBucket(-6.2, 106.8)),
    );
  });
}
