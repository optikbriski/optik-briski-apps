// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

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

  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _defaultSections = [
    {'key': 'hero', 'label': 'Header / Banner', 'visible': true, 'order': 0},
    {'key': 'greeting', 'label': 'Kartu sapaan', 'visible': true, 'order': 1},
    {'key': 'promo', 'label': 'Kartu promo', 'visible': true, 'order': 2},
    {'key': 'reminders', 'label': 'Pengingat', 'visible': true, 'order': 3},
    {'key': 'store', 'label': 'Cabang terkait', 'visible': true, 'order': 4},
    {
      'key': 'services_main',
      'label': 'Layanan utama',
      'visible': true,
      'order': 5
    },
    {'key': 'services_other', 'label': 'Lainnya', 'visible': true, 'order': 6},
  ];

  static const _flagLabels = {
    'katalog': 'Katalog produk',
    'janji_kontrol': 'Janji kontrol',
    'resep': 'Resep / reorder',
    'rating': 'Rating',
    'notif': 'Notifikasi',
    'perawatan': 'Perawatan',
    'bentuk_wajah': 'Bentuk wajah (scan)',
  };

  static const _sectionMeta = <String, ({IconData icon, String hint})>{
    'hero': (icon: Icons.image_outlined, hint: 'Banner atas beranda'),
    'greeting': (icon: Icons.waving_hand_outlined, hint: 'Sapaan + poin'),
    'promo': (icon: Icons.local_offer_outlined, hint: 'Shortcut promo'),
    'reminders': (
      icon: Icons.notifications_active_outlined,
      hint: 'Status pesanan'
    ),
    'store': (icon: Icons.storefront_outlined, hint: 'Cabang terkait'),
    'services_main': (
      icon: Icons.grid_view_rounded,
      hint: 'Katalog & janji kontrol'
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
            backgroundColor: Colors.redAccent,
          ),
        );
        Navigator.pop(context);
      });
      return;
    }
    _load();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
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
    });
    try {
      final row = await _db
          .from('member_home_content')
          .select()
          .eq('id', 'default')
          .maybeSingle();
      final data =
          row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row);

      _brand.text = (data['brand_label'] ?? 'OPTIK B. RISKI').toString();
      _greeting.text =
          (data['greeting_guest'] ?? 'Hi, Teman Optik!').toString();
      _greetingSub.text = (data['greeting_subtitle_guest'] ??
              'Login untuk lihat pesanan & garansi')
          .toString();
      _promoTitle.text =
          (data['promo_title'] ?? 'Promo & poin').toString();
      _promoSub.text =
          (data['promo_subtitle'] ?? 'Voucher dan saldo poin kamu')
              .toString();

      for (final s in _slides) {
        s.dispose();
      }
      _slides.clear();
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
            'title': 'Garansi digital\nOptik B. Riski',
            'subtitle': 'Data asli sistem · klaim wajib cek di toko',
            'image_url': '',
          },
        ];
      }
      for (final s in slidesList) {
        final m = Map<String, dynamic>.from(s as Map);
        _slides.add(_SlideEditors(
          title: (m['title'] ?? '').toString(),
          subtitle: (m['subtitle'] ?? '').toString(),
          imageUrl: (m['image_url'] ?? '').toString(),
        ));
      }
      _wireSlideListeners();

      _sections = _parseSections(data['sections']);
      _flags = _parseFlags(data['feature_flags']);

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
      _promos = promoRows
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<Map<String, dynamic>> _parseSections(dynamic raw) {
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    }
    if (list.isEmpty) {
      return _defaultSections
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
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
      setState(() => _slides[index].imageUrl = url ?? '');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload gagal: $e')),
      );
    }
  }

  Future<void> _saveHome() async {
    setState(() => _saving = true);
    try {
      final slides = _slides
          .map((s) => {
                'title': s.titleCtrl.text.trim(),
                'subtitle': s.subtitleCtrl.text.trim(),
                'image_url': s.imageUrl.trim(),
              })
          .where((s) => (s['title'] as String).isNotEmpty)
          .toList();
      if (slides.isEmpty) throw Exception('Minimal 1 slide banner.');

      for (var i = 0; i < _sections.length; i++) {
        _sections[i]['order'] = i;
      }

      await _db.from('member_home_content').upsert({
        'id': 'default',
        'brand_label': _brand.text.trim().isEmpty
            ? 'OPTIK B. RISKI'
            : _brand.text.trim(),
        'slides': slides,
        'greeting_guest': _greeting.text.trim(),
        'greeting_subtitle_guest': _greetingSub.text.trim(),
        'promo_title': _promoTitle.text.trim(),
        'promo_subtitle': _promoSub.text.trim(),
        'sections': _sections,
        'feature_flags': _flags,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Layout & banner tersimpan.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Gagal: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                      decoration: const InputDecoration(
                          labelText: 'Kode voucher (untuk POS/Member)')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: discType,
                    decoration:
                        const InputDecoration(labelText: 'Tipe diskon POS'),
                    items: const [
                      DropdownMenuItem(
                          value: 'nominal', child: Text('Nominal (Rp)')),
                      DropdownMenuItem(
                          value: 'percent', child: Text('Persen (%)')),
                      DropdownMenuItem(
                          value: 'info',
                          child: Text('Info saja (tanpa potong POS)')),
                    ],
                    onChanged: (v) =>
                        setLocal(() => discType = v ?? 'nominal'),
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
                child: const Text('Simpan')),
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

    final payload = {
      'title': title.text.trim(),
      'description': desc.text.trim(),
      'voucher_code': code.text.trim().isEmpty ? null : code.text.trim(),
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
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      if (isNew) {
        await _db.from('member_promos').insert(payload);
      } else {
        await _db
            .from('member_promos')
            .update(payload)
            .eq('id', existing['id']);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Promo tersimpan'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Gagal simpan promo: $e'),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _deletePromo(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus promo?'),
        content: Text('Hapus "${p['title']}"?'),
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
    await _db.from('member_promos').delete().eq('id', p['id']);
    await _load();
  }

  void _openPreview() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.72),
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
                              size: 18, color: Colors.white),
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
                        child: Center(child: _buildPhonePreview()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Belum tersimpan ke server — ini preview editan saat ini.',
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

  Widget _buildPhonePreview() {
    return _MemberHomePhonePreview(
      brand: _brand.text.trim().isEmpty ? 'OPTIK B. RISKI' : _brand.text.trim(),
      greeting: _greeting.text.trim().isEmpty
          ? 'Hi, Teman Optik!'
          : _greeting.text.trim(),
      greetingSub: _greetingSub.text.trim(),
      promoTitle: _promoTitle.text.trim().isEmpty
          ? 'Promo & poin'
          : _promoTitle.text.trim(),
      promoSub: _promoSub.text.trim(),
      slides: _slides
          .map((s) => (
                title: s.titleCtrl.text,
                subtitle: s.subtitleCtrl.text,
                imageUrl: s.imageUrl,
              ))
          .toList(),
      sections: _sections,
      flags: _flags,
      promoCount: _promos.where((p) => p['show_on_member'] != false).length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: OptikAdminTokens.bgGradient),
        child: SafeArea(
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Konten Home Member',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Atur konsep beranda · tekan Preview untuk lihat di HP',
                  style: TextStyle(
                    color: OptikAdminTokens.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (!_loading && _error == null) ...[
            OutlinedButton.icon(
              onPressed: _openPreview,
              icon: const Icon(Icons.phone_iphone_rounded, size: 18),
              label: const Text('Preview'),
            ),
            if (_tabs.index != 2) const SizedBox(width: 8),
          ],
          if (_tabs.index != 2)
            FilledButton.icon(
              onPressed: _loading || _saving ? null : _saveHome,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_saving ? 'Menyimpan…' : 'Simpan'),
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
        labelColor: Colors.white,
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
              child: Icon(icon, size: 18, color: OptikAdminTokens.accentSoft),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        PremiumPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                'Urutan & tampilan section',
                'Geser ↑↓ untuk urutan. Matikan switch untuk hide di APK.',
                icon: Icons.view_agenda_outlined,
              ),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                proxyDecorator: (child, index, animation) {
                  return Material(
                    color: Colors.transparent,
                    elevation: 8,
                    shadowColor: OptikAdminTokens.accent.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                    child: child,
                  );
                },
                itemCount: _sections.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _sections.removeAt(oldIndex);
                    _sections.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, i) {
                  final s = _sections[i];
                  final key = (s['key'] ?? '').toString();
                  final meta = _sectionMeta[key];
                  final on = s['visible'] != false;
                  return Container(
                    key: ValueKey(key),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: on
                          ? OptikAdminTokens.panel
                          : OptikAdminTokens.bg.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: on
                            ? OptikAdminTokens.accent.withOpacity(0.28)
                            : OptikAdminTokens.line,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.drag_handle_rounded,
                              color: OptikAdminTokens.textMuted),
                          const SizedBox(width: 6),
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: OptikAdminTokens.accent.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: OptikAdminTokens.accentSoft,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            meta?.icon ?? Icons.widgets_outlined,
                            size: 20,
                            color: on
                                ? OptikAdminTokens.accentSoft
                                : OptikAdminTokens.textMuted,
                          ),
                        ],
                      ),
                      title: Text(
                        (s['label'] ?? key).toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: on
                              ? OptikAdminTokens.textPrimary
                              : OptikAdminTokens.textMuted,
                        ),
                      ),
                      subtitle: Text(
                        meta?.hint ?? key,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Switch.adaptive(
                        value: on,
                        onChanged: (v) =>
                            setState(() => _sections[i]['visible'] = v),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PremiumPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                'Fitur tombol (hide / see)',
                'Matikan agar tidak muncul di grid layanan Member.',
                icon: Icons.toggle_on_outlined,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _flagLabels.entries.map((e) {
                  final on = _flags[e.key] != false;
                  return FilterChip(
                    selected: on,
                    showCheckmark: false,
                    label: Text(e.value),
                    avatar: Icon(
                      on
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_outlined,
                      size: 16,
                    ),
                    onSelected: (v) => setState(() => _flags[e.key] = v),
                    selectedColor: OptikAdminTokens.accent.withOpacity(0.25),
                    labelStyle: TextStyle(
                      color: on
                          ? OptikAdminTokens.textPrimary
                          : OptikAdminTokens.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PremiumPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                'Teks sapaan & kartu promo',
                'Langsung terlihat di preview HP.',
                icon: Icons.edit_note_rounded,
              ),
              TextField(
                controller: _greeting,
                decoration:
                    const InputDecoration(labelText: 'Sapaan (belum login)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _greetingSub,
                decoration:
                    const InputDecoration(labelText: 'Subtitle sapaan'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _promoTitle,
                decoration:
                    const InputDecoration(labelText: 'Judul kartu promo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _promoSub,
                decoration:
                    const InputDecoration(labelText: 'Subtitle kartu promo'),
              ),
            ],
          ),
        ),
      ],
    );
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
                        onPressed: () => setState(() {
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
                            setState(() => _slides[i].imageUrl = ''),
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
          onPressed: () => setState(() {
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
          Icon(icon, size: 18, color: OptikAdminTokens.accentSoft),
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
                  'Kuota, kode voucher, nilai diskon — kasir bisa Cek di POS.',
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
                                      color: Colors.white70, fontSize: 12.5)),
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
              : Colors.white12,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: ok
                ? OptikAdminTokens.success.withOpacity(0.35)
                : Colors.white10,
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
                        OptikMemberTokens.blueDeep,
                        OptikMemberTokens.blue,
                        Color(0xFF2E86DE),
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
                  child: ColoredBox(color: Colors.red.withOpacity(0.28)),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 28,
                  child: ColoredBox(color: Colors.red.withOpacity(0.28)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 22,
                  child: ColoredBox(color: Colors.red.withOpacity(0.22)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 22,
                  child: ColoredBox(color: Colors.red.withOpacity(0.22)),
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
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            height: 1.25,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black54),
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
                      color: Colors.white70,
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
                      color: Colors.white,
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
        const Row(
          children: [
            _LegendDot(color: Color(0x88EF4444), label: 'Bisa kepotong'),
            SizedBox(width: 12),
            _LegendDot(color: OptikAdminTokens.success, label: 'Area aman'),
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
                        OptikMemberTokens.blueDeep,
                        OptikMemberTokens.blue,
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
            if (imageUrl.trim().isNotEmpty)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x550F172A), Color(0x990F172A)],
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
                      color: Colors.white.withOpacity(0.75),
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
                      color: Colors.white,
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
                        color: Colors.white.withOpacity(0.88),
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
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Phone mock — meniru layout beranda Member (bukan runtime APK).
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
    required this.promoCount,
  });

  final String brand;
  final String greeting;
  final String greetingSub;
  final String promoTitle;
  final String promoSub;
  final List<({String title, String subtitle, String imageUrl})> slides;
  final List<Map<String, dynamic>> sections;
  final Map<String, bool> flags;
  final int promoCount;

  bool _visible(String key) {
    for (final s in sections) {
      if ((s['key'] ?? '') == key) return s['visible'] != false;
    }
    return false;
  }

  List<String> get _orderedVisibleKeys {
    final list = sections
        .where((s) => s['visible'] != false)
        .map((s) => (s['key'] ?? '').toString())
        .where((k) => k.isNotEmpty)
        .toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    const phoneW = 280.0;
    const phoneH = 560.0;
    final slide = slides.isEmpty
        ? (title: 'Banner', subtitle: '', imageUrl: '')
        : slides.first;

    return Column(
      children: [
        Container(
          width: phoneW + 18,
          height: phoneH + 18,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF334155),
                Color(0xFF0F172A),
                Color(0xFF1E293B),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: OptikAdminTokens.accent.withOpacity(0.12),
                blurRadius: 36,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Container(
            width: phoneW,
            height: phoneH,
            decoration: BoxDecoration(
              color: OptikMemberTokens.canvas,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF1E293B), width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Status bar fake
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
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final key in _orderedVisibleKeys)
                        if (key == 'hero')
                          _previewHero(slide)
                        else if (key == 'greeting')
                          _previewGreeting()
                        else if (key == 'promo')
                          _previewPromoCard()
                        else if (key == 'reminders')
                          _previewReminders()
                        else if (key == 'store')
                          _previewStore()
                        else if (key == 'services_main')
                          _previewServicesMain()
                        else if (key == 'services_other')
                          _previewServicesOther(),
                      const SizedBox(height: 56),
                    ],
                  ),
                ),
                // Bottom nav fake
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: OptikMemberTokens.lineSoft),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: OptikMemberTokens.blueDeep.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _nav(Icons.home_rounded, 'Beranda', true),
                      _nav(Icons.receipt_long_outlined, 'Pesanan', false),
                      Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              OptikMemberTokens.blue,
                              OptikMemberTokens.blueDeep,
                            ],
                          ),
                        ),
                        child: const Icon(Icons.qr_code_2_rounded,
                            color: Colors.white, size: 20),
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
          promoCount > 0
              ? '$promoCount promo aktif di Member'
              : 'Belum ada promo Member',
          style: const TextStyle(
            color: OptikAdminTokens.textMuted,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  Widget _nav(IconData icon, String label, bool on) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon,
            size: 18,
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
    );
  }

  Widget _previewHero(
      ({String title, String subtitle, String imageUrl}) slide) {
    return SizedBox(
      height: 148,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (slide.imageUrl.trim().isNotEmpty)
            Image.network(
              slide.imageUrl.trim(),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: OptikMemberTokens.blueDeep,
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
                  colors: [Color(0x550F172A), Color(0x990F172A)],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brand,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  slide.title.isEmpty ? 'Judul banner' : slide.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  slide.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
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
    final overlap = _visible('hero');
    return Transform.translate(
      offset: Offset(0, overlap ? -18 : 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: OptikMemberTokens.cardShadow,
            border: Border.all(color: OptikMemberTokens.lineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: OptikMemberTokens.ink,
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
              const SizedBox(height: 8),
              Row(
                children: [
                  _miniStat('Poin', '—'),
                  const SizedBox(width: 6),
                  _miniStat('Pesanan', '—'),
                  const SizedBox(width: 6),
                  _miniStat('Garansi', '—'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: OptikMemberTokens.blueMist,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: OptikMemberTokens.blueDeep)),
            Text(label,
                style: const TextStyle(
                    fontSize: 8, color: OptikMemberTokens.inkMuted)),
          ],
        ),
      ),
    );
  }

  Widget _previewPromoCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OptikMemberTokens.lineSoft),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: OptikMemberTokens.blueSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.local_offer_outlined,
                  size: 16, color: OptikMemberTokens.blue),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(promoTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          color: OptikMemberTokens.ink)),
                  Text(promoSub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 9.5, color: OptikMemberTokens.inkMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: OptikMemberTokens.inkMuted),
          ],
        ),
      ),
    );
  }

  Widget _previewReminders() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pengingat',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: OptikMemberTokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OptikMemberTokens.lineSoft),
            ),
            child: const Text(
              'Login untuk lihat status pesanan aktif',
              style: TextStyle(
                  fontSize: 10, color: OptikMemberTokens.inkMuted, height: 1.3),
            ),
          ),
        ],
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
            'Cabang terkait',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: OptikMemberTokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: OptikMemberTokens.blueSoft,
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_rounded,
                    size: 14, color: OptikMemberTokens.blueDeep),
                SizedBox(width: 6),
                Text('Contoh cabang',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: OptikMemberTokens.blueDeep)),
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
        (Icons.visibility_outlined, 'Katalog\nproduk'),
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
              fontSize: 11.5,
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
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OptikMemberTokens.lineSoft),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(items[i].$1,
                            size: 18, color: OptikMemberTokens.blue),
                        const SizedBox(height: 4),
                        Text(
                          items[i].$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: OptikMemberTokens.ink,
                            height: 1.15,
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
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lainnya',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: OptikMemberTokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in items)
                SizedBox(
                  width: 58,
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: OptikMemberTokens.lineSoft),
                        ),
                        child: Icon(item.$1,
                            size: 18, color: OptikMemberTokens.blue),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.$2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: OptikMemberTokens.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
