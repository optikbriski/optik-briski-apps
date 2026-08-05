import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../shared/maps/osm_address_search.dart';
import '../../../shared/member/member_shop_address.dart';
import '../../../shared/theme.dart';
import 'member_shop_address_map_page.dart';

enum _AddrTab { recent, suggested, saved }

/// Pilih / simpan alamat Belanja Online (Recent · Suggested · Saved).
class MemberShopAddressPickerPage extends StatefulWidget {
  const MemberShopAddressPickerPage({super.key});

  @override
  State<MemberShopAddressPickerPage> createState() =>
      _MemberShopAddressPickerPageState();
}

class _MemberShopAddressPickerPageState
    extends State<MemberShopAddressPickerPage> {
  final _search = TextEditingController();
  final _addr = MemberShopAddress.instance;
  Timer? _debounce;

  _AddrTab _tab = _AddrTab.recent;
  bool _loading = true;
  bool _searching = false;
  double? _gpsLat;
  double? _gpsLng;
  List<OsmAddressHit> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _addr.removeListener(_onAddr);
    super.dispose();
  }

  void _onAddr() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    _addr.addListener(_onAddr);
    await _addr.ensureLoaded();
    await _loadGps();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      _gpsLat = pos.latitude;
      _gpsLng = pos.longitude;
    } catch (_) {}
  }

  String _fmtDist(double? m) {
    if (m == null) return '';
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.round()} m';
  }

  double? _distTo(double lat, double lng) {
    final glat = _gpsLat;
    final glng = _gpsLng;
    if (glat == null || glng == null) return null;
    return Geolocator.distanceBetween(glat, glng, lat, lng);
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    final t = q.trim();
    if (t.length < 3) {
      setState(() {
        _suggestions = const [];
        _searching = false;
        if (_tab != _AddrTab.saved) _tab = _AddrTab.suggested;
      });
      return;
    }
    setState(() {
      _tab = _AddrTab.suggested;
      _searching = true;
    });
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final hits = await OsmAddressSearch.search(t, limit: 8);
        if (!mounted) return;
        setState(() {
          _suggestions = hits;
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _suggestions = const [];
          _searching = false;
        });
      }
    });
  }

  Future<void> _confirmEntry(MemberShopAddressEntry entry) async {
    await _addr.confirm(entry);
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  Future<void> _confirmHit(OsmAddressHit hit) async {
    await _confirmEntry(
      MemberShopAddressEntry.fromCoords(
        displayName: hit.displayName,
        lat: hit.lat,
        lng: hit.lng,
        label: hit.title,
      ),
    );
  }

  Future<void> _useGps() async {
    await _loadGps();
    if (!mounted) return;
    if (_gpsLat == null || _gpsLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lokasi GPS tidak tersedia')),
      );
      return;
    }
    final entry = await Navigator.of(context).push<MemberShopAddressEntry>(
      MaterialPageRoute(
        builder: (_) => MemberShopAddressMapPage(
          initialLat: _gpsLat,
          initialLng: _gpsLng,
        ),
      ),
    );
    if (entry != null && mounted) Navigator.of(context).pop(entry);
  }

  Future<void> _openMap({ShopAddressKind? saveAs}) async {
    final a = _addr.active;
    final entry = await Navigator.of(context).push<MemberShopAddressEntry>(
      MaterialPageRoute(
        builder: (_) => MemberShopAddressMapPage(
          initialLat: a?.lat ?? _gpsLat,
          initialLng: a?.lng ?? _gpsLng,
          saveAsKind: saveAs,
        ),
      ),
    );
    if (entry != null && mounted) Navigator.of(context).pop(entry);
  }

  Future<void> _savePrompt(MemberShopAddressEntry base) async {
    final labelCtrl = TextEditingController(text: base.label);
    final detailCtrl = TextEditingController(text: base.detail);
    final noteCtrl = TextEditingController(text: base.note);
    var kind = ShopAddressKind.favorite;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Simpan alamat',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: OptikMemberTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Favorit'),
                        selected: kind == ShopAddressKind.favorite,
                        onSelected: (_) =>
                            setModal(() => kind = ShopAddressKind.favorite),
                      ),
                      ChoiceChip(
                        label: const Text('Rumah'),
                        selected: kind == ShopAddressKind.home,
                        onSelected: (_) =>
                            setModal(() => kind = ShopAddressKind.home),
                      ),
                      ChoiceChip(
                        label: const Text('Kantor'),
                        selected: kind == ShopAddressKind.work,
                        onSelected: (_) =>
                            setModal(() => kind = ShopAddressKind.work),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama (contoh: Rumah / Apart)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Detail (lobby, unit, patokan)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Catatan kurir (opsional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Simpan'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (ok != true) return;
    final saved = base.copyWith(
      kind: kind,
      label: labelCtrl.text.trim().isEmpty
          ? (kind == ShopAddressKind.home
              ? 'Rumah'
              : kind == ShopAddressKind.work
                  ? 'Kantor'
                  : base.label)
          : labelCtrl.text.trim(),
      detail: detailCtrl.text.trim(),
      note: noteCtrl.text.trim(),
      savedAt: DateTime.now(),
    );
    await _addr.savePlace(saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alamat disimpan')),
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
            padding: EdgeInsets.fromLTRB(8, top + 6, 12, 12),
            decoration: const BoxDecoration(
              color: OptikMemberTokens.blueMist,
              border: Border(
                bottom: BorderSide(color: OptikMemberTokens.lineSoft),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: OptikMemberTokens.ink,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: _onQuery,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Kirim ke…',
                          prefixIcon: const Icon(
                            Icons.location_on_rounded,
                            color: OptikMemberTokens.blueDeep,
                          ),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: OptikMemberTokens.line,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: OptikMemberTokens.line,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: OptikMemberTokens.blue,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final t in _AddrTab.values) ...[
                      if (t != _AddrTab.values.first) const SizedBox(width: 8),
                      Expanded(
                        child: _TabChip(
                          label: switch (t) {
                            _AddrTab.recent => 'Terbaru',
                            _AddrTab.suggested => 'Saran',
                            _AddrTab.saved => 'Tersimpan',
                          },
                          selected: _tab == t,
                          onTap: () => setState(() => _tab = t),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _buildTabBody()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: OptikMemberTokens.blueDeep,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _openMap(),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text(
                    'Pilih di peta',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody() {
    switch (_tab) {
      case _AddrTab.recent:
        return _listOrEmpty(
          leading: ListTile(
            leading: CircleAvatar(
              backgroundColor: OptikMemberTokens.blueSoft,
              child: const Icon(
                Icons.my_location_rounded,
                color: OptikMemberTokens.blueDeep,
              ),
            ),
            title: const Text(
              'Lokasi saat ini',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Pakai GPS lalu sesuaikan di peta'),
            onTap: _useGps,
          ),
          items: _addr.recent,
          empty: 'Belum ada alamat recent.',
          icon: Icons.history_rounded,
        );
      case _AddrTab.suggested:
        if (_search.text.trim().length < 3 && _suggestions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Ketik alamat untuk saran dari Maps.',
                textAlign: TextAlign.center,
                style: TextStyle(color: OptikMemberTokens.inkMuted),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final hit = _suggestions[i];
            final dist = _distTo(hit.lat, hit.lng);
            return ListTile(
              leading: const Icon(
                Icons.place_outlined,
                color: OptikMemberTokens.blueDeep,
              ),
              title: Text(
                hit.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  if (dist != null) _fmtDist(dist),
                  hit.subtitle ?? hit.displayName,
                ].where((e) => e.toString().isNotEmpty).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _confirmHit(hit),
            );
          },
        );
      case _AddrTab.saved:
        return ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          children: [
            _SavedAction(
              icon: Icons.add_rounded,
              label: 'Tambah baru',
              onTap: () => _openMap(saveAs: ShopAddressKind.favorite),
            ),
            _SavedAction(
              icon: Icons.home_rounded,
              label: _addr.home == null ? 'Tambah rumah' : 'Ubah rumah',
              onTap: () => _openMap(saveAs: ShopAddressKind.home),
            ),
            _SavedAction(
              icon: Icons.work_rounded,
              label: _addr.work == null ? 'Tambah kantor' : 'Ubah kantor',
              onTap: () => _openMap(saveAs: ShopAddressKind.work),
            ),
            const Divider(height: 20),
            if (_addr.saved.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Belum ada alamat tersimpan.\nTambah rumah, kantor, atau favorit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: OptikMemberTokens.inkMuted),
                ),
              )
            else
              ..._addr.saved.map((e) {
                final dist = _distTo(e.lat, e.lng);
                return ListTile(
                  leading: Icon(
                    e.kind == ShopAddressKind.home
                        ? Icons.home_rounded
                        : e.kind == ShopAddressKind.work
                            ? Icons.work_rounded
                            : Icons.favorite_rounded,
                    color: OptikMemberTokens.blueDeep,
                  ),
                  title: Text(
                    e.shortTitle,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    [
                      if (dist != null) _fmtDist(dist),
                      e.displayName,
                      if (e.detail.trim().isNotEmpty) e.detail,
                    ].join(' · '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Edit / simpan ulang',
                    onPressed: () => _savePrompt(e),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  onTap: () => _confirmEntry(e),
                  onLongPress: () async {
                    final del = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Hapus alamat?'),
                        content: Text(e.shortTitle),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Batal'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Hapus'),
                          ),
                        ],
                      ),
                    );
                    if (del == true) await _addr.removeSaved(e.id);
                  },
                );
              }),
          ],
        );
    }
  }

  Widget _listOrEmpty({
    Widget? leading,
    required List<MemberShopAddressEntry> items,
    required String empty,
    required IconData icon,
  }) {
    if (items.isEmpty && leading == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            empty,
            textAlign: TextAlign.center,
            style: const TextStyle(color: OptikMemberTokens.inkMuted),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      itemCount: items.length + (leading != null ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (leading != null && i == 0) return leading;
        final e = items[leading != null ? i - 1 : i];
        final dist = _distTo(e.lat, e.lng);
        return ListTile(
          leading: Icon(icon, color: OptikMemberTokens.blueDeep),
          title: Text(
            e.shortTitle,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            [
              if (dist != null) _fmtDist(dist),
              e.displayName,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Simpan',
            onPressed: () => _savePrompt(e),
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
          ),
          onTap: () => _confirmEntry(e),
        );
      },
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? OptikMemberTokens.blueSoft : OptikMemberTokens.blueMist,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: selected
                  ? OptikMemberTokens.blueDeep
                  : OptikMemberTokens.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedAction extends StatelessWidget {
  const _SavedAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: OptikMemberTokens.blueSoft,
        child: Icon(icon, color: OptikMemberTokens.blueDeep),
      ),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      onTap: onTap,
    );
  }
}
