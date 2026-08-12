import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../../shared/member/member_cart.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/member/member_shipping_voucher.dart';
import '../../../shared/member/member_shop_address.dart';
import '../../../shared/member/member_shop_order_detail_logic.dart';
import '../../../shared/theme.dart';
import 'member_checkout_page.dart';
import 'member_option_picker.dart';
import 'member_shop_address_picker_page.dart';
import 'member_voucher_picker_page.dart';

/// Detail order sebelum checkout — putih–biru premium.
class MemberShopOrderDetailPage extends StatefulWidget {
  const MemberShopOrderDetailPage({super.key});

  @override
  State<MemberShopOrderDetailPage> createState() =>
      _MemberShopOrderDetailPageState();
}

class _MemberShopOrderDetailPageState extends State<MemberShopOrderDetailPage> {
  final _repo = MemberRepository();
  final _cart = MemberCart.instance;
  final _addr = MemberShopAddress.instance;
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  List<Map<String, dynamic>> _stores = const [];
  String? _tokoId;
  String _fulfillment = 'delivery';
  String _courier = 'obr';
  String? _selectedRateId;
  int _shippingFee = 0;
  bool _loading = true;
  bool _loadingRates = false;
  String? _storeHint;
  String? _rateError;
  String? _obrHint;
  bool _storeOverride = false;
  List<Map<String, dynamic>> _rateGroups = const [];
  Map<String, dynamic>? _selectedRate;
  bool _useShippingVoucher = false;
  Map<String, dynamic>? _productPromo;
  /// Serialisasi quote ongkir — respon lama diabaikan.
  int _rateGen = 0;
  Timer? _cartRateDebounce;

  @override
  void initState() {
    super.initState();
    _addr.addListener(_onAddr);
    _cart.addListener(_onCart);
    _boot();
  }

  @override
  void dispose() {
    _cartRateDebounce?.cancel();
    _addr.removeListener(_onAddr);
    _cart.removeListener(_onCart);
    super.dispose();
  }

  void _onAddr() {
    if (!mounted) return;
    if (!_storeOverride) {
      unawaited(_suggestNearest());
      return;
    }
    // Cabang manual tetap — tetap hitung ulang ongkir ke alamat baru.
    setState(() {});
    unawaited(_refreshShipping());
  }

