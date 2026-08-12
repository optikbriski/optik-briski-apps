import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../shared/maps/osm_address_search.dart';
import '../../../shared/member/member_shop_address.dart';
import '../../../shared/theme.dart';

/// Peta geser (pin di tengah) — konfirmasi titik alamat Belanja Online.
class MemberShopAddressMapPage extends StatefulWidget {
  const MemberShopAddressMapPage({
    super.key,
    this.initialLat,
    this.initialLng,
    this.saveAsKind,
  });

  final double? initialLat;
  final double? initialLng;
  final ShopAddressKind? saveAsKind;

  @override
  State<MemberShopAddressMapPage> createState() =>
      _MemberShopAddressMapPageState();
}

class _MemberShopAddressMapPageState extends State<MemberShopAddressMapPage> {
  final _mapCtrl = MapController();
  Timer? _settle;

  double _lat = -6.9175;
  double _lng = 107.6191;
  String _label = 'Geser peta untuk menyesuaikan';
  String _display = '';
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat ?? _lat;
    _lng = widget.initialLng ?? _lng;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reverse());
  }

  @override
  void dispose() {
    _settle?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _goMyLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
    });
    try {
      _mapCtrl.move(LatLng(_lat, _lng), 17);
    } catch (_) {}
    await _reverse();
  }

  void _onMapMoved(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _lat = camera.center.latitude;
    _lng = camera.center.longitude;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 420), _reverse);
  }

  Future<void> _reverse() async {
    setState(() => _resolving = true);
    try {
      final hit = await OsmAddressSearch.reverse(LatLng(_lat, _lng));
      if (!mounted) return;
      setState(() {
        if (hit != null) {
          _label = hit.title;
          _display = hit.displayName;
        } else {
          _label = 'Titik terpilih';
          _display =
              '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}';
        }
        _resolving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _label = 'Titik terpilih';
        _display = '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}';
      });
    }
  }

  Future<void> _choose() async {
    final display = (_display.isEmpty ? _label : _display).trim();
    if (display.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alamat belum terbaca. Geser peta lalu coba lagi.')),
      );
      return;
    }
    final entry = MemberShopAddressEntry.fromCoords(
      displayName: display,
      lat: _lat,
      lng: _lng,
      label: _label.trim().isEmpty ? null : _label.trim(),
      kind: widget.saveAsKind ?? ShopAddressKind.custom,
    );
    if (!MemberShopAddressEntry.isValidForShipping(entry)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Titik lokasi tidak valid')),
      );
      return;
    }
    if (widget.saveAsKind == ShopAddressKind.home ||
        widget.saveAsKind == ShopAddressKind.work ||
        widget.saveAsKind == ShopAddressKind.favorite) {
      await MemberShopAddress.instance.savePlace(entry);
    }
    await MemberShopAddress.instance.confirm(entry);
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: OptikMemberTokens.canvas,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: LatLng(_lat, _lng),
              initialZoom: 17,
              onPositionChanged: _onMapMoved,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'optik_b_riski',
              ),
            ],
          ),
          // Pin tetap di tengah (geser peta).
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(
                  Icons.location_on,
                  size: 52,
                  color: OptikMemberTokens.blueDeep,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: OptikMemberTokens.ink,
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip: 'Lokasi saya',
                      onPressed: _goMyLocation,
                      icon: const Icon(Icons.my_location_rounded),
                      color: OptikMemberTokens.blueDeep,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16, 16, 16, 14 + bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x220B3D8C),
                    blurRadius: 20,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _resolving ? 'Mencari alamat…' : _label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: OptikMemberTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _display.isEmpty
                        ? 'Geser peta hingga pin tepat di lokasi Anda'
                        : _display,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: OptikMemberTokens.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: OptikMemberTokens.blueDeep,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _resolving ? null : _choose,
                      child: const Text(
                        'Pilih lokasi ini',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
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
