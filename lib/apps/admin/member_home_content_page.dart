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
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
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

  @override
  void dispose() {
    _tabs.dispose();
    _brand.dispose();
    _greeting.dispose();
    _greetingSub.dispose();
    _promoTitle.dispose();
    _promoSub.dispose();
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
    list.sort((a, b) =>
        ((a['order'] as num?)?.toInt() ?? 0)
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
    final points = TextEditingController(
        text: '${existing?['points_cost'] ?? 0}');
    final qty = TextEditingController(
        text: existing?['quantity']?.toString() ?? '');
    final qtyLeft = TextEditingController(
        text: existing?['quantity_remaining']?.toString() ?? '');
    final discVal = TextEditingController(
        text: '${existing?['discount_value'] ?? 0}');
    final terms = TextEditingController(text: existing?['terms']?.toString());
    final sort = TextEditingController(
        text: '${existing?['sort_order'] ?? 0}');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: const Text('Konten Home Member'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Tata letak'),
            Tab(text: 'Banner'),
            Tab(text: 'Promo'),
          ],
        ),
        actions: [
          if (_tabs.index != 2)
            TextButton(
              onPressed: _loading || _saving ? null : _saveHome,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Simpan'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const Text('Coba lagi')),
                        const SizedBox(height: 8),
                        const Text(
                          'Jalankan migration:\n'
                          '20260728000001_member_home_content.sql\n'
                          '20260728000002_member_cms_layout_promo.sql',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildLayoutTab(),
                    _buildBannerTab(),
                    _buildPromoTab(),
                  ],
                ),
    );
  }

  Widget _buildLayoutTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        PremiumPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Urutan & tampilkan section',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 6),
              const Text(
                'Geser ↑↓ untuk urutan. Matikan switch untuk hide di APK Member.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
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
                  return Card(
                    key: ValueKey(key),
                    color: OptikAdminTokens.panel,
                    child: ListTile(
                      leading: const Icon(Icons.drag_handle),
                      title: Text((s['label'] ?? key).toString()),
                      subtitle: Text(key,
                          style: const TextStyle(fontSize: 11)),
                      trailing: Switch(
                        value: s['visible'] != false,
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
              const Text('Fitur tombol (hide / see)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 8),
              ..._flagLabels.entries.map((e) {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: _flags[e.key] != false,
                  onChanged: (v) => setState(() => _flags[e.key] = v),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PremiumPanel(
          child: Column(
            children: [
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
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _saveHome,
          icon: const Icon(Icons.save_rounded),
          label: const Text('Simpan tata letak & teks'),
        ),
      ],
    );
  }

  Widget _buildBannerTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        PremiumPanel(
          child: TextField(
            controller: _brand,
            decoration: const InputDecoration(
              labelText: 'Label brand di banner',
              hintText: 'OPTIK B. RISKI',
            ),
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
                    Text('Banner ${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_slides.length > 1)
                      IconButton(
                        onPressed: () => setState(() {
                          _slides[i].dispose();
                          _slides.removeAt(i);
                        }),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 16 / 7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _slides[i].imageUrl.isEmpty
                        ? Container(
                            color: OptikAdminTokens.panel,
                            alignment: Alignment.center,
                            child: const Text('Belum ada gambar\n(gradient default)',
                                textAlign: TextAlign.center),
                          )
                        : Image.network(_slides[i].imageUrl, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 8),
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
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _slides.add(_SlideEditors(title: '', subtitle: '', imageUrl: ''));
          }),
          icon: const Icon(Icons.add),
          label: const Text('Tambah banner'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _saveHome,
          icon: const Icon(Icons.save_rounded),
          label: const Text('Simpan banner'),
        ),
      ],
    );
  }

  Widget _buildPromoTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Promo sinkron Member + POS',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _editPromo(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Isi kuota, kode voucher, nilai diskon. POS bisa lookup kode; Member lihat kartu promo.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
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
                            borderRadius: BorderRadius.circular(8),
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
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _chip(p['active'] == true ? 'Aktif' : 'Nonaktif'),
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

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(t, style: const TextStyle(fontSize: 11)),
      );
}

class _SlideEditors {
  _SlideEditors({
    required String title,
    required String subtitle,
    required String imageUrl,
  })  : titleCtrl = TextEditingController(text: title),
        subtitleCtrl = TextEditingController(text: subtitle),
        imageUrl = imageUrl;

  final TextEditingController titleCtrl;
  final TextEditingController subtitleCtrl;
  String imageUrl;

  void dispose() {
    titleCtrl.dispose();
    subtitleCtrl.dispose();
  }
}