  void _onCart() {
    if (!mounted) return;
    _syncVoucherWithCurrentRate();
    setState(() {});
    _cartRateDebounce?.cancel();
    _cartRateDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (_fulfillment == 'delivery' &&
          _tokoId != null &&
          _addr.isConfirmed) {
        unawaited(_refreshShipping());
      }
    });
  }

  void _syncVoucherWithCurrentRate() {
    if (!_useShippingVoucher) return;
    final r = _selectedRate;
    final ok = _shipTier.canApply(
      isObr: r?['is_obr'] == true,
      category: r?['category']?.toString(),
      shippingFee: _shippingFee,
    );
    if (!ok) _useShippingVoucher = false;
  }

  Map<String, dynamic>? _storeById(String? id) {
    final tid = (id ?? '').trim();
    if (tid.isEmpty) return null;
    for (final s in _stores) {
      if ((s['toko_id'] ?? '').toString() == tid) return s;
    }
    return null;
  }

  bool get _payBlocked => memberShopOrderDetailPayBlocked(
        hasSelection: _cart.hasSelection,
        isDelivery: _fulfillment == 'delivery',
        addressConfirmed: _addr.isConfirmed,
        loadingRates: _loadingRates,
        hasSelectedRate: _selectedRate != null,
        hasRateGroups: _rateGroups.isNotEmpty,
        hasRateError: _rateError != null && _rateError!.trim().isNotEmpty,
      );

  Future<void> _boot() async {
    await _cart.ensureLoaded();
    // Lensa tidak boleh ikut detail / checkout online.
    await _cart.purgeOnlineBlocked();
    await _addr.ensureLoaded();
    List<Map<String, dynamic>> stores = const [];
    try {
      stores = await _repo.listOnlineStores();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _stores = stores;
      _loading = false;
    });
    if (_addr.isConfirmed) {
      await _suggestNearest();
    }
  }

  bool _hasGeo(Map<String, dynamic> s) {
    final lat = (s['latitude'] as num?)?.toDouble();
    final lng = (s['longitude'] as num?)?.toDouble();
    return lat != null && lng != null && !(lat == 0 && lng == 0);
  }

  String _fmtDist(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

  String get _courierTitle {
    final r = _selectedRate;
    if (r == null) return _courier == 'obr' ? 'OBR Delivery' : _courier;
    final name = (r['label'] ?? r['courier_name'] ?? 'Kurir').toString();
    final cat = (r['courier_service_name'] ?? '').toString();
    if (r['is_obr'] == true && cat.isNotEmpty) {
      return '$name · $cat';
    }
    return name;
  }

  String get _courierDetailLine {
    final r = _selectedRate;
    if (r == null) {
      return _rateError ?? 'Menunggu tarif Biteship…';
    }
    final price = _money.format(_shippingFee);
    final svc = (r['courier_service_name'] ?? '').toString();
    final bits = <String>[
      price,
      if (svc.isNotEmpty && r['is_obr'] != true) svc,
    ];
    return bits.join(' · ');
  }

  String? get _etaLine {
    final r = _selectedRate;
    if (r == null || _fulfillment != 'delivery') return null;
    final label = (r['eta_label'] ?? '').toString();
    if (label.isNotEmpty) return label;
    final short = (r['eta_short'] ?? '').toString();
    if (short.isEmpty) return null;
    return 'Estimasi tiba $short';
  }

  String? get _readyLine {
    final r = _selectedRate;
    if (r == null || _fulfillment != 'delivery') return null;
    final note = (r['ready_note'] ?? '').toString();
    if (note.isNotEmpty) return note;
    final ready = (r['ready_label'] ?? '').toString();
    if (ready.isEmpty) return null;
    return 'Barang jadi $ready (5–7 hari)';
  }

  ({double? oLat, double? oLng, double? dLat, double? dLng}) _geoPair() {
    final store = _storeById(_tokoId);
    return (
      oLat: (store?['latitude'] as num?)?.toDouble(),
      oLng: (store?['longitude'] as num?)?.toDouble(),
      dLat: _addr.lat,
      dLng: _addr.lng,
    );
  }

  Future<void> _suggestNearest() async {
    final lat = _addr.lat;
    final lng = _addr.lng;
    if (lat == null || lng == null) {
      if (!mounted) return;
      setState(() {
        _tokoId = null;
        _storeHint =
            'Isi alamat untuk saran cabang terdekat — atau pilih cabang manual.';
      });
      return;
    }
    Map<String, dynamic>? best;
    var bestM = double.infinity;
    for (final s in _stores.where(_hasGeo)) {
      final d = Geolocator.distanceBetween(
        lat,
        lng,
        (s['latitude'] as num).toDouble(),
        (s['longitude'] as num).toDouble(),
      );
      if (d < bestM) {
        bestM = d;
        best = s;
      }
    }
    if (!mounted) return;
    if (best == null) {
      setState(() {
        _tokoId = null;
        _storeHint =
            'Belum ada cabang berkoordinat. Isi lat/lng toko di Admin.';
      });
      return;
    }
    setState(() {
      _tokoId = (best!['toko_id'] ?? '').toString();
      _storeOverride = false;
      _storeHint =
          'Saran terdekat · ${_fmtDist(bestM)}. '
          'Pesanan masuk ke cabang ini — atau ganti jika mau cabang lain.';
    });
    await _refreshShipping();
  }

  Future<void> _pickAddress() async {
    if (!mounted) return;
    final entry = await Navigator.of(context).push<MemberShopAddressEntry>(
      MaterialPageRoute(builder: (_) => const MemberShopAddressPickerPage()),
    );
    if (!mounted) return;
    if (entry != null) {
      _storeOverride = false;
      await _suggestNearest();
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickStoreForPickup() async {
    if (_stores.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada cabang jual online')),
      );
      return;
    }
    final pickupStores =
        _stores.where((s) => storeAllowsPickup(s)).toList(growable: false);
    if (pickupStores.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belum ada cabang yang menerima ambil di toko'),
        ),
      );
      return;
    }
    final options = pickupStores
        .map(
          (s) => MemberPickerOption(
            value: (s['toko_id'] ?? '').toString(),
            label: (s['label'] ?? s['toko_id'] ?? '-').toString(),
            subtitle: 'Ambil di toko',
            icon: Icons.storefront_outlined,
          ),
        )
        .where((o) => o.value.isNotEmpty)
        .toList();
    final pref = MemberSession.instance.preferredTokoId?.trim();
    final currentOk = _tokoId != null &&
        _tokoId!.isNotEmpty &&
        storeAllowsPickup(_storeById(_tokoId));
    final preselect = currentOk
        ? _tokoId
        : (pref != null &&
                pref.isNotEmpty &&
                options.any((o) => o.value == pref)
            ? pref
            : null);
    final pickedId = await showMemberOptionPicker<String>(
      context,
      title: 'Pilih cabang ambil',
      subtitle:
          'Pesanan diproses di cabang yang Anda pilih (bukan otomatis tetap terdekat).',
      icon: Icons.store_mall_directory_outlined,
      selected: preselect,
      options: options,
    );
    if (pickedId == null || !mounted) return;
    var pickedLabel = pickedId;
    for (final o in options) {
      if (o.value == pickedId) {
        pickedLabel = o.label;
        break;
      }
    }
    setState(() {
      _tokoId = pickedId;
      _storeOverride = true;
      _storeHint =
          'Cabang dipilih: $pickedLabel. Pesanan masuk ke cabang ini.';
    });
  }

  Future<void> _changeStore() async {
    if (_fulfillment == 'pickup' && !_addr.isConfirmed) {
      await _pickStoreForPickup();
      return;
    }
    if (!_addr.isConfirmed) {
      await _pickAddress();
      return;
    }
    final lat = _addr.lat!;
    final lng = _addr.lng!;
    final ranked = _stores.where(_hasGeo).toList()
      ..sort((a, b) {
        final da = Geolocator.distanceBetween(
          lat,
          lng,
          (a['latitude'] as num).toDouble(),
          (a['longitude'] as num).toDouble(),
        );
        final db = Geolocator.distanceBetween(
          lat,
          lng,
          (b['latitude'] as num).toDouble(),
          (b['longitude'] as num).toDouble(),
        );
        return da.compareTo(db);
      });
    if (ranked.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Belum ada cabang berkoordinat. Isi lat/lng toko di Admin.',
          ),
        ),
      );
      return;
    }

    final nearestDist = Geolocator.distanceBetween(
      lat,
      lng,
      (ranked.first['latitude'] as num).toDouble(),
      (ranked.first['longitude'] as num).toDouble(),
    );

    final options = <MemberPickerOption<String>>[];
    for (var i = 0; i < ranked.length; i++) {
      final s = ranked[i];
      final id = (s['toko_id'] ?? '').toString();
      final d = Geolocator.distanceBetween(
        lat,
        lng,
        (s['latitude'] as num).toDouble(),
        (s['longitude'] as num).toDouble(),
      );
      options.add(
        MemberPickerOption(
          value: id,
          label: (s['label'] ?? id).toString(),
          subtitle: i == 0
              ? '${_fmtDist(d)} · terdekat'
              : '${_fmtDist(d)} dari alamat Anda',
          icon: i == 0 ? Icons.near_me_rounded : Icons.storefront_outlined,
        ),
      );
    }

    final pickedId = await showMemberOptionPicker<String>(
      context,
      title: 'Pilih cabang',
      subtitle:
          'Saran terdekat di atas. Pesanan diproses di cabang yang Anda pilih.',
      icon: Icons.store_mall_directory_outlined,
      selected: _tokoId,
      options: options,
    );
    if (pickedId == null || !mounted) return;

    Map<String, dynamic>? picked;
    for (final s in ranked) {
      if ((s['toko_id'] ?? '').toString() == pickedId) {
        picked = s;
        break;
      }
    }
    if (picked == null) return;

    final d = Geolocator.distanceBetween(
      lat,
      lng,
      (picked['latitude'] as num).toDouble(),
      (picked['longitude'] as num).toDouble(),
    );
    final label = (picked['label'] ?? picked['toko_id']).toString();
    if (d >= 5000 || d > nearestDist + 1500) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Yakin pilih cabang ini?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: OptikMemberTokens.blueDeep,
            ),
          ),
          content: Text(
            '“$label” berjarak ${_fmtDist(d)} dari alamat Anda '
            '(saran terdekat ${_fmtDist(nearestDist)}).\n\n'
            'Pesanan akan diproses di cabang ini, bukan di saran terdekat.\n\n'
            'Yakin?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tidak'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: OptikMemberTokens.blueDeep,
                minimumSize: const Size(0, 40),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yakin'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() {
      _tokoId = pickedId;
      _storeOverride = true;
      _storeHint =
          'Cabang dipilih: $label · ${_fmtDist(d)}. '
          'Pesanan masuk ke cabang ini.';
    });
    await _refreshShipping();
  }

  Future<void> _pickFulfillment() async {
    final v = await showMemberOptionPicker<String>(
      context,
      title: 'Cara terima barang',
      subtitle: 'Pilih metode pengiriman',
      icon: Icons.local_shipping_outlined,
      selected: _fulfillment,
      options: const [
        MemberPickerOption(
          value: 'pickup',
          label: 'Ambil di toko',
          subtitle: 'Siap diambil di cabang terpilih',
          icon: Icons.storefront_outlined,
        ),
        MemberPickerOption(
          value: 'delivery',
          label: 'Kirim ke alamat',
          subtitle: 'Diantar kurir ke lokasi Anda',
          icon: Icons.delivery_dining_outlined,
        ),
      ],
    );
    if (v == null || !mounted) return;
    setState(() {
      _fulfillment = v;
      if (v == 'pickup' && !storeAllowsPickup(_storeById(_tokoId))) {
        _tokoId = null;
        _storeOverride = false;
        _storeHint = 'Pilih cabang untuk ambil di toko';
      }
    });
    await _refreshShipping();
  }

  void _applySelectedRate(Map<String, dynamic> rate) {
    final id = rate['id']?.toString() ?? '';
    final fee = int.tryParse('${rate['price'] ?? 0}') ?? 0;
    final isObr = rate['is_obr'] == true;
    final cat = rate['category']?.toString();
    final tier = ObrShippingVoucherTier.resolve(_cart.selectedSubtotal);
    final shipOk = tier.canApply(
      isObr: isObr,
      category: cat,
      shippingFee: fee,
    );
    setState(() {
      _selectedRate = rate;
      _selectedRateId = id;
      _courier = (rate['courier'] ?? 'other').toString();
      _shippingFee = fee;
      if (!shipOk) _useShippingVoucher = false;
    });
  }

  ObrShippingVoucherTier get _shipTier =>
      ObrShippingVoucherTier.resolve(_cart.selectedSubtotal);

  bool get _shipVoucherActive {
    if (!_useShippingVoucher || _fulfillment != 'delivery') return false;
    final r = _selectedRate;
    return _shipTier.canApply(
      isObr: r?['is_obr'] == true,
      category: r?['category']?.toString(),
      shippingFee: _shippingFee,
    );
  }

  int get _shippingDiscount =>
      _shipVoucherActive ? _shipTier.applyDiscount(_shippingFee) : 0;

  int get _shippingFeePayable {
    final after = _shippingFee - _shippingDiscount;
    return after < 0 ? 0 : after;
  }

  int get _productDiscount {
    final p = _productPromo;
    if (p == null) return 0;
    return productPromoDiscountRp(p, _cart.selectedSubtotal);
  }

  Future<void> _pickVoucher() async {
    final r = _selectedRate;
    final picked = await Navigator.of(context).push<MemberVoucherSelection>(
      MaterialPageRoute(
        builder: (_) => MemberVoucherPickerPage(
          subtotal: _cart.selectedSubtotal,
          shippingFee: _shippingFee,
          isObr: r?['is_obr'] == true,
          shippingCategory: r?['category']?.toString(),
          initial: MemberVoucherSelection(
            useShippingVoucher: _useShippingVoucher,
            shippingTierId: _useShippingVoucher ? _shipTier.id : null,
            productPromo: _productPromo,
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final prevDisc = _productDiscount;
    setState(() {
      _useShippingVoucher = picked.useShippingVoucher;
      _productPromo = picked.productPromo;
    });
    // Diskon produk mengubah orderValue / jangkauan OBR → quote ulang.
    if (_fulfillment == 'delivery' && prevDisc != _productDiscount) {
      await _refreshShipping();
    }
  }

  String get _voucherSubtitle {
    final bits = <String>[];
    if (_shipVoucherActive) {
      bits.add('Ongkir −${_money.format(_shippingDiscount)}');
    }
    if (_productDiscount > 0) {
      bits.add('Diskon −${_money.format(_productDiscount)}');
    }
    if (bits.isEmpty) {
      return 'Voucher ongkir OBR & diskon/cashback';
    }
    return bits.join(' · ');
  }

  Future<void> _pickCourier() async {
    if (_tokoId == null || !_addr.isConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih alamat & cabang dulu untuk cek ongkir real'),
        ),
      );
      return;
    }

    if (_rateGroups.isEmpty && !_loadingRates) {
      await _refreshShipping();
    }
    if (!mounted) return;

    if (_rateGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _rateError ??
                'Tarif Biteship belum tersedia. Cek koordinat cabang & alamat.',
          ),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CourierCategorySheet(
        groups: _rateGroups,
        selectedId: _selectedRateId,
        money: _money,
      ),
    );
    if (picked == null || !mounted) return;
    _applySelectedRate(picked);
  }

  Future<void> _refreshShipping() async {
    final gen = ++_rateGen;

    if (_fulfillment != 'delivery' || _tokoId == null) {
      if (!mounted || gen != _rateGen) return;
      setState(() {
        _shippingFee = 0;
        _rateGroups = const [];
        _selectedRate = null;
        _selectedRateId = null;
        _rateError = null;
        _obrHint = null;
        _loadingRates = false;
        _useShippingVoucher = false;
      });
      return;
    }

    final geo = _geoPair();
    final oLat = geo.oLat;
    final oLng = geo.oLng;
    final dLat = geo.dLat;
    final dLng = geo.dLng;

    if (oLat == null ||
        oLng == null ||
        dLat == null ||
        dLng == null ||
        (oLat == 0 && oLng == 0)) {
      if (!mounted || gen != _rateGen) return;
      setState(() {
        _shippingFee = 0;
        _rateGroups = const [];
        _selectedRate = null;
        _selectedRateId = null;
        _rateError =
            'Butuh koordinat cabang + alamat untuk tarif Biteship.';
        _obrHint = null;
        _loadingRates = false;
        _useShippingVoucher = false;
      });
      return;
    }

    final distanceM = Geolocator.distanceBetween(oLat, oLng, dLat, dLng);
    final orderValue = _cart.selectedSubtotal - _productDiscount;
    final goodsValue = orderValue < 0 ? 0 : orderValue;

    if (!mounted || gen != _rateGen) return;
    setState(() {
      _loadingRates = true;
      _rateError = null;
    });

    final store = _storeById(_tokoId);

    final q = await _repo.quoteCourierFeeTable(
      originLat: oLat,
      originLng: oLng,
      destinationLat: dLat,
      destinationLng: dLng,
      orderValue: goodsValue,
      distanceMeters: distanceM,
      obrEnabledCategories: MemberRepository.obrCategoriesFromStore(store),
    );

    if (!mounted || gen != _rateGen) return;

    final groups = <Map<String, dynamic>>[];
    final rawGroups = q['groups'];
    if (rawGroups is List) {
      for (final g in rawGroups) {
        if (g is Map) groups.add(Map<String, dynamic>.from(g));
      }
    }

    final selected = pickDefaultShippingRate(
      groups,
      keepId: _selectedRateId,
    );

    final obrOk = q['obr_eligible'] == true;
    final obrMaxKm =
        (q['obr_max_km'] as num?)?.toDouble() ??
            MemberRepository.obrMaxKmForOrderValue(goodsValue);
    final distKm = distanceM / 1000;
    final obrCats = MemberRepository.obrCategoriesFromStore(store);
    String? obrHint;
    if (!obrOk) {
      if (obrCats.isEmpty) {
        obrHint =
            'OBR Delivery dimatikan cabang ini. Pilih kurir Biteship.';
      } else {
        final needHigh = goodsValue <= MemberRepository.obrHighValueThreshold;
        obrHint = needHigh
            ? 'OBR (anak toko) max ${MemberRepository.obrMaxKmDefault.toStringAsFixed(0)} km '
                '(sekarang ${distKm.toStringAsFixed(1)} km). '
                'Belanja di atas Rp 1.000.000 → jangkauan sampai '
                '${MemberRepository.obrMaxKmHighValue.toStringAsFixed(0)} km. '
                'Di luar itu hanya kurir Biteship.'
            : 'OBR (anak toko) max ${obrMaxKm.toStringAsFixed(0)} km '
                '(sekarang ${distKm.toStringAsFixed(1)} km). '
                'Pilih kurir Biteship.';
      }
    }

    setState(() {
      _loadingRates = false;
      _rateGroups = groups;
      _obrHint = obrHint;
      _rateError = q['ok'] == true
          ? null
          : (q['error']?.toString() ?? 'Gagal ambil tarif Biteship');
      if (selected != null) {
        _selectedRate = selected;
        _selectedRateId = selected['id']?.toString();
        _courier = (selected['courier'] ?? 'other').toString();
        _shippingFee = int.tryParse('${selected['price'] ?? 0}') ?? 0;
      } else {
        _selectedRate = null;
        _selectedRateId = null;
        _shippingFee = 0;
      }
      _syncVoucherWithCurrentRate();
    });
  }

  String? get _cabangLabel {
    final s = _storeById(_tokoId);
    if (s == null) return _tokoId;
    return (s['label'] ?? s['toko_id']).toString();
  }

  int get _total {
    final goods = _cart.selectedSubtotal - _productDiscount;
    final base = goods < 0 ? 0 : goods;
    final ship = _fulfillment == 'delivery' ? _shippingFeePayable : 0;
    return base + ship;
  }

  Future<void> _reviewOrder() async {
    if (!_cart.hasSelection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _cart.isEmpty
                ? 'Keranjang kosong'
                : 'Pilih minimal 1 produk di keranjang untuk lanjut.',
          ),
        ),
      );
      return;
    }
    final blockedErr = _cart.onlineBlockedSelectionError;
    if (blockedErr != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(blockedErr)),
      );
      await _cart.purgeOnlineBlocked();
      return;
    }
    if (!MemberSession.instance.isLoggedIn) {
      await Navigator.of(context).pushNamed('/login');
      if (!mounted || !MemberSession.instance.isLoggedIn) return;
    }
    if (_fulfillment == 'delivery') {
      if (!_addr.isConfirmed) {
        await _pickAddress();
        if (!mounted || !_addr.isConfirmed) return;
      }
      if (_loadingRates) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tunggu tarif kurir selesai dimuat')),
        );
        return;
      }
      if (_rateGroups.isEmpty || _selectedRate == null) {
        await _refreshShipping();
        if (!mounted) return;
        if (_loadingRates) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tunggu tarif kurir selesai dimuat')),
          );
          return;
        }
      }
      if (_selectedRate == null || (_courier).trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _rateError ?? 'Pilih kurir pengiriman dulu',
            ),
          ),
        );
        return;
      }
      if (_rateGroups.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _rateError ?? 'Tarif kurir belum tersedia. Coba muat ulang.',
            ),
          ),
        );
        return;
      }
    } else {
      // Pickup: wajib pilih cabang yang terima ambil di toko.
      if (_tokoId == null ||
          _tokoId!.isEmpty ||
          !storeAllowsPickup(_storeById(_tokoId))) {
        await _pickStoreForPickup();
        if (!mounted ||
            _tokoId == null ||
            _tokoId!.isEmpty ||
            !storeAllowsPickup(_storeById(_tokoId))) {
          return;
        }
      }
    }
    if (_tokoId == null || _tokoId!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih cabang dulu — pesanan masuk ke cabang itu'),
        ),
      );
      return;
    }

    if (!mounted) return;
    final rate = _selectedRate;
    final isObr = rate?['is_obr'] == true;
    if (isObr && _fulfillment == 'delivery') {
      final geo = _geoPair();
      if (geo.oLat != null &&
          geo.oLng != null &&
          geo.dLat != null &&
          geo.dLng != null) {
        final dm = Geolocator.distanceBetween(
          geo.oLat!,
          geo.oLng!,
          geo.dLat!,
          geo.dLng!,
        );
        final goods = _cart.selectedSubtotal - _productDiscount;
        final goodsValue = goods < 0 ? 0 : goods;
        if (!MemberRepository.isObrDistanceEligible(
          distanceMeters: dm,
          orderValue: goodsValue,
        )) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'OBR di luar jangkauan. Pilih kurir Biteship.',
              ),
            ),
          );
          await _refreshShipping();
          return;
        }
      }
    }
    final company = isObr
        ? (rate?['biteship_company'] ?? '').toString()
        : (rate?['biteship_company'] ?? rate?['company'] ?? '').toString();
    final serviceCode = isObr
        ? (rate?['biteship_service_code'] ?? '').toString()
        : (rate?['biteship_service_code'] ??
                rate?['courier_service_code'] ??
                '')
            .toString();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberCheckoutPage(
          presetTokoId: _tokoId,
          presetFulfillment: _fulfillment,
          presetCourier: _courier,
          presetShippingFee: _shippingFee,
          presetCourierCompany: company.isEmpty ? null : company,
          presetCourierServiceCode:
              serviceCode.isEmpty ? null : serviceCode,
          presetCourierServiceName:
              (rate?['courier_service_name'] ?? '').toString().isEmpty
                  ? null
                  : (rate?['courier_service_name'] ?? '').toString(),
          presetShippingCategory:
              (rate?['category'] ?? '').toString().isEmpty
                  ? null
                  : (rate?['category'] ?? '').toString(),
          presetIsObr: isObr,
          presetShippingVoucherDiscount: _shippingDiscount,
          // Diskon produk wajib punya kode — tanpa kode tidak dikirim (anti bypass).
          presetProductPromoCode:
              (_productPromo?['voucher_code'] ?? '').toString().isEmpty
                  ? null
                  : (_productPromo?['voucher_code'] ?? '').toString(),
          presetProductPromoDiscount:
              (_productPromo?['voucher_code'] ?? '').toString().isEmpty
                  ? 0
                  : _productDiscount,
          useShopAddress: true,
        ),
      ),
    );
  }

  Widget _iconBadge(IconData icon, {Color? bg, Color? fg}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg ?? OptikMemberTokens.blueSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: fg ?? OptikMemberTokens.blueDeep),
    );
  }

  Widget _linkChip(String label, VoidCallback onTap) {
    return Material(
      color: OptikMemberTokens.blueSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: OptikMemberTokens.blueDeep,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (_loading) {
      return const Scaffold(
        backgroundColor: OptikMemberTokens.canvas,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: OptikMemberTokens.canvas,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(4, top + 4, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  OptikMemberTokens.blueMist,
                  OptikMemberTokens.white,
                ],
              ),
              border: Border(
                bottom: BorderSide(color: OptikMemberTokens.lineSoft),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: OptikMemberTokens.ink,
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detail pesanan',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          color: OptikMemberTokens.ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Cabang yang dipilih = yang memproses pesanan',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: OptikMemberTokens.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const _SectionLabel(
                  icon: Icons.route_outlined,
                  label: 'Pengiriman',
                ),
                const SizedBox(height: 8),
                _Card(
                  child: Column(
                    children: [
                      _RowTile(
                        leading: _iconBadge(Icons.store_mall_directory_rounded),
                        title: _cabangLabel ?? 'Pilih cabang',
                        subtitle: _storeHint ??
                            (_fulfillment == 'pickup'
                                ? 'Wajib pilih — pesanan masuk ke cabang ini'
                                : 'Setelah alamat: saran terdekat, boleh diganti'),
                        trailing: _linkChip('Ganti', _changeStore),
                      ),
                      const Divider(height: 1, color: OptikMemberTokens.lineSoft),
                      _RowTile(
                        leading: _iconBadge(
                          Icons.location_on_rounded,
                          bg: const Color(0xFFFFEBEE),
                          fg: const Color(0xFFC62828),
                        ),
                        title: _addr.isConfirmed
                            ? _addr.shortLabel
                            : (_fulfillment == 'pickup'
                                ? 'Alamat (opsional)'
                                : 'Alamat pengiriman'),
                        subtitle: _addr.isConfirmed
                            ? _addr.displayWithDetail
                            : (_fulfillment == 'pickup'
                                ? 'Opsional — untuk saran cabang terdekat'
                                : 'Wajib pilih & konfirmasi alamat Maps'),
                        trailing: _linkChip(
                          _addr.isConfirmed ? 'Ubah' : 'Pilih',
                          _pickAddress,
                        ),
                      ),
                      const Divider(height: 1, color: OptikMemberTokens.lineSoft),
                      _RowTile(
                        leading: _iconBadge(
                          _fulfillment == 'pickup'
                              ? Icons.storefront_rounded
                              : Icons.local_shipping_rounded,
                        ),
                        title: _fulfillment == 'pickup'
                            ? 'Ambil di toko'
                            : 'Kirim ke alamat',
                        subtitle: _fulfillment == 'pickup'
                            ? 'Siap diambil di cabang terpilih'
                            : (_loadingRates
                                ? 'Menghitung ongkir Biteship…'
                                : 'Kurir: $_courierTitle · ${_money.format(_shippingFee)}'),
                        onTap: _pickFulfillment,
                      ),
                      if (_fulfillment == 'delivery') ...[
                        const Divider(
                          height: 1,
                          color: OptikMemberTokens.lineSoft,
                        ),
                        _RowTile(
                          leading: _iconBadge(Icons.two_wheeler_rounded),
                          title: _loadingRates
                              ? 'Kurir (memuat tarif…)'
                              : 'Kurir · $_courierTitle',
                          subtitle: _loadingRates
                              ? 'Mengambil harga real dari Biteship…'
                              : (_rateGroups.isEmpty
                                  ? (_rateError ??
                                      'Tarif belum tersedia — cek koordinat')
                                  : _courierDetailLine),
                          trailing: (!_loadingRates &&
                                  _rateGroups.isEmpty &&
                                  _rateError != null)
                              ? _linkChip('Coba lagi', () {
                                  unawaited(_refreshShipping());
                                })
                              : null,
                          onTap: _loadingRates ? null : _pickCourier,
                        ),
                        if (_obrHint != null) ...[
                          const Divider(
                            height: 1,
                            color: OptikMemberTokens.lineSoft,
                          ),
                          _RowTile(
                            leading: _iconBadge(
                              Icons.info_outline_rounded,
                              bg: const Color(0xFFFFF7ED),
                              fg: OptikMemberTokens.warning,
                            ),
                            title: 'OBR tidak tersedia di jarak ini',
                            subtitle: _obrHint!,
                          ),
                        ],
                        if (_readyLine != null || _etaLine != null) ...[
                          const Divider(
                            height: 1,
                            color: OptikMemberTokens.lineSoft,
                          ),
                          _RowTile(
                            leading: _iconBadge(Icons.event_available_rounded),
                            title: 'Estimasi jadwal',
                            subtitle: [
                              if (_readyLine != null) _readyLine!,
                              if (_etaLine != null) _etaLine!,
                            ].join('\n'),
                          ),
                        ],
                      ],
                      const Divider(
                        height: 1,
                        color: OptikMemberTokens.lineSoft,
                      ),
                      _RowTile(
                        leading: _iconBadge(Icons.local_offer_outlined),
                        title: _shipVoucherActive || _productDiscount > 0
                            ? 'Voucher terpasang'
                            : 'Voucher',
                        subtitle: _voucherSubtitle,
                        onTap: _pickVoucher,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionLabel(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Item pesanan',
                ),
                const SizedBox(height: 8),
                _Card(
                  child: !_cart.hasSelection
                      ? Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            _cart.isEmpty
                                ? 'Keranjang kosong'
                                : 'Tidak ada item terpilih. '
                                    'Centang produk di keranjang dulu.',
                            style: const TextStyle(
                              color: OptikMemberTokens.inkMuted,
                            ),
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            final lines = _cart.selectedItems;
                            return Column(
                              children: [
                                for (var i = 0; i < lines.length; i++) ...[
                                  if (i > 0)
                                    const Divider(
                                      height: 1,
                                      color: OptikMemberTokens.lineSoft,
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      12,
                                      14,
                                      12,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: OptikMemberTokens.blueMist,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.visibility_outlined,
                                            color: OptikMemberTokens.blueDeep,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                lines[i].nama,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: OptikMemberTokens.ink,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_money.format(lines[i].harga)} · ×${lines[i].qty}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  color:
                                                      OptikMemberTokens.inkMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          _money.format(lines[i].lineTotal),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: OptikMemberTokens.blueDeep,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: OptikMemberTokens.lineSoft),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x140B3D8C),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            color: OptikMemberTokens.inkMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _money.format(_total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: OptikMemberTokens.blueDeep,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (_fulfillment == 'delivery')
                          Text(
                            _shippingDiscount > 0
                                ? 'Ongkir ${_money.format(_shippingFeePayable)} (−${_money.format(_shippingDiscount)})'
                                : 'Termasuk ongkir ${_money.format(_shippingFee)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: OptikMemberTokens.inkMuted,
                            ),
                          ),
                        if (_productDiscount > 0)
                          Text(
                            'Diskon produk −${_money.format(_productDiscount)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: OptikMemberTokens.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: OptikMemberTokens.blueDeep,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    // Tanpa alamat / error tarif: aktif → picker atau retry di _reviewOrder.
                    onPressed: _payBlocked ? null : _reviewOrder,
                    child: Text(
                      _loadingRates && _fulfillment == 'delivery'
                          ? 'Memuat tarif…'
                          : 'Lanjut bayar',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: OptikMemberTokens.blueDeep),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: OptikMemberTokens.blueDeep,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OptikMemberTokens.lineSoft),
        boxShadow: OptikMemberTokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: OptikMemberTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: OptikMemberTokens.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (onTap != null && trailing == null)
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: OptikMemberTokens.blueMist,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: OptikMemberTokens.blueDeep,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Picker kurir berkelompok (Instant / Same Day / …) ala Shopee.
class _CourierCategorySheet extends StatelessWidget {
  const _CourierCategorySheet({
    required this.groups,
    required this.selectedId,
    required this.money,
  });

  final List<Map<String, dynamic>> groups;
  final String? selectedId;
  final NumberFormat money;

  IconData _iconFor(Map<String, dynamic> o) {
    if (o['is_obr'] == true) return Icons.local_shipping_rounded;
    final c = '${o['company'] ?? ''} ${o['courier_name'] ?? ''}'.toLowerCase();
    if (c.contains('grab') || c.contains('gojek') || c.contains('paxel')) {
      return Icons.two_wheeler_outlined;
    }
    if ((o['category'] ?? '') == 'kargo') {
      return Icons.fire_truck_outlined;
    }
    return Icons.local_shipping_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.82;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: OptikMemberTokens.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: maxH,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.lineSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: OptikMemberTokens.blueSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.delivery_dining_outlined,
                          color: OptikMemberTokens.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pilih kurir',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: OptikMemberTokens.blueDeep,
                              ),
                            ),
                            Text(
                              'Barang jadi 5–7 hari · Instant/Same Day/Next Day/Reguler dihitung dari situ',
                              style: TextStyle(
                                fontSize: 12,
                                color: OptikMemberTokens.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: groups.length,
                    itemBuilder: (context, gi) {
                      final g = groups[gi];
                      final title = (g['title'] ?? '').toString();
                      final opts = (g['options'] as List?) ?? const [];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                            child: Text(
                              title.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                letterSpacing: 0.6,
                                color: OptikMemberTokens.blueDeep,
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: OptikMemberTokens.blueMist,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: OptikMemberTokens.lineSoft,
                              ),
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < opts.length; i++) ...[
                                  if (i > 0)
                                    const Divider(
                                      height: 1,
                                      color: OptikMemberTokens.lineSoft,
                                    ),
                                  Builder(
                                    builder: (_) {
                                      final raw = opts[i];
                                      if (raw is! Map) {
                                        return const SizedBox.shrink();
                                      }
                                      final o =
                                          Map<String, dynamic>.from(raw);
                                      final id = o['id']?.toString() ?? '';
                                      final selected = id == selectedId;
                                      final price =
                                          int.tryParse('${o['price']}') ?? 0;
                                      final isObr = o['is_obr'] == true;
                                      return Material(
                                        color: selected
                                            ? OptikMemberTokens.blueDeep
                                            : Colors.white,
                                        child: InkWell(
                                          onTap: () =>
                                              Navigator.pop(context, o),
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              12,
                                              12,
                                              12,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color: selected
                                                        ? Colors.white
                                                            .withValues(
                                                            alpha: 0.18,
                                                          )
                                                        : OptikMemberTokens
                                                            .blueSoft,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      10,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    _iconFor(o),
                                                    size: 18,
                                                    color: selected
                                                        ? Colors.white
                                                        : OptikMemberTokens
                                                            .blue,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        (o['label'] ??
                                                                o['courier_name'] ??
                                                                'Kurir')
                                                            .toString(),
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 14,
                                                          color: selected
                                                              ? Colors.white
                                                              : OptikMemberTokens
                                                                  .ink,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 2,
                                                      ),
                                                      Text(
                                                        (o['subtitle'] ?? '')
                                                            .toString(),
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          height: 1.3,
                                                          color: selected
                                                              ? Colors.white
                                                                  .withValues(
                                                                  alpha: 0.85,
                                                                )
                                                              : OptikMemberTokens
                                                                  .inkMuted,
                                                        ),
                                                      ),
                                                      if (isObr)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                            top: 4,
                                                          ),
                                                          child: Text(
                                                            'HEMAT Rp 2.000',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: selected
                                                                  ? Colors
                                                                      .white
                                                                  : OptikMemberTokens
                                                                      .blueDeep,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  money.format(price),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14,
                                                    color: selected
                                                        ? Colors.white
                                                        : OptikMemberTokens
                                                            .blueDeep,
                                                  ),
                                                ),
                                                if (selected) ...[
                                                  const SizedBox(width: 8),
                                                  const Icon(
                                                    Icons
                                                        .check_circle_rounded,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OptikMemberTokens.blueDeep,
                        side: const BorderSide(color: OptikMemberTokens.blue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
