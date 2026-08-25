import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../garansi/garansi_rules.dart';
import '../tenant/tenant_service.dart';

enum TokoAntrianKind { pickupPos, pickupOnline, booking, klaim }

/// Satu baris di inbox lantai toko.
class TokoAntrianItem {
  const TokoAntrianItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    this.when,
    this.noInvoice,
    this.status,
    this.meta = const {},
  });

  final TokoAntrianKind kind;
  final String id;
  final String title;
  final String subtitle;
  final DateTime? when;
  final String? noInvoice;
  final String? status;
  final Map<String, dynamic> meta;

  String get kindKey => switch (kind) {
        TokoAntrianKind.pickupPos => 'pickup_pos',
        TokoAntrianKind.pickupOnline => 'pickup_online',
        TokoAntrianKind.booking => 'booking',
        TokoAntrianKind.klaim => 'klaim',
      };
}

/// Hasil load antrian — item + error per sumber (jangan tutup gagal jadi daftar kosong).
class TokoAntrianLoadResult {
  const TokoAntrianLoadResult({
    required this.items,
    this.errors = const [],
  });

  final List<TokoAntrianItem> items;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
  bool get isEmpty => items.isEmpty;
}

/// Antrian kerja lantai toko untuk APK Karyawan (pickup / online / booking / klaim).
class TokoAntrianService {
  TokoAntrianService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<List<TokoAntrianItem>> load({required String tokoId}) async {
    final r = await loadDetailed(tokoId: tokoId);
    if (r.hasErrors && r.items.isEmpty) {
      throw r.errors.join(' · ');
    }
    return r.items;
  }

  Future<TokoAntrianLoadResult> loadDetailed({required String tokoId}) async {
    final toko = tokoId.trim();
    if (toko.isEmpty) {
      return const TokoAntrianLoadResult(items: []);
    }

    final results = await Future.wait([
      _safeLoad('pickup_pos', () => _loadPickupPos(toko)),
      _safeLoad('pickup_online', () => _loadPickupOnline(toko)),
      _safeLoad('booking', () => _loadBookingsToday(toko)),
      _safeLoad('klaim', () => _loadKlaimToday(toko)),
    ]);

    final out = <TokoAntrianItem>[];
    final errors = <String>[];
    for (final r in results) {
      out.addAll(r.items);
      if (r.error != null) errors.add(r.error!);
    }
    out.sort((a, b) {
      final aw = a.when?.millisecondsSinceEpoch ?? 0;
      final bw = b.when?.millisecondsSinceEpoch ?? 0;
      if (aw != bw) return aw.compareTo(bw);
      return a.title.compareTo(b.title);
    });
    return TokoAntrianLoadResult(items: out, errors: errors);
  }

  Future<({List<TokoAntrianItem> items, String? error})> _safeLoad(
    String label,
    Future<List<TokoAntrianItem>> Function() run,
  ) async {
    try {
      return (items: await run(), error: null);
    } catch (e) {
      debugPrint('TokoAntrian $label: $e');
      return (items: const <TokoAntrianItem>[], error: '$label: $e');
    }
  }

  Future<List<TokoAntrianItem>> _loadPickupPos(String tokoId) async {
    final aliases = AttendanceAdminScope.storeIdAliases(tokoId);
    final keys = aliases.isEmpty ? [tokoId] : aliases;
    final tid = TenantService.instance.id;
    var q = _db
        .from('sales')
        .select(
          'id, no_invoice, nama_pelanggan, tracking_status, diambil_at, '
          'toko_id, created_at',
        )
        .inFilter('toko_id', keys)
        .inFilter('tracking_status', ['SIAP_DIAMBIL', 'CLEAR'])
        .isFilter('diambil_at', null);
    if (tid != null && tid.isNotEmpty) {
      q = q.eq('tenant_id', tid);
    }
    final rows = await q.order('created_at', ascending: false).limit(40);
    return [
      for (final raw in List<dynamic>.from(rows as List))
        () {
          final m = Map<String, dynamic>.from(raw as Map);
          final inv = (m['no_invoice'] ?? '').toString();
          final nama = (m['nama_pelanggan'] ?? '-').toString();
          return TokoAntrianItem(
            kind: TokoAntrianKind.pickupPos,
            id: (m['id'] ?? '').toString(),
            title: inv.isEmpty ? 'Pickup POS' : inv,
            subtitle: nama,
            when: _parseTs(m['created_at']),
            noInvoice: inv.isEmpty ? null : inv,
            status: (m['tracking_status'] ?? '').toString(),
            meta: m,
          );
        }(),
    ];
  }

