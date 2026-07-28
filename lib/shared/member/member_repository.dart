import 'package:supabase_flutter/supabase_flutter.dart';

import '../whatsapp_launcher.dart';
import 'member_session.dart';

class MemberRepository {
  MemberRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<Map<String, dynamic>> requestOtp(String phone) async {
    final res = await _db.rpc('member_request_otp', params: {
      'p_phone': phone.trim(),
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async {
    final res = await _db.rpc('member_verify_otp', params: {
      'p_phone': phone.trim(),
      'p_code': code.trim(),
    });
    final map = Map<String, dynamic>.from(res as Map);
    final member = map['member'];
    if (member is Map) {
      await MemberSession.instance
          .applyMember(Map<String, dynamic>.from(member));
    }
    return map;
  }

  Future<void> upsertProfile({
    required String phone,
    String? nama,
    String? email,
    String? alamat,
    double? fontScale,
    String? locale,
  }) async {
    final res = await _db.rpc('member_upsert_profile', params: {
      'p_phone': phone,
      'p_nama': nama,
      'p_email': email,
      'p_alamat': alamat,
      'p_font_scale': fontScale,
      'p_locale': locale,
    });
    if (res is Map) {
      await MemberSession.instance
          .applyMember(Map<String, dynamic>.from(res));
    }
  }

  Future<List<Map<String, dynamic>>> listSales(String phone) async {
    try {
      final res = await _db.rpc('list_member_sales', params: {
        'p_phone': phone,
      });
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    // Fallback: direct query (butuh RLS / auth)
    final digits = normalizeWaNumber(phone);
    final alt = digits.startsWith('62') ? '0${digits.substring(2)}' : digits;
    try {
      final rows = await _db
          .from('sales')
          .select(
            'id, no_invoice, toko_id, nama_pelanggan, status_pembayaran, '
            'tracking_status, diambil_at, foto_hasil_url, sisa_tagihan, '
            'total_harga, dibayarkan, created_at, lunas_at, no_wa',
          )
          .or('no_wa.eq.$phone,no_wa.eq.$digits,no_wa.eq.$alt')
          .order('created_at', ascending: false)
          .limit(100);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> listGaransi(String phone) async {
    try {
      final res = await _db.rpc('list_member_garansi', params: {
        'p_phone': phone,
      });
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Konten beranda Member (CMS Admin Pusat). Null = pakai default hardcode.
  Future<Map<String, dynamic>?> homeContent() async {
    try {
      final row = await _db
          .from('member_home_content')
          .select(
            'brand_label, slides, greeting_guest, greeting_subtitle_guest, '
            'promo_title, promo_subtitle, sections, feature_flags',
          )
          .eq('id', 'default')
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listPromos({bool forMember = true}) async {
    try {
      var q = _db.from('member_promos').select().eq('active', true);
      if (forMember) q = q.eq('show_on_member', true);
      final rows = await q.order('sort_order').order('created_at');
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((p) {
        final left = p['quantity_remaining'];
        if (left == null) return true;
        return (int.tryParse('$left') ?? 0) > 0;
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Lookup voucher untuk POS (RPC).
  Future<Map<String, dynamic>> lookupPromo(String code) async {
    try {
      final res = await _db.rpc('lookup_member_promo', params: {
        'p_code': code.trim(),
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return {'ok': false, 'error': 'Voucher tidak ditemukan'};
  }

  /// Katalog Member = baris `toko_id = PUSAT` (sama sumber katalog POS / parity).
  Future<List<Map<String, dynamic>>> listCatalog({
    String? kategori,
    String? search,
    int limit = 120,
  }) async {
    try {
      final res = await _db.rpc('list_member_catalog', params: {
        'p_kategori': (kategori == null || kategori.trim().isEmpty)
            ? null
            : kategori.trim(),
        'p_q': (search == null || search.trim().isEmpty) ? null : search.trim(),
        'p_limit': limit,
      });
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    // Fallback jika RPC belum di-deploy (butuh RLS authenticated).
    try {
      var filter = _db
          .from('products')
          .select(
            'id, sku, barcode, nama, kategori, sub_kategori, warna, '
            'jenis_lensa, harga, harga_jual, image_url, foto_url',
          )
          .eq('toko_id', 'PUSAT');
      if (kategori != null && kategori.trim().isNotEmpty) {
        filter = filter.eq('kategori', kategori.trim());
      }
      if (search != null && search.trim().isNotEmpty) {
        final s = search.trim();
        filter = filter.or('nama.ilike.%$s%,sku.ilike.%$s%,barcode.ilike.%$s%');
      }
      final rows = await filter.order('nama').limit(limit);
      return (rows as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['harga'] = m['harga_jual'] ?? m['harga'];
        m['image_url'] = (m['image_url']?.toString().trim().isNotEmpty == true)
            ? m['image_url']
            : m['foto_url'];
        return m;
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<int> pointsBalance(String memberId) async {
    try {
      final rows = await _db
          .from('member_points_ledger')
          .select('delta')
          .eq('member_id', memberId);
      var sum = 0;
      for (final r in (rows as List)) {
        sum += int.tryParse('${r['delta'] ?? 0}') ?? 0;
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> listBookings(String phone) async {
    final digits = normalizeWaNumber(phone);
    try {
      final rows = await _db
          .from('member_bookings')
          .select()
          .eq('phone_e164', digits)
          .order('scheduled_at', ascending: true);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> createBooking({
    required String phone,
    required String tokoId,
    required DateTime scheduledAt,
    String jenis = 'kontrol',
    String? catatan,
    String? memberId,
  }) async {
    await _db.from('member_bookings').insert({
      'phone_e164': normalizeWaNumber(phone),
      'member_id': memberId,
      'toko_id': tokoId,
      'jenis': jenis,
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'catatan': catatan,
      'status': 'booked',
    });
  }

  Future<void> cancelBooking(String id) async {
    await _db
        .from('member_bookings')
        .update({'status': 'cancelled'}).eq('id', id);
  }

  Future<void> submitClaimRequest({
    required String phone,
    required String kartuId,
    required String tokoId,
    required String alasan,
    String? saleId,
    String? memberId,
    String? fotoUrl,
  }) async {
    await _db.from('garansi_klaim_request').insert({
      'phone_e164': normalizeWaNumber(phone),
      'member_id': memberId,
      'kartu_id': kartuId,
      'sale_id': saleId,
      'toko_id': tokoId,
      'alasan': alasan,
      'foto_url': fotoUrl,
      'status': 'diajukan',
    });
  }

  Future<List<Map<String, dynamic>>> listClaimRequests(String phone) async {
    try {
      final rows = await _db
          .from('garansi_klaim_request')
          .select()
          .eq('phone_e164', normalizeWaNumber(phone))
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> submitSurvey({
    required String saleId,
    required String phone,
    required int nyaman,
    required int cocok,
    required int pelayanan,
    String? komentar,
  }) async {
    await _db.from('member_survey').upsert({
      'sale_id': saleId,
      'phone_e164': normalizeWaNumber(phone),
      'nyaman': nyaman,
      'cocok': cocok,
      'pelayanan': pelayanan,
      'komentar': komentar,
    });
  }

  Future<List<Map<String, dynamic>>> listFamily(String memberId) async {
    try {
      final rows = await _db
          .from('member_family')
          .select()
          .eq('member_id', memberId)
          .order('created_at');
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> addFamily({
    required String memberId,
    required String nama,
    String? hubungan,
    String? phone,
  }) async {
    await _db.from('member_family').insert({
      'member_id': memberId,
      'nama': nama,
      'hubungan': hubungan,
      'phone_e164':
          phone == null || phone.isEmpty ? null : normalizeWaNumber(phone),
    });
  }

  Future<Map<String, dynamic>?> storeSettings(String tokoId) async {
    try {
      final row = await _db
          .from('invoice_settings')
          .select('toko_id, shop_name, address, phone, google_review_url')
          .eq('toko_id', tokoId)
          .maybeSingle();
      if (row != null) return Map<String, dynamic>.from(row);
      return await _db
          .from('invoice_settings')
          .select('toko_id, shop_name, address, phone, google_review_url')
          .eq('toko_id', 'PUSAT')
          .maybeSingle()
          .then((e) => e == null ? null : Map<String, dynamic>.from(e));
    } catch (_) {
      return null;
    }
  }
}
