// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/tenant/tenant_service.dart';

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
  String? _error;

  static const _defaultSections = [
    {'key': 'hero', 'label': 'Header / Banner', 'visible': true, 'order': 0},
    {'key': 'greeting', 'label': 'Kartu sapaan', 'visible': true, 'order': 1},
    {'key': 'promo', 'label': 'Kartu promo', 'visible': true, 'order': 2},
    {'key': 'reminders', 'label': 'Pengingat', 'visible': true, 'order': 3},
    {'key': 'store', 'label': 'Cabang saya', 'visible': true, 'order': 4},
    {
      'key': 'services_main',
      'label': 'Layanan utama',
      'visible': true,
      'order': 5
    },
    {'key': 'services_other', 'label': 'Lainnya', 'visible': true, 'order': 6},
  ];

  static const _flagLabels = {
    'katalog': 'Belanja Online',
    'janji_kontrol': 'Janji kontrol',
    'resep': 'Resep / reorder',
    'rating': 'Rating',
    'notif': 'Inbox',
    'perawatan': 'Perawatan',
    'bentuk_wajah': 'Bentuk (referensi frame)',
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
          const SnackBar(
            content: Text('Hanya Owner / Admin Pusat.'),
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
          (data['brand_label'] ?? 'OPTIK B. RISKI').toString();
      final greeting =
          (data['greeting_guest'] ?? 'Hi, Teman Optik!').toString();
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
            'title': 'Kacamata siap?\nLangsung tahu di sini',
            'subtitle': 'Pantau status pesanan & ambil tanpa ribet',
            'image_url': '',
          },
          {
            'title': 'Garansi digital\n${BrandService.name}',
            'subtitle': 'Data asli sistem · klaim wajib cek di toko',
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

      List promoRows = [];
      try {
        promoRows = await _db
            .from('member_promos')
            .select()
            .order('sort_order')
            .order('created_at', ascending: false);
      } catch (_) {
        promoRows = [];
      }
      final newPromos = promoRows
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

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

  Future<String?> _uploadBanner(Uint8List bytes, String name) async {
    final path =
        'banners/${DateTime.now().millisecondsSinceEpoch}_$name';
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
        SnackBar(content: Text('Upload gagal: $e')),
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
          content: Text('$e'),
          backgroundColor: OptikAdminTokens.warning,
        ),
      );
      return;
    }
    if (!_draftDirty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Simpan draft?'),
        content: const Text(
          'Draft di kunci di editor. APK Member belum berubah — '
          'tekan Update setelah ini untuk apply ke APK.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan draft'),
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
      const SnackBar(
        content: Text(
          'Draft tersimpan. APK belum berubah — tekan Update untuk apply.',
        ),
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
      'brand_label': _brand.text.trim().isEmpty
          ? 'OPTIK B. RISKI'
          : _brand.text.trim(),
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
      'title': (p['title'] ?? '').toString().trim(),
      'description': (p['description'] ?? '').toString(),
      'voucher_code': () {
        final c = (p['voucher_code'] ?? '').toString().trim();
        return c.isEmpty ? null : c.toUpperCase();
      }(),
      'points_cost': int.tryParse('${p['points_cost'] ?? 0}') ?? 0,
      'quantity': int.tryParse('${p['quantity'] ?? ''}'),
      'quantity_remaining': int.tryParse('${p['quantity_remaining'] ?? ''}'),
      'discount_type': (p['discount_type'] ?? 'nominal').toString(),
      'discount_value': int.tryParse('${p['discount_value'] ?? 0}') ?? 0,
      'show_on_member': p['show_on_member'] != false,
      'show_on_pos': p['show_on_pos'] != false,
      'active': p['active'] != false,
      'sort_order': int.tryParse('${p['sort_order'] ?? 0}') ?? 0,
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
        const SnackBar(
          content: Text('Ada edit baru. Tekan Simpan dulu, lalu Update.'),
          backgroundColor: OptikAdminTokens.warning,
        ),
      );
      return;
    }
    if (!_pendingUpdate) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update ke APK Member?'),
        content: const Text(
          'Draft yang sudah disimpan akan diterapkan ke beranda APK Member. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update APK'),
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
        const SnackBar(
          content: Text('Beranda Member diperbarui di APK.'),
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
        title: const Text('Buang draft?'),
        content: const Text(
          'Semua edit yang belum di-Update ke APK akan dibuang. Kembali ke data server?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Buang draft'),
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
        title: const Text('Keluar tanpa Update?'),
        content: Text(
          _pendingUpdate && !_draftDirty
              ? 'Draft sudah di-Simpan tapi belum di-Update ke APK. Keluar dan buang?'
              : 'Ada draft yang belum di-Update ke APK. Keluar dan buang?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjut edit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Buang & keluar'),
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
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isNew ? 'Tambah promo' : 'Edit promo'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Judul *')),
                  TextField(
                      controller: desc,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Deskripsi')),
                  TextField(
                      controller: code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText:
                              'Kode voucher * (wajib jika Nominal/Persen)',
                          helperText:
                              'Dipakai redeem kuota/poin di POS & Belanja Online')),
                  const SizedBox(height: 8),
                  AdminPickerField(
                    label: 'Tipe diskon POS',
                    valueText: switch (discType) {
                      'percent' => 'Persen (%)',
                      'info' => 'Info saja (tanpa potong POS)',
                      _ => 'Nominal (Rp)',
                    },
                    icon: Icons.discount_outlined,
                    onTap: () async {
                      const options = [
                        AdminPickerOption(
                          value: 'nominal',
                          label: 'Nominal (Rp)',
                          icon: Icons.payments_outlined,
                        ),
                        AdminPickerOption(
                          value: 'percent',
                          label: 'Persen (%)',
                          icon: Icons.percent_rounded,
                        ),
                        AdminPickerOption(
                          value: 'info',
                          label: 'Info saja (tanpa potong POS)',
                          icon: Icons.info_outline_rounded,
                        ),
                      ];
                      final sel = await showAdminPicker<String>(
                        context: ctx,
                        title: 'Tipe diskon POS',
                        selected: discType,
                        searchable: false,
                        options: options,
                      );
                      if (sel == null || sel.isClear) return;
                      setLocal(() => discType = sel.value!);
                    },
                  ),
                  TextField(
                    controller: discVal,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText: 'Nilai diskon (Rp atau %)'),
                  ),
                  TextField(
                    controller: points,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Biaya poin Member'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Kuota total (kosong=∞)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: qtyLeft,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Sisa kuota'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: sort,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Urutan tampil'),
                  ),
                  TextField(
                    controller: terms,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Syarat & ketentuan'),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(validUntil == null
                        ? 'Tanpa tanggal habis'
                        : 'Berlaku s/d ${validUntil!.toLocal().toString().substring(0, 10)}'),
                    trailing: TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2100),
                          initialDate: validUntil ?? DateTime.now(),
                        );
                        if (d != null) setLocal(() => validUntil = d);
                      },
                      child: const Text('Pilih'),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktif'),
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tampil di APK Member'),
                    value: onMember,
                    onChanged: (v) => setLocal(() => onMember = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bisa dipakai di POS'),
                    value: onPos,
                    onChanged: (v) => setLocal(() => onPos = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(imageUrl,
                              width: 64, height: 64, fit: BoxFit.cover),
                        ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
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
                              SnackBar(content: Text('Upload gagal: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Gambar promo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ke draft')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Judul wajib diisi')),
      );
      return;
    }
    if (discType != 'info' && code.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kode voucher wajib diisi untuk tipe Nominal/Persen '
            '(supaya bisa di-redeem di POS & Belanja Online).',
          ),
          backgroundColor: OptikAdminTokens.warning,
        ),
      );
      return;
    }
    if (discType != 'info' &&
        (int.tryParse(discVal.text) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nilai diskon harus > 0 untuk Nominal/Persen'),
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
      'points_cost': int.tryParse(points.text) ?? 0,
      'quantity': int.tryParse(qty.text),
      'quantity_remaining': int.tryParse(qtyLeft.text.isEmpty
              ? qty.text
              : qtyLeft.text) ??
          int.tryParse(qty.text),
      'discount_type': discType,
      'discount_value': int.tryParse(discVal.text) ?? 0,
      'show_on_member': onMember,
      'show_on_pos': onPos,
      'active': active,
      'sort_order': int.tryParse(sort.text) ?? 0,
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
      const SnackBar(
        content: Text('Promo masuk draft. Simpan → Update untuk ke APK.'),
        backgroundColor: OptikAdminTokens.warning,
      ),
    );
  }

  Future<void> _deletePromo(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus promo dari draft?'),
        content: Text(
          'Hapus "${p['title']}"? Baru hilang dari APK setelah Update.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
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
                          child: const Icon(Icons.phone_iphone_rounded,
                              size: 18, color: OptikAdminTokens.navy),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
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
                      style: const TextStyle(
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
      brand: _brand.text.trim().isEmpty ? 'OPTIK B. RISKI' : _brand.text.trim(),
      greeting: _greeting.text.trim().isEmpty
          ? 'Hi, Teman Optik!'
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
                title: (p['title'] ?? 'Promo').toString(),
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
              const Text(
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
                      label: const Text('Naik'),
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
                      label: const Text('Turun'),
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

  String _promoDiscountPreview(Map<String, dynamic> p) {
    final type = (p['discount_type'] ?? 'nominal').toString();
    final value = int.tryParse('${p['discount_value'] ?? 0}') ?? 0;
    if (type == 'percent') return 'Diskon $value%';
    if (type == 'nominal' && value > 0) return 'Potongan Rp $value';
    return (p['title'] ?? 'Promo Member').toString();
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
                        : TabBarView(
                            controller: _tabs,
                            children: [
                              _buildLayoutTab(),
                              _buildBannerTab(),
                              _buildPromoTab(),
                            ],
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
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _publishing
                    ? null
                    : () async {
                        final leave = await _confirmLeaveIfDirty();
                        if (leave && mounted) Navigator.pop(context);
                      },
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Konten Home Member',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      _draftDirty
                          ? 'Draft di preview · tekan Simpan (belum ke APK)'
                          : _pendingUpdate
                              ? 'Draft siap · tekan Update untuk apply ke APK'
                              : 'Ketuk HP untuk atur · Simpan lalu Update ke APK',
                      style: TextStyle(
                        color: _hasUnpublishedWork
                            ? OptikAdminTokens.warning
                            : OptikAdminTokens.textMuted,
                        fontSize: 12.5,
                        fontWeight: _hasUnpublishedWork
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (statusChip != null) statusChip,
            ],
          ),
          if (!_loading && _error == null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (_hasUnpublishedWork)
                  TextButton(
                    onPressed:
                        _loading || _publishing ? null : _discardDraft,
                    child: const Text('Buang'),
                  ),
                OutlinedButton.icon(
                  onPressed: _publishing ? null : _openPreview,
                  icon: const Icon(Icons.fullscreen_rounded, size: 18),
                  label: const Text('Fullscreen'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _loading || _publishing || !_draftDirty
                          ? null
                          : _saveDraft,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan'),
                ),
                FilledButton.icon(
                  onPressed: _loading ||
                          _publishing ||
                          _draftDirty ||
                          !_pendingUpdate
                      ? null
                      : _publishToApk,
                  icon: _publishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: OptikAdminTokens.navy,
                          ),
                        )
                      : const Icon(Icons.system_update_alt_rounded, size: 18),
                  label: Text(_publishing ? 'Updating…' : 'Update'),
                ),
              ],
            ),
          ],
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
              FilledButton(onPressed: _load, child: const Text('Coba lagi')),
              const SizedBox(height: 8),
              const Text(
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
                    style: const TextStyle(
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
            child: Container(
              decoration: BoxDecoration(
                color: OptikAdminTokens.bgMid,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.touch_app_rounded,
                            size: 18, color: OptikAdminTokens.navy),
                        const SizedBox(width: 8),
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
                          child: const Text('Fullscreen'),
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
        children: [
          _sectionHeader(
            'Mengatur: $label',
            'Edit = draft. Simpan = kunci draft. Update = apply ke APK.',
            icon: meta?.icon ?? Icons.tune_rounded,
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _sections)
                ChoiceChip(
                  label: Text(
                    (s['label'] ?? s['key']).toString(),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  selected: (s['key'] ?? '') == key,
                  onSelected: (_) =>
                      _selectSection((s['key'] ?? '').toString()),
                  selectedColor: OptikAdminTokens.accent.withOpacity(0.35),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (section != null) ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tampil di beranda'),
              subtitle: Text(visible
                  ? 'Section ini muncul di APK (setelah Update)'
                  : 'Disembunyikan dari beranda'),
              value: visible,
              onChanged: (v) => _markDraft(() => section['visible'] = v),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: idx <= 0 ? null : () => _moveSection(key, -1),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: const Text('Naik'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: idx < 0 || idx >= _sections.length - 1
                        ? null
                        : () => _moveSection(key, 1),
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    label: const Text('Turun'),
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
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
            decoration: const InputDecoration(
              labelText: 'Label brand di banner',
              hintText: 'OPTIK B. RISKI',
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Slide banner',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _slides.length; i++) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: OptikAdminTokens.line),
                borderRadius: BorderRadius.circular(12),
                color: OptikAdminTokens.panel,
              ),
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
                          tooltip: 'Hapus slide',
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
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickSlideImage(i),
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: const Text('Gambar'),
                      ),
                      if (_slides[i].imageUrl.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              _markDraft(() => _slides[i].imageUrl = ''),
                          child: const Text('Hapus gambar'),
                        ),
                    ],
                  ),
                  TextField(
                    controller: _slides[i].titleCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Judul'),
                  ),
                  TextField(
                    controller: _slides[i].subtitleCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Subtitle'),
                  ),
                ],
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
            label: const Text('Tambah slide'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _tabs.animateTo(1),
            child: const Text('Buka tab Banner (panduan ukuran)'),
          ),
        ];
      case 'greeting':
        return [
          TextField(
            controller: _greeting,
            decoration:
                const InputDecoration(labelText: 'Sapaan (belum login)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _greetingSub,
            decoration: const InputDecoration(labelText: 'Subtitle sapaan'),
          ),
          const SizedBox(height: 8),
          const Text(
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
            decoration: const InputDecoration(labelText: 'Judul kartu promo'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _promoSub,
            decoration:
                const InputDecoration(labelText: 'Subtitle kartu promo'),
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
                label: const Text('Tambah'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_promos.isEmpty)
            const Text(
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
            child: const Text('Buka tab Promo lengkap'),
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
            title: const Text('Belanja Online'),
            value: _flags['katalog'] != false,
            onChanged: (v) => _markDraft(() => _flags['katalog'] = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Janji Kontrol'),
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
          Text('Pilih bagian di preview HP.'),
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
                decoration: const InputDecoration(
                  labelText: 'Label brand',
                  hintText: 'OPTIK B. RISKI',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _slides.length; i++) ...[
          PremiumPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: OptikAdminTokens.accentGradient,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'Banner ${i + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_slides.length > 1)
                      IconButton(
                        tooltip: 'Hapus banner',
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
                const Text(
                  'Di APK Member (full-bleed, cover)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: OptikAdminTokens.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                _BannerApkMock(
                  brand: _brand.text.trim().isEmpty
                      ? 'OPTIK B. RISKI'
                      : _brand.text.trim(),
                  title: _slides[i].titleCtrl.text,
                  subtitle: _slides[i].subtitleCtrl.text,
                  imageUrl: _slides[i].imageUrl,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickSlideImage(i),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Ganti gambar'),
                    ),
                    if (_slides[i].imageUrl.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            _markDraft(() => _slides[i].imageUrl = ''),
                        child: const Text('Hapus gambar'),
                      ),
                  ],
                ),
                TextField(
                  controller: _slides[i].titleCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Judul',
                    helperText: 'Maks ~2–3 baris di HP kecil',
                  ),
                ),
                TextField(
                  controller: _slides[i].subtitleCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Subtitle',
                    helperText: '1–2 kalimat pendek',
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
          label: const Text('Tambah banner'),
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
                      '2 : 1 (lebar × tinggi)'),
                  _guideRow(Icons.high_quality_outlined, 'Ukuran upload',
                      '1200 × 600 px (JPG/PNG)'),
                  _guideRow(Icons.fit_screen_rounded, 'Di APK',
                      'Full lebar HP · tinggi ~168–200 px · BoxFit.cover'),
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
              label: const Text('Lihat preview beranda lengkap'),
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
                style: const TextStyle(
                  color: OptikAdminTokens.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$title · ',
                    style: const TextStyle(
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
          child: Row(
            children: [
              Expanded(
                child: _sectionHeader(
                  'Promo sinkron Member + POS',
                  'Edit masuk draft. Simpan lalu Update agar masuk APK & POS.',
                  icon: Icons.confirmation_number_outlined,
                ),
              ),
              FilledButton.icon(
                onPressed: () => _editPromo(),
                icon: const Icon(Icons.add),
                label: const Text('Tambah'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_promos.isEmpty)
          const PremiumPanel(
            child: Text('Belum ada promo. Ketuk Tambah.'),
          )
        else
          ..._promos.map((p) {
            final qty = p['quantity_remaining'] ?? p['quantity'];
            final code = (p['voucher_code'] ?? '-').toString();
            final dtype = (p['discount_type'] ?? 'info').toString();
            final dval = p['discount_value'] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PremiumPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if ((p['image_url'] ?? '').toString().isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              p['image_url'].toString(),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                        if ((p['image_url'] ?? '').toString().isNotEmpty)
                          const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (p['title'] ?? '-').toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              Text('Kode: $code',
                                  style: const TextStyle(
                                      color: OptikAdminTokens.textSecondary, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _editPromo(p),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: () => _deletePromo(p),
                          icon: const Icon(Icons.delete_outline,
                              color: OptikAdminTokens.danger),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _chip(p['active'] == true ? 'Aktif' : 'Nonaktif',
                            ok: p['active'] == true),
                        if (p['show_on_member'] == true) _chip('Member'),
                        if (p['show_on_pos'] == true) _chip('POS'),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ok
              ? OptikAdminTokens.success.withOpacity(0.15)
              : OptikAdminTokens.line,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: ok
                ? OptikAdminTokens.success.withOpacity(0.35)
                : OptikAdminTokens.line,
          ),
        ),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 11,
            color: ok ? OptikAdminTokens.success : null,
            fontWeight: FontWeight.w600,
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
          aspectRatio: 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
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
                      child: const Center(
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
                const Positioned(
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
                const Positioned(
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
              label: 'Bisa kepotong',
            ),
            const SizedBox(width: 12),
            const _LegendDot(
              color: OptikAdminTokens.success,
              label: 'Area aman',
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
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
            style: const TextStyle(
                fontSize: 11, color: OptikAdminTokens.textMuted)),
      ],
    );
  }
}

/// Mock banner seperti di beranda Member (rasio & overlay teks).
class _BannerApkMock extends StatelessWidget {
  const _BannerApkMock({
    required this.brand,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
  });

  final String brand;
  final String title;
  final String subtitle;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.trim().isNotEmpty)
              Image.network(
                imageUrl.trim(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        OptikAdminTokens.navy,
                        OptikAdminTokens.navy,
                      ],
                    ),
                  ),
                ),
              )
            else
              const DecoratedBox(
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
            if (imageUrl.trim().isNotEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      OptikAdminTokens.bgMid.withOpacity(0.33),
                      OptikAdminTokens.bgMid.withOpacity(0.60),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    brand,
                    style: TextStyle(
                      color: OptikAdminTokens.navy.withOpacity(0.75),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      fontSize: 9,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    title.trim().isEmpty ? 'Judul banner' : title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: OptikAdminTokens.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  if (subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: OptikAdminTokens.navy.withOpacity(0.88),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (imageUrl.trim().isEmpty)
              const Positioned(
                right: 12,
                top: 12,
                child: Text(
                  'Belum ada gambar',
                  style: TextStyle(color: OptikAdminTokens.textMuted, fontSize: 10),
                ),
              ),
          ],
        ),
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
    final slide = slides.isEmpty
        ? (
            title: 'Kacamata siap?\nLangsung tahu di sini',
            subtitle: 'Pantau status pesanan & ambil tanpa ribet',
            imageUrl: '',
          )
        : slides.first;

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
                                  ? _previewHero(slide)
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
                          const SizedBox(height: 64),
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
                      if (interactive)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: OptikAdminTokens.navy.withOpacity(0.82),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              pendingUpdate
                                  ? 'SIAP UPDATE · belum ke APK'
                                  : draftBadge
                                      ? 'DRAFT · Simpan dulu'
                                      : 'Ketuk edit · tahan urutan',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
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
        Text(
          promoPreviews.isEmpty
              ? 'Belum ada promo Member · samakan dengan tab Promo'
              : '${promoPreviews.length} promo tampil di strip beranda',
          style: const TextStyle(
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

  Widget _previewHero(
      ({String title, String subtitle, String imageUrl}) slide) {
    return SizedBox(
      height: 132,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (slide.imageUrl.trim().isNotEmpty)
            Image.network(
              slide.imageUrl.trim(),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      OptikMemberTokens.blueDeep,
                      OptikMemberTokens.blue,
                      Color(0xFF2E86DE),
                    ],
                  ),
                ),
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    OptikMemberTokens.blueDeep,
                    OptikMemberTokens.blue,
                    Color(0xFF2E86DE),
                  ],
                ),
              ),
            ),
          if (slide.imageUrl.trim().isNotEmpty)
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  slide.title.isEmpty ? 'Judul banner' : slide.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  slide.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 9.5,
                    height: 1.3,
                  ),
                ),
              ],
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
