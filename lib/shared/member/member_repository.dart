import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../whatsapp_launcher.dart';
import 'member_points_grade.dart';
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
            'qr_dp_token, qr_lunas_token, qr_claim_token',
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
        final core = int.tryParse('${m['harga'] ?? 0}') ?? 0;
        final jual = int.tryParse('${m['harga_jual'] ?? m['harga'] ?? 0}') ?? 0;
        m['harga'] = jual > 0 ? jual : core;
        if (core > jual && jual > 0) {
          m['harga_asli'] = core;
        }
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

  Future<List<Map<String, dynamic>>> listOnlineStores() async {
    try {
      final res = await _db.rpc('list_online_selling_stores');
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return const [];
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
          'items': items,
        },
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'ok': false, 'error': 'Respons checkout tidak valid'};
    } catch (e) {
      // Fallback: RPC tanpa Snap (dev) bila Edge belum deploy
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
        });
        if (created is Map) {
          final m = Map<String, dynamic>.from(created);
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
                'Edge Midtrans belum tersedia. Pakai Bayar uji setelah RPC OK.',
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
