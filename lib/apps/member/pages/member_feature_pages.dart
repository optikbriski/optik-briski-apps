import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme.dart';
import '../member_widgets.dart';

export 'member_notifications_page.dart';
export 'member_profile_page.dart';

/// Semua cabang Optik B. Riski (fitur 7 + 12) + rekomendasi GPS terdekat.
class MemberStoresPage extends StatefulWidget {
  const MemberStoresPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MemberStoresPage> createState() => _MemberStoresPageState();
}

class _MemberStoresPageState extends State<MemberStoresPage> {
  bool _loading = true;
  bool _locating = false;
  String? _error;
  String? _locationHint;
  List<Map<String, dynamic>> _stores = const [];
  String _query = '';
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _load();
    if (!mounted) return;
    await _detectNearest(silent: true);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final geoById = <String, Map<String, dynamic>>{};
      try {
        final geoRows = await client
            .from('toko_id')
            .select('id, latitude, longitude')
            .order('id');
        for (final raw in (geoRows as List)) {
          final m = Map<String, dynamic>.from(raw as Map);
          final id = (m['id'] ?? '').toString().trim().toUpperCase();
          if (id.isNotEmpty) geoById[id] = m;
        }
      } catch (_) {}

      List<dynamic> rows = [];
      try {
        rows = await client
            .from('invoice_settings')
            .select('toko_id, shop_name, address, phone, google_review_url')
            .order('toko_id');
      } catch (_) {
        rows = [];
      }
      if (rows.isEmpty) {
        rows = geoById.keys
            .map((id) => {
                  'toko_id': id,
                  'shop_name': 'Optik B. Riski',
                  'address': '',
                  'phone': '',
                })
            .toList();
      }