  Future<List<TokoAntrianItem>> _loadPickupOnline(String tokoId) async {
    final aliases = AttendanceAdminScope.storeIdAliases(tokoId);
    final keys = aliases.isEmpty ? [tokoId] : aliases;
    final tid = TenantService.instance.id;
    var q = _db
        .from('online_orders')
        .select(
          'id, customer_name, phone_e164, toko_id, fulfillment, status, '
          'store_note, created_at, paid_at',
        )
        .inFilter('toko_id', keys)
        .eq('fulfillment', 'pickup')
        .inFilter('status', ['paid', 'packing', 'ready']);
    if (tid != null && tid.isNotEmpty) {
      q = q.eq('tenant_id', tid);
    }
    final rows = await q.order('created_at', ascending: false).limit(40);
    return [
      for (final raw in List<dynamic>.from(rows as List))
        () {
          final m = Map<String, dynamic>.from(raw as Map);
          final nama = (m['customer_name'] ?? m['phone_e164'] ?? '-').toString();
          final st = (m['status'] ?? '').toString();
          final note = (m['store_note'] ?? '').toString().trim();
          final phone = (m['phone_e164'] ?? '').toString();
          return TokoAntrianItem(
            kind: TokoAntrianKind.pickupOnline,
            id: (m['id'] ?? '').toString(),
            title: nama,
            subtitle: note.isEmpty
                ? 'Online · $st${phone.isEmpty ? '' : ' · $phone'}'
                : 'Online · $st · $note',
            when: _parseTs(m['paid_at'] ?? m['created_at']),
            status: st,
            meta: m,
          );
        }(),
    ];
  }

  Future<List<TokoAntrianItem>> _loadBookingsToday(String tokoId) async {
    final (start, end) = _jakartaDayBoundsUtc();
    final aliases = AttendanceAdminScope.storeIdAliases(tokoId);
    final keys = aliases.isEmpty ? [tokoId] : aliases;
    final tid = TenantService.instance.id;
    var q = _db
        .from('member_bookings')
        .select(
          'id, phone_e164, toko_id, jenis, scheduled_at, status, catatan',
        )
        .inFilter('toko_id', keys)
        .inFilter('status', ['booked', 'checked_in'])
        .gte('scheduled_at', start.toIso8601String())
        .lt('scheduled_at', end.toIso8601String());
    if (tid != null && tid.isNotEmpty) {
      q = q.eq('tenant_id', tid);
    }
    final rows = await q.order('scheduled_at').limit(40);
    return [
      for (final raw in List<dynamic>.from(rows as List))
        () {
          final m = Map<String, dynamic>.from(raw as Map);
          final phone = (m['phone_e164'] ?? '-').toString();
          final jenis = (m['jenis'] ?? 'kontrol').toString();
          final st = (m['status'] ?? '').toString();
          final note = (m['catatan'] ?? '').toString().trim();
          return TokoAntrianItem(
            kind: TokoAntrianKind.booking,
            id: (m['id'] ?? '').toString(),
            title: phone,
            subtitle: note.isEmpty ? '$jenis · $st' : '$jenis · $st · $note',
            when: _parseTs(m['scheduled_at']),
            status: st,
            meta: m,
          );
        }(),
    ];
  }

