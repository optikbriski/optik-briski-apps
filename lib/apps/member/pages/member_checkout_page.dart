import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/logistics/stock_realtime.dart';
import '../../../shared/maps/osm_address_search.dart';
import '../../../shared/member/member_cart.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/member/member_shop_address.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_midtrans_pay_page.dart';
import 'member_online_order_page.dart';
import 'member_orders_list_page.dart';

/// Jarak alamat vs GPS saat ini yang memicu konfirmasi (meter).
const _kFarAddressConfirmMeters = 5000.0;

class MemberCheckoutPage extends StatefulWidget {
  const MemberCheckoutPage({
    super.key,
    this.presetTokoId,
    this.presetFulfillment,
    this.presetCourier,
    this.presetShippingFee,
    this.presetCourierCompany,
    this.presetCourierServiceCode,
    this.presetCourierServiceName,
    this.presetShippingCategory,
    this.presetIsObr = false,
    this.presetShippingVoucherDiscount,
    this.presetProductPromoCode,
    this.presetProductPromoDiscount,
    this.useShopAddress = false,
  });

  /// Prefill dari Detail Pesanan Belanja Online.
  final String? presetTokoId;
  final String? presetFulfillment;
  final String? presetCourier;
  final int? presetShippingFee;
  final String? presetCourierCompany;
  final String? presetCourierServiceCode;
  final String? presetCourierServiceName;
  final String? presetShippingCategory;
  final bool presetIsObr;
  final int? presetShippingVoucherDiscount;
  final String? presetProductPromoCode;
  final int? presetProductPromoDiscount;

  /// true = alamat/cabang dari MemberShopAddress (tanpa UI Maps ulang).
  final bool useShopAddress;

  @override
  State<MemberCheckoutPage> createState() => _MemberCheckoutPageState();
}

class _MemberCheckoutPageState extends State<MemberCheckoutPage> {
  final _repo = MemberRepository();
  final _cart = MemberCart.instance;
  final _search = TextEditingController();
  final _detail = TextEditingController();
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final _mapCtrl = MapController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _stores = const [];
  List<OsmAddressHit> _hits = const [];
  String? _tokoId;
  String _fulfillment = 'pickup';
  String _courier = 'obr';
  int _shippingFee = 0;
  bool _loading = true;
  bool _paying = false;
  bool _resolvingStore = false;
  bool _searching = false;
  bool _mapsVerified = false;
  /// true jika user sengaja ganti cabang (bukan saran terdekat).
  /// Reset ke false setiap alamat Maps diganti / dikonfirmasi ulang.
  bool _storeUserOverride = false;
  String? _error;
  String? _storeHint;
  String? _verifiedLabel;
  double? _addressLat;
  double? _addressLng;
  double? _gpsDistanceM;
  List<String> _preorderSkus = const [];
  /// SKU yang sudah dikonfirmasi pre-order (hindari popup berulang).
  final Set<String> _acceptedPreorderSkus = {};
  StockRealtimeSubscription? _stockRt;
  Timer? _stockRtDebounce;
  String? _stockRtToko;
  bool _shortageDialogOpen = false;

  /// Alamat yang dikirim ke order: hasil Maps + catatan opsional.
  String get _fullAddress {
    if (widget.useShopAddress) {
      final a = MemberShopAddress.instance.active;
      if (a == null) return '';
      final base = a.displayName.trim();
      final extra = a.detail.trim().isNotEmpty
          ? a.detail.trim()
          : a.note.trim();
      final typed = _detail.text.trim();
      final note = typed.isNotEmpty ? typed : extra;
      if (base.isEmpty) return note;
      if (note.isEmpty) return base;
      return '$base\nCatatan: $note';
    }
    final base = (_verifiedLabel ?? '').trim();
    final note = _detail.text.trim();
    if (base.isEmpty) return note;
    if (note.isEmpty) return base;
    return '$base\nCatatan: $note';
  }

  bool get _hasVerifiedCoords =>
      _mapsVerified && _addressLat != null && _addressLng != null;

