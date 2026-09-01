// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/app_brand_mark.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/member/member_home_models.dart';
import '../../shared/member/member_home_rules.dart';
import '../../shared/tenant/tenant_service.dart';

InputDecoration _cmsDeco(String label, {String? helper}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    helperMaxLines: 3,
    alignLabelWithHint: true,
    floatingLabelBehavior: FloatingLabelBehavior.always,
  );
}

const _cmsFieldGap = SizedBox(height: 14);

/// CMS Member: layout hide/show, banner bergambar, promo detail (Member + POS).
class MemberHomeContentPage extends StatefulWidget {
  const MemberHomeContentPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<MemberHomeContentPage> createState() => _MemberHomeContentPageState();
}

class _MemberHomeContentPageState extends State<MemberHomeContentPage>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  late final TabController _tabs;

  final _brand = TextEditingController();
  final _greeting = TextEditingController();
  final _greetingSub = TextEditingController();
  final _promoTitle = TextEditingController();
  final _promoSub = TextEditingController();
  final List<_SlideEditors> _slides = [];
  List<Map<String, dynamic>> _sections = [];
  Map<String, bool> _flags = {};
  List<Map<String, dynamic>> _promos = [];
  /// ID promo server yang dihapus di draft — di-commit saat Update.
  final Set<String> _promoDeletedIds = {};

  bool _loading = true;
  bool _publishing = false;
  bool _ready = false;
  bool _draftDirty = false;
  /// true = Simpan sudah dikunci; tunggu tombol Update untuk push ke APK.
  bool _pendingUpdate = false;
  String? _selectedSectionKey;

  String get _defaultBrandLabel => BrandService.name;
  String get _defaultGuestHello => BrandService.guestHelloFallback();
  String get _bannerBrand =>
      _brand.text.trim().isEmpty ? _defaultBrandLabel : _brand.text.trim();
  String? _error;

  static List<Map<String, dynamic>> get _defaultSections => [
    {'key': 'hero', 'label': 'admin_mhc_section_hero'.tr(), 'visible': true, 'order': 0},
    {'key': 'greeting', 'label': 'admin_mhc_section_greeting'.tr(), 'visible': true, 'order': 1},
    {'key': 'promo', 'label': 'admin_mhc_section_promo'.tr(), 'visible': true, 'order': 2},
    {'key': 'reminders', 'label': 'admin_mhc_section_reminders'.tr(), 'visible': true, 'order': 3},
    {'key': 'store', 'label': 'admin_mhc_section_store'.tr(), 'visible': true, 'order': 4},
    {
      'key': 'services_main',
      'label': 'admin_mhc_section_services_main'.tr(),
      'visible': true,
      'order': 5
    },
    {'key': 'services_other', 'label': 'admin_mhc_section_services_other'.tr(), 'visible': true, 'order': 6},
  ];

  static Map<String, String> get _flagLabels => {
    'katalog': 'member_shop_title'.tr(),
    'janji_kontrol': 'admin_mhc_flag_janji_kontrol'.tr(),
    'resep': 'admin_mhc_flag_resep'.tr(),
    'rating': 'admin_mhc_flag_rating'.tr(),
    'notif': 'member_inbox_title'.tr(),
    'perawatan': 'admin_mhc_flag_perawatan'.tr(),
    'bentuk_wajah': 'admin_mhc_flag_bentuk_wajah'.tr(),
  };

  static const _sectionMeta = <String, ({IconData icon, String hint})>{
    'hero': (icon: Icons.image_outlined, hint: 'Banner atas beranda'),
    'greeting': (icon: Icons.waving_hand_outlined, hint: 'Sapaan + poin'),
    'promo': (
      icon: Icons.local_offer_outlined,
      hint: 'Promo live + shortcut poin'
    ),
    'reminders': (
      icon: Icons.notifications_active_outlined,
      hint: 'Status pesanan'
    ),
    'store': (icon: Icons.storefront_outlined, hint: 'Cabang saya (pilihan)'),
    'services_main': (
      icon: Icons.grid_view_rounded,
      hint: 'Belanja Online & janji kontrol'
    ),
    'services_other': (icon: Icons.apps_outlined, hint: 'Menu sekunder'),
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    for (final c in [
      _brand,
      _greeting,
      _greetingSub,
      _promoTitle,
      _promoSub,
    ]) {
      c.addListener(_refreshPreview);
    }
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    if (role != 'owner' && role != 'admin_pusat' && role != 'super_admin') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('admin_auto_fbb4dba519'.tr()),
            backgroundColor: OptikAdminTokens.danger,
          ),
        );
        Navigator.pop(context);
      });
      return;
    }
    _load();
  }

  void _refreshPreview() {
    if (!mounted) return;
    setState(() {
      if (_ready) {
        _draftDirty = true;
        _pendingUpdate = false;
      }
    });
  }

  void _markDraft([VoidCallback? mutate]) {
    setState(() {
      mutate?.call();
      if (_ready) {
        _draftDirty = true;
        _pendingUpdate = false;
      }
    });
  }

  bool get _hasUnpublishedWork => _draftDirty || _pendingUpdate;

  void _selectSection(String key) {
    setState(() => _selectedSectionKey = key);
    // Ketuk section di HP → pastikan tab Tata letak (inspector) terbuka.
    if (_tabs.index != 0) {
      _tabs.animateTo(0);
    }
  }

  void _wireSlideListeners() {
    for (final s in _slides) {
      s.titleCtrl.removeListener(_refreshPreview);
      s.subtitleCtrl.removeListener(_refreshPreview);
      s.titleCtrl.addListener(_refreshPreview);
      s.subtitleCtrl.addListener(_refreshPreview);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _brand,
      _greeting,
      _greetingSub,
      _promoTitle,
      _promoSub,
    ]) {
      c.removeListener(_refreshPreview);
      c.dispose();
    }
    for (final s in _slides) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      // Cegah listener controller menandai draft kotor saat isi ulang dari server.
      _ready = false;
      _draftDirty = false;
      _pendingUpdate = false;
    });
    try {
      final row = await _db
          .from('member_home_content')
          .select()
          .eq('tenant_id', TenantService.instance.boundId)
          .maybeSingle();
      final data =
          row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row);

      final brand =
          (data['brand_label'] ?? _defaultBrandLabel).toString();
      final greeting =
          (data['greeting_guest'] ?? _defaultGuestHello).toString();
      final greetingSub = (data['greeting_subtitle_guest'] ??
              'Login untuk lihat pesanan & garansi')
          .toString();
      final promoTitle =
          (data['promo_title'] ?? 'Promo & poin').toString();
      final promoSub =
          (data['promo_subtitle'] ?? 'Voucher dan saldo poin kamu')
              .toString();

      var slidesList = <dynamic>[];
      final rawSlides = data['slides'];
      if (rawSlides is List) {
        slidesList = rawSlides;
      } else if (rawSlides is String && rawSlides.isNotEmpty) {
        slidesList = jsonDecode(rawSlides) as List;
      }
      if (slidesList.isEmpty) {
        slidesList = [
          {
            'title': 'admin_auto_kacamata_siap_title'.tr(),
            'subtitle': 'admin_auto_c8dae62f61'.tr(),
            'image_url': '',
          },
          {
            'title': 'admin_mhc_slide2_title'.tr(namedArgs: {'brand': BrandService.name}),
            'subtitle': 'admin_mhc_slide2_sub'.tr(),
            'image_url': '',
          },
        ];
      }
      final newSlides = <_SlideEditors>[];
      for (final s in slidesList) {
        final m = Map<String, dynamic>.from(s as Map);
        newSlides.add(_SlideEditors(
          title: (m['title'] ?? '').toString(),
          subtitle: (m['subtitle'] ?? '').toString(),
          imageUrl: (m['image_url'] ?? '').toString(),
        ));
      }

      final newSections = _parseSections(data['sections']);
      final newFlags = _parseFlags(data['feature_flags']);

      List<Map<String, dynamic>> newPromos = const [];
      try {
        newPromos = await _loadPromoRows();
      } catch (_) {
        newPromos = [];
      }

      if (!mounted) {
        for (final s in newSlides) {
          s.dispose();
        }
        return;
      }

      // Swap hanya setelah fetch sukses — gagal reload tidak mengosongkan draft.
      for (final s in _slides) {
        s.dispose();
      }
      _slides
        ..clear()
        ..addAll(newSlides);
      _wireSlideListeners();

      _brand.text = brand;
      _greeting.text = greeting;
      _greetingSub.text = greetingSub;
      _promoTitle.text = promoTitle;
      _promoSub.text = promoSub;
      _sections = newSections;
      _flags = newFlags;
      _promos = newPromos;
      _promoDeletedIds.clear();

      setState(() {
        _loading = false;
        _ready = true;
        _draftDirty = false;
        _pendingUpdate = false;
        _selectedSectionKey ??= 'hero';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
        // Tetap ready agar draft lokal / tombol Coba lagi tidak stuck.
        _ready = true;
      });
    }
  }

  bool _isDraftPromoId(dynamic id) {
    final s = id?.toString() ?? '';
    return s.isEmpty || s.startsWith('draft_');
  }

  List<Map<String, dynamic>> _parseSections(dynamic raw) {
    final defaultsByKey = {
      for (final e in _defaultSections) (e['key'] ?? '').toString(): e,
    };
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final key = (m['key'] ?? '').toString();
        final def = defaultsByKey[key];
        if (def != null) {
          // Label CMS selalu ikut copy terbaru (key tetap kontrak app).
          m['label'] = def['label'];
        }
        list.add(m);
      }
    }
    if (list.isEmpty) {
      return _defaultSections
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    // Pastikan section baru (jika ada) ikut masuk.
    for (final def in _defaultSections) {
      final key = (def['key'] ?? '').toString();
      if (list.every((s) => (s['key'] ?? '') != key)) {
        list.add(Map<String, dynamic>.from(def));
      }
    }
    list.sort((a, b) => ((a['order'] as num?)?.toInt() ?? 0)
        .compareTo((b['order'] as num?)?.toInt() ?? 0));
    return list;
  }

  Map<String, bool> _parseFlags(dynamic raw) {
    final out = <String, bool>{
      for (final k in _flagLabels.keys) k: true,
    };
    if (raw is Map) {
      for (final e in raw.entries) {
        out[e.key.toString()] = e.value == true;
      }
    }
    return out;
  }

  static const _promoPageSize = 500;

  Future<List<Map<String, dynamic>>> _loadPromoRows() async {
    final tenant = TenantService.instance.boundId;
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final chunk = await _db
          .from('member_promos')
          .select()
          .eq('tenant_id', tenant)
          .order('sort_order')
          .order('created_at', ascending: false)
          .range(offset, offset + _promoPageSize - 1);
      final rows = (chunk as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      out.addAll(rows);
      if (rows.length < _promoPageSize) break;
      offset += _promoPageSize;
    }
    return out;
  }

  Future<String?> _uploadBanner(Uint8List bytes, String name) async {
    final path = MemberHomeRules.bannerObjectPath(
      tenantId: TenantService.instance.boundId,
      fileName: name,
    );
    await _db.storage.from('Foto Frame').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    return _db.storage.from('Foto Frame').getPublicUrl(path);
  }

  Future<void> _pickSlideImage(int index) async {
    if (index < 0 || index >= _slides.length) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final url = await _uploadBanner(bytes, file.name);
      if (!mounted) return;
      if (index < 0 || index >= _slides.length) return;
      _markDraft(() => _slides[index].imageUrl = url ?? '');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('admin_auto_0dde50f348'.tr(namedArgs: {'error': '$e'}))),
      );
    }
  }

  List<Map<String, dynamic>> _collectSlidesOrThrow() {
    final slides = _slides
        .map((s) => {
              'title': s.titleCtrl.text.trim(),
              'subtitle': s.subtitleCtrl.text.trim(),
              'image_url': s.imageUrl.trim(),
            })
        .where((s) => (s['title'] as String).isNotEmpty)
        .toList();
    if (slides.isEmpty) {
      throw Exception('Minimal 1 slide banner dengan judul.');
    }
    return slides;
  }

  /// Simpan = kunci draft lokal. Belum menyentuh APK / server home.
  Future<void> _saveDraft() async {
    if (_publishing) return;
    try {
      _collectSlidesOrThrow();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('admin_auto_564b2dc6f1'.tr(namedArgs: {'error': '$e'})),
          backgroundColor: OptikAdminTokens.warning,
        ),
      );
      return;
    }
    if (!_draftDirty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('admin_auto_07b5ee28fa'.tr()),
        content: Text('admin_auto_7175bb3a6d'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('appr_btn_batal'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('admin_auto_fb9c77167e'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    for (var i = 0; i < _sections.length; i++) {
      _sections[i]['order'] = i;
    }
    setState(() {
      _draftDirty = false;
      _pendingUpdate = true;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('admin_gl_row_5ba088f5bf'.tr()),
        backgroundColor: OptikAdminTokens.warning,
      ),
    );
  }

  Map<String, dynamic> _homeContentPayload(List<Map<String, dynamic>> slides) {
    for (var i = 0; i < _sections.length; i++) {
      _sections[i]['order'] = i;
    }
    // Salin JSON-safe agar upsert tidak gagal karena referensi mutable.
    final sectionsJson = jsonDecode(jsonEncode(_sections)) as List<dynamic>;
    final flagsJson =
        jsonDecode(jsonEncode(_flags)) as Map<String, dynamic>;
    return {
      'id': TenantService.instance.boundId == TenantService.optikId
          ? 'default'
          : TenantService.instance.boundId,
      'tenant_id': TenantService.instance.boundId,
      'brand_label': _bannerBrand,
      'slides': slides,
      'greeting_guest': _greeting.text.trim(),
      'greeting_subtitle_guest': _greetingSub.text.trim(),
      'promo_title': _promoTitle.text.trim(),
      'promo_subtitle': _promoSub.text.trim(),
      'sections': sectionsJson,
      'feature_flags': flagsJson,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _promoDbPayload(Map<String, dynamic> p) {
    final payload = <String, dynamic>{
      'tenant_id': TenantService.instance.boundId,
      'title': (p['title'] ?? '').toString().trim(),
      'description': (p['description'] ?? '').toString(),
      'voucher_code': () {
        final c = (p['voucher_code'] ?? '').toString().trim();
        return c.isEmpty ? null : c.toUpperCase();
      }(),
      'points_cost': MemberHomeRules.moneyOf(p['points_cost']),
      'quantity': MemberHomeRules.optionalCount(p['quantity']),
      'quantity_remaining': MemberHomeRules.optionalCount(p['quantity_remaining']),
      'discount_type': (p['discount_type'] ?? 'nominal').toString(),
      'discount_value': MemberHomeRules.moneyOf(p['discount_value']),
      'show_on_member': p['show_on_member'] != false,
      'show_on_pos': p['show_on_pos'] != false,
      'active': p['active'] != false,
      'sort_order': MemberHomeRules.countOf(p['sort_order']),
      'terms': () {
        final t = (p['terms'] ?? '').toString().trim();
        return t.isEmpty ? null : t;
      }(),
      'image_url': () {
        final u = (p['image_url'] ?? '').toString().trim();
        return u.isEmpty ? null : u;
      }(),
      'valid_until': p['valid_until'],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    return payload;
  }

  /// Update = push draft yang sudah di-Simpan ke APK (server).
  Future<void> _publishToApk() async {
    if (_publishing) return;
    if (_draftDirty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('admin_auto_b2bf716b54'.tr()),
          backgroundColor: OptikAdminTokens.warning,
        ),
      );
      return;
    }
    if (!_pendingUpdate) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('admin_auto_62dcf584da'.tr()),
        content: Text('admin_gl_row_091abb59d1'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('appr_btn_batal'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('dash_menu_update_apk'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _publishing = true);
    var homeOk = false;
    var promoOk = false;
    try {
      final slides = _collectSlidesOrThrow();
      await _db.from('member_home_content').upsert(_homeContentPayload(slides));
      homeOk = true;

      await _commitPromoDrafts();
      promoOk = true;

      if (!mounted) return;
      setState(() {
        _pendingUpdate = false;
        _draftDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('admin_auto_d80b7d9188'.tr()),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      // Reload terpisah: gagal refresh UI jangan dianggap gagal Update.
      try {
        await _load();
      } catch (e) {
        debugPrint('reload after publish: $e');
        if (mounted) {
          setState(() {
            _loading = false;
            _ready = true;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      final msg = !homeOk
          ? 'Gagal update APK: $e'
          : !promoOk
              ? 'Layout sudah ter-update, tapi promo gagal: $e'
              : 'Gagal update APK: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: OptikAdminTokens.danger),
      );
      if (homeOk) {
        setState(() {
          _pendingUpdate = false;
          _draftDirty = !promoOk;
        });
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  /// Hanya promo yang diubah/dihapus di draft — aman di-retry jika gagal di tengah.
  Future<void> _commitPromoDrafts() async {
    // Hapus dulu — tiap sukses langsung lepas dari set agar tidak dobel.
    for (final id in _promoDeletedIds.toList(growable: false)) {
      if (_isDraftPromoId(id)) {
        _promoDeletedIds.remove(id);
        continue;
      }
      await _db.from('member_promos').delete().eq('id', id);
      _promoDeletedIds.remove(id);
    }

    // Insert draft baru. Tanpa .select(): insert sukses + select gagal
    // dulu bisa meninggalkan draft_* → retry dobel. Setelah insert OK,
    // id lokal diganti non-draft; reload berikutnya sync id server.
    for (final p in _promos.where((e) => _isDraftPromoId(e['id'])).toList()) {
      await _db.from('member_promos').insert(_promoDbPayload(p));
      p['id'] = 'synced_${DateTime.now().microsecondsSinceEpoch}';
      p.remove('_draft');
    }

    // Update hanya yang diedit di draft.
    for (final p in _promos
        .where((e) =>
            e['_draft'] == true &&
            !_isDraftPromoId(e['id']) &&
            (e['id']?.toString().isNotEmpty ?? false))
        .toList()) {
      await _db
          .from('member_promos')
          .update(_promoDbPayload(p))
          .eq('id', p['id']);
      p.remove('_draft');
    }
  }

  Future<void> _discardDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('admin_auto_c3a435b8c8'.tr()),
        content: Text('admin_gl_row_1b72c272e8'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('appr_btn_batal'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('admin_auto_4880e310e3'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _load();
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (!_hasUnpublishedWork) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('admin_auto_9f59e9bc60'.tr()),
        content: Text(
          _pendingUpdate && !_draftDirty
              ? 'Draft sudah di-Simpan tapi belum di-Update ke APK. Keluar dan buang?'
              : 'Ada draft yang belum di-Update ke APK. Keluar dan buang?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('admin_auto_186d712a62'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('admin_auto_1c72019858'.tr()),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _moveSection(String key, int delta) {
    final i = _sections.indexWhere((s) => (s['key'] ?? '') == key);
    if (i < 0) return;
    final j = i + delta;
    if (j < 0 || j >= _sections.length) return;
    _markDraft(() {
      final item = _sections.removeAt(i);
      _sections.insert(j, item);
      for (var n = 0; n < _sections.length; n++) {
        _sections[n]['order'] = n;
      }
    });
  }

  Map<String, dynamic>? _sectionByKey(String key) {
    for (final s in _sections) {
      if ((s['key'] ?? '') == key) return s;
    }
    return null;
  }

  Future<void> _editPromo([Map<String, dynamic>? existing]) async {
    final isNew = existing == null;
    final title = TextEditingController(text: existing?['title']?.toString());
    final desc =
        TextEditingController(text: existing?['description']?.toString());
    final code =
        TextEditingController(text: existing?['voucher_code']?.toString());
    final points =
        TextEditingController(text: '${existing?['points_cost'] ?? 0}');
    final qty =
        TextEditingController(text: existing?['quantity']?.toString() ?? '');
    final qtyLeft = TextEditingController(
        text: existing?['quantity_remaining']?.toString() ?? '');
    final discVal =
        TextEditingController(text: '${existing?['discount_value'] ?? 0}');
    final terms = TextEditingController(text: existing?['terms']?.toString());
    final sort =
        TextEditingController(text: '${existing?['sort_order'] ?? 0}');
    var discType = (existing?['discount_type'] ?? 'nominal').toString();
    var active = existing?['active'] != false;
    var onMember = existing?['show_on_member'] != false;
    var onPos = existing?['show_on_pos'] != false;
    var imageUrl = (existing?['image_url'] ?? '').toString();
    DateTime? validUntil;
    final vu = existing?['valid_until']?.toString();
    if (vu != null && vu.isNotEmpty) {
      validUntil = DateTime.tryParse(vu);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: OptikAdminTokens.card,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: OptikAdminTokens.chromeEdge),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
            ),
            child: _cmsThemed(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 12, 8),
                    child: Row(
                      children: [
                        PremiumIconBadge(
                          icon: Icons.local_offer_outlined,
                          color: OptikAdminTokens.navy,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isNew ? 'Tambah promo' : 'Edit promo',
                            style: TextStyle(
                              color: OptikAdminTokens.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: Icon(
                            Icons.close_rounded,
                            color: OptikAdminTokens.slate,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _cmsEyebrow('Identitas'),
                          TextField(
                            controller: title,
                            decoration: _cmsDeco('Judul *'),
                          ),
                          _cmsFieldGap,
                          TextField(
                            controller: desc,
                            maxLines: 2,
                            decoration: _cmsDeco('Deskripsi'),
                          ),
                          _cmsFieldGap,
                          TextField(
                            controller: code,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _cmsDeco(
                              'Kode voucher *',
                              helper:
                                  'Wajib jika Nominal/Persen. Dipakai redeem kuota/poin di POS & Belanja Online.',
                            ),
                          ),
                          const SizedBox(height: 8),
                          _cmsEyebrow('Diskon & kuota'),
                          AdminPickerField(
                            label: 'admin_auto_ae15fa1f5b'.tr(),
                            valueText: switch (discType) {
                              'percent' => 'Persen (%)',
                              'info' => 'Info saja (tanpa potong POS)',
                              _ => 'Nominal (Rp)',
                            },
                            icon: Icons.discount_outlined,
                            onTap: () async {
                              final options = [
                                AdminPickerOption(
                                  value: 'nominal',
                                  label: 'admin_lbl_nominal_rp'.tr(),
                                  icon: Icons.payments_outlined,
                                ),
                                AdminPickerOption(
                                  value: 'percent',
                                  label: 'admin_auto_b895a4d7da'.tr(),
                                  icon: Icons.percent_rounded,
                                ),
                                AdminPickerOption(
                                  value: 'info',
                                  label: 'admin_auto_700e8db6fa'.tr(),
                                  icon: Icons.info_outline_rounded,
                                ),
                              ];
                              final sel = await showAdminPicker<String>(
                                context: ctx,
                                title: 'admin_auto_ae15fa1f5b'.tr(),
                                selected: discType,
                                searchable: false,
                                options: options,
                              );
                              if (sel == null || sel.isClear) return;
                              setLocal(() => discType = sel.value!);
                            },
                          ),
                          _cmsFieldGap,
                          TextField(
                            controller: discVal,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: _cmsDeco('Nilai diskon (Rp atau %)'),
                          ),
                          _cmsFieldGap,
                          TextField(
                            controller: points,
                            keyboardType: TextInputType.number,
                            decoration: _cmsDeco('Biaya poin Member'),
                          ),
                          _cmsFieldGap,
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: qty,
                                  keyboardType: TextInputType.number,
                                  decoration:
                                      _cmsDeco('Kuota total (kosong=∞)'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: qtyLeft,
                                  keyboardType: TextInputType.number,
                                  decoration: _cmsDeco('Sisa kuota'),
                                ),
                              ),
                            ],
                          ),
                          _cmsFieldGap,
                          TextField(
                            controller: sort,
                            keyboardType: TextInputType.number,
                            decoration: _cmsDeco('Urutan tampil'),
                          ),
                          _cmsFieldGap,
                          TextField(
                            controller: terms,
                            maxLines: 2,
                            decoration: _cmsDeco('Syarat & ketentuan'),
                          ),
                          const SizedBox(height: 8),
                          _cmsEyebrow('Tayang'),
                          _cmsSoftCard(
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    validUntil == null
                                        ? 'Tanpa tanggal habis'
                                        : 'Berlaku s/d ${validUntil!.toLocal().toString().substring(0, 10)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  trailing: TextButton(
                                    onPressed: () async {
                                      final d = await showDatePicker(
                                        context: ctx,
                                        firstDate: DateTime(2024),
                                        lastDate: DateTime(2100),
                                        initialDate:
                                            validUntil ?? DateTime.now(),
                                      );
                                      if (d != null) {
                                        setLocal(() => validUntil = d);
                                      }
                                    },
                                    child: Text('admin_btn_pilih'.tr()),
                                  ),
                                ),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('admin_lbl_aktif'.tr()),
                                  value: active,
                                  onChanged: (v) =>
                                      setLocal(() => active = v),
                                ),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('admin_auto_d1ce83b6e9'.tr()),
                                  value: onMember,
                                  onChanged: (v) =>
                                      setLocal(() => onMember = v),
                                ),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('admin_auto_f82ba34521'.tr()),
                                  value: onPos,
                                  onChanged: (v) => setLocal(() => onPos = v),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final file = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                  maxWidth: 1200,
                                  imageQuality: 85,
                                );
                                if (file == null) return;
                                final bytes = await file.readAsBytes();
                                try {
                                  final url =
                                      await _uploadBanner(bytes, file.name);
                                  setLocal(() => imageUrl = url ?? '');
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('admin_auto_0dde50f348'.tr(namedArgs: {'error': '$e'}))),
                                  );
                                }
                              },
                              child: Ink(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: OptikAdminTokens.ice.withOpacity(0.3),
                                  border: Border.all(
                                    color: OptikAdminTokens.chromeEdge,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    if (imageUrl.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          imageUrl,
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    else
                                      PremiumIconBadge(
                                        icon: Icons.image_outlined,
                                        color: OptikAdminTokens.navy,
                                        size: 44,
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            imageUrl.isEmpty
                                                ? 'Gambar promo'
                                                : 'Ganti gambar',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: OptikAdminTokens.navy,
                                            ),
                                          ),
                                          Text(
                                            'JPG/PNG · tampil di kartu beranda Member',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: OptikAdminTokens.slate,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: OptikAdminTokens.slate,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('appr_btn_batal'.tr()),
                        ),
                        const Spacer(),
                        PremiumPrimaryButton(
                          expand: false,
                          label: 'admin_auto_a8b888bfb3'.tr(),
                          onPressed: () => Navigator.pop(ctx, true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;
    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('admin_auto_7ad7078762'.tr())),
      );
      return;
    }
    if (discType != 'info' && code.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('admin_auto_d171181a04'.tr()),
          backgroundColor: OptikAdminTokens.warning,
        ),
      );
      return;
    }
    if (!MemberHomeRules.promoDiscountValueOk(discType, discVal.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('admin_auto_b140f08203'.tr()),
          backgroundColor: OptikAdminTokens.warning,
        ),
      );
      return;
    }

    final payload = <String, dynamic>{
      'title': title.text.trim(),
      'description': desc.text.trim(),
      'voucher_code': code.text.trim().isEmpty
          ? null
          : code.text.trim().toUpperCase(),
      'points_cost': MemberHomeRules.moneyOf(points.text),
      'quantity': MemberHomeRules.optionalCount(qty.text),
      'quantity_remaining': MemberHomeRules.optionalCount(
        qtyLeft.text.isEmpty ? qty.text : qtyLeft.text,
      ),
      'discount_type': discType,
      'discount_value': MemberHomeRules.moneyOf(discVal.text),
      'show_on_member': onMember,
      'show_on_pos': onPos,
      'active': active,
      'sort_order': MemberHomeRules.countOf(sort.text),
      'terms': terms.text.trim().isEmpty ? null : terms.text.trim(),
      'image_url': imageUrl.isEmpty ? null : imageUrl,
      'valid_until': validUntil?.toIso8601String().substring(0, 10),
      '_draft': true,
    };

    _markDraft(() {
      if (isNew) {
        _promos.insert(0, {
          ...payload,
          'id': 'draft_${DateTime.now().microsecondsSinceEpoch}',
        });
      } else {
        final i = _promos.indexWhere((e) => e['id'] == existing['id']);
        if (i >= 0) {
          _promos[i] = {...existing, ...payload, 'id': existing['id']};
        }
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('admin_auto_5d6e0228d6'.tr()),
        backgroundColor: OptikAdminTokens.warning,
      ),
    );
  }

  Future<void> _deletePromo(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('admin_auto_6fa2cf0781'.tr()),
        content: Text(
          'Hapus "${p['title']}"? Baru hilang dari APK setelah Update.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('appr_btn_batal'.tr())),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('btn_hapus'.tr())),
        ],
      ),
    );
    if (ok != true) return;
    final id = p['id']?.toString();
    _markDraft(() {
      _promos.removeWhere((e) => e['id'] == p['id']);
      if (id != null && !_isDraftPromoId(id)) {
        _promoDeletedIds.add(id);
      }
    });
  }

  void _openPreview() {
    showDialog(
      context: context,
      barrierColor: OptikAdminTokens.navy.withOpacity(0.72),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.9;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
            child: Material(
              color: OptikAdminTokens.bgMid,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: OptikAdminTokens.accentGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.phone_iphone_rounded,
                              size: 18, color: OptikAdminTokens.navy),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Preview APK Member',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Begini bentukan beranda di HP member',
                                style: TextStyle(
                                  color: OptikAdminTokens.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Center(
                            child: _buildPhonePreview(interactive: false)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _pendingUpdate && !_draftDirty
                          ? 'Draft siap Update — belum ke APK sampai Update ditekan.'
                          : _draftDirty
                              ? 'Preview draft lokal — tekan Simpan lalu Update ke APK.'
                              : 'Preview sesuai data yang sedang di editor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: OptikAdminTokens.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhonePreview({bool interactive = false}) {
    final memberPromos = _promos
        .where((p) =>
            p['active'] != false &&
            p['show_on_member'] != false)
        .toList();
    return _MemberHomePhonePreview(
      brand: _bannerBrand,
      greeting: _greeting.text.trim().isEmpty
          ? _defaultGuestHello
          : _greeting.text.trim(),
      greetingSub: _greetingSub.text.trim().isEmpty
          ? 'Login untuk lihat pesanan & garansi'
          : _greetingSub.text.trim(),
      promoTitle: _promoTitle.text.trim().isEmpty
          ? 'Promo & poin'
          : _promoTitle.text.trim(),
      promoSub: _promoSub.text.trim().isEmpty
          ? 'Voucher dan saldo poin kamu'
          : _promoSub.text.trim(),
      slides: _slides
          .map((s) => (
                title: s.titleCtrl.text,
                subtitle: s.subtitleCtrl.text,
                imageUrl: s.imageUrl,
              ))
          .where((s) => s.title.trim().isNotEmpty)
          .toList(),
      sections: _sections,
      flags: _flags,
      promoPreviews: memberPromos
          .take(6)
          .map((p) => (
                title: (p['title'] ?? 'admin_lbl_promo_fallback'.tr()).toString(),
                label: _promoDiscountPreview(p),
                code: (p['voucher_code'] ?? '').toString(),
              ))
          .toList(),
      interactive: interactive,
      selectedKey: _selectedSectionKey,
      onSectionTap: interactive ? _selectSection : null,
      onSectionLongPress: interactive
          ? (key) => _showReorderSheet(key)
          : null,
      draftBadge: _hasUnpublishedWork,
      pendingUpdate: _pendingUpdate && !_draftDirty,
      selectedLabel: () {
        final k = _selectedSectionKey;
        if (k == null) return null;
        return (_sectionByKey(k)?['label'] ?? k).toString();
      }(),
    );
  }

  Future<void> _showReorderSheet(String key) async {
    _selectSection(key);
    final label = (_sectionByKey(key)?['label'] ?? key).toString();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Urutan: $label',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Long-press di preview untuk ubah urutan section.',
                style: TextStyle(
                  color: OptikAdminTokens.textMuted,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _moveSection(key, -1);
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.arrow_upward_rounded),
                      label: Text('admin_btn_naik'.tr()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _moveSection(key, 1);
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.arrow_downward_rounded),
                      label: Text('admin_btn_turun'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _promoDiscountPreview(Map<String, dynamic> p) =>
      MemberHomeSnapshot.promoDiscountLabel(p);

  Widget _cmsThemed({required Widget child}) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: OptikAdminTokens.card,
          contentPadding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        ),
      ),
      child: child,
    );
  }

  Widget _cmsEyebrow(String label) {
    return PremiumSectionHeader(
      label: label,
      padding: const EdgeInsets.only(bottom: 12, top: 6),
    );
  }

  Widget _cmsSoftCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.fromLTRB(14, 4, 14, 8),
      decoration: BoxDecoration(
        color: OptikAdminTokens.ice.withOpacity(
          OptikAdminTokens.isKombo ? 0.5 : 0.34,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: OptikAdminTokens.chromeEdge.withOpacity(0.72),
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnpublishedWork && !_publishing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _publishing) return;
        final leave = await _confirmLeaveIfDirty();
        if (leave && context.mounted) Navigator.pop(context);
      },
      child: PremiumScaffold(
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildTopBar(),
              if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: _buildTabBar(),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _buildError()
                        : _cmsThemed(
                            child: TabBarView(
                              controller: _tabs,
                              children: [
                                _buildLayoutTab(),
                                _buildBannerTab(),
                                _buildPromoTab(),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final statusChip = !_hasUnpublishedWork
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (_pendingUpdate && !_draftDirty
                      ? OptikAdminTokens.accent
                      : OptikAdminTokens.warning)
                  .withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: (_pendingUpdate && !_draftDirty
                        ? OptikAdminTokens.navy
                        : OptikAdminTokens.warning)
                    .withOpacity(0.45),
              ),
            ),
            child: Text(
              _pendingUpdate && !_draftDirty ? 'SIAP UPDATE' : 'DRAFT',
              style: TextStyle(
                color: _pendingUpdate && !_draftDirty
                    ? OptikAdminTokens.navy
                    : OptikAdminTokens.warning,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Konten Home Member',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  _draftDirty
                      ? 'Draft di preview · tekan Simpan (belum ke APK)'
                      : _pendingUpdate
                          ? 'Draft siap · tekan Update untuk apply ke APK'
                          : 'Simpan dulu, lalu Update supaya APK Member ikut',
                  style: TextStyle(
                    color: _hasUnpublishedWork
                        ? OptikAdminTokens.warning
                        : OptikAdminTokens.textMuted,
                    fontSize: 11.5,
                    fontWeight: _hasUnpublishedWork
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (statusChip != null) ...[
            statusChip,
            const SizedBox(width: 8),
          ],
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasUnpublishedWork)
                    TextButton(
                      onPressed:
                          _loading || _publishing ? null : _discardDraft,
                      child: Text('admin_auto_c02364c24d'.tr()),
                    ),
                  IconButton(
                    tooltip: 'admin_auto_e928402a95'.tr(),
                    onPressed: _publishing ? null : _openPreview,
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    onPressed: _loading || _publishing || !_draftDirty
                        ? null
                        : _saveDraft,
                    child: Text('btn_simpan'.tr()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _loading ||
                            _publishing ||
                            _draftDirty ||
                            !_pendingUpdate
                        ? null
                        : _publishToApk,
                    child: _publishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('admin_btn_update'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: OptikAdminTokens.panel.withOpacity(0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: TabBar(
        controller: _tabs,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: OptikAdminTokens.accentGradient,
        ),
        labelColor: OptikAdminTokens.snow,
        unselectedLabelColor: OptikAdminTokens.textMuted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        tabs: const [
          Tab(text: 'Tata letak'),
          Tab(text: 'Banner'),
          Tab(text: 'Promo'),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: PremiumPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 40, color: OptikAdminTokens.warning),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text('common_retry'.tr())),
              const SizedBox(height: 8),
              Text(
                'Jalankan migration:\n'
                '20260728000001_member_home_content.sql\n'
                '20260728000002_member_cms_layout_promo.sql',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: OptikAdminTokens.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: OptikAdminTokens.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: OptikAdminTokens.navy),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                Text(subtitle,
                    style: TextStyle(
                        color: OptikAdminTokens.textMuted,
                        fontSize: 12.5,
                        height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutTab() {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final phone = _buildPhonePreview(interactive: true);
    final inspector = _buildSectionInspector();

    if (!wide) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(child: phone),
          const SizedBox(height: 16),
          inspector,
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: PremiumPanel(
              padding: EdgeInsets.zero,
              borderRadius: 22,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                    child: Row(
                      children: [
                        PremiumIconBadge(
                          icon: Icons.touch_app_rounded,
                          size: 36,
                          color: OptikAdminTokens.navy,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Ketuk bagian di HP untuk membuka setting',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _openPreview,
                          child: Text('admin_btn_fullscreen'.tr()),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: phone,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 6, child: inspector),
        ],
      ),
    );
  }

  Widget _buildSectionInspector() {
    final key = _selectedSectionKey ?? 'hero';
    final section = _sectionByKey(key);
    final meta = _sectionMeta[key];
    final label = (section?['label'] ?? meta?.hint ?? key).toString();
    final visible = section?['visible'] != false;
    final idx = _sections.indexWhere((s) => (s['key'] ?? '') == key);

    return PremiumPanel(
      showAccentBar: true,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 12),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 16),
        children: [
          _sectionHeader(
            'Mengatur: $label',
            'Edit = draft. Simpan = kunci draft. Update = apply ke APK.',
            icon: meta?.icon ?? Icons.tune_rounded,
          ),
          PremiumChipWrap(
            children: [
              for (final s in _sections)
                FilterChip(
                  showCheckmark: false,
                  selected: (s['key'] ?? '') == key,
                  label: Text(
                    (s['label'] ?? s['key']).toString(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: (s['key'] ?? '') == key
                          ? OptikAdminTokens.onHighlight
                          : OptikAdminTokens.navy,
                    ),
                  ),
                  selectedColor: OptikAdminTokens.navy,
                  backgroundColor: OptikAdminTokens.ice.withOpacity(0.4),
                  side: BorderSide(
                    color: (s['key'] ?? '') == key
                        ? OptikAdminTokens.navy
                        : OptikAdminTokens.chromeEdge,
                  ),
                  onSelected: (_) =>
                      _selectSection((s['key'] ?? '').toString()),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (section != null) ...[
            _cmsSoftCard(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Tampil di beranda',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: Text(visible
                    ? 'Section ini muncul di APK (setelah Update)'
                    : 'Disembunyikan dari beranda'),
                value: visible,
                onChanged: (v) => _markDraft(() => section['visible'] = v),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: idx <= 0 ? null : () => _moveSection(key, -1),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: Text('admin_btn_naik'.tr()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: idx < 0 || idx >= _sections.length - 1
                        ? null
                        : () => _moveSection(key, 1),
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    label: Text('admin_btn_turun'.tr()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _cmsEyebrow('Isi section'),
          ],
          ..._inspectorFieldsFor(key),
        ],
      ),
    );
  }

  List<Widget> _inspectorFieldsFor(String key) {
    switch (key) {
      case 'hero':
        return [
          TextField(
            controller: _brand,
            decoration: _cmsDeco(
              'Label brand di banner',
              helper: _defaultBrandLabel,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Slide banner',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _slides.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PremiumPanel(
                showAccentBar: true,
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 14),
                borderRadius: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Row(
                    children: [
                      Text(
                        'Slide ${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      if (_slides.length > 1)
                        IconButton(
                          tooltip: 'admin_auto_c733f62af8'.tr(),
                          onPressed: () => _markDraft(() {
                            _slides[i].dispose();
                            _slides.removeAt(i);
                          }),
                          icon: const Icon(Icons.delete_outline,
                              color: OptikAdminTokens.danger, size: 20),
                        ),
                    ],
                  ),
                  if (_slides[i].imageUrl.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _slides[i].imageUrl,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox(height: 80),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickSlideImage(i),
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: Text('admin_auto_5b891268ee'.tr()),
                      ),
                      if (_slides[i].imageUrl.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              _markDraft(() => _slides[i].imageUrl = ''),
                          child: Text('admin_auto_e1d5663fd3'.tr()),
                        ),
                    ],
                  ),
                  _cmsFieldGap,
                  TextField(
                    controller: _slides[i].titleCtrl,
                    maxLines: 2,
                    decoration: _cmsDeco('Judul'),
                  ),
                  _cmsFieldGap,
                  TextField(
                    controller: _slides[i].subtitleCtrl,
                    maxLines: 2,
                    decoration: _cmsDeco('Subtitle'),
                  ),
                ],
              ),
            ),
            ),
          ],
          OutlinedButton.icon(
            onPressed: () => _markDraft(() {
              _slides.add(
                  _SlideEditors(title: '', subtitle: '', imageUrl: ''));
              _wireSlideListeners();
            }),
            icon: const Icon(Icons.add),
            label: Text('admin_auto_d8a386f75e'.tr()),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _tabs.animateTo(1),
            child: Text('admin_auto_23a9b62203'.tr()),
          ),
        ];
      case 'greeting':
        return [
          TextField(
            controller: _greeting,
            decoration:
                InputDecoration(labelText: 'admin_auto_da57bf579e'.tr()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _greetingSub,
            decoration: InputDecoration(labelText: 'admin_auto_e7e900d8ca'.tr()),
          ),
          const SizedBox(height: 8),
          Text(
            'Poin / Pesanan / Garansi diisi otomatis dari data Member (live di APK).',
            style: TextStyle(
              color: OptikAdminTokens.textMuted,
              fontSize: 12.5,
            ),
          ),
        ];
      case 'promo':
        return [
          TextField(
            controller: _promoTitle,
            decoration: InputDecoration(labelText: 'admin_auto_436fa08acc'.tr()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _promoSub,
            decoration:
                InputDecoration(labelText: 'admin_auto_7c47aba2d6'.tr()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Promo (draft)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _editPromo(),
                icon: const Icon(Icons.add, size: 18),
                label: Text('pm_btn_tambah'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_promos.isEmpty)
            Text(
              'Belum ada promo di draft.',
              style: TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 12.5,
              ),
            )
          else
            for (final p in _promos.take(8))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  (p['title'] ?? 'Promo').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if ((p['voucher_code'] ?? '').toString().isNotEmpty)
                      p['voucher_code'].toString(),
                    if (p['_draft'] == true || _isDraftPromoId(p['id']))
                      'baru',
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _editPromo(p),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      onPressed: () => _deletePromo(p),
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: OptikAdminTokens.danger),
                    ),
                  ],
                ),
              ),
          TextButton(
            onPressed: () => _tabs.animateTo(2),
            child: Text('admin_auto_68d4a3b163'.tr()),
          ),
        ];
      case 'reminders':
        return [
          Text(
            'Pengingat diisi otomatis dari pesanan aktif, DP, dan janji kontrol Member. Tidak ada teks CMS di sini — hanya show/hide & urutan.',
            style: TextStyle(
              color: OptikAdminTokens.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ];
      case 'store':
        return [
          Text(
            'Cabang dipilih Member di APK (atau dari nota terakhir). CMS hanya mengatur apakah section ini tampil.',
            style: TextStyle(
              color: OptikAdminTokens.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ];
      case 'services_main':
        return [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('member_shop_title'.tr()),
            value: _flags['katalog'] != false,
            onChanged: (v) => _markDraft(() => _flags['katalog'] = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('admin_auto_61c450577c'.tr()),
            value: _flags['janji_kontrol'] != false,
            onChanged: (v) => _markDraft(() => _flags['janji_kontrol'] = v),
          ),
        ];
      case 'services_other':
        return [
          for (final e in _flagLabels.entries)
            if (e.key != 'katalog' && e.key != 'janji_kontrol')
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(e.value),
                value: _flags[e.key] != false,
                onChanged: (v) => _markDraft(() => _flags[e.key] = v),
              ),
        ];
      default:
        return [
          Text('admin_auto_6035815194'.tr()),
        ];
    }
  }

  Widget _buildBannerTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        _buildBannerGuide(),
        const SizedBox(height: 12),
        PremiumPanel(
          showAccentBar: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                'Brand di banner',
                'Teks kecil di pojok kiri atas hero (di atas gambar).',
                icon: Icons.branding_watermark_outlined,
              ),
              TextField(
                controller: _brand,
                decoration: _cmsDeco(
                  'Label brand',
                  helper: _defaultBrandLabel,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _slides.length; i++) ...[
          PremiumPanel(
            showAccentBar: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: OptikAdminTokens.navy,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'Banner ${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: OptikAdminTokens.onHighlight,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_slides.length > 1)
                      IconButton(
                        tooltip: 'admin_auto_be1c09179c'.tr(),
                        onPressed: () => _markDraft(() {
                          _slides[i].dispose();
                          _slides.removeAt(i);
                        }),
                        icon: const Icon(Icons.delete_outline,
                            color: OptikAdminTokens.danger),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Sama seperti hero APK Member: gambar cover, overlay gelap, teks putih.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: OptikAdminTokens.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                _MemberHeroSlide(
                  brand: _bannerBrand,
                  title: _slides[i].titleCtrl.text,
                  subtitle: _slides[i].subtitleCtrl.text,
                  imageUrl: _slides[i].imageUrl,
                  pageIndex: i,
                  pageCount: _slides.length,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickSlideImage(i),
                      icon: const Icon(Icons.image_outlined),
                      label: Text('admin_auto_ed95ab401d'.tr()),
                    ),
                    if (_slides[i].imageUrl.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            _markDraft(() => _slides[i].imageUrl = ''),
                        child: Text('admin_auto_e1d5663fd3'.tr()),
                      ),
                  ],
                ),
                _cmsFieldGap,
                TextField(
                  controller: _slides[i].titleCtrl,
                  maxLines: 3,
                  decoration: _cmsDeco(
                    'Judul',
                    helper: 'Maks ~2–3 baris di HP kecil',
                  ),
                ),
                _cmsFieldGap,
                TextField(
                  controller: _slides[i].subtitleCtrl,
                  maxLines: 2,
                  decoration: _cmsDeco(
                    'Subtitle',
                    helper: '1–2 kalimat pendek',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: () => _markDraft(() {
            _slides.add(_SlideEditors(title: '', subtitle: '', imageUrl: ''));
            _wireSlideListeners();
          }),
          icon: const Icon(Icons.add),
          label: Text('admin_auto_9173401dcb'.tr()),
        ),
      ],
    );
  }

  Widget _buildBannerGuide() {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'Panduan ukuran banner',
            'Supaya foto tidak kepotong aneh di HP member.',
            icon: Icons.straighten_rounded,
          ),
          LayoutBuilder(
            builder: (context, c) {
              final sideBySide = c.maxWidth >= 720;
              final guide = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _guideRow(Icons.crop_landscape_rounded, 'Rasio ideal',
                      '~2,1 : 1 — sama tinggi hero APK (~168 px di HP)'),
                  _guideRow(Icons.high_quality_outlined, 'Ukuran upload',
                      '1200 × 560 px (JPG/PNG)'),
                  _guideRow(Icons.fit_screen_rounded, 'Di APK',
                      'Full lebar HP · tinggi ~168 px · BoxFit.cover'),
                  _guideRow(Icons.center_focus_strong_outlined, 'Area aman',
                      'Subjek & teks penting di tengah (±15% dari tepi)'),
                  _guideRow(Icons.text_fields_rounded, 'Teks overlay',
                      'Brand kiri atas · judul/subtitle kiri · titik slide kanan bawah'),
                  const SizedBox(height: 8),
                  Text(
                    'Tip: wajah/produk jangan mentok pinggir — HP beda lebar, gambar di-crop cover.',
                    style: TextStyle(
                      color: OptikAdminTokens.textMuted.withOpacity(0.95),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              );
              final diagram = _BannerSafeZoneDiagram();
              if (sideBySide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: guide),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: diagram),
                  ],
                );
              }
              return Column(
                children: [
                  guide,
                  const SizedBox(height: 14),
                  diagram,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openPreview,
              icon: const Icon(Icons.phone_iphone_rounded, size: 18),
              label: Text('admin_auto_eb315c26d6'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideRow(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: OptikAdminTokens.navy),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: OptikAdminTokens.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$title · ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: OptikAdminTokens.textPrimary,
                    ),
                  ),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        PremiumPanel(
          showAccentBar: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _sectionHeader(
                  'Promo sinkron Member + POS',
                  'Edit masuk draft. Simpan lalu Update agar masuk APK & POS.',
                  icon: Icons.confirmation_number_outlined,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _editPromo(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('pm_btn_tambah'.tr()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OptikAdminTokens.navy,
                  side: BorderSide(color: OptikAdminTokens.navy),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_promos.isEmpty)
          PremiumPanel(
            child: PremiumEmptyState(
              title: 'admin_auto_07a6a4b99e'.tr(),
              message: 'admin_auto_2247210139'.tr(),
              icon: Icons.confirmation_number_outlined,
            ),
          )
        else
          ..._promos.map((p) {
            final qty = p['quantity_remaining'] ?? p['quantity'];
            final code = (p['voucher_code'] ?? '-').toString();
            final dtype = (p['discount_type'] ?? 'info').toString();
            final dval = p['discount_value'] ?? 0;
            final img = (p['image_url'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PremiumPanel(
                showAccentBar: true,
                onTap: () => _editPromo(p),
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (img.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              img,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: PremiumIconBadge(
                              icon: Icons.local_offer_outlined,
                              color: OptikAdminTokens.navy,
                              size: 44,
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (p['title'] ?? '-').toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  color: OptikAdminTokens.navy,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Kode $code',
                                style: TextStyle(
                                  color: OptikAdminTokens.slate,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'admin_auto_7dce122004'.tr(),
                          onPressed: () => _editPromo(p),
                          icon: Icon(
                            Icons.edit_outlined,
                            color: OptikAdminTokens.slate,
                          ),
                        ),
                        IconButton(
                          tooltip: 'btn_hapus'.tr(),
                          onPressed: () => _deletePromo(p),
                          icon: const Icon(Icons.delete_outline,
                              color: OptikAdminTokens.danger),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    PremiumChipWrap(
                      children: [
                        _chip(p['active'] == true ? 'Aktif' : 'Nonaktif',
                            ok: p['active'] == true),
                        if (p['show_on_member'] == true)
                          _chip('Member', ok: true),
                        if (p['show_on_pos'] == true) _chip('POS', ok: true),
                        _chip(qty == null ? 'Kuota ∞' : 'Sisa $qty'),
                        _chip(dtype == 'nominal'
                            ? 'Diskon Rp $dval'
                            : dtype == 'percent'
                                ? 'Diskon $dval%'
                                : 'Info saja'),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _chip(String t, {bool ok = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: ok
              ? OptikAdminTokens.ice.withOpacity(0.72)
              : OptikAdminTokens.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: ok
                ? OptikAdminTokens.navy.withOpacity(0.28)
                : OptikAdminTokens.chromeEdge,
          ),
        ),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 11,
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
      );
}

class _SlideEditors {
  _SlideEditors({
    required String title,
    required String subtitle,
    required this.imageUrl,
  })  : titleCtrl = TextEditingController(text: title),
        subtitleCtrl = TextEditingController(text: subtitle);

  final TextEditingController titleCtrl;
  final TextEditingController subtitleCtrl;
  String imageUrl;

  void dispose() {
    titleCtrl.dispose();
    subtitleCtrl.dispose();
  }
}

/// Diagram area aman banner (rasio 2:1 seperti di APK).
class _BannerSafeZoneDiagram extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: _MemberHeroSlide.apkRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        OptikAdminTokens.navy,
                        OptikAdminTokens.navy,
                        OptikAdminTokens.accent,
                      ],
                    ),
                  ),
                ),
                // Crop risk zones (edges)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 28,
                  child: ColoredBox(color: OptikAdminTokens.danger.withOpacity(0.28)),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 28,
                  child: ColoredBox(color: OptikAdminTokens.danger.withOpacity(0.28)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 22,
                  child: ColoredBox(color: OptikAdminTokens.danger.withOpacity(0.22)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 22,
                  child: ColoredBox(color: OptikAdminTokens.danger.withOpacity(0.22)),
                ),
                // Safe zone
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: OptikAdminTokens.success.withOpacity(0.85),
                          width: 1.5,
                        ),
                        color: OptikAdminTokens.success.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          'AREA AMAN\n(subjek & fokus penting)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: OptikAdminTokens.navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            height: 1.25,
                            shadows: [
                              Shadow(blurRadius: 6, color: OptikAdminTokens.slate),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 8,
                  child: Text(
                    'BRAND',
                    style: TextStyle(
                      color: OptikAdminTokens.textSecondary,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 28,
                  child: Text(
                    'Judul + subtitle',
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _LegendDot(
              color: OptikAdminTokens.danger.withOpacity(0.53),
              label: 'admin_auto_4a4ef204b6'.tr(),
            ),
            const SizedBox(width: 12),
            _LegendDot(
              color: OptikAdminTokens.success,
              label: 'admin_auto_2eafe9c4c2'.tr(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Contoh kerangka 1200×600 (2:1)',
          style: TextStyle(
            color: OptikAdminTokens.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: OptikAdminTokens.textMuted)),
      ],
    );
  }
}

/// Hero slide visual — mirror `_HeroBanner` di APK Member (bukan token Admin).
class _MemberHeroSlide extends StatelessWidget {
  const _MemberHeroSlide({
    required this.brand,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.pageIndex = 0,
    this.pageCount = 1,
    this.compact = false,
  });

  /// Lebar HP tipikal : tinggi hero APK (168).
  static const apkRatio = 360 / 168;

  final String brand;
  final String title;
  final String subtitle;
  final String imageUrl;
  final int pageIndex;
  final int pageCount;
  final bool compact;

  static const _fallbackGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      OptikMemberTokens.blueDeep,
      OptikMemberTokens.blue,
      Color(0xFF2E86DE),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: compact ? 13 : 16,
      fontWeight: FontWeight.w800,
      height: 1.15,
    );
    final subStyle = TextStyle(
      color: Colors.white.withOpacity(0.88),
      fontSize: compact ? 9.5 : 12,
      height: 1.3,
    );
    final stack = Stack(
      fit: StackFit.expand,
      children: [
            if (hasImage)
              Image.network(
                imageUrl.trim(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const DecoratedBox(decoration: BoxDecoration(gradient: _fallbackGradient)),
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(gradient: _fallbackGradient),
              ),
            if (hasImage)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x660F172A), Color(0x990F172A)],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 16,
                compact ? 8 : 12,
                compact ? 12 : 16,
                compact ? 16 : 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppBrandMark(height: compact ? 14 : 20, onDark: true),
                      if (brand.trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            brand,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.92),
                              fontWeight: FontWeight.w800,
                              fontSize: compact ? 8 : 11,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: compact ? 4 : 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.trim().isEmpty ? 'Judul banner' : title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        if (subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: subStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (pageCount > 1)
              Positioned(
                right: compact ? 10 : 14,
                bottom: compact ? 10 : 12,
                child: Row(
                  children: List.generate(pageCount, (i) {
                    final on = i == pageIndex;
                    return Container(
                      margin: const EdgeInsets.only(left: 4),
                      width: on ? 12 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(on ? 0.95 : 0.45),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ),
            if (!hasImage)
              Positioned(
                right: 12,
                top: 10,
                child: Text(
                  'Belum ada gambar',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: compact ? 8 : 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 0 : 14),
      child: stack,
    );
    if (compact) return clipped;
    return AspectRatio(aspectRatio: apkRatio, child: clipped);
  }
}

class _PreviewHeroCarousel extends StatefulWidget {
  const _PreviewHeroCarousel({
    required this.brand,
    required this.slides,
  });

  final String brand;
  final List<({String title, String subtitle, String imageUrl})> slides;

  @override
  State<_PreviewHeroCarousel> createState() => _PreviewHeroCarouselState();
}

class _PreviewHeroCarouselState extends State<_PreviewHeroCarousel> {
  final _controller = PageController();
  int _page = 0;

  List<({String title, String subtitle, String imageUrl})> get _slides {
    if (widget.slides.isNotEmpty) return widget.slides;
    return [
      (
        title: 'admin_auto_kacamata_siap_title'.tr(),
        subtitle: 'admin_auto_c8dae62f61'.tr(),
        imageUrl: '',
      ),
    ];
  }

  @override
  void didUpdateWidget(covariant _PreviewHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slides.length != widget.slides.length && _page > 0) {
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    return AspectRatio(
      aspectRatio: _MemberHeroSlide.apkRatio,
      child: PageView.builder(
        controller: _controller,
        onPageChanged: (i) => setState(() => _page = i),
        itemCount: slides.length,
        itemBuilder: (context, i) {
          final s = slides[i];
          return _MemberHeroSlide(
            brand: widget.brand,
            title: s.title,
            subtitle: s.subtitle,
            imageUrl: s.imageUrl,
            pageIndex: _page,
            pageCount: slides.length,
            compact: true,
          );
        },
      ),
    );
  }
}

/// Phone mock — mirror visual Home Member APK (OptikMemberTokens).
class _MemberHomePhonePreview extends StatelessWidget {
  const _MemberHomePhonePreview({
    required this.brand,
    required this.greeting,
    required this.greetingSub,
    required this.promoTitle,
    required this.promoSub,
    required this.slides,
    required this.sections,
    required this.flags,
    required this.promoPreviews,
    this.interactive = false,
    this.selectedKey,
    this.onSectionTap,
    this.onSectionLongPress,
    this.draftBadge = false,
    this.pendingUpdate = false,
    this.selectedLabel,
  });

  final String brand;
  final String greeting;
  final String greetingSub;
  final String promoTitle;
  final String promoSub;
  final List<({String title, String subtitle, String imageUrl})> slides;
  final List<Map<String, dynamic>> sections;
  final Map<String, bool> flags;
  final List<({String title, String label, String code})> promoPreviews;
  final bool interactive;
  final String? selectedKey;
  final ValueChanged<String>? onSectionTap;
  final ValueChanged<String>? onSectionLongPress;
  final bool draftBadge;
  final bool pendingUpdate;
  final String? selectedLabel;

  bool _visible(String key) {
    for (final s in sections) {
      if ((s['key'] ?? '') == key) return s['visible'] != false;
    }
    return false;
  }

  List<String> get _orderedVisibleKeys {
    final sorted = [...sections]..sort((a, b) =>
        ((a['order'] as num?)?.toInt() ?? 0)
            .compareTo((b['order'] as num?)?.toInt() ?? 0));
    return sorted
        .where((s) => s['visible'] != false)
        .map((s) => (s['key'] ?? '').toString())
        .where((k) => k.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    const phoneW = 280.0;
    const phoneH = 580.0;
    return Column(
      children: [
        Container(
          width: phoneW + 18,
          height: phoneH + 18,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            color: const Color(0xFF1A1A1A),
            boxShadow: [
              BoxShadow(
                color: OptikAdminTokens.navy.withOpacity(0.35),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Container(
            width: phoneW,
            height: phoneH,
            decoration: BoxDecoration(
              color: OptikMemberTokens.canvas,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.black87, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  height: 22,
                  color: _visible('hero')
                      ? OptikMemberTokens.blueDeep
                      : OptikMemberTokens.canvas,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Text(
                        '9:41',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _visible('hero')
                              ? Colors.white70
                              : OptikMemberTokens.inkMuted,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.signal_cellular_alt_rounded,
                        size: 10,
                        color: _visible('hero')
                            ? Colors.white70
                            : OptikMemberTokens.inkMuted,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final key in _orderedVisibleKeys)
                            _tapWrap(
                              key,
                              child: key == 'hero'
                                  ? _PreviewHeroCarousel(
                                      brand: brand,
                                      slides: slides,
                                    )
                                  : key == 'greeting'
                                      ? _previewGreeting()
                                      : key == 'promo'
                                          ? _previewPromoCard()
                                          : key == 'reminders'
                                              ? _previewReminders()
                                              : key == 'store'
                                                  ? _previewStore()
                                                  : key == 'services_main'
                                                      ? _previewServicesMain()
                                                      : key == 'services_other'
                                                          ? _previewServicesOther()
                                                          : const SizedBox
                                                              .shrink(),
                            ),
                          const SizedBox(height: 56),
                        ],
                      ),
                      if (_visible('hero'))
                        Positioned(
                          top: 6,
                          right: 10,
                          child: Material(
                            color: Colors.white.withOpacity(0.92),
                            shape: const CircleBorder(),
                            elevation: 1,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.shopping_cart_outlined,
                                size: 14,
                                color: OptikMemberTokens.blueDeep,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  height: 52,
                  decoration: const BoxDecoration(
                    color: OptikMemberTokens.white,
                    border: Border(
                      top: BorderSide(color: OptikMemberTokens.lineSoft),
                    ),
                  ),
                  child: Row(
                    children: [
                      _nav(Icons.home_rounded, 'Beranda', true),
                      _nav(Icons.receipt_long_outlined, 'Pesanan', false),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: OptikMemberTokens.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.qr_code_scanner_rounded,
                                  color: Colors.white, size: 16),
                            ),
                          ],
                        ),
                      ),
                      _nav(Icons.storefront_outlined, 'Cabang', false),
                      _nav(Icons.person_outline_rounded, 'Akun', false),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (interactive)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              pendingUpdate
                  ? 'SIAP UPDATE · belum ke APK'
                  : draftBadge
                      ? 'DRAFT · Simpan dulu'
                      : 'Ketuk bagian di HP untuk edit · tahan untuk urutan',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: OptikAdminTokens.navy,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Text(
          promoPreviews.isEmpty
              ? 'Belum ada promo Member · samakan dengan tab Promo'
              : '${promoPreviews.length} promo tampil di strip beranda',
          style: TextStyle(
            color: OptikAdminTokens.textMuted,
            fontSize: 11.5,
          ),
        ),
        if (draftBadge)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              pendingUpdate
                  ? 'Draft siap · tekan Update untuk ke APK'
                  : 'Preview draft · APK Member belum berubah',
              style: const TextStyle(
                color: OptikAdminTokens.warning,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _tapWrap(String key, {required Widget child}) {
    if (!interactive || onSectionTap == null) return child;
    final selected = selectedKey == key;
    final tag = selected
        ? (selectedLabel == null || selectedLabel!.isEmpty
            ? 'Mengatur'
            : 'Mengatur: $selectedLabel')
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSectionTap!(key),
          onLongPress: onSectionLongPress == null
              ? null
              : () => onSectionLongPress!(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? OptikMemberTokens.blue
                    : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: OptikMemberTokens.blue.withOpacity(0.22),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                child,
                if (tag != null)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: OptikMemberTokens.blue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
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

  Widget _nav(IconData icon, String label, bool on) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 17,
              color: on ? OptikMemberTokens.blue : OptikMemberTokens.inkMuted),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? OptikMemberTokens.blue : OptikMemberTokens.inkMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewGreeting() {
    // Overlap hanya jika greeting langsung setelah hero (sama seperti APK).
    final keys = _orderedVisibleKeys;
    final gi = keys.indexOf('greeting');
    final overlap = gi > 0 && keys[gi - 1] == 'hero';
    return Transform.translate(
      offset: Offset(0, overlap ? -20 : 0),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, overlap ? 0 : 8, 12, 0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: OptikMemberTokens.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: OptikMemberTokens.cardShadow,
            border: Border.all(color: OptikMemberTokens.lineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: OptikMemberTokens.blueDeep,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          greetingSub,
                          style: const TextStyle(
                            fontSize: 10,
                            color: OptikMemberTokens.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _roundStat(Icons.loyalty_rounded, 'Poin', '0'),
                  _roundStat(Icons.local_shipping_outlined, 'Pesanan', '0 aktif'),
                  _roundStat(Icons.verified_user_outlined, 'Garansi', '0'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundStat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: OptikMemberTokens.blueSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: OptikMemberTokens.blue),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: OptikMemberTokens.inkMuted)),
          Text(value,
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: OptikMemberTokens.blueDeep)),
        ],
      ),
    );
  }

  Widget _previewPromoCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: OptikMemberTokens.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OptikMemberTokens.lineSoft),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(promoTitle,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                              color: OptikMemberTokens.blueDeep)),
                      Text(
                        'Login untuk lihat voucher & tukar poin',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 9.5, color: OptikMemberTokens.inkMuted),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.blueSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_offer_outlined,
                      size: 15, color: OptikMemberTokens.blue),
                ),
              ],
            ),
          ),
          if (promoPreviews.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: promoPreviews.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = promoPreviews[i];
                  return Container(
                    width: 120,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OptikMemberTokens.lineSoft),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            color: OptikMemberTokens.blueDeep,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          p.code.isEmpty ? p.title : p.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: OptikMemberTokens.blue,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewReminders() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: OptikMemberTokens.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OptikMemberTokens.lineSoft),
          boxShadow: OptikMemberTokens.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pengingat',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: OptikMemberTokens.blueDeep,
                    ),
                  ),
                ),
                Text(
                  'Login dulu',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: OptikMemberTokens.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Login untuk melihat kacamata siap diambil, DP, dan jadwal kontrol.',
              style: TextStyle(
                fontSize: 10,
                color: OptikMemberTokens.inkMuted,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewStore() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cabang saya',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: OptikMemberTokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: OptikMemberTokens.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OptikMemberTokens.lineSoft),
            ),
            child: Row(
              children: [
                const Icon(Icons.store_mall_directory_outlined,
                    size: 16, color: OptikMemberTokens.blue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Belum dipilih',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: OptikMemberTokens.inkMuted,
                        ),
                      ),
                      Text(
                        'Pilih cabang untuk janji & pengingat',
                        style: TextStyle(
                          fontSize: 9,
                          color: OptikMemberTokens.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Pilih',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: OptikMemberTokens.blue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewServicesMain() {
    final items = <(IconData, String)>[
      if (flags['katalog'] != false)
        (Icons.storefront_rounded, 'Belanja\nOnline'),
      if (flags['janji_kontrol'] != false)
        (Icons.event_available_rounded, 'Janji\nKontrol'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Layanan utama',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: OptikMemberTokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.blueDeep,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: OptikMemberTokens.blue,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(items[i].$1,
                              size: 14, color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            items[i].$2,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewServicesOther() {
    final items = <(IconData, String)>[
      if (flags['resep'] != false) (Icons.history_edu_outlined, 'Resep'),
      if (flags['rating'] != false) (Icons.star_rate_rounded, 'Rating'),
      if (flags['notif'] != false)
        (Icons.notifications_active_outlined, 'Notif'),
      if (flags['perawatan'] != false) (Icons.menu_book_outlined, 'Perawatan'),
      if (flags['bentuk_wajah'] != false)
        (Icons.face_retouching_natural_rounded, 'Bentuk'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lainnya',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: OptikMemberTokens.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: i < items.length
                      ? Column(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: OptikMemberTokens.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: OptikMemberTokens.lineSoft),
                              ),
                              child: Icon(items[i].$1,
                                  size: 18, color: OptikMemberTokens.blue),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              items[i].$2,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w600,
                                color: OptikMemberTokens.inkSecondary,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
