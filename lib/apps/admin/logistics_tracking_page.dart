// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/logistics/kurir_pick_dialog.dart';
import '../../shared/logistics/logistics_osm_map.dart';
import '../../shared/logistics/logistics_tracking_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Tracking gratis Admin: list surat jalan + detail/kurir + peta OSM.
class LogisticsTrackingPage extends StatefulWidget {
  const LogisticsTrackingPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<LogisticsTrackingPage> createState() => _LogisticsTrackingPageState();
}

class _LogisticsTrackingPageState extends State<LogisticsTrackingPage> {
  final _svc = LogisticsTrackingService();
  final _dt = DateFormat('dd MMM yyyy HH:mm');

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _moves = [];
  List<TokoGeo> _toko = [];
  Map<String, dynamic>? _selected;
  bool _busyKurir = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final moves = await _svc.listOpenMoves(profile: widget.profile);
      final toko = await _svc.listTokoGeo();
      if (!mounted) return;
      Map<String, dynamic>? sel;
      final prevId = _selected?['id']?.toString();
      if (prevId != null) {
        for (final m in moves) {
          if (m['id']?.toString() == prevId) {
            sel = m;
            break;
          }
        }
      }
      sel ??= moves.isNotEmpty ? moves.first : null;
      setState(() {
        _moves = moves;
        _toko = toko;
        _selected = sel;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _assignKurir() async {
    final move = _selected;
    if (move == null || _busyKurir) return;
    final isPusat = _svc.isPusatView(widget.profile);
    final picked = await showKurirPickDialog(
      context,
      service: _svc,
      pusatOnly: isPusat,
      tokoId: isPusat ? null : widget.profile['toko_id']?.toString(),
      allowSkip: true,
      title: 'Assign kurir',
    );
    if (kurirPickCancelled(picked) || !mounted) return;

    setState(() => _busyKurir = true);
    try {
      final id = move['id']?.toString();
      if (id == null) throw 'ID surat jalan kosong.';
      if (kurirPickSkipped(picked)) {
        await _svc.clearKurir(id);
      } else {
        await _svc.assignKurir(
          moveId: id,
          karyawanId: picked!['id'].toString(),
          nama: picked['nama']?.toString() ?? '-',
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busyKurir = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Tracking Logistics',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
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
                        Text(_error!,
                            style: const TextStyle(color: Colors.redAccent),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Coba lagi')),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(OptikAdminTokens.spaceLg),
                  child: wide
                      ? SizedBox.expand(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 340, child: _listPanel()),
                              const SizedBox(width: 16),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: _detailAndMap(),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          children: [
                            SizedBox(height: 280, child: _listPanel()),
                            const SizedBox(height: 16),
                            _detailAndMap(),
                          ],
                        ),
                ),
    );
  }

  Widget _listPanel() {
    return Container(
      decoration: BoxDecoration(
        color: OptikAdminTokens.card.withOpacity(0.55),
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusMd),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              'Surat jalan aktif (${_moves.length})',
              style: const TextStyle(
                color: OptikAdminTokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: _moves.isEmpty
                ? const Center(
                    child: Text(
                      'Tidak ada paket WAITING / TRANSIT / PENDING.',
                      style: TextStyle(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: _moves.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (_, i) {
                      final m = _moves[i];
                      final selected =
                          _selected?['id']?.toString() == m['id']?.toString();
                      final tipe = LogisticsTrackingService.tipeLabel(m);
                      return ListTile(
                        selected: selected,
                        selectedTileColor: OptikAdminTokens.accent.withOpacity(0.12),
                        title: Text(
                          m['product_name']?.toString() ?? '-',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '$tipe · ${m['dari_lokasi']} → ${m['ke_lokasi']}\n'
                          '${LogisticsTrackingService.statusLabel(m['status']?.toString())}'
                          '${m['kurir_nama'] != null ? ' · ${m['kurir_nama']}' : ''}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                        isThreeLine: true,
                        onTap: () => setState(() => _selected = m),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _detailAndMap() {
    final m = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LogisticsOsmMap(
          toko: _toko,
          selectedMove: m,
          height: 300,
        ),
        const SizedBox(height: 14),
        if (m == null)
          const Text(
            'Pilih surat jalan di daftar untuk melihat detail & rute.',
            style: TextStyle(color: Colors.white54),
          )
        else
          _detailCard(m),
      ],
    );
  }

  Widget _detailCard(Map<String, dynamic> m) {
    final created = DateTime.tryParse(m['created_at']?.toString() ?? '');
    final steps = LogisticsTrackingService.timeline(m);
    final verified = m['verified_by_name']?.toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OptikAdminTokens.card.withOpacity(0.6),
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusMd),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m['product_name']?.toString() ?? '-',
                  style: const TextStyle(
                    color: OptikAdminTokens.warning,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: OptikAdminTokens.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  LogisticsTrackingService.tipeLabel(m),
                  style: const TextStyle(
                    color: OptikAdminTokens.accentSoft,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${m['dari_lokasi']} → ${m['ke_lokasi']} · '
            '${m['jumlah'] ?? 0} pcs',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (created != null)
            Text(
              'Dibuat: ${_dt.format(created.toLocal())}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: steps[i].done
                          ? OptikAdminTokens.success.withOpacity(0.7)
                          : Colors.white12,
                    ),
                  ),
                _stepDot(steps[i].label, steps[i].done, steps[i].current),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Kurir: ${m['kurir_nama']?.toString().trim().isNotEmpty == true ? m['kurir_nama'] : '— belum di-assign'}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (verified != null && verified.isNotEmpty)
            Text(
              'Diterima oleh: $verified',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busyKurir ? null : _assignKurir,
              style: FilledButton.styleFrom(
                backgroundColor: OptikAdminTokens.accent,
                foregroundColor: Colors.white,
              ),
              icon: _busyKurir
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_search_rounded, size: 18),
              label: Text(
                m['kurir_nama'] != null ? 'Ganti / hapus kurir' : 'Assign kurir',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepDot(String label, bool done, bool current) {
    return Column(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? (current ? OptikAdminTokens.warning : OptikAdminTokens.success)
                : Colors.white24,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: current ? Colors.white : Colors.white54,
            fontSize: 10,
            fontWeight: current ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