  Future<List<TokoAntrianItem>> _loadKlaimToday(String tokoId) async {
    final (start, end) = _jakartaDayBoundsUtc();
    final aliases = GaransiRules.storeAliases(tokoId);
    final keys = aliases.isEmpty ? [tokoId] : aliases;
    final tid = TenantService.instance.id;
    var q = _db
        .from('garansi_klaim_request')
        .select(
          'id, phone_e164, toko_id, alasan, status, jadwal_kunjungan, '
          'kartu_id, sale_id, '
          'garansi_kartu:kartu_id(no_invoice, nama_pelanggan, nama_produk)',
        )
        .inFilter('toko_id', keys)
        .inFilter('status', ['diajukan', 'diproses_toko'])
        .gte('jadwal_kunjungan', start.toIso8601String())
        .lt('jadwal_kunjungan', end.toIso8601String());
    if (tid != null && tid.isNotEmpty) {
      q = q.eq('tenant_id', tid);
    }
    final rows = await q.order('jadwal_kunjungan').limit(40);
    return [
      for (final raw in List<dynamic>.from(rows as List))
        () {
          final m = Map<String, dynamic>.from(raw as Map);
          final kartu = m['garansi_kartu'];
          final kartuMap = kartu is Map
              ? Map<String, dynamic>.from(kartu)
              : <String, dynamic>{};
          final nama =
              (kartuMap['nama_pelanggan'] ?? m['phone_e164'] ?? '-').toString();
          final inv = (kartuMap['no_invoice'] ?? '').toString();
          final st = (m['status'] ?? '').toString();
          return TokoAntrianItem(
            kind: TokoAntrianKind.klaim,
            id: (m['id'] ?? '').toString(),
            title: nama,
            subtitle: inv.isEmpty ? 'Klaim · $st' : '$inv · $st',
            when: _parseTs(m['jadwal_kunjungan']),
            noInvoice: inv.isEmpty ? null : inv,
            status: st,
            meta: m,
          );
        }(),
    ];
  }

  /// Booking: checked_in | done | no_show — hanya lewat RPC (store + duty).
  Future<void> updateBookingStatus({
    required String bookingId,
    required String status,
  }) async {
    final st = status.trim().toLowerCase();
    if (!const {'checked_in', 'done', 'no_show'}.contains(st)) {
      throw 'Status booking tidak valid';
    }
    final res = await _db.rpc('karyawan_antrian_action', params: {
      'p_kind': 'booking',
      'p_id': bookingId,
      'p_action': st,
    });
    _assertRpcOk(res);
  }

  /// Klaim request: diproses_toko
  Future<void> markKlaimDiproses({required String requestId}) async {
    final res = await _db.rpc('karyawan_antrian_action', params: {
      'p_kind': 'klaim',
      'p_id': requestId,
      'p_action': 'diproses_toko',
    });
    _assertRpcOk(res);
  }

  /// Online pickup: paid → packing → ready → fulfilled
  Future<void> advanceOnlinePickup({
    required String orderId,
    required String currentStatus,
  }) async {
    final cur = currentStatus.trim().toLowerCase();
    final next = nextOnlinePickupStatus(cur);
    if (next == null) {
      throw 'Status online tidak bisa diproses dari HP: $cur';
    }
    final res = await _db.rpc('karyawan_antrian_action', params: {
      'p_kind': 'online',
      'p_id': orderId,
      'p_action': next,
    });
    _assertRpcOk(res);
  }

  /// Mapping status advance (uji unit + UI label).
  static String? nextOnlinePickupStatus(String currentStatus) {
    return switch (currentStatus.trim().toLowerCase()) {
      'paid' => 'packing',
      'packing' => 'ready',
      'ready' => 'fulfilled',
      _ => null,
    };
  }

  void _assertRpcOk(dynamic res) {
    if (res is Map && res['ok'] == false) {
      throw (res['error'] ?? 'Gagal').toString();
    }
  }

  /// Visible for tests: Jakarta calendar day as UTC [start, end).
  static (DateTime, DateTime) jakartaDayBoundsUtc() => _jakartaDayBoundsUtc();

  static (DateTime, DateTime) _jakartaDayBoundsUtc() {
    final nowUtc = DateTime.now().toUtc();
    // Asia/Jakarta = UTC+7 (tanpa DST)
    final jakarta = nowUtc.add(const Duration(hours: 7));
    final startJakarta = DateTime.utc(jakarta.year, jakarta.month, jakarta.day);
    final endJakarta = startJakarta.add(const Duration(days: 1));
    final startUtc = startJakarta.subtract(const Duration(hours: 7)).toUtc();
    final endUtc = endJakarta.subtract(const Duration(hours: 7)).toUtc();
    return (startUtc, endUtc);
  }

  static DateTime? _parseTs(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }
}