      final list = <Map<String, dynamic>>[];
      for (final raw in rows) {
        final s = Map<String, dynamic>.from(raw as Map);
        final id = (s['toko_id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final geo = geoById[id.toUpperCase()];
        s['latitude'] = geo?['latitude'];
        s['longitude'] = geo?['longitude'];
        list.add(s);
      }

      if (!mounted) return;
      setState(() {
        _stores = list;
        _loading = false;
        _applyDistances();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _applyDistances() {
    final lat = _userLat;
    final lng = _userLng;
    if (lat == null || lng == null) return;
    for (final s in _stores) {
      final slat = (s['latitude'] as num?)?.toDouble();
      final slng = (s['longitude'] as num?)?.toDouble();
      if (slat == null || slng == null) {
        s.remove('distance_m');
        continue;
      }
      s['distance_m'] =
          Geolocator.distanceBetween(lat, lng, slat, slng);
    }
    _stores.sort((a, b) {
      final da = (a['distance_m'] as num?)?.toDouble();
      final db = (b['distance_m'] as num?)?.toDouble();
      if (da == null && db == null) {
        return (a['toko_id'] ?? '')
            .toString()
            .compareTo((b['toko_id'] ?? '').toString());
      }
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
  }

  Future<void> _detectNearest({bool silent = false}) async {
    if (_locating) return;
    setState(() {
      _locating = true;
      if (!silent) _locationHint = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _locationHint =
              'GPS mati. Nyalakan lokasi HP, lalu ketuk “Cabang terdekat”.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _locationHint =
              'Izin lokasi ditolak. Izinkan GPS untuk rekomendasi cabang terdekat.';
        });
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _locationHint =
              'Izin lokasi diblokir. Buka Pengaturan HP → izinkan lokasi untuk Optik B. Riski.';
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
        _locating = false;
        _locationHint = null;
        _applyDistances();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationHint = silent
            ? 'Ketuk “Cabang terdekat” untuk pakai GPS.'
            : 'Gagal membaca GPS. Coba lagi di area terbuka.';
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final base = List<Map<String, dynamic>>.from(_stores);
    if (q.isEmpty) return base;
    return base.where((s) {
      final id = (s['toko_id'] ?? '').toString().toLowerCase();
      final name = (s['shop_name'] ?? '').toString().toLowerCase();
      final addr = (s['address'] ?? '').toString().toLowerCase();
      return id.contains(q) || name.contains(q) || addr.contains(q);
    }).toList();
  }

  Map<String, dynamic>? get _nearest {
    if (_userLat == null || _userLng == null) return null;
    for (final s in _filtered) {
      if (s['distance_m'] != null) return s;
    }
    return null;
  }

  String _labelToko(String raw) {
    final t = raw.trim().toUpperCase();
    if (t == 'PUSAT') return 'Pusat';
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  String _fmtDistance(num? meters) {
    if (meters == null) return '';
    final m = meters.toDouble();
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km';
  }

  Future<void> _openMaps(Map<String, dynamic> store) async {
    final lat = (store['latitude'] as num?)?.toDouble();
    final lng = (store['longitude'] as num?)?.toDouble();
    final name = (store['shop_name'] ?? 'Optik B. Riski').toString();
    final addr = (store['address'] ?? '').toString();
    final Uri uri;
    if (lat != null && lng != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
    } else {
      final q = Uri.encodeComponent('$name $addr Optik B Riski');
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWa(String phone, {String? message}) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    var p = digits;
    if (p.startsWith('0')) p = '62${p.substring(1)}';
    final uri = Uri.parse(
      message == null || message.isEmpty
          ? 'https://wa.me/$p'
          : 'https://wa.me/$p?text=${Uri.encodeComponent(message)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _storeCard(Map<String, dynamic> s, {bool highlighted = false}) {
    final id = (s['toko_id'] ?? '').toString();
    final name = (s['shop_name'] ?? 'Optik B. Riski').toString();
    final addr = (s['address'] ?? '').toString();
    final phone = (s['phone'] ?? '').toString();
    final review = (s['google_review_url'] ?? '').toString();
    final dist = s['distance_m'] as num?;
    final hasGeo =
        (s['latitude'] as num?) != null && (s['longitude'] as num?) != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OptikMemberTokens.white,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        border: Border.all(
          color: highlighted
              ? OptikMemberTokens.blue
              : OptikMemberTokens.lineSoft,
          width: highlighted ? 1.6 : 1,
        ),
        boxShadow: OptikMemberTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: OptikMemberTokens.blueSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _labelToko(id),
                  style: const TextStyle(
                    color: OptikMemberTokens.blueDeep,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              if (highlighted) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.blue,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'TERDEKAT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (dist != null)
                Text(
                  _fmtDistance(dist),
                  style: const TextStyle(
                    color: OptikMemberTokens.blueDeep,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                )
              else
                const Icon(Icons.storefront_rounded,
                    color: OptikMemberTokens.blue, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Text(name,
              style: const TextStyle(
                  color: OptikMemberTokens.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5)),
          if (addr.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(addr,
                style: const TextStyle(
                    color: OptikMemberTokens.inkSecondary,
                    height: 1.4,
                    fontSize: 13)),
          ],
          if (!hasGeo) ...[
            const SizedBox(height: 6),
            const Text(
              'Koordinat GPS toko belum diisi admin — jarak tidak dihitung.',
              style: TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Telp / WA: $phone',
                style: const TextStyle(
                    color: OptikMemberTokens.blueDeep,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (addr.isNotEmpty || hasGeo)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                  onPressed: () => _openMaps(s),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Peta'),
                ),
              if (phone.isNotEmpty)
                FilledButton.icon(
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => _openWa(phone),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: const Text('WhatsApp'),
                ),
              if (phone.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                  onPressed: () => _openWa(
                    phone,
                    message:
                        'Halo Optik B. Riski ($id), saya ingin bertanya.',
                  ),
                  icon: const Icon(Icons.support_agent_outlined, size: 18),
                  label: const Text('Tanya'),
                ),
              if (review.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                  onPressed: () => launchUrl(
                    Uri.parse(review),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.reviews_outlined, size: 18),
                  label: const Text('Google'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nearest = _nearest;
    final list = _filtered;
    final rest = nearest == null
        ? list
        : list
            .where((s) =>
                s['toko_id']?.toString() != nearest['toko_id']?.toString())
            .toList();

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Cari cabang / kota / alamat…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _locating ? null : () => _detectNearest(),
                  icon: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(
                    _userLat == null
                        ? 'Cabang terdekat'
                        : 'Perbarui lokasi',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_locationHint != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _locationHint!,
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ] else if (_userLat != null) ...[
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Daftar diurutkan dari cabang terdekat ke lokasi Anda.',
              style: TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Semua cabang Optik B. Riski — aktifkan GPS untuk rekomendasi terdekat.',
              style: TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? MemberEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Gagal memuat cabang',
                      message: _error!,
                      actionLabel: 'Coba lagi',
                      onAction: _load,
                    )
                  : list.isEmpty
                      ? const MemberEmptyState(
                          icon: Icons.store_mall_directory_outlined,
                          title: 'Cabang tidak ditemukan',
                          message: 'Coba kata kunci lain.',
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            await _load();
                            await _detectNearest(silent: true);
                          },
                          color: OptikMemberTokens.blue,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                            itemCount: rest.length + (nearest != null ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              if (nearest != null && i == 0) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'Rekomendasi untuk Anda',
                                      style: TextStyle(
                                        color: OptikMemberTokens.blueDeep,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _storeCard(nearest, highlighted: true),
                                    if (rest.isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      const Text(
                                        'Cabang lain',
                                        style: TextStyle(
                                          color: OptikMemberTokens.inkMuted,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              }
                              final idx = nearest == null ? i : i - 1;
                              return _storeCard(rest[idx]);
                            },
                          ),
                        ),
        ),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(color: OptikMemberTokens.canvas, child: body);
    }
    return MemberPremiumScaffold(
      title: 'Semua cabang',
      subtitle: 'GPS · cabang terdekat',
      body: body,
    );
  }
}

