import 'package:supabase_flutter/supabase_flutter.dart';

/// Status surat jalan yang masih “di jalan” (bisa dilacak di peta gratis).
const kLogisticsOpenStatuses = ['WAITING', 'TRANSIT', 'PENDING'];

class TokoGeo {
  const TokoGeo({
    required this.id,
    this.latitude,
    this.longitude,
    this.label,
  });

  final String id;
  final double? latitude;
  final double? longitude;
  final String? label;

  bool get hasCoords =>
      latitude != null &&
      longitude != null &&
      latitude!.abs() > 0.0001 &&
      longitude!.abs() > 0.0001;
}

class LogisticsTrackingService {
  LogisticsTrackingService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  bool isPusatView(Map<String, dynamic> profile) {
    final toko = (profile['toko_id'] ?? '').toString().toUpperCase();
    final role = (profile['role'] ?? '').toString().toLowerCase();
    return toko == 'PUSAT' ||
        role == 'super_admin' ||
        role == 'owner' ||
        role == 'admin_pusat';
  }

  /// Surat jalan terbuka untuk tracking Admin.
  Future<List<Map<String, dynamic>>> listOpenMoves({
    required Map<String, dynamic> profile,
    int limit = 80,
  }) async {
    var q = _db
        .from('stock_move_history')
        .select()
        .inFilter('status', kLogisticsOpenStatuses)
        .order('created_at', ascending: false)
        .limit(limit);

    final rows = await q;
    final list = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (isPusatView(profile)) return list;

    final myToko = (profile['toko_id'] ?? '').toString().toUpperCase();
    return list.where((item) {
      final ke = (item['ke_lokasi'] ?? '').toString().toUpperCase();
      final dari = (item['dari_lokasi'] ?? '').toString().toUpperCase();
      return ke == myToko || dari == myToko;
    }).toList();
  }

  Future<List<TokoGeo>> listTokoGeo() async {
    final rows = await _db
        .from('toko_id')
        .select('id, latitude, longitude')
        .order('id');
    return (rows as List).map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id'] ?? '').toString();
      return TokoGeo(
        id: id,
        label: id,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listKaryawanAktif({
    String? tokoId,
    bool pusatOnly = false,
  }) async {
    final filterToko =
        pusatOnly ? 'PUSAT' : (tokoId?.trim().isNotEmpty == true ? tokoId!.trim() : null);

    final base = _db
        .from('karyawan')
        .select('id, nik, nama, jabatan, toko_id, status_approval')
        .eq('status_approval', 'Aktif');

    final rows = filterToko == null
        ? await base.order('nama')
        : await base.eq('toko_id', filterToko).order('nama');

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> assignKurir({
    required String moveId,
    required String karyawanId,
    required String nama,
  }) async {
    await _db.from('stock_move_history').update({
      'kurir_karyawan_id': karyawanId,
      'kurir_nama': nama.trim(),
    }).eq('id', moveId);
  }

  Future<void> clearKurir(String moveId) async {
    await _db.from('stock_move_history').update({
      'kurir_karyawan_id': null,
      'kurir_nama': null,
    }).eq('id', moveId);
  }

  static String tipeLabel(Map<String, dynamic> move) {
    final t = (move['tipe'] ?? '').toString().toUpperCase();
    final resi = (move['product_name'] ?? '').toString().toUpperCase();
    if (t == 'DELIVERY' || resi.startsWith('DO-')) return 'DO';
    if (t == 'REQUEST' || resi.startsWith('RO-')) return 'RO';
    if (t == 'RETUR' || resi.startsWith('RET-')) return 'Retur';
    return t.isEmpty ? 'Mutasi' : t;
  }

  static String statusLabel(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'WAITING':
        return 'Menunggu kirim / jemput';
      case 'TRANSIT':
        return 'Dalam perjalanan';
      case 'PENDING':
        return 'Menunggu verifikasi';
      case 'SUCCESS':
        return 'Diterima';
      case 'BATAL':
        return 'Dibatalkan';
      case 'REJECTED':
        return 'Ditolak';
      default:
        return status?.isNotEmpty == true ? status! : '-';
    }
  }

  /// Langkah timeline untuk UI (urutan kiri→kanan).
  static List<({String key, String label, bool done, bool current})> timeline(
    Map<String, dynamic> move,
  ) {
    final st = (move['status'] ?? '').toString().toUpperCase();
    final created = true;
    final onRoad = st == 'WAITING' || st == 'TRANSIT' || st == 'PENDING';
    final done = st == 'SUCCESS';
    final batal = st == 'BATAL' || st == 'REJECTED';

    return [
      (
        key: 'created',
        label: 'Dibuat',
        done: created,
        current: st.isEmpty,
      ),
      (
        key: 'road',
        label: st == 'PENDING'
            ? 'Menunggu'
            : (st == 'WAITING' ? 'Siap kirim' : 'Transit'),
        done: onRoad || done,
        current: onRoad && !done,
      ),
      (
        key: 'done',
        label: batal ? 'Batal' : 'Diterima',
        done: done || batal,
        current: done || batal,
      ),
    ];
  }
}
