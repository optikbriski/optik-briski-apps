import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../invoice/invoice_hub_service.dart';
import '../invoice/invoice_settings_service.dart';
import '../maps/osm_address_search.dart';
import '../whatsapp_launcher.dart';
import 'member_points_grade.dart';
import 'member_session.dart';

/// Hasil paralel load Beranda Member.
class MemberHomeBundle {
  const MemberHomeBundle({
    required this.content,
    required this.sales,
    required this.garansiCount,
    required this.bookings,
    required this.points,
    required this.promos,
    this.onlineOrders = const [],
    this.highlightToko,
    this.partialError,
  });

  final Map<String, dynamic>? content;
  final List<Map<String, dynamic>> sales;
  final int garansiCount;
  final List<Map<String, dynamic>> bookings;
  final int points;
  final List<Map<String, dynamic>> promos;
  final List<Map<String, dynamic>> onlineOrders;
  final String? highlightToko;
  final String? partialError;
}

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

  Future<Map<String, dynamic>> loginWithPassword({
    required String identifier,
    required String password,
  }) async {
    final res = await _db.rpc('member_login', params: {
      'p_identifier': identifier.trim(),
      'p_password': password,
    });
    final map = Map<String, dynamic>.from(res as Map);
    if (map['ok'] == true && map['member'] is Map) {
      await MemberSession.instance
          .applyMember(Map<String, dynamic>.from(map['member'] as Map));
    }
    return map;
  }

  Future<Map<String, dynamic>> registerMember({
    required String phone,
    required String password,
    String? nama,
    String? email,
    DateTime? tanggalLahir,
  }) async {
    final res = await _db.rpc('member_register', params: {
      'p_phone': phone.trim(),
      'p_password': password,
      'p_nama': nama?.trim(),
      'p_email': email?.trim(),
      'p_tanggal_lahir':
          tanggalLahir?.toIso8601String().substring(0, 10),
    });
    final map = Map<String, dynamic>.from(res as Map);
    if (map['ok'] == true && map['member'] is Map) {
      await MemberSession.instance
          .applyMember(Map<String, dynamic>.from(map['member'] as Map));
    }
    return map;
  }

  Map<String, dynamic> _draftPayload({
    required String phone,
    String password = '',
    String email = '',
    DateTime? tanggalLahir,
    String? nama,
  }) =>
      {
        'phone': phone.trim(),
        'password': password,
        'email': email.trim(),
        'nama': nama?.trim(),
        'tanggal_lahir': tanggalLahir?.toIso8601String().substring(0, 10),
      };

  Future<Map<String, dynamic>> saveRegisterDraft({
    required String phone,
    String password = '',
    String email = '',
    DateTime? tanggalLahir,
    String? nama,
  }) async {
    try {
      final res = await _db.rpc('member_save_register_draft', params: {
        'p_phone': phone.trim(),
        'p_password': password,
        'p_nama': nama?.trim(),
        'p_email': email.trim().isEmpty ? null : email.trim(),
        'p_tanggal_lahir': tanggalLahir?.toIso8601String().substring(0, 10),
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return {'ok': false, 'error': 'Gagal simpan draft'};
  }

  /// Kirim OTP ke satu channel: `wa` atau `email`.
  /// Nama / password / DOB boleh masih kosong — diisi sebelum bikin akun.
  Future<Map<String, dynamic>> sendRegisterChannelOtp({
    required String channel,
    required String phone,
    String password = '',
    String email = '',
    DateTime? tanggalLahir,
    String? nama,
  }) async {
    final body = {
      ..._draftPayload(
        phone: phone,
        password: password,
        email: email,
        tanggalLahir: tanggalLahir,
        nama: nama,
      ),
      'channel': channel,
    };
    try {
      final res = await _db.functions.invoke(
        'member-send-channel-otp',
        body: body,
      );
      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      if (res.status >= 400) {
        return {
          'ok': false,
          'error': 'Edge OTP gagal (HTTP ${res.status}). Deploy function + cek RESEND_API_KEY.',
        };
      }
    } catch (e) {
      // Function belum deploy / jaringan — fallback debug lokal
      debugPrint('member-send-channel-otp invoke: $e');
    }

    // Fallback lokal tanpa Edge (OTP tetap bisa diverifikasi, tidak lewat Resend)
    final draft = await saveRegisterDraft(
      phone: phone,
      password: password,
      email: email,
      tanggalLahir: tanggalLahir,
      nama: nama,
    );
    if (draft['ok'] != true) return draft;
    try {
      final issued = await _db.rpc('member_issue_register_otp', params: {
        'p_phone': phone.trim(),
        'p_channel': channel,
      });
      if (issued is Map) {
        final m = Map<String, dynamic>.from(issued);
        return {
          ...m,
          'sent': false,
          'debug_otp': m['otp'],
          'message':
              'Edge/Resend belum aktif — pakai kode debug. Deploy member-send-channel-otp.',
        };
      }
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return {'ok': false, 'error': 'Gagal kirim OTP'};
  }

  Future<Map<String, dynamic>> checkRegisterChannelOtp({
    required String phone,
    required String channel,
    required String code,
  }) async {
    try {
      final res = await _db.rpc('member_check_register_otp', params: {
        'p_phone': phone.trim(),
        'p_channel': channel,
        'p_code': code.trim(),
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'verified': false, 'error': '$e'};
    }
    return {'ok': false, 'verified': false, 'error': 'Gagal cek OTP'};
  }

  /// Buat akun setelah WA + email verified. Tidak auto-login.
  /// Nama / password / DOB disimpan dulu ke draft (boleh diisi belakangan setelah OTP).
  Future<Map<String, dynamic>> finalizeRegister({
    required String phone,
    String password = '',
    String email = '',
    DateTime? tanggalLahir,
    String? nama,
  }) async {
    try {
      final res = await _db.rpc('member_finalize_register_with_profile', params: {
        'p_phone': phone.trim(),
        'p_password': password,
        'p_nama': nama?.trim(),
        'p_email': email.trim().isEmpty ? null : email.trim(),
        'p_tanggal_lahir': tanggalLahir?.toIso8601String().substring(0, 10),
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (_) {
      // Fallback kalau RPC with_profile belum di-deploy
      final draft = await saveRegisterDraft(
        phone: phone,
        password: password,
        email: email,
        tanggalLahir: tanggalLahir,
        nama: nama,
      );
      if (draft['ok'] != true) return draft;
      try {
        final res = await _db.rpc('member_finalize_register', params: {
          'p_phone': phone.trim(),
        });
        if (res is Map) return Map<String, dynamic>.from(res);
      } catch (e) {
        return {'ok': false, 'error': '$e'};
      }
    }
    return {'ok': false, 'error': 'Gagal buat akun'};
  }

  Future<Map<String, dynamic>> requestPasswordReset(String identifier) async {
    final res = await _db.rpc('member_request_password_reset', params: {
      'p_identifier': identifier.trim(),
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    final res = await _db.rpc('member_reset_password', params: {
      'p_identifier': identifier.trim(),
      'p_code': code.trim(),
      'p_new_password': newPassword,
    });
    final map = Map<String, dynamic>.from(res as Map);
    if (map['ok'] == true && map['member'] is Map) {
      await MemberSession.instance
          .applyMember(Map<String, dynamic>.from(map['member'] as Map));
    }
    return map;
  }

  Future<void> upsertProfile({
    required String phone,
    String? nama,
    String? email,
    String? alamat,
    String? phoneRaw,
    DateTime? tanggalLahir,
    double? fontScale,
    String? locale,
  }) async {
    try {
      final res = await _db.rpc('member_upsert_profile', params: {
        'p_phone': phone,
        'p_nama': nama,
        'p_email': email,
        'p_alamat': alamat,
        'p_phone_raw': phoneRaw,
        'p_tanggal_lahir': tanggalLahir?.toIso8601String().substring(0, 10),
        'p_font_scale': fontScale,
        'p_locale': locale,
      });
      if (res is Map) {
        await MemberSession.instance
            .applyMember(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      throw Exception(
        'Gagal simpan profil. Jalankan SQL 20260728000013_member_profile_fields.sql di Supabase. ($e)',
      );
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
            'total_harga, dibayarkan, created_at, lunas_at, no_wa, '
            'qr_dp_token, qr_lunas_token, qr_claim_token, '
            'channel, online_order_id, fulfillment, courier',
          )
          .or('no_wa.eq.$phone,no_wa.eq.$digits,no_wa.eq.$alt')
          .order('created_at', ascending: false)
          .limit(100);
      return (rows as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['has_qr_dp'] =
            (m['qr_dp_token'] ?? '').toString().trim().length >= 8;
        m['has_qr_lunas'] =
            (m['qr_lunas_token'] ?? '').toString().trim().length >= 8;
        m['has_qr_claim'] =
            (m['qr_claim_token'] ?? '').toString().trim().length >= 8;
        return m;
      }).toList();
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
  /// Error jaringan/DB dibiarkan throw agar [fetchHomeBundle] bisa set partialError.
  Future<Map<String, dynamic>?> homeContent() async {
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
  }

  Future<({T value, bool ok})> _safeHomeTracked<T>(
    Future<T> future,
    T fallback,
  ) async {
    try {
      return (value: await future, ok: true);
    } catch (e, st) {
      debugPrint('fetchHomeBundle soft-fail: $e\n$st');
      return (value: fallback, ok: false);
    }
  }

  /// Satu round-trip paralel untuk Beranda Member (CMS + live data).
  Future<MemberHomeBundle> fetchHomeBundle({
    required bool loggedIn,
    required String phone,
    String? memberId,
    String? preferredTokoId,
  }) async {
    if (!loggedIn || phone.trim().isEmpty) {
      final results = await Future.wait([
        _safeHomeTracked<Map<String, dynamic>?>(homeContent(), null),
        _safeHomeTracked(
          _listPromosOrThrow(forMember: true),
          <Map<String, dynamic>>[],
        ),
      ]);
      final fails = results.where((r) => !r.ok).length;
      return MemberHomeBundle(
        content: results[0].value as Map<String, dynamic>?,
        sales: const [],
        garansiCount: 0,
        bookings: const [],
        points: 0,
        promos: results[1].value as List<Map<String, dynamic>>,
        onlineOrders: const [],
        highlightToko: preferredTokoId?.trim().isNotEmpty == true
            ? preferredTokoId!.trim()
            : null,
        partialError: fails > 0
            ? 'Sebagian data gagal dimuat. Tarik untuk coba lagi.'
            : null,
      );
    }

    final results = await Future.wait([
      _safeHomeTracked<Map<String, dynamic>?>(homeContent(), null),
      _safeHomeTracked(listSales(phone), <Map<String, dynamic>>[]),
      _safeHomeTracked(listGaransi(phone), <Map<String, dynamic>>[]),
      _safeHomeTracked(listBookings(phone), <Map<String, dynamic>>[]),
      _safeHomeTracked(
        (memberId == null || memberId.isEmpty)
            ? Future<int>.value(0)
            : pointsBalance(memberId),
        0,
      ),
      _safeHomeTracked(
        _listPromosOrThrow(forMember: true),
        <Map<String, dynamic>>[],
      ),
      _safeHomeTracked(listOnlineOrders(phone), <Map<String, dynamic>>[]),
    ]);

    final content = results[0].value as Map<String, dynamic>?;
    final sales = results[1].value as List<Map<String, dynamic>>;
    final garansi = results[2].value as List<Map<String, dynamic>>;
    final bookings = results[3].value as List<Map<String, dynamic>>;
    final points = results[4].value as int;
    final promos = results[5].value as List<Map<String, dynamic>>;
    final onlineOrders = results[6].value as List<Map<String, dynamic>>;
    final fails = results.where((r) => !r.ok).length;

    String? toko = preferredTokoId?.trim();
    if (toko == null || toko.isEmpty) {
      for (final s in sales) {
        if (InvoiceHubService.sudahDiambil(s)) continue;
        final t = (s['toko_id'] ?? '').toString().trim();
        if (t.isNotEmpty) {
          toko = t;
          break;
        }
      }
      if ((toko == null || toko.isEmpty) && sales.isNotEmpty) {
        final t = (sales.first['toko_id'] ?? '').toString().trim();
        if (t.isNotEmpty) toko = t;
      }
    }

    return MemberHomeBundle(
      content: content,
      sales: sales,
      garansiCount: garansi.length,
      bookings: bookings,
      points: points,
      promos: promos,
      onlineOrders: onlineOrders,
      highlightToko: toko,
      partialError: fails > 0
          ? 'Sebagian data gagal dimuat. Tarik untuk coba lagi.'
          : null,
    );
  }

  Future<List<Map<String, dynamic>>> listPromos({bool forMember = true}) async {
    try {
      return await _listPromosOrThrow(forMember: forMember);
    } catch (_) {
      return const [];
    }
  }

  /// Versi ketat untuk Beranda — error naik ke [fetchHomeBundle].
  Future<List<Map<String, dynamic>>> _listPromosOrThrow({
    bool forMember = true,
  }) async {
    var q = _db.from('member_promos').select().eq('active', true);
    if (forMember) q = q.eq('show_on_member', true);
    final rows = await q.order('sort_order').order('created_at');
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((p) {
      final left = p['quantity_remaining'];
      if (left != null && (int.tryParse('$left') ?? 0) <= 0) return false;
      final untilRaw = p['valid_until'];
      if (untilRaw != null) {
        final until = DateTime.tryParse(untilRaw.toString());
        if (until != null) {
          final end = DateTime(until.year, until.month, until.day);
          if (end.isBefore(todayDate)) return false;
        }
      }
      return true;
    }).toList();
  }

  /// Inbox pemberitahuan pesanan (RPC `list_member_order_alerts`).
  Future<List<Map<String, dynamic>>> listOrderAlerts({
    required String phone,
    DateTime? after,
  }) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const [];
    try {
      final params = <String, dynamic>{'p_phone': digits};
      if (after != null) {
        params['p_after'] = after.toUtc().toIso8601String();
      }
      final res = await _db.rpc('list_member_order_alerts', params: params);
      if (res is List) {
        return res
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Lookup voucher. [channel]: `pos` | `online` | `member` | `any`.
  Future<Map<String, dynamic>> lookupPromo(
    String code, {
    String channel = 'pos',
  }) async {
    try {
      final res = await _db.rpc('lookup_member_promo', params: {
        'p_code': code.trim(),
        'p_channel': channel,
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return {'ok': false, 'error': 'Voucher tidak ditemukan'};
  }

  /// Redeem voucher: POS (`saleId`) atau Belanja Online (`onlineOrderId`).
  Future<Map<String, dynamic>> redeemPromo({
    required String code,
    String? saleId,
    String? onlineOrderId,
    String? phone,
    int discountApplied = 0,
    String channel = 'pos',
  }) async {
    final hasSale = (saleId ?? '').trim().isNotEmpty;
    final hasOnline = (onlineOrderId ?? '').trim().isNotEmpty;
    if (hasSale == hasOnline) {
      return {
        'ok': false,
        'error': 'Harus ada tepat satu: saleId atau onlineOrderId',
      };
    }
    try {
      final res = await _db.rpc('redeem_member_promo', params: {
        'p_code': code.trim(),
        'p_sale_id': hasSale ? saleId!.trim() : null,
        'p_phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
        'p_discount_applied': discountApplied,
        'p_online_order_id': hasOnline ? onlineOrderId!.trim() : null,
        'p_channel': channel,
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return {'ok': false, 'error': 'Redeem voucher gagal'};
  }

  /// Katalog identitas dari PUSAT; `available_qty` dari [tokoId] bila diisi
  /// (cabang fulfill Belanja Online), else PUSAT.
  Future<List<Map<String, dynamic>>> listCatalog({
    String? kategori,
    String? search,
    int limit = 120,
    String? tokoId,
  }) async {
    try {
      final toko = (tokoId ?? '').trim().toUpperCase();
      final res = await _db.rpc('list_member_catalog', params: {
        'p_kategori': (kategori == null || kategori.trim().isEmpty)
            ? null
            : kategori.trim(),
        'p_q': (search == null || search.trim().isEmpty) ? null : search.trim(),
        'p_limit': limit,
        if (toko.isNotEmpty && toko != 'PUSAT') 'p_toko': toko,
      });
      if (res is List) {
        return res.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final jual = int.tryParse('${m['harga'] ?? 0}') ?? 0;
          final asli = int.tryParse('${m['harga_asli'] ?? ''}');
          if (asli != null && asli > jual && jual > 0) {
            m['harga_asli'] = asli;
          } else {
            m.remove('harga_asli');
          }
          return m;
        }).toList();
      }
    } catch (_) {}
    // Fallback jika RPC belum di-deploy (butuh RLS authenticated).
    try {
      var filter = _db
          .from('products')
          .select(
            'id, sku, barcode, nama, kategori, sub_kategori, warna, '
            'jenis_lensa, harga, harga_jual, image_url, foto_url, '
            'stock, reserved_qty',
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
        final core = int.tryParse('${m['harga'] ?? 0}') ?? 0;
        final jual = int.tryParse('${m['harga_jual'] ?? m['harga'] ?? 0}') ?? 0;
        m['harga'] = jual > 0 ? jual : core;
        if (core > jual && jual > 0) {
          m['harga_asli'] = core;
        }
        m['image_url'] = (m['image_url']?.toString().trim().isNotEmpty == true)
            ? m['image_url']
            : m['foto_url'];
        final stock = int.tryParse('${m['stock'] ?? 0}') ?? 0;
        final reserved = int.tryParse('${m['reserved_qty'] ?? 0}') ?? 0;
        m['available_qty'] = stock > reserved ? stock - reserved : 0;
        return m;
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<int> pointsBalance(String memberId) async {
    final snap = await pointsSummary(memberId);
    return snap.rewardPoints;
  }

  /// Saldo tukar + Status Poin (untuk grade).
  Future<MemberPointsSnapshot> pointsSummary(String memberId) async {
    try {
      final res = await _db.rpc(
        'get_member_points_summary',
        params: {'p_member_id': memberId},
      );
      if (res is Map) {
        return MemberPointsSnapshot(
          rewardPoints: int.tryParse('${res['reward_points'] ?? 0}') ?? 0,
          statusPoints: int.tryParse('${res['status_points'] ?? 0}') ?? 0,
        );
      }
    } catch (_) {
      // Fallback: agregasi lokal bila RPC belum di-deploy.
    }
    try {
      final rows = await _db
          .from('member_points_ledger')
          .select('delta')
          .eq('member_id', memberId);
      var reward = 0;
      var status = 0;
      for (final r in (rows as List)) {
        final d = int.tryParse('${r['delta'] ?? 0}') ?? 0;
        reward += d;
        if (d > 0) status += d;
      }
      return MemberPointsSnapshot(
        rewardPoints: reward,
        statusPoints: status,
      );
    } catch (_) {
      return const MemberPointsSnapshot(rewardPoints: 0, statusPoints: 0);
    }
  }

  Future<List<Map<String, dynamic>>> pointsLedger(
    String memberId, {
    int limit = 40,
  }) async {
    try {
      final rows = await _db
          .from('member_points_ledger')
          .select('id, delta, reason, sale_id, meta, created_at')
          .eq('member_id', memberId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
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

  Future<String> uploadClaimPhoto({
    required String phone,
    required Uint8List bytes,
    String ext = 'jpg',
  }) async {
    final safePhone = normalizeWaNumber(phone).replaceAll(RegExp(r'[^\d+]'), '');
    final path =
        'klaim/$safePhone/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    await _db.storage.from('member-claim-photos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return _db.storage.from('member-claim-photos').getPublicUrl(path);
  }

  Future<void> submitClaimRequest({
    required String phone,
    required String kartuId,
    required String tokoId,
    required String alasan,
    required DateTime jadwalKunjungan,
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
      'jadwal_kunjungan': jadwalKunjungan.toUtc().toIso8601String(),
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
      final s = await InvoiceSettingsService(client: _db).fetchForToko(tokoId);
      return {
        'toko_id': s.tokoId,
        'shop_name': s.shopName,
        'address': s.address,
        'phone': s.phone,
        'google_review_url':
            s.googleReviewUrl.isEmpty ? null : s.googleReviewUrl,
      };
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listOnlineStores() async {
    List<Map<String, dynamic>> stores = const [];
    try {
      dynamic res = await _db.rpc('list_online_selling_stores');
      // RPC returns jsonb — kadang List, kadang String JSON.
      if (res is String) {
        res = jsonDecode(res);
      }
      if (res is List) {
        stores = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    // Lengkapi lat/lng + alamat toko dari master.
    try {
      final geoRows =
          await _db.from('toko_id').select('id, latitude, longitude');
      final byId = <String, Map<String, dynamic>>{};
      for (final raw in (geoRows as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['id'] ?? '').toString().trim().toUpperCase();
        if (id.isNotEmpty) byId[id] = m;
      }

      final addrById = <String, String>{};
      try {
        final inv = await _db
            .from('invoice_settings')
            .select('toko_id, shop_name, address');
        for (final raw in (inv as List)) {
          final m = Map<String, dynamic>.from(raw as Map);
          final id = (m['toko_id'] ?? '').toString().trim().toUpperCase();
          if (id.isEmpty) continue;
          final addr = (m['address'] ?? '').toString().trim();
          final name = (m['shop_name'] ?? '').toString().trim();
          if (addr.isNotEmpty) addrById[id] = addr;
          if (name.isNotEmpty) {
            for (final s in stores) {
              if ((s['toko_id'] ?? '').toString().trim().toUpperCase() == id) {
                s['shop_name'] = name;
              }
            }
          }
        }
      } catch (_) {}

      for (final s in stores) {
        final id = (s['toko_id'] ?? '').toString().trim().toUpperCase();
        final geo = byId[id];
        if (geo != null) {
          final lat = (s['latitude'] as num?)?.toDouble();
          final lng = (s['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null || (lat == 0 && lng == 0)) {
            s['latitude'] = geo['latitude'];
            s['longitude'] = geo['longitude'];
          }
        }
        if (addrById[id] != null) {
          s['shop_address'] = addrById[id];
        }
      }

      // Cabang tanpa lat/lng di DB → geocode dari alamat invoice (OSM).
      for (final s in stores) {
        final lat = (s['latitude'] as num?)?.toDouble();
        final lng = (s['longitude'] as num?)?.toDouble();
        final hasGeo = lat != null &&
            lng != null &&
            !(lat == 0 && lng == 0);
        if (hasGeo) continue;
        final addr = (s['shop_address'] ?? '').toString().trim();
        if (addr.length < 8) continue;
        try {
          final hits = await OsmAddressSearch.search(addr, limit: 1);
          if (hits.isEmpty) continue;
          s['latitude'] = hits.first.lat;
          s['longitude'] = hits.first.lng;
          s['geo_source'] = 'geocode_shop_address';
        } catch (e) {
          debugPrint('geocode store ${s['toko_id']}: $e');
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    } catch (_) {}

    return stores;
  }

  Future<Map<String, dynamic>> quoteDelivery({
    required String tokoId,
    required String courier,
  }) async {
    try {
      final res = await _db.rpc('quote_online_delivery', params: {
        'p_toko_id': tokoId,
        'p_courier': courier,
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return {'ok': false, 'error': 'Gagal hitung ongkir'};
  }

  /// Ongkir real via Edge Function → Biteship Rates API (tanpa flat fee).
  Future<Map<String, dynamic>> quoteDeliveryBiteship({
    required String tokoId,
    required String courier,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    int orderValue = 100000,
    int weightGrams = 500,
  }) async {
    try {
      final res = await _db.functions.invoke(
        'biteship-rates',
        body: {
          'origin_lat': originLat,
          'origin_lng': originLng,
          'destination_lat': destinationLat,
          'destination_lng': destinationLng,
          'courier': courier,
          'order_value': orderValue,
          'weight': weightGrams,
        },
      );
      if (res.data is Map) {
        final m = Map<String, dynamic>.from(res.data as Map);
        if (m['ok'] == true) {
          return {...m, 'source': 'biteship'};
        }
        return {
          'ok': false,
          'error': m['error']?.toString() ?? 'Biteship gagal hitung ongkir',
          'source': 'biteship',
        };
      }
      return {
        'ok': false,
        'error': 'Biteship HTTP ${res.status}',
        'source': 'biteship',
      };
    } catch (e) {
      debugPrint('biteship-rates invoke: $e');
      return {'ok': false, 'error': '$e', 'source': 'biteship'};
    }
  }

  /// Kurir yang diminta ke Biteship (tanpa Borzo / on-demand lain).
  static const _biteshipAllCouriers =
      'grab,gojek,jne,tiki,sicepat,jnt,anteraja,idexpress,ninja,lion,'
      'wahana,pos,sap,rpx';

  static const _categoryOrder = [
    'instant',
    'sameday',
    'nextday',
    'regular',
  ];

  static const _categoryTitles = {
    'instant': 'Instant',
    'sameday': 'Same Day',
    'nextday': 'Next Day',
    'regular': 'Reguler',
  };

  /// OBR (anak toko) hanya Instant / Same Day / Next Day — bukan Reguler.
  static const _obrCategories = {'instant', 'sameday', 'nextday'};

  static const _instantSameDayCompanies = {'grab', 'gojek'};

  /// Jangkauan OBR: max 10 km; belanja > Rp 1 jt → sampai 15 km.
  static const obrMaxKmDefault = 10.0;
  static const obrMaxKmHighValue = 15.0;
  static const obrHighValueThreshold = 1000000;
  static const obrPriceDiscount = 2000;

  /// Batas km OBR menurut nilai belanja (subtotal barang).
  static double obrMaxKmForOrderValue(int orderValue) {
    return orderValue > obrHighValueThreshold
        ? obrMaxKmHighValue
        : obrMaxKmDefault;
  }

  static bool isObrDistanceEligible({
    required double distanceMeters,
    required int orderValue,
  }) {
    if (distanceMeters < 0 || !distanceMeters.isFinite) return false;
    final maxM = obrMaxKmForOrderValue(orderValue) * 1000;
    return distanceMeters <= maxM + 0.5; // toleransi GPS kecil
  }

  /// Kategori OBR yang dinyalakan cabang.
  /// - [store] null → kosong (jangan tampilkan OBR sebelum cabang diketahui).
  /// - flag absen di map → dianggap ON (aman sebelum migrasi).
  static Set<String> obrCategoriesFromStore(Map<String, dynamic>? store) {
    if (store == null) return {};
    return {
      if (store['obr_instant_enabled'] != false) 'instant',
      if (store['obr_sameday_enabled'] != false) 'sameday',
      if (store['obr_nextday_enabled'] != false) 'nextday',
    };
  }

  static String classifyShippingCategory({
    required String serviceName,
    required String serviceCode,
    required String description,
    required String duration,
  }) {
    final t =
        '$serviceName $serviceCode $description $duration'.toLowerCase();
    if (t.contains('instant') ||
        t.contains('on demand') ||
        t.contains('same hour') ||
        t.contains('instant_car') ||
        t.contains('instant_bike')) {
      return 'instant';
    }
    if (t.contains('same_day') ||
        t.contains('sameday') ||
        t.contains('same day') ||
        t.contains(' sds') ||
        t.endsWith('sds') ||
        serviceCode.toLowerCase() == 'smd' ||
        serviceCode.toLowerCase() == 'sdp') {
      return 'sameday';
    }
    if (t.contains('next_day') ||
        t.contains('nextday') ||
        t.contains('next day') ||
        t.contains('overnight') ||
        t.contains('besok') ||
        t.contains('one night') ||
        RegExp(r'\byes\b').hasMatch(t) ||
        RegExp(r'\bbest\b').hasMatch(t) ||
        serviceCode.toLowerCase() == 'ons' ||
        serviceCode.toLowerCase() == 'ndp' ||
        serviceCode.toLowerCase() == 'ods') {
      return 'nextday';
    }
    // Sisanya kandidat Reguler (≥2 hari) — dicek lewat ETA.
    return 'regular';
  }

  /// ETA hari dari teks Biteship. "1 - 2 days" → min=1, max=2 (bukan cuma 1).
  static ({int? min, int? max}) parseDeliveryDayRange({
    required String duration,
    String durationRange = '',
    String durationUnit = '',
  }) {
    final unit = durationUnit.toLowerCase().trim();
    final text = '$durationRange $duration $unit'.toLowerCase().trim();
    if (text.isEmpty) return (min: null, max: null);

    if (unit.contains('hour') ||
        text.contains('hour') ||
        text.contains('jam')) {
      return (min: 0, max: 0);
    }

    final nums = RegExp(r'(\d+)')
        .allMatches(text)
        .map((m) => int.tryParse(m.group(1)!) ?? 0)
        .where((n) => n > 0)
        .toList();
    if (nums.isEmpty) return (min: null, max: null);

    final a = nums.first;
    final b = nums.length >= 2 ? nums[1] : a;
    final minD = a < b ? a : b;
    final maxD = a < b ? b : a;
    return (min: minD, max: maxD);
  }

  /// ETA minimum (kompatibel pemanggil lama).
  static int? parseMinDeliveryDays({
    required String duration,
    String durationRange = '',
    String durationUnit = '',
  }) =>
      parseDeliveryDayRange(
        duration: duration,
        durationRange: durationRange,
        durationUnit: durationUnit,
      ).min;

  static bool _looksLikeNamedRegular(String serviceCode, String serviceName) {
    final t = '$serviceCode $serviceName'.toLowerCase();
    return t.contains('reg') ||
        t.contains('ez') ||
        t.contains('standard') ||
        t.contains('reguler') ||
        t.contains('regular') ||
        t.contains('normal') ||
        t.contains('land_pack') ||
        t.contains('reg_pack');
  }

  /// Barang jadi (siap kirim): 5–7 hari sejak order.
  static const orderReadyMinDays = 5;
  static const orderReadyMaxDays = 7;

  /// Reguler: dikirim 2 hari setelah barang jadi.
  static const regularShipAfterReadyDays = 2;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String formatEtaDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  static String _rangeLabel(DateTime start, DateTime end) => start == end
      ? formatEtaDate(start)
      : '${formatEtaDate(start)} – ${formatEtaDate(end)}';

  /// Estimasi tiba dihitung dari tanggal **barang jadi** (5–7 hari), lalu + kurir:
  /// Instant = kirim saat jadi · Same Day = hari jadi · Next Day = +1 · Reguler = +2.
  static Map<String, dynamic> estimateArrivalDates({
    required String category,
    DateTime? from,
  }) {
    final today = _dateOnly(from ?? DateTime.now());
    final readyStart = today.add(const Duration(days: orderReadyMinDays));
    final readyEnd = today.add(const Duration(days: orderReadyMaxDays));
    final readyLabel = _rangeLabel(readyStart, readyEnd);

    late final DateTime start;
    late final DateTime end;
    late final String shortLabel;
    late final String relativeNote;

    switch (category) {
      case 'instant':
        // Langsung kirim saat barang jadi.
        start = readyStart;
        end = readyEnd;
        relativeNote = 'kirim saat barang jadi';
        shortLabel = '$readyLabel ($relativeNote)';
        break;
      case 'sameday':
        // Di hari yang sama saat barang jadi.
        start = readyStart;
        end = readyEnd;
        relativeNote = 'hari barang jadi';
        shortLabel = '$readyLabel ($relativeNote)';
        break;
      case 'nextday':
        // Besok setelah barang jadi.
        start = readyStart.add(const Duration(days: 1));
        end = readyEnd.add(const Duration(days: 1));
        relativeNote = 'besok setelah barang jadi';
        shortLabel = '${_rangeLabel(start, end)} ($relativeNote)';
        break;
      case 'regular':
      default:
        // 2 hari setelah barang jadi.
        start = readyStart.add(
          const Duration(days: regularShipAfterReadyDays),
        );
        end = readyEnd.add(const Duration(days: regularShipAfterReadyDays));
        relativeNote = '+$regularShipAfterReadyDays hari setelah barang jadi';
        shortLabel = '${_rangeLabel(start, end)} ($relativeNote)';
        break;
    }

    return {
      'ready_from': readyStart.toIso8601String(),
      'ready_to': readyEnd.toIso8601String(),
      'ready_label': readyLabel,
      'ready_note':
          'Barang jadi $readyLabel ($orderReadyMinDays–$orderReadyMaxDays hari)',
      'eta_from': start.toIso8601String(),
      'eta_to': end.toIso8601String(),
      'eta_date_label': _rangeLabel(start, end),
      'eta_relative': relativeNote,
      'eta_label': 'Estimasi tiba ${_rangeLabel(start, end)} · $relativeNote',
      'eta_short': shortLabel,
      'eta_min_days': start.difference(today).inDays,
      'eta_max_days': end.difference(today).inDays,
    };
  }

  static String _companyKey(String company) =>
      company.trim().toLowerCase().replaceAll(' ', '');

  /// Reguler: max 5 ekspedisi termurah (≥2 hari), 1/perusahaan, harga unik.
  static List<Map<String, dynamic>> _pickRegularTop5Distinct(
    List<Map<String, dynamic>> list,
  ) {
    final eligible = list.where((o) {
      final maxDays = int.tryParse('${o['max_days']}');
      final minDays = int.tryParse('${o['min_days']}');
      // Pakai max range: "1-2 hari" tetap reguler; "1 hari" saja bukan.
      if (maxDays != null && maxDays < 2) return false;
      if (maxDays == null && minDays != null && minDays < 2) return false;
      return true;
    }).toList();

    eligible.sort((a, b) {
      final pa = int.tryParse('${a['price']}') ?? 0;
      final pb = int.tryParse('${b['price']}') ?? 0;
      return pa.compareTo(pb);
    });

    final picked = <Map<String, dynamic>>[];
    final usedCompanies = <String>{};
    final usedPrices = <int>{};

    for (final o in eligible) {
      if (picked.length >= 5) break;
      final company = _companyKey('${o['company'] ?? ''}');
      final price = int.tryParse('${o['price']}') ?? 0;
      if (company.isEmpty || price <= 0) continue;
      if (usedCompanies.contains(company)) continue;
      if (usedPrices.contains(price)) continue;
      usedCompanies.add(company);
      usedPrices.add(price);
      picked.add(o);
    }
    return picked;
  }

  static String mapCompanyToCourierKey(String company) {
    final c = company.toLowerCase();
    if (c.contains('grab')) return 'grab';
    if (c.contains('gojek') || c.contains('gosend')) return 'gojek';
    if (c.startsWith('obr')) return 'obr';
    return 'other';
  }

  /// Ongkir Biteship dikelompokkan ala Shopee + OBR (instant/sameday/nextday).
  ///
  /// OBR (anak toko) hanya muncul bila [distanceMeters] dalam jangkauan
  /// dan kategori di [obrEnabledCategories] aktif (dari pengaturan cabang).
  Future<Map<String, dynamic>> quoteCourierFeeTable({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    int orderValue = 100000,
    int weightGrams = 500,
    double? distanceMeters,
    Set<String>? obrEnabledCategories,
  }) async {
    final fees = <String, int>{};
    final labels = <String, String>{};
    final obrMaxKm = obrMaxKmForOrderValue(orderValue);
    final obrCats = obrEnabledCategories ?? {..._obrCategories};
    final obrEligible = obrCats.isNotEmpty &&
        distanceMeters != null &&
        isObrDistanceEligible(
          distanceMeters: distanceMeters,
          orderValue: orderValue,
        );

    if (originLat == 0 && originLng == 0) {
      return {
        'ok': false,
        'error': 'Koordinat cabang belum ada',
        'source': 'biteship',
        'fees': fees,
        'groups': <Map<String, dynamic>>[],
        'obr_eligible': false,
        'obr_max_km': obrMaxKm,
        'distance_m': distanceMeters,
      };
    }

    try {
      final res = await _db.functions.invoke(
        'biteship-rates',
        body: {
          'origin_lat': originLat,
          'origin_lng': originLng,
          'destination_lat': destinationLat,
          'destination_lng': destinationLng,
          'couriers': _biteshipAllCouriers,
          'order_value': orderValue,
          'weight': weightGrams,
        },
      );
      if (res.data is! Map) {
        return {
          'ok': false,
          'error': 'Respons Biteship tidak valid (HTTP ${res.status})',
          'source': 'biteship',
          'fees': fees,
          'groups': <Map<String, dynamic>>[],
          'obr_eligible': obrEligible,
          'obr_max_km': obrMaxKm,
          'distance_m': distanceMeters,
        };
      }
      final m = Map<String, dynamic>.from(res.data as Map);
      if (m['ok'] != true) {
        return {
          'ok': false,
          'error': m['error']?.toString() ?? 'Biteship gagal',
          'source': 'biteship',
          'fees': fees,
          'biteship': m['biteship'],
          'groups': <Map<String, dynamic>>[],
          'obr_eligible': obrEligible,
          'obr_max_km': obrMaxKm,
          'distance_m': distanceMeters,
        };
      }

      final byCat = <String, List<Map<String, dynamic>>>{};
      for (final cat in _categoryOrder) {
        byCat[cat] = [];
      }

      final options = (m['options'] as List?) ?? const [];
      for (final raw in options) {
        if (raw is! Map) continue;
        final o = Map<String, dynamic>.from(raw);
        final company = (o['company'] ?? o['courier_code'] ?? '').toString();
        final companyKey = _companyKey(company);
        if (companyKey == 'borzo') continue;

        final courierName =
            (o['courier_name'] ?? company).toString().trim();
        final service = (o['courier_service_name'] ?? o['description'] ?? '')
            .toString()
            .trim();
        final serviceCode =
            (o['courier_service_code'] ?? '').toString().trim();
        final duration = (o['duration'] ?? '').toString().trim();
        final durationRange =
            (o['shipment_duration_range'] ?? '').toString().trim();
        final durationUnit =
            (o['shipment_duration_unit'] ?? '').toString().trim();
        final price = int.tryParse('${o['price'] ?? 0}') ?? 0;
        if (price <= 0 || company.isEmpty) continue;

        var category = classifyShippingCategory(
          serviceName: service,
          serviceCode: serviceCode,
          description: (o['description'] ?? '').toString(),
          duration: duration,
        );
        final dayRange = parseDeliveryDayRange(
          duration: duration,
          durationRange: durationRange,
          durationUnit: durationUnit,
        );
        final minDays = dayRange.min;
        final maxDays = dayRange.max;

        // Jangan campur Reguler ↔ Next Day:
        // - "1 - 2 days" REG → Reguler (lihat max ≥ 2)
        // - tepat 1 hari saja → Next Day
        // - layanan bernama BEST/YES/next day tetap Next Day
        if (category == 'regular') {
          if (maxDays != null) {
            if (maxDays <= 0) continue; // jam
            if (maxDays <= 1) {
              category = 'nextday';
            }
            // maxDays >= 2 → tetap regular (meski min = 1)
          } else if (minDays == 1 &&
              !_looksLikeNamedRegular(serviceCode, service)) {
            category = 'nextday';
          }
        }
        // Jangan pindah Next Day → Reguler hanya karena ETA 2+ hari
        // (BEST/YES tetap di Next Day).

        if (!_categoryOrder.contains(category)) continue;

        // Instant & Same Day: hanya Grab + Gojek.
        if ((category == 'instant' || category == 'sameday') &&
            !_instantSameDayCompanies.contains(companyKey)) {
          continue;
        }

        // Reguler: ETA max harus ≥ 2 hari bila diketahui.
        if (category == 'regular' && maxDays != null && maxDays < 2) {
          continue;
        }

        final courierKey = mapCompanyToCourierKey(company);
        final id =
            '${courierKey}_${category}_${companyKey}_${serviceCode}_$price';

        final eta = estimateArrivalDates(category: category);
        final etaShort = (eta['eta_short'] ?? '').toString();

        final option = <String, dynamic>{
          'id': id,
          'category': category,
          'courier': courierKey,
          'company': company,
          'courier_name': courierName.isEmpty ? company : courierName,
          'courier_service_name': service,
          'courier_service_code': serviceCode,
          'biteship_company': company,
          'biteship_service_code': serviceCode,
          'duration': duration,
          'min_days': minDays,
          'max_days': maxDays,
          'price': price,
          'is_obr': false,
          'label': courierName.isEmpty ? company : courierName,
          ...eta,
          'subtitle': [
            if (service.isNotEmpty) service,
            if (etaShort.isNotEmpty) etaShort,
          ].join(' · '),
        };
        byCat.putIfAbsent(category, () => []).add(option);
      }

      // Reguler: 5 ekspedisi termurah (≥2 hari), harga beda, 1 per merek.
      byCat['regular'] = _pickRegularTop5Distinct(byCat['regular'] ?? []);

      // OBR = anak toko antar (Instant / Same Day / Next Day).
      // Hanya dalam jangkauan km; di luar itu Member hanya lihat Biteship.
      if (obrEligible) {
        const discount = obrPriceDiscount;
        final distM = distanceMeters;
        final kmLabel = '${(distM / 1000).toStringAsFixed(1)} km';
        for (final cat in _obrCategories) {
          if (!obrCats.contains(cat)) continue;
          final list = byCat[cat] ?? const [];
          if (list.isEmpty) continue;
          var minPrice = 0;
          for (final o in list) {
            final p = int.tryParse('${o['price']}') ?? 0;
            if (p <= 0) continue;
            if (minPrice == 0 || p < minPrice) minPrice = p;
          }
          if (minPrice <= 0) continue;
          final obrPrice = minPrice > discount ? minPrice - discount : 0;
          final obrId = 'obr_$cat';
          final eta = estimateArrivalDates(category: cat);
          final etaShort = (eta['eta_short'] ?? '').toString();
          final obrOption = <String, dynamic>{
            'id': obrId,
            'category': cat,
            'courier': 'obr',
            'company': 'obr',
            'courier_name': 'OBR Delivery',
            'courier_service_name': _categoryTitles[cat] ?? cat,
            'courier_service_code': cat,
            // Anak toko — jangan panggil Biteship.
            'biteship_company': '',
            'biteship_service_code': '',
            'duration': '',
            'price': obrPrice,
            'is_obr': true,
            'staff_delivery': true,
            'biteship_min': minPrice,
            'label': 'OBR Delivery',
            'distance_m': distM,
            'obr_max_km': obrMaxKm,
            ...eta,
            'subtitle':
                'Anak toko · hemat Rp 2.000 · $kmLabel'
                '${etaShort.isNotEmpty ? ' · $etaShort' : ''}',
          };
          byCat[cat] = [obrOption, ...list];
          fees[obrId] = obrPrice;
          labels[obrId] = obrOption['subtitle'] as String;
        }
      }

      // Sort tiap kategori: OBR dulu, lalu harga naik.
      final groups = <Map<String, dynamic>>[];
      for (final cat in _categoryOrder) {
        final list = byCat[cat] ?? [];
        if (list.isEmpty) continue;
        list.sort((a, b) {
          final ao = a['is_obr'] == true ? 0 : 1;
          final bo = b['is_obr'] == true ? 0 : 1;
          if (ao != bo) return ao.compareTo(bo);
          final pa = int.tryParse('${a['price']}') ?? 0;
          final pb = int.tryParse('${b['price']}') ?? 0;
          return pa.compareTo(pb);
        });
        for (final o in list) {
          final id = o['id'].toString();
          fees[id] = int.tryParse('${o['price']}') ?? 0;
          labels[id] = (o['subtitle'] ?? '').toString();
        }
        groups.add({
          'category': cat,
          'title': _categoryTitles[cat] ?? cat,
          'options': list,
        });
      }

      return {
        'ok': groups.isNotEmpty,
        'source': 'biteship',
        'fees': fees,
        'labels': labels,
        'groups': groups,
        'obr_eligible': obrEligible,
        'obr_max_km': obrMaxKm,
        'distance_m': distanceMeters,
        'error': groups.isEmpty
            ? 'Tidak ada tarif kurir untuk rute ini'
            : null,
      };
    } catch (e) {
      debugPrint('quoteCourierFeeTable biteship: $e');
      return {
        'ok': false,
        'error': '$e',
        'source': 'biteship',
        'fees': fees,
        'groups': <Map<String, dynamic>>[],
        'obr_eligible': obrEligible,
        'obr_max_km': obrMaxKm,
        'distance_m': distanceMeters,
      };
    }
  }

  Future<List<Map<String, dynamic>>> listBranchSellable({
    required String tokoId,
    List<String>? skus,
  }) async {
    try {
      final res = await _db.rpc('list_branch_sellable', params: {
        'p_toko_id': tokoId,
        'p_skus': skus,
      });
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Buat order + Snap Midtrans via Edge Function.
  Future<Map<String, dynamic>> createOnlineCheckout({
    required String phone,
    String? memberId,
    String? customerName,
    required String tokoId,
    required String fulfillment,
    String? courier,
    String? addressText,
    double? addressLat,
    double? addressLng,
    int? shippingFee,
    String? courierCompany,
    String? courierServiceCode,
    String? courierServiceName,
    String? shippingCategory,
    bool isObr = false,
    int shippingVoucherDiscount = 0,
    String? productPromoCode,
    int productPromoDiscount = 0,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final res = await _db.functions.invoke(
        'online-checkout-create',
        body: {
          'phone': phone,
          'member_id': memberId,
          'customer_name': customerName,
          'toko_id': tokoId,
          'fulfillment': fulfillment,
          'courier': courier,
          'address_text': addressText,
          'address_lat': addressLat,
          'address_lng': addressLng,
          'shipping_fee': shippingFee,
          'courier_company': courierCompany,
          'courier_service_code': courierServiceCode,
          'courier_service_name': courierServiceName,
          'shipping_category': shippingCategory,
          'is_obr': isObr,
          'shipping_voucher_discount': shippingVoucherDiscount,
          'product_promo_code': productPromoCode,
          'product_promo_discount': productPromoDiscount,
          'items': items,
        },
      );
      final data = res.data;
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        // Jangan anggap sukses bila Edge mengembalikan ok:false.
        if (m['ok'] == false) return m;
        return m;
      }
      return {'ok': false, 'error': 'Respons checkout tidak valid'};
    } catch (e) {
      // Release: jangan buat order+hold lewat RPC (hindari bayar uji / double hold).
      if (kReleaseMode) {
        return {
          'ok': false,
          'error':
              'Checkout gagal (Edge Midtrans). Coba lagi atau hubungi toko. ($e)',
        };
      }
      // Debug only: RPC + DEV snap bila Edge belum deploy.
      try {
        final created = await _db.rpc('create_online_order', params: {
          'p_phone': phone,
          'p_member_id': memberId,
          'p_customer_name': customerName,
          'p_toko_id': tokoId,
          'p_fulfillment': fulfillment,
          'p_courier': courier,
          'p_address_text': addressText,
          'p_address_lat': addressLat,
          'p_address_lng': addressLng,
          'p_items': items,
          'p_shipping_fee': shippingFee,
          'p_courier_company': courierCompany,
          'p_courier_service_code': courierServiceCode,
          'p_courier_service_name': courierServiceName,
          'p_shipping_category': shippingCategory,
          'p_is_obr': isObr,
          'p_shipping_voucher_discount': shippingVoucherDiscount,
          'p_product_promo_code': productPromoCode,
          'p_product_promo_discount': productPromoDiscount,
        });
        if (created is Map) {
          final m = Map<String, dynamic>.from(created);
          if (m['ok'] != true) return m;
          final oid = m['online_order_id'];
          if (oid != null) {
            try {
              await _db.rpc('attach_online_order_snap', params: {
                'p_online_order_id': oid,
                'p_snap_token': 'DEV_NO_EDGE',
                'p_redirect_url': '',
              });
            } catch (_) {}
          }
          return {
            ...m,
            'mock_payment': true,
            'snap_token': 'DEV_NO_EDGE',
            'message':
                'DEBUG: Edge belum tersedia. Pakai Bayar uji (token DEV_*).',
          };
        }
      } catch (e2) {
        return {'ok': false, 'error': '$e | fallback: $e2'};
      }
      return {'ok': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> getOnlineOrder({
    required String phone,
    required String onlineOrderId,
  }) async {
    try {
      final res = await _db.rpc('get_online_order_for_member', params: {
        'p_phone': phone,
        'p_online_order_id': onlineOrderId,
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return {'ok': false, 'error': 'Order tidak ditemukan'};
  }

  /// Daftar `online_orders` Member (termasuk pending bayar). RPC expire 15m dulu.
  Future<List<Map<String, dynamic>>> listOnlineOrders(String phone) async {
    try {
      final res = await _db.rpc('list_member_online_orders', params: {
        'p_phone': phone.trim(),
      });
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      if (res is Map && res['orders'] is List) {
        return (res['orders'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      debugPrint('listOnlineOrders rpc: $e');
    }

    // Fallback: expire server dulu, lalu soft-mark UI dari expires_at (15 menit).
    try {
      try {
        await _db.rpc('expire_all_stale_stock_holds');
      } catch (_) {
        try {
          await _db.rpc('expire_stale_online_orders');
        } catch (_) {}
      }
      final digits = normalizeWaNumber(phone);
      if (digits.isEmpty) return const [];
      final alt = digits.startsWith('62') ? '0${digits.substring(2)}' : digits;
      final rows = await _db
          .from('online_orders')
          .select()
          .or('phone_e164.eq.$digits,phone_e164.eq.$alt')
          .order('created_at', ascending: false)
          .limit(40);
      final now = DateTime.now().toUtc();
      final out = <Map<String, dynamic>>[];
      for (final raw in (rows as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final st = (m['status'] ?? '').toString();
        final exp = DateTime.tryParse('${m['expires_at'] ?? ''}');
        final created = DateTime.tryParse('${m['created_at']}');
        final deadline = exp?.toUtc() ??
            created?.toUtc().add(const Duration(minutes: 15));
        if (st == 'pending_payment' &&
            deadline != null &&
            deadline.isBefore(now)) {
          m['status'] = 'expired';
        }
        out.add(m);
      }
      return out;
    } catch (e) {
      debugPrint('listOnlineOrders fallback: $e');
      return const [];
    }
  }

  /// Member batalkan pending sendiri → lepas ONLINE_HOLD.
  Future<Map<String, dynamic>> cancelPendingOnlineOrder({
    required String phone,
    required String onlineOrderId,
    String reason = 'member_cancel',
  }) async {
    try {
      final res = await _db.rpc(
        'cancel_pending_online_order_for_member',
        params: {
          'p_phone': phone.trim(),
          'p_online_order_id': onlineOrderId,
          'p_reason': reason,
        },
      );
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return {'ok': false, 'error': 'Gagal batalkan pesanan'};
  }

  /// Dev / tanpa Midtrans: lunasi via RPC khusus DEV_*.
  Future<Map<String, dynamic>> mockPayOnlineOrder(String midtransOrderId) async {
    try {
      final res = await _db.rpc('dev_fulfill_online_order', params: {
        'p_midtrans_order_id': midtransOrderId,
      });
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return {'ok': false, 'error': 'Gagal bayar uji'};
  }
}
