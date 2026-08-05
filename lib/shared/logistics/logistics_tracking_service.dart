import 'package:supabase_flutter/supabase_flutter.dart';

/// Status surat jalan yang masih “di jalan” (bisa dilacak di peta gratis).
const kLogisticsOpenStatuses = ['PREPARING', 'WAITING', 'TRANSIT', 'PENDING'];

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

  static const _openSelect =
      'id, product_name, dari_lokasi, ke_lokasi, jumlah, status, tipe, '
      'keterangan, created_at, kurir_karyawan_id, kurir_nama, '
      'verified_by_name, verified_at, bukti_foto_pengirim, bukti_foto_kurir, '
      'bukti_foto_penerima, bukti_foto_penerim';

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
    int limit = 120,
  }) async {
    var q = _db
        .from('stock_move_history')
        .select(_openSelect)
        .inFilter('status', kLogisticsOpenStatuses);

    if (!isPusatView(profile)) {
      final myToko = (profile['toko_id'] ?? '').toString().toUpperCase();
      if (myToko.isNotEmpty) {
        // Filter di server agar cabang tidak menarik seluruh antrian pusat.
        q = q.or('ke_lokasi.eq.$myToko,dari_lokasi.eq.$myToko');
      }
    }

    final rows =
        await q.order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
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
        label: tokoLabel(id),
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listKaryawanAktif({
    String? tokoId,
    bool pusatOnly = false,
  }) async {
    final filterToko = pusatOnly
        ? 'PUSAT'
        : (tokoId?.trim().isNotEmpty == true ? tokoId!.trim() : null);

    var q = _db
        .from('karyawan')
        .select('id, nik, nama, jabatan, toko_id, status_approval')
        .inFilter('status_approval', const ['Aktif', 'aktif', 'approved']);

    if (filterToko != null) {
      q = q.eq('toko_id', filterToko.toUpperCase());
    }

    final rows = await q.order('nama');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> assignKurir({
    required String moveId,
    required String karyawanId,
    required String nama,
  }) async {
    final id = moveId.trim();
    if (id.isEmpty) throw 'ID surat jalan kosong.';
    final kid = karyawanId.trim();
    final nm = nama.trim();
    if (kid.isEmpty || nm.isEmpty) throw 'Data kurir tidak lengkap.';

    final row = await _db
        .from('stock_move_history')
        .select('id, status')
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw 'Surat jalan tidak ditemukan.';
    final st = (row['status'] ?? '').toString().toUpperCase();
    if (!kLogisticsOpenStatuses.contains(st)) {
      throw 'Tidak bisa set kurir — status ${statusLabel(st)}.';
    }

    await _db.from('stock_move_history').update({
      'kurir_karyawan_id': kid,
      'kurir_nama': nm,
    }).eq('id', id);
  }

  Future<void> clearKurir(String moveId) async {
    final id = moveId.trim();
    if (id.isEmpty) throw 'ID surat jalan kosong.';

    final row = await _db
        .from('stock_move_history')
        .select('id, status')
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw 'Surat jalan tidak ditemukan.';
    final st = (row['status'] ?? '').toString().toUpperCase();
    if (!kLogisticsOpenStatuses.contains(st)) {
      throw 'Tidak bisa hapus kurir — status ${statusLabel(st)}.';
    }

    await _db.from('stock_move_history').update({
      'kurir_karyawan_id': null,
      'kurir_nama': null,
    }).eq('id', id);
  }

  static String tipeLabel(Map<String, dynamic> move) {
    final t = (move['tipe'] ?? '').toString().toUpperCase();
    final resi = (move['product_name'] ?? '').toString().toUpperCase();
    if (t == 'DELIVERY' || resi.startsWith('DO-')) return 'DO';
    if (t == 'REQUEST' || resi.startsWith('RO-')) return 'RO';
    if (t == 'RETUR' || resi.startsWith('RET-')) return 'Retur';
    return t.isEmpty ? 'Mutasi' : t;
  }

  /// DO | RO | RETUR | OTHER — untuk filter chip.
  static String kindCode(Map<String, dynamic> move) {
    final label = tipeLabel(move);
    if (label == 'DO') return 'DO';
    if (label == 'RO') return 'RO';
    if (label == 'Retur') return 'RETUR';
    return 'OTHER';
  }

  static String statusLabel(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'PREPARING':
        return 'Disiapkan';
      case 'WAITING':
        return 'Siap dijemput';
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

  static String tokoLabel(String? id) {
    final t = (id ?? '').trim().toUpperCase();
    if (t.isEmpty) return '-';
    if (t == 'PUSAT') return 'Pusat';
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  /// Langkah timeline untuk UI (urutan kiri→kanan).
  static List<({String key, String label, bool done, bool current})> timeline(
    Map<String, dynamic> move,
  ) {
    final st = (move['status'] ?? '').toString().toUpperCase();
    final created = true;
    final preparing = st == 'PREPARING' || st == 'WAITING';
    final onRoad = st == 'TRANSIT' || st == 'PENDING';
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
        key: 'prep',
        label: 'Disiapkan',
        done: preparing || onRoad || done || batal,
        current: preparing && !onRoad && !done && !batal,
      ),
      (
        key: 'road',
        label: st == 'PENDING' ? 'Verifikasi' : 'Perjalanan',
        done: onRoad || done || batal,
        current: onRoad && !done && !batal,
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