  @override
  void initState() {
    super.initState();
    final profileAlamat = (MemberSession.instance.alamat ?? '').trim();
    if (profileAlamat.isNotEmpty) {
      _search.text = profileAlamat;
    }
    _boot();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _stockRtDebounce?.cancel();
    unawaited(_stockRt?.dispose() ?? Future.value());
    _search.dispose();
    _detail.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _bindStockRealtime(String? tokoId) {
    final tid = (tokoId ?? '').trim().toUpperCase();
    if (tid.isEmpty) {
      unawaited(_stockRt?.dispose() ?? Future.value());
      _stockRt = null;
      _stockRtToko = null;
      return;
    }
    if (_stockRtToko == tid && _stockRt != null) return;
    _stockRtToko = tid;
    unawaited(_stockRt?.dispose() ?? Future.value());
    _stockRt = StockRealtime.subscribeToko(
      tokoId: tid,
      onEvent: (ev) {
        if (!mounted) return;
        // Stok cabang berubah (hold POS/Member lain) → cek pre-order + popup.
        _stockRtDebounce?.cancel();
        _stockRtDebounce = Timer(const Duration(milliseconds: 200), () {
          if (mounted) {
            unawaited(_refreshPreorderFlags(fromRealtime: true));
          }
        });
      },
    );
  }

  Future<void> _boot() async {
    await _cart.ensureLoaded();
    if (widget.useShopAddress) {
      await MemberShopAddress.instance.ensureLoaded();
    }
    if (!MemberSession.instance.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Login dulu untuk checkout.';
      });
      return;
    }
    if (_cart.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Keranjang kosong.';
      });
      return;
    }
    try {
      final stores = await _repo.listOnlineStores();
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _loading = false;
      });
      // Isi koordinat cabang yang punya alamat terdaftar (bukan tebak Bandung).
      await _fillMissingStoreCoords();

      if (widget.useShopAddress) {
        await _applyShopAddressPresets();
        return;
      }

      // Prefill profil → tampilkan saran Maps (wajib pilih, jangan auto-buat).
      if (_search.text.trim().length >= 4) {
        await _runAddressSearch(_search.text.trim());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _applyShopAddressPresets() async {
    final a = MemberShopAddress.instance.active;
    if (a != null && a.hasCoords) {
      _mapsVerified = true;
      _verifiedLabel = a.displayName;
      _addressLat = a.lat;
      _addressLng = a.lng;
      if (a.detail.trim().isNotEmpty) {
        _detail.text = a.detail.trim();
      } else if (a.note.trim().isNotEmpty) {
        _detail.text = a.note.trim();
      }
    }
    if (widget.presetFulfillment != null &&
        widget.presetFulfillment!.isNotEmpty) {
      _fulfillment = widget.presetFulfillment!;
    }
    if (widget.presetCourier != null && widget.presetCourier!.isNotEmpty) {
      _courier = widget.presetCourier!;
    }
    final tid = (widget.presetTokoId ?? '').trim();
    if (tid.isNotEmpty) {
      _tokoId = tid;
      // Cabang yang dipilih Member di detail — jangan diganti ke terdekat.
      _storeUserOverride = true;
      _storeHint =
          'Cabang yang Anda pilih. Pesanan diproses di cabang ini.';
      _bindStockRealtime(tid);
    }
    // Ongkir real dari Detail Pesanan (Biteship / OBR), bukan flat fee.
    if (widget.presetShippingFee != null) {
      _shippingFee = widget.presetShippingFee!;
    }
    if (!mounted) return;
    setState(() {});
    if (widget.presetShippingFee == null) {
      await _refreshShipping();
    }
    await _refreshPreorderFlags();
  }

  void _invalidateMapsAddress() {
    _mapsVerified = false;
    _verifiedLabel = null;
    _addressLat = null;
    _addressLng = null;
    _gpsDistanceM = null;
    _tokoId = null;
    _storeUserOverride = false;
    _storeHint = null;
    _preorderSkus = const [];
    _shippingFee = 0;
  }

  /// Alamat baru/terkonfirmasi ulang → cabang selalu balik ke terdekat.
  void _resetStoreForNewAddress() {
    _tokoId = null;
    _storeUserOverride = false;
    _preorderSkus = const [];
    _shippingFee = 0;
    _storeHint = 'Alamat baru — menghitung ulang cabang terdekat…';
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (_mapsVerified) {
      setState(_invalidateMapsAddress);
    }
    final q = value.trim();
    if (q.length < 4) {
      setState(() {
        _hits = const [];
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _runAddressSearch(q);
    });
  }

  Future<void> _runAddressSearch(String query) async {
    setState(() => _searching = true);
    try {
      final hits = await OsmAddressSearch.search(query, limit: 6);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hits = const [];
        _searching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mencari di Maps. Coba lagi / cek koneksi.'),
        ),
      );
    }
  }

  Future<void> _applyVerifiedHit(
    OsmAddressHit hit, {
    required bool fromGps,
  }) async {
    final hadPreviousStore = _tokoId != null || _storeUserOverride;
    setState(() {
      _mapsVerified = true;
      _verifiedLabel = hit.displayName;
      _addressLat = hit.lat;
      _addressLng = hit.lng;
      _hits = const [];
      _search.text = hit.title;
      _searching = false;
      _resetStoreForNewAddress();
    });
    try {
      _mapCtrl.move(LatLng(hit.lat, hit.lng), 16);
    } catch (_) {}

    if (!fromGps) {
      final pos = await _currentGps();
      if (pos != null) {
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          hit.lat,
          hit.lng,
        );
        if (!mounted) return;
        setState(() => _gpsDistanceM = dist);
        if (dist >= _kFarAddressConfirmMeters) {
          final km = (dist / 1000).toStringAsFixed(1);
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Konfirmasi alamat Maps'),
              content: Text(
                'Alamat dari Maps sekitar $km km dari posisi GPS Anda sekarang.\n\n'
                '“${hit.displayName}”\n\n'
                'Yakin ini alamat yang benar?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Tidak'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Yakin'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (ok != true) {
            setState(_invalidateMapsAddress);
            return;
          }
        }
      } else {
        setState(() => _gpsDistanceM = null);
      }
    } else {
      setState(() => _gpsDistanceM = 0);
    }

    setState(() => _resolvingStore = true);
    try {
      // Alamat (baru) sudah dikonfirmasi → selalu saran cabang terdekat lagi.
      await _pickNearestFromCoords(hit.lat, hit.lng);
      if (hadPreviousStore && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Alamat berubah — cabang dikembalikan ke terdekat dari alamat baru.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resolvingStore = false);
    }
  }

  Future<void> _openInMaps() async {
    final lat = _addressLat;
    final lng = _addressLng;
    if (lat == null || lng == null) return;
    final uri = Uri.parse(
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _storeHasGeo(Map<String, dynamic> s) {
    final lat = (s['latitude'] as num?)?.toDouble();
    final lng = (s['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return false;
    if (lat == 0 && lng == 0) return false;
    return true;
  }

  List<Map<String, dynamic>> get _storesWithGeo =>
      _stores.where(_storeHasGeo).toList();

  /// Geocode alamat cabang yang terdaftar — cabang tanpa alamat dilewati.
  Future<void> _fillMissingStoreCoords() async {
    for (final s in _stores) {
      if (_storeHasGeo(s)) continue;
      final addr = (s['shop_address'] ?? '').toString().trim();
      if (addr.isEmpty) continue;
      try {
        final hits = await OsmAddressSearch.search(addr, limit: 1);
        if (hits.isEmpty) continue;
        s['latitude'] = hits.first.lat;
        s['longitude'] = hits.first.lng;
        s['geo_source'] = 'geocode_shop_address';
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    if (mounted) setState(() {});
  }

  Future<void> _onPinMoved(LatLng point, {required bool confirmFar}) async {
    final prevLat = _addressLat;
    final prevLng = _addressLng;
    final prevLabel = _verifiedLabel;
    final prevToko = _tokoId;
    final prevOverride = _storeUserOverride;
    final prevHint = _storeHint;
    final hadPreviousStore = _tokoId != null || _storeUserOverride;

    setState(() {
      _addressLat = point.latitude;
      _addressLng = point.longitude;
      _mapsVerified = true;
      _resetStoreForNewAddress();
    });
    try {
      _mapCtrl.move(point, _mapCtrl.camera.zoom);
    } catch (_) {}

    setState(() => _resolvingStore = true);
    try {
      final hit = await OsmAddressSearch.reverse(point);
      if (!mounted) return;
      if (hit != null) {
        setState(() {
          _verifiedLabel = hit.displayName;
          _search.text = hit.title;
        });
      } else {
        setState(() {
          _verifiedLabel =
              'Titik peta (${point.latitude.toStringAsFixed(5)}, '
              '${point.longitude.toStringAsFixed(5)})';
        });
      }

      final pos = await _currentGps();
      if (pos != null) {
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          point.latitude,
          point.longitude,
        );
        setState(() => _gpsDistanceM = dist);
        if (confirmFar && dist >= _kFarAddressConfirmMeters) {
          if (!mounted) return;
          final km = (dist / 1000).toStringAsFixed(1);
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Titik jauh dari GPS Anda'),
              content: Text(
                'Titik yang dipilih ±$km km dari posisi sekarang.\n\n'
                'Yakin pakai titik ini?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Tidak'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Yakin'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (ok != true) {
            // Batalkan geser pin → kembalikan alamat & cabang sebelumnya.
            setState(() {
              _addressLat = prevLat;
              _addressLng = prevLng;
              _verifiedLabel = prevLabel;
              _tokoId = prevToko;
              _storeUserOverride = prevOverride;
              _storeHint = prevHint;
            });
            if (prevLat != null && prevLng != null) {
              try {
                _mapCtrl.move(LatLng(prevLat, prevLng), _mapCtrl.camera.zoom);
              } catch (_) {}
            }
            return;
          }
        }
      }

      await _pickNearestFromCoords(point.latitude, point.longitude);
      if (hadPreviousStore && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Titik alamat berubah — cabang dikembalikan ke terdekat.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resolvingStore = false);
    }
  }

  Map<String, dynamic>? get _selectedStore {
    if (_tokoId == null) return null;
    for (final s in _stores) {
      if ((s['toko_id'] ?? '').toString() == _tokoId) return s;
    }
    return null;
  }

  String? get _cabangLabel {
    final s = _selectedStore;
    if (s == null) return null;
    return (s['label'] ?? s['toko_id']).toString();
  }

  Future<Position?> _currentGps() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
  }

  Future<void> _useMyLocation() async {
    setState(() => _resolvingStore = true);
    try {
      final pos = await _currentGps();
      if (pos == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lokasi tidak tersedia. Izinkan GPS lalu coba lagi.',
            ),
          ),
        );
        return;
      }
      final hit = await OsmAddressSearch.reverse(
        LatLng(pos.latitude, pos.longitude),
      );
      if (!mounted) return;
      if (hit == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membaca alamat dari Maps/GPS')),
        );
        return;
      }
      await _applyVerifiedHit(hit, fromGps: true);
    } finally {
      if (mounted) setState(() => _resolvingStore = false);
    }
  }

  String _fmtDist(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  double? _distanceFromAddress(Map<String, dynamic> store) {
    final lat = _addressLat;
    final lng = _addressLng;
    if (lat == null || lng == null || !_storeHasGeo(store)) return null;
    return Geolocator.distanceBetween(
      lat,
      lng,
      (store['latitude'] as num).toDouble(),
      (store['longitude'] as num).toDouble(),
    );
  }

  /// Toko diurutkan jarak dari alamat terkonfirmasi (terdekat dulu).
  List<Map<String, dynamic>> _storesRankedByAddress() {
    final ranked = [..._storesWithGeo];
    ranked.sort((a, b) {
      final da = _distanceFromAddress(a) ?? double.infinity;
      final db = _distanceFromAddress(b) ?? double.infinity;
      return da.compareTo(db);
    });
    return ranked;
  }

  Future<void> _pickNearestFromCoords(double lat, double lng) async {
    Map<String, dynamic>? best;
    double bestM = double.infinity;
    for (final s in _storesWithGeo) {
      final slat = (s['latitude'] as num).toDouble();
      final slng = (s['longitude'] as num).toDouble();
      final d = Geolocator.distanceBetween(lat, lng, slat, slng);
      if (d < bestM) {
        bestM = d;
        best = s;
      }
    }
    if (best == null) {
      if (!mounted) return;
      setState(() {
        _tokoId = null;
        _storeHint =
            'Belum bisa suggest cabang: tidak ada toko dengan koordinat Maps. '
            'Admin perlu isi latitude/longitude tiap cabang. '
            'Tidak ada cabang default.';
        _preorderSkus = const [];
        _shippingFee = 0;
      });
      return;
    }

    await _applySelectedStore(
      best,
      distanceM: bestM,
      suggested: true,
    );
  }

  Future<void> _applySelectedStore(
    Map<String, dynamic> store, {
    required double? distanceM,
    required bool suggested,
  }) async {
    final tid = (store['toko_id'] ?? '').toString();
    final label = (store['label'] ?? store['shop_name'] ?? tid).toString();
    final distLabel = distanceM == null ? null : _fmtDist(distanceM);

    if (!mounted) return;
    setState(() {
      _tokoId = tid;
      if (suggested) {
        _storeHint =
            'Saran otomatis (terdekat dari alamat Anda): $label'
            '${distLabel != null ? ' · $distLabel' : ''}. '
            'Boleh ganti cabang — jarak selalu dihitung dari alamat Maps Anda.';
      } else {
        _storeHint =
            'Cabang dipilih manual: $label'
            '${distLabel != null ? ' · $distLabel dari alamat Anda' : ''}. '
            'Jika Anda ganti alamat Maps, cabang akan dihitung ulang ke terdekat.';
      }
    });
    _bindStockRealtime(tid);
    await _refreshShipping();
    await _refreshPreorderFlags();
  }

  Future<void> _changeStore() async {
    if (!_hasVerifiedCoords) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konfirmasi alamat Maps dulu sebelum ganti cabang'),
        ),
      );
      return;
    }
    final ranked = _storesRankedByAddress();
    if (ranked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Belum ada cabang berkoordinat. Isi lat/lng toko di Admin dulu.',
          ),
        ),
      );
      return;
    }

    final nearestId = (ranked.first['toko_id'] ?? '').toString();
    final nearestDist = _distanceFromAddress(ranked.first) ?? 0;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    'Pilih cabang',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Jarak dihitung dari alamat Maps yang sudah dikonfirmasi. '
                    'Saran = terdekat; pesanan ikut yang dipilih.',
                    style: TextStyle(
                      color: OptikMemberTokens.inkMuted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: ranked.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = ranked[i];
                      final id = (s['toko_id'] ?? '').toString();
                      final label =
                          (s['label'] ?? s['shop_name'] ?? id).toString();
                      final dist = _distanceFromAddress(s);
                      final selected = id == _tokoId;
                      final isNearest = i == 0;
                      return ListTile(
                        selected: selected,
                        leading: Icon(
                          isNearest
                              ? Icons.near_me_rounded
                              : Icons.storefront_outlined,
                          color: OptikMemberTokens.blueDeep,
                        ),
                        title: Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          dist == null
                              ? 'Jarak tidak tersedia'
                              : '${_fmtDist(dist)} dari alamat Anda'
                                  '${isNearest ? ' · terdekat' : ''}',
                        ),
                        trailing: Text(
                          dist == null ? '—' : _fmtDist(dist),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: (dist != null &&
                                    dist >= _kFarAddressConfirmMeters)
                                ? const Color(0xFFC45C4A)
                                : OptikMemberTokens.blueDeep,
                          ),
                        ),
                        onTap: () => Navigator.pop(ctx, s),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    final pickId = (picked['toko_id'] ?? '').toString();
    final dist = _distanceFromAddress(picked);
    final label =
        (picked['label'] ?? picked['shop_name'] ?? pickId).toString();

    // Konfirmasi jika jauh dari alamat, atau jauh lebih jauh dari saran terdekat.
    final farFromAddress =
        dist != null && dist >= _kFarAddressConfirmMeters;
    final muchFartherThanNearest = dist != null &&
        pickId != nearestId &&
        dist > nearestDist + 1500;

    if (farFromAddress || muchFartherThanNearest) {
      final distLabel = _fmtDist(dist);
      final nearestLabel =
          (ranked.first['label'] ?? ranked.first['toko_id']).toString();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Yakin pilih cabang ini?'),
          content: Text(
            'Cabang “$label” berjarak $distLabel dari alamat Maps Anda.\n\n'
            'Saran terdekat: $nearestLabel (${_fmtDist(nearestDist)}).\n\n'
            'Yakin tetap pakai cabang yang lebih jauh?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tidak'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yakin'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (ok != true) return;
    }

    _storeUserOverride = true;
    await _applySelectedStore(
      picked,
      distanceM: dist,
      suggested: false,
    );
  }

  Future<void> _refreshPreorderFlags({bool fromRealtime = false}) async {
    if (_tokoId == null || _cart.isEmpty) {
      setState(() => _preorderSkus = const []);
      return;
    }
    final skus = _cart.items.map((e) => e.sku).toList();
    final sellable = await _repo.listBranchSellable(
      tokoId: _tokoId!,
      skus: skus,
    );
    final bySku = <String, int>{};
    for (final s in sellable) {
      final sku = (s['sku'] ?? '').toString().toUpperCase();
      bySku[sku] = int.tryParse('${s['available_qty'] ?? 0}') ?? 0;
    }
    final need = <String>[];
    final newlyShort = <MemberCartItem>[];
    for (final it in _cart.items) {
      final avail = bySku[it.sku.toUpperCase()] ?? 0;
      if (avail < it.qty) {
        need.add(it.sku);
        final key = it.sku.toUpperCase();
        if (fromRealtime && !_acceptedPreorderSkus.contains(key)) {
          newlyShort.add(it);
        }
      }
    }
    if (!mounted) return;
    setState(() => _preorderSkus = need);

    if (fromRealtime && newlyShort.isNotEmpty) {
      await _showRealtimePreorderPopup(newlyShort, bySku);
    }
  }

  /// Popup realtime: stok cabang kurang → pre-order 5–7 hari atau cari produk lain.
  Future<void> _showRealtimePreorderPopup(
    List<MemberCartItem> shortItems,
    Map<String, int> availBySku,
  ) async {
    if (!mounted || _shortageDialogOpen || shortItems.isEmpty) return;
    _shortageDialogOpen = true;
    try {
      final lines = shortItems.map((it) {
        final avail = availBySku[it.sku.toUpperCase()] ?? 0;
        final kurang = it.qty - avail;
        return '• ${it.nama} (pesan ${it.qty}, tersedia $avail'
            '${kurang > 0 ? ', kurang $kurang' : ''})';
      }).join('\n');

      final continuePo = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Stok kurang — Pre-order'),
          content: Text(
            'Stok di cabang $_cabangLabel baru saja berkurang untuk:\n\n'
            '$lines\n\n'
            'Kalau lanjut, kekurangan masuk Request Order (RO) cabang ini. '
            'Estimasi tiba 5–7 hari kerja setelah pembayaran lunas.\n\n'
            'Lanjutkan pre-order atau cari produk lain?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cari produk lain'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lanjutkan pre-order'),
            ),
          ],
        ),
      );
      if (!mounted) return;

      if (continuePo == true) {
        setState(() {
          for (final it in shortItems) {
            _acceptedPreorderSkus.add(it.sku.toUpperCase());
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pre-order dicatat. Setelah lunas → RO cabang (estimasi 5–7 hari).',
            ),
          ),
        );
        return;
      }

      // Batalkan: hapus item yang stoknya kurang, kembali cari produk.
      for (final it in shortItems) {
        await _cart.remove(it.sku);
        _acceptedPreorderSkus.remove(it.sku.toUpperCase());
      }
      if (!mounted) return;
      if (_cart.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item dihapus. Silakan cari produk lain.'),
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      await _refreshPreorderFlags();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${shortItems.length} item dihapus dari keranjang. '
            'Lanjut dengan sisa item atau cari produk lain.',
          ),
        ),
      );
    } finally {
      _shortageDialogOpen = false;
    }
  }

  Future<void> _refreshShipping() async {
    if (_fulfillment != 'delivery' || _tokoId == null) {
      setState(() => _shippingFee = 0);
      return;
    }
    // Detail Belanja Online sudah kirim ongkir Biteship/OBR live —
    // jangan timpa dengan flat fee cadangan.
    if (widget.useShopAddress && widget.presetShippingFee != null) {
      setState(() => _shippingFee = widget.presetShippingFee!);
      return;
    }
    final q = await _repo.quoteDelivery(tokoId: _tokoId!, courier: _courier);
    if (!mounted) return;
    if (q['ok'] == true) {
      setState(() {
        _shippingFee = int.tryParse('${q['shipping_fee'] ?? 0}') ?? 0;
      });
    } else {
      setState(() => _shippingFee = 0);
    }
  }

  int get _shipVoucherDiscount {
    final d = widget.presetShippingVoucherDiscount ?? 0;
    if (d <= 0 || _fulfillment != 'delivery') return 0;
    return d > _shippingFee ? _shippingFee : d;
  }

  int get _productPromoDiscount {
    final d = widget.presetProductPromoDiscount ?? 0;
    if (d <= 0) return 0;
    return d > _cart.subtotal ? _cart.subtotal : d;
  }

  int get _shippingFeePayable {
    final after = _shippingFee - _shipVoucherDiscount;
    return after < 0 ? 0 : after;
  }

  int get _total {
    final goods = _cart.subtotal - _productPromoDiscount;
    final base = goods < 0 ? 0 : goods;
    final ship = _fulfillment == 'delivery' ? _shippingFeePayable : 0;
    return base + ship;
  }

  Future<void> _pay() async {
    final session = MemberSession.instance;
    if (!session.isLoggedIn) {
      Navigator.of(context).pushNamed('/login');
      return;
    }
    // Pengiriman: alamat Maps wajib. Pickup: cukup cabang terpilih.
    if (_fulfillment == 'delivery') {
      if (!_hasVerifiedCoords || _fullAddress.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pilih alamat pengiriman dari saran Maps dulu (jangan ketik bebas).',
            ),
          ),
        );
        return;
      }
    }
    if (_tokoId == null || _tokoId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fulfillment == 'pickup'
                ? 'Pilih cabang ambil di toko dulu.'
                : 'Cabang belum terhitung dari alamat Maps. '
                    'Pastikan titik alamat sudah dipilih, dan cabang punya koordinat di sistem.',
          ),
        ),
      );
      return;
    }

    if (_fulfillment == 'delivery' &&
        _gpsDistanceM != null &&
        _gpsDistanceM! >= _kFarAddressConfirmMeters) {
      final km = (_gpsDistanceM! / 1000).toStringAsFixed(1);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Alamat jauh dari posisi Anda'),
          content: Text(
            'Alamat Maps ±$km km dari GPS sekarang.\n\n'
            'Yakin pakai alamat ini dan cabang $_cabangLabel?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tidak'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yakin'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (ok != true) return;
    }

    if (!mounted) return;
    final store = _selectedStore;
    if (_fulfillment == 'pickup' && store?['pickup_enabled'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cabang ini tidak terima pickup')),
      );
      return;
    }
    if (_fulfillment == 'delivery') {
      // Biteship selalu boleh selama cabang jual online (list sudah filter).
      if (_courier.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih kurir')),
        );
        return;
      }
      // Path Belanja Online: ongkir harus dari Detail Pesanan (quote live).
      if (widget.useShopAddress && widget.presetShippingFee == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ongkir belum dipilih. Kembali ke detail pesanan.'),
          ),
        );
        return;
      }
    }

    if (_preorderSkus.isNotEmpty) {
      final lines = _cart.items
          .where((it) => _preorderSkus.contains(it.sku))
          .map((it) => '• ${it.nama} (x${it.qty})')
          .join('\n');
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Konfirmasi pre-order'),
          content: Text(
            'Item berikut stok cabang $_cabangLabel kurang:\n'
            '$lines\n\n'
            'Estimasi tiba 5–7 hari kerja setelah lunas '
            '(RO cabang $_cabangLabel → Pusat).\n\n'
            'Lanjutkan bayar, atau kembali cari produk lain?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cari produk lain'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lanjutkan bayar'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (ok != true) return;
    }

    if (!mounted) return;
    setState(() => _paying = true);
    try {
      final res = await _repo.createOnlineCheckout(
        phone: session.phoneForQuery,
        memberId: session.memberId,
        customerName: session.nama,
        tokoId: _tokoId!,
        fulfillment: _fulfillment,
        courier: _fulfillment == 'delivery' ? _courier : null,
        addressText: _fulfillment == 'delivery'
            ? _fullAddress
            : (_fullAddress.trim().isEmpty ? null : _fullAddress),
        addressLat: _fulfillment == 'delivery' ? _addressLat : null,
        addressLng: _fulfillment == 'delivery' ? _addressLng : null,
        shippingFee:
            _fulfillment == 'delivery' ? _shippingFee : 0,
        // Meta Biteship hanya jika kurir masih sama dengan preset (jangan stale).
        courierCompany: _fulfillment == 'delivery' &&
                _courier == (widget.presetCourier ?? _courier) &&
                (widget.presetCourierCompany ?? '').trim().isNotEmpty
            ? widget.presetCourierCompany
            : null,
        courierServiceCode: _fulfillment == 'delivery' &&
                _courier == (widget.presetCourier ?? _courier) &&
                (widget.presetCourierServiceCode ?? '').trim().isNotEmpty
            ? widget.presetCourierServiceCode
            : null,
        courierServiceName: _fulfillment == 'delivery' &&
                _courier == (widget.presetCourier ?? _courier) &&
                (widget.presetCourierServiceName ?? '').trim().isNotEmpty
            ? widget.presetCourierServiceName
            : null,
        shippingCategory: _fulfillment == 'delivery' &&
                _courier == (widget.presetCourier ?? _courier)
            ? widget.presetShippingCategory
            : null,
        isObr: _fulfillment == 'delivery' &&
            widget.presetIsObr &&
            (_courier == 'obr' ||
                _courier == (widget.presetCourier ?? '')),
        shippingVoucherDiscount: widget.presetShippingVoucherDiscount ?? 0,
        productPromoCode: (widget.presetProductPromoCode ?? '').trim().isEmpty
            ? null
            : widget.presetProductPromoCode!.trim(),
        // Server menghitung ulang + redeem; kirim 0 jika tanpa kode.
        productPromoDiscount:
            (widget.presetProductPromoCode ?? '').trim().isEmpty
                ? 0
                : (widget.presetProductPromoDiscount ?? 0),
        items: _cart.toCheckoutItems(),
      );
      if (!mounted) return;
      if (res['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${res['error'] ?? 'Checkout gagal'}'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final mock = res['mock_payment'] == true;
      final redirect = (res['redirect_url'] ?? '').toString();
      final midOrderId = (res['midtrans_order_id'] ?? '').toString();
      final onlineId = (res['online_order_id'] ?? '').toString();
      final hasPre = res['has_preorder'] == true;
      final expiresAt = DateTime.tryParse('${res['expires_at'] ?? ''}')
              ?.toLocal() ??
          DateTime.now().add(const Duration(minutes: 15));

      if (mock || redirect.isEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Bayar (uji / tanpa Midtrans)'),
            content: Text(
              'Order $midOrderId siap.\n'
              'Total ${_money.format(_total)}.\n'
              'Cabang: $_cabangLabel\n'
              'Batas bayar 15 menit (stok di-hold).\n'
              '${hasPre ? '\nTermasuk pre-order → RO cabang saat lunas.' : ''}\n\n'
              'Set MIDTRANS_SERVER_KEY di Edge untuk bayar asli.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Nanti'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Bayar uji'),
              ),
            ],
          ),
        );
        if (ok == true) {
          final paid = await _repo.mockPayOnlineOrder(midOrderId);
          if (!mounted) return;
          if (paid['ok'] == true) {
            await _cart.clear();
            await _showSuccess(onlineId, hasPreorder: hasPre);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${paid['error'] ?? 'Gagal lunasi'}'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        } else if (onlineId.isNotEmpty && mounted) {
          // "Nanti" — jangan hilang: buka detail pending.
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MemberOnlineOrderPage(onlineOrderId: onlineId),
            ),
          );
        }
        return;
      }

      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MemberMidtransPayPage(
            redirectUrl: redirect,
            phone: session.phoneForQuery,
            onlineOrderId: onlineId,
            expiresAt: expiresAt,
          ),
        ),
      );
      if (!mounted) return;
      if (paid == true) {
        await _cart.clear();
        await _showSuccess(onlineId, hasPreorder: hasPre);
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _showSuccess(
    String onlineId, {
    required bool hasPreorder,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pembayaran berhasil'),
        content: Text(
          hasPreorder
              ? 'Pesanan masuk cabang $_cabangLabel. '
                  'Item pre-order sudah masuk Request Order (RO) cabang tersebut. '
                  'Lacak di menu Pesanan.'
              : 'Pesanan masuk cabang $_cabangLabel dan tercatat di keuangan cabang. '
                  'Lacak di menu Pesanan.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) =>
                      const MemberOrdersListPage(title: 'Pesanan saya'),
                ),
                (r) => r.isFirst,
              );
            },
            child: const Text('Lihat pesanan'),
          ),
        ],
      ),
    );
  }

  Widget _buildShopAddressCheckout(Map<String, dynamic>? store) {
    final addr = MemberShopAddress.instance;
    return MemberPremiumScaffold(
      title: 'Pembayaran',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OptikMemberTokens.blueMist,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: OptikMemberTokens.blue.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fulfillment == 'pickup'
                      ? 'Alamat (opsional)'
                      : 'Alamat pengiriman',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: OptikMemberTokens.blueDeep,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  addr.isConfirmed
                      ? addr.shortLabel
                      : (_fulfillment == 'pickup'
                          ? 'Tidak wajib untuk ambil di toko'
                          : 'Belum ada alamat'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: OptikMemberTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  addr.isConfirmed
                      ? addr.fullAddress
                      : (_fulfillment == 'pickup'
                          ? 'Cabang ambil sudah dipilih di langkah sebelumnya.'
                          : 'Kembali ke detail pesanan untuk memilih alamat.'),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: OptikMemberTokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OptikMemberTokens.lineSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cabang: ${_cabangLabel ?? '-'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: OptikMemberTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fulfillment == 'pickup'
                      ? 'Ambil di toko · diproses cabang ini'
                      : 'Kirim · kurir ${_courier.toUpperCase()} · diproses cabang ini',
                  style: const TextStyle(
                    fontSize: 13,
                    color: OptikMemberTokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _storeHint ??
                      'Pesanan masuk ke cabang yang Anda pilih di langkah sebelumnya.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: OptikMemberTokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_preorderSkus.isNotEmpty && _tokoId != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OptikMemberTokens.blueSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Pre-order: ${_preorderSkus.length} SKU stok cabang kurang. '
                'Setelah lunas → RO cabang $_cabangLabel.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: OptikMemberTokens.blueDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _detail,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan alamat (opsional)',
              hintText: 'RT/RW, nomor rumah, patokan…',
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ringkasan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ..._cart.items.map(
            (it) {
              final pre = _preorderSkus.contains(it.sku);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${it.nama} ×${it.qty}'
                        '${pre ? '  · Pre-order' : ''}',
                      ),
                    ),
                    Text(_money.format(it.lineTotal)),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 24),
          _sumRow('Subtotal', _cart.subtotal),
          if (_productPromoDiscount > 0)
            _sumRow(
              widget.presetProductPromoCode != null &&
                      widget.presetProductPromoCode!.isNotEmpty
                  ? 'Diskon (${widget.presetProductPromoCode})'
                  : 'Diskon produk',
              -_productPromoDiscount,
            ),
          if (_fulfillment == 'delivery') ...[
            _sumRow('Ongkir ($_courier)', _shippingFee),
            if (_shipVoucherDiscount > 0)
              _sumRow('Voucher ongkir', -_shipVoucherDiscount),
          ],
          const SizedBox(height: 6),
          _sumRow('Total bayar (lunas)', _total, bold: true),
          if (store != null && _fulfillment == 'pickup') ...[
            const SizedBox(height: 10),
            Text(
              'Ambil di ${(store['label'] ?? _tokoId)} setelah status siap.',
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: OptikMemberTokens.blueDeep,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _paying || _resolvingStore ? null : _pay,
            icon: _paying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_rounded),
            label: Text(
              _paying ? 'Memproses…' : 'Bayar lunas ${_money.format(_total)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MemberPremiumScaffold(
        title: 'Checkout',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return MemberPremiumScaffold(
        title: 'Checkout',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                if (!MemberSession.instance.isLoggedIn)
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/login'),
                    child: const Text('Login'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final store = _selectedStore;

    if (widget.useShopAddress) {
      return _buildShopAddressCheckout(store);
    }

    return MemberPremiumScaffold(
      title: 'Checkout',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          const Text(
            '1. Alamat (Maps)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Wajib pilih dari saran OpenStreetMap — bukan teks bebas. '
            'Cabang disarankan dari alamat (terdekat). '
            'Anda boleh ganti — pesanan & RO masuk ke cabang yang dipilih.',
            style: TextStyle(
              color: OptikMemberTokens.inkMuted,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onSubmitted: (v) {
              final q = v.trim();
              if (q.length >= 4) _runAddressSearch(q);
            },
            decoration: InputDecoration(
              labelText: 'Cari alamat di Maps',
              hintText: 'Contoh: Jl. A.H. Nasution Arcamanik Bandung',
              prefixIcon: const Icon(Icons.map_outlined),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(() {
                              _hits = const [];
                              _invalidateMapsAddress();
                            });
                          },
                        )),
            ),
          ),
          if (_hits.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OptikMemberTokens.lineSoft),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _hits.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final hit = _hits[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.place_outlined,
                      color: OptikMemberTokens.blue,
                    ),
                    title: Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: hit.subtitle == null
                        ? Text(
                            hit.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          )
                        : Text(
                            hit.subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                    onTap: () => _applyVerifiedHit(hit, fromGps: false),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resolvingStore ? null : _useMyLocation,
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: Text(
                _resolvingStore
                    ? 'Mengambil lokasi…'
                    : 'Pakai lokasi GPS saya (Maps)',
              ),
            ),
          ),
          if (_hasVerifiedCoords) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_rounded,
                          size: 18, color: Color(0xFF2E7D32)),
                      SizedBox(width: 6),
                      Text(
                        'Alamat terverifikasi Maps',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _verifiedLabel ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Koordinat: ${_addressLat!.toStringAsFixed(5)}, '
                    '${_addressLng!.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF388E3C),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _openInMaps,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Buka di OpenStreetMap'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Geser pin atau ketuk peta untuk sesuaikan titik.',
              style: TextStyle(
                fontSize: 12.5,
                color: OptikMemberTokens.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 200,
                child: FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: LatLng(_addressLat!, _addressLng!),
                    initialZoom: 16,
                    onTap: (_, point) =>
                        _onPinMoved(point, confirmFar: true),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom |
                          InteractiveFlag.drag |
                          InteractiveFlag.doubleTapZoom,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'optik_b_riski',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_addressLat!, _addressLng!),
                          width: 48,
                          height: 48,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) {
                              try {
                                final cam = _mapCtrl.camera;
                                final screen = cam.latLngToScreenPoint(
                                  LatLng(_addressLat!, _addressLng!),
                                );
                                final next = cam.offsetToCrs(
                                  Offset(
                                    screen.x + details.delta.dx,
                                    screen.y + details.delta.dy,
                                  ),
                                );
                                setState(() {
                                  _addressLat = next.latitude;
                                  _addressLng = next.longitude;
                                });
                              } catch (_) {}
                            },
                            onPanEnd: (_) {
                              if (_addressLat == null || _addressLng == null) {
                                return;
                              }
                              _onPinMoved(
                                LatLng(_addressLat!, _addressLng!),
                                confirmFar: true,
                              );
                            },
                            child: const Icon(
                              Icons.location_on,
                              color: OptikMemberTokens.blueDeep,
                              size: 42,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _detail,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Detail tambahan (opsional)',
                hintText: 'RT/RW, nomor rumah, patokan…',
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: const Text(
                'Ketik alamat lalu pilih salah satu saran Maps, '
                'atau pakai lokasi GPS. Tanpa itu checkout dikunci.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Color(0xFF8A5A00),
                ),
              ),
            ),
          ],
          if (_gpsDistanceM != null &&
              _gpsDistanceM! >= _kFarAddressConfirmMeters) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: Text(
                'Alamat Maps ±${(_gpsDistanceM! / 1000).toStringAsFixed(1)} km '
                'dari posisi GPS Anda.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Color(0xFF8A5A00),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            '2. Cabang pemenuhan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _tokoId == null
                  ? const Color(0xFFFFF4E5)
                  : OptikMemberTokens.blueMist,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _tokoId == null
                    ? const Color(0xFFFFCC80)
                    : OptikMemberTokens.blue.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _cabangLabel ??
                      (_fulfillment == 'pickup'
                          ? 'Pilih cabang ambil'
                          : 'Menunggu alamat Maps…'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _tokoId == null
                        ? const Color(0xFF8A5A00)
                        : OptikMemberTokens.blueDeep,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _storeHint ??
                      (_fulfillment == 'pickup'
                          ? 'Ambil di toko: pilih cabang. Alamat Maps tidak wajib.'
                          : 'Setelah alamat dikonfirmasi, sistem menyarankan '
                              'cabang terdekat. Anda bisa ganti — jarak ditampilkan '
                              'dari alamat Anda '
                              '(${_storesWithGeo.length}/${_stores.length} cabang berkoordinat).'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: _tokoId == null
                        ? const Color(0xFF8A5A00)
                        : OptikMemberTokens.inkMuted,
                  ),
                ),
                if (_hasVerifiedCoords) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _changeStore,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Ganti cabang'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_preorderSkus.isNotEmpty && _tokoId != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OptikMemberTokens.blueSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Pre-order: ${_preorderSkus.length} SKU stok cabang kurang. '
                'Setelah lunas → Request Order (RO) cabang $_cabangLabel.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: OptikMemberTokens.blueDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            '3. Cara terima barang',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'pickup',
                label: Text('Ambil di toko'),
                icon: Icon(Icons.storefront_outlined, size: 18),
              ),
              ButtonSegment(
                value: 'delivery',
                label: Text('Kirim'),
                icon: Icon(Icons.delivery_dining_outlined, size: 18),
              ),
            ],
            selected: {_fulfillment},
            onSelectionChanged: (s) async {
              setState(() => _fulfillment = s.first);
              await _refreshShipping();
            },
          ),
          if (_fulfillment == 'delivery') ...[
            const SizedBox(height: 14),
            const Text(
              'Kurir',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final c in [
                  ('grab', 'Grab'),
                  ('gojek', 'Gojek'),
                  ('other', 'Lainnya'),
                ])
                  ChoiceChip(
                    label: Text(c.$2),
                    selected: _courier == c.$1,
                    onSelected: (_) async {
                      setState(() => _courier = c.$1);
                      await _refreshShipping();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Ongkir flat cabang: ${_money.format(_shippingFee)}',
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12,
              ),
            ),
          ],
          if (store != null && _fulfillment == 'pickup') ...[
            const SizedBox(height: 10),
            Text(
              'Ambil di ${(store['label'] ?? _tokoId)} setelah status siap.',
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12.5,
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Ringkasan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ..._cart.items.map(
            (it) {
              final pre = _preorderSkus.contains(it.sku);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${it.nama} ×${it.qty}'
                        '${pre ? '  · Pre-order' : ''}',
                      ),
                    ),
                    Text(_money.format(it.lineTotal)),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 24),
          _sumRow('Subtotal', _cart.subtotal),
          if (_productPromoDiscount > 0)
            _sumRow(
              widget.presetProductPromoCode != null &&
                      widget.presetProductPromoCode!.isNotEmpty
                  ? 'Diskon (${widget.presetProductPromoCode})'
                  : 'Diskon produk',
              -_productPromoDiscount,
            ),
          if (_fulfillment == 'delivery') ...[
            _sumRow('Ongkir ($_courier)', _shippingFee),
            if (_shipVoucherDiscount > 0)
              _sumRow('Voucher ongkir', -_shipVoucherDiscount),
          ],
          const SizedBox(height: 6),
          _sumRow('Total bayar (lunas)', _total, bold: true),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _paying || _resolvingStore ? null : _pay,
            icon: _paying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_rounded),
            label: Text(
              _paying ? 'Memproses…' : 'Bayar lunas ${_money.format(_total)}',
            ),
          ),
        ),
      ),
    );
  }

  Widget _sumRow(String label, int amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: bold
                  ? OptikMemberTokens.blueDeep
                  : OptikMemberTokens.inkSecondary,
            ),
          ),
          const Spacer(),
          Text(
            _money.format(amount),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 17 : 14,
              color: bold
                  ? OptikMemberTokens.blueDeep
                  : OptikMemberTokens.ink,
            ),
          ),
        ],
      ),
    );
  }
}
