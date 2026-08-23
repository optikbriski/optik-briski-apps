// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/logistics/kurir_pick_dialog.dart';
import '../../shared/logistics/logistics_google_map.dart';
import '../../shared/logistics/logistics_live_map_rules.dart';
import '../../shared/logistics/logistics_tracking_rules.dart';
import '../../shared/logistics/logistics_tracking_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'do_preparing_page.dart';
import 'verifikasi_terima.dart';

/// Tracking Admin: daftar surat jalan; peta Google hanya setelah tiba di kota.
class LogisticsTrackingPage extends StatefulWidget {
  const LogisticsTrackingPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<LogisticsTrackingPage> createState() => _LogisticsTrackingPageState();
}

class _LogisticsTrackingPageState extends State<LogisticsTrackingPage> {
  final _svc = LogisticsTrackingService();
  final _dt = DateFormat('dd MMM yyyy · HH:mm', 'id_ID');
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _moves = [];
  List<Map<String, dynamic>> _closedMoves = [];
  List<TokoGeo> _toko = [];
  Map<String, dynamic>? _selected;
  bool _busyKurir = false;

  /// DO | RO | RETUR | '' (semua)
  String _kindFilter = '';

  /// '' | preparing | transit | pending
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!LogisticsTrackingRules.bolehBuka(widget.profile)) {
      setState(() {
        _loading = false;
        _error = 'Hanya admin toko/pusat yang boleh buka tracking logistics.';
        _moves = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final moves = await _svc.listOpenMoves(profile: widget.profile);
      List<Map<String, dynamic>> closed = const [];
      try {
        closed = await _svc.listRecentClosedMoves(profile: widget.profile);
      } catch (_) {
        closed = const [];
      }
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
      setState(() {
        _moves = moves;
        _closedMoves = closed;
        _toko = toko;
        _selected = sel;
        _loading = false;
      });
      _ensureSelection();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _moves.where((m) {
      if (_kindFilter.isNotEmpty &&
          LogisticsTrackingService.kindCode(m) != _kindFilter) {
        return false;
      }
      final st = (m['status'] ?? '').toString().toUpperCase();
      if (_statusFilter == 'preparing' &&
          st != 'PREPARING' &&
          st != 'WAITING') {
        return false;
      }
      if (_statusFilter == 'transit' && st != 'TRANSIT') return false;
      if (_statusFilter == 'pending' && st != 'PENDING') return false;

      if (q.isEmpty) return true;
      final kurir = (m['kurir_nama'] ?? '').toString();
      final hay =
          '${m['product_name']} ${m['dari_lokasi']} ${m['ke_lokasi']} $kurir ${m['status']}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _ensureSelection() {
    final list = _filtered;
    if (list.isEmpty) {
      if (_selected != null) setState(() => _selected = null);
      return;
    }
    final id = _selected?['id']?.toString();
    final still = id != null && list.any((m) => m['id']?.toString() == id);
    if (!still) {
      setState(() => _selected = list.first);
    }
  }

  int _countKind(String code) => _moves
      .where((m) => LogisticsTrackingService.kindCode(m) == code)
      .length;

  int _countStatus(bool Function(String st) test) => _moves
      .where((m) => test((m['status'] ?? '').toString().toUpperCase()))
      .length;

  Future<void> _assignKurir([Map<String, dynamic>? target]) async {
    final move = target ?? _selected;
    if (move == null || _busyKurir) return;
    if (!LogisticsTrackingRules.bolehAssignKurir(
      profile: widget.profile,
      dari: move['dari_lokasi']?.toString(),
      status: move['status']?.toString(),
    )) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Hanya gudang asal yang boleh set kurir, dan hanya saat paket masih terbuka.',
        ),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    final isPusat = _svc.isPusatView(widget.profile);
    final picked = await showKurirPickDialog(
      context,
      service: _svc,
      pusatOnly: isPusat,
      tokoId: isPusat ? null : widget.profile['toko_id']?.toString(),
      allowSkip: true,
      title: 'Pilih kurir',
    );
    if (kurirPickCancelled(picked) || !mounted) return;

    setState(() => _busyKurir = true);
    try {
      final id = move['id']?.toString();
      if (id == null || id.isEmpty) throw 'ID surat jalan kosong.';
      if (kurirPickSkipped(picked)) {
        await _svc.clearKurir(id);
      } else {
        await _svc.assignKurir(
          moveId: id,
          karyawanId: picked!['id'].toString(),
          nama: picked['nama']?.toString() ?? '-',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          kurirPickSkipped(picked)
              ? 'Kurir dihapus dari surat jalan.'
              : 'Kurir diset: ${picked!['nama']}',
        ),
        backgroundColor: OptikAdminTokens.success,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal set kurir: $e'),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyKurir = false);
    }
  }

  Future<void> _openPreparing(Map<String, dynamic> m) async {
    final id = m['id']?.toString();
    if (id == null || id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoPreparingPage(
          profile: widget.profile,
          moveId: id,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openVerifikasi() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncomingVerification(profile: widget.profile),
      ),
    );
    if (mounted) _load();
  }

  Color _statusAccent(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'TRANSIT':
        return OptikAdminTokens.warning;
      case 'PENDING':
        return OptikAdminTokens.ice;
      case 'PREPARING':
      case 'WAITING':
        return OptikAdminTokens.navy;
      default:
        return OptikAdminTokens.textMuted;
    }
  }

  String _routeLabel(Map<String, dynamic> m) {
    final dari =
        LogisticsTrackingService.tokoLabel(m['dari_lokasi']?.toString());
    final ke = LogisticsTrackingService.tokoLabel(m['ke_lokasi']?.toString());
    return '$dari → $ke';
  }

  bool _isLive(Map<String, dynamic>? m) {
    if (m == null) return false;
    return LogisticsLiveMapRules.bolehLihatPetaLive(
      profile: widget.profile,
      move: m,
      tripSameCity: _tripFor(m),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final live = _isLive(_selected);

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Tracking Logistics',
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? PremiumEmptyState(
                  message: 'Gagal memuat tracking.\n$_error',
                  icon: Icons.cloud_off_rounded,
                  accent: OptikAdminTokens.danger,
                  action: FilledButton(
                    onPressed: _load,
                    child: const Text('Coba lagi'),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(OptikAdminTokens.spaceLg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _filterBar(),
                      const SizedBox(height: 12),
                      Expanded(
                        child: !live
                            ? _listPanel()
                            : wide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: 360,
                                        child: _listPanel(),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: _detailAndMap(),
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView(
                                    children: [
                                      SizedBox(
                                        height: 280,
                                        child: _listPanel(),
                                      ),
                                      const SizedBox(height: 16),
                                      _detailAndMap(),
                                    ],
                                  ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _filterBar() {
    final nPrep = _countStatus(
        (s) => s == 'PREPARING' || s == 'WAITING');
    final nTransit = _countStatus((s) => s == 'TRANSIT');
    final nPending = _countStatus((s) => s == 'PENDING');

    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (_) {
              setState(() {});
              _ensureSelection();
            },
            style: const TextStyle(color: OptikAdminTokens.navy, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Cari resi, cabang, kurir…',
              hintStyle: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.35),
                fontSize: 13,
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: OptikAdminTokens.navy.withOpacity(0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OptikAdminTokens.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OptikAdminTokens.line),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          PremiumChipWrap(
            children: [
              _chip(
                label: 'Semua (${_moves.length})',
                selected: _kindFilter.isEmpty,
                onTap: () {
                  setState(() => _kindFilter = '');
                  _ensureSelection();
                },
              ),
              _chip(
                label: 'DO (${_countKind('DO')})',
                selected: _kindFilter == 'DO',
                onTap: () {
                  setState(() => _kindFilter = 'DO');
                  _ensureSelection();
                },
              ),
              _chip(
                label: 'RO (${_countKind('RO')})',
                selected: _kindFilter == 'RO',
                onTap: () {
                  setState(() => _kindFilter = 'RO');
                  _ensureSelection();
                },
              ),
              _chip(
                label: 'Retur (${_countKind('RETUR')})',
                selected: _kindFilter == 'RETUR',
                onTap: () {
                  setState(() => _kindFilter = 'RETUR');
                  _ensureSelection();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          PremiumChipWrap(
            children: [
              _chip(
                label: 'Semua status',
                selected: _statusFilter.isEmpty,
                onTap: () {
                  setState(() => _statusFilter = '');
                  _ensureSelection();
                },
              ),
              _chip(
                label: 'Disiapkan ($nPrep)',
                selected: _statusFilter == 'preparing',
                onTap: () {
                  setState(() => _statusFilter = 'preparing');
                  _ensureSelection();
                },
              ),
              _chip(
                label: 'Perjalanan ($nTransit)',
                selected: _statusFilter == 'transit',
                onTap: () {
                  setState(() => _statusFilter = 'transit');
                  _ensureSelection();
                },
              ),
              _chip(
                label: 'Verifikasi ($nPending)',
                selected: _statusFilter == 'pending',
                onTap: () {
                  setState(() => _statusFilter = 'pending');
                  _ensureSelection();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: OptikAdminTokens.navy.withOpacity(0.14),
      checkmarkColor: OptikAdminTokens.navy,
      labelStyle: TextStyle(
        color: OptikAdminTokens.navy,
        fontSize: 11.5,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      side: BorderSide(
        color: selected
            ? OptikAdminTokens.navy.withOpacity(0.45)
            : OptikAdminTokens.line,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _listPanel() {
    final list = _filtered;
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
              'Surat jalan aktif (${list.length})',
              style: const TextStyle(
                color: OptikAdminTokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Divider(color: OptikAdminTokens.line, height: 1),
          Expanded(
            child: list.isEmpty
                ? PremiumEmptyState(
                    message: _moves.isEmpty
                        ? 'Tidak ada paket Disiapkan / dalam perjalanan / menunggu verifikasi.'
                        : 'Tidak ada hasil filter. Ubah pencarian atau chip di atas.',
                    icon: Icons.local_shipping_outlined,
                    accent: OptikAdminTokens.ice,
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: OptikAdminTokens.line, height: 1),
                    itemBuilder: (_, i) {
                      final m = list[i];
                      final selected =
                          _selected?['id']?.toString() == m['id']?.toString();
                      final tipe = LogisticsTrackingService.tipeLabel(m);
                      final st = (m['status'] ?? '').toString();
                      final accent = _statusAccent(st);
                      final kurir = (m['kurir_nama'] ?? '').toString().trim();
                      return ListTile(
                        selected: selected,
                        selectedTileColor:
                            OptikAdminTokens.navy.withOpacity(0.08),
                        title: Text(
                          m['product_name']?.toString() ?? '-',
                          style: const TextStyle(
                            color: OptikAdminTokens.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$tipe · ${_routeLabel(m)}',
                                style: TextStyle(
                                  color: OptikAdminTokens.navy.withOpacity(0.5),
                                  fontSize: 11.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _miniBadge(
                                    LogisticsTrackingService.statusLabel(st),
                                    accent,
                                  ),
                                  if (kurir.isNotEmpty)
                                    _miniBadge(
                                      kurir,
                                      OptikAdminTokens.textMuted,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        isThreeLine: true,
                        onTap: () => setState(() => _selected = m),
                        trailing: LogisticsTrackingRules.bolehAssignKurir(
                          profile: widget.profile,
                          dari: m['dari_lokasi']?.toString(),
                          status: st,
                        )
                            ? IconButton(
                                tooltip: 'Ganti / hapus kurir',
                                onPressed: _busyKurir
                                    ? null
                                    : () => _assignKurir(m),
                                icon: const Icon(
                                  Icons.person_search_rounded,
                                  size: 20,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _kotaOf(String? ke) {
    final t = _findToko(ke);
    if (t == null || !t.hasCoords) return '';
    return LogisticsLiveMapRules.kotaBucket(t.latitude, t.longitude);
  }

  List<Map<String, dynamic>> _tripFor(Map<String, dynamic> move) {
    return LogisticsLiveMapRules.tripSameCity(
      move: move,
      allMoves: [..._moves, ..._closedMoves],
      kotaOf: _kotaOf,
    );
  }

  TokoGeo? _findToko(String? id) {
    if (id == null || id.isEmpty) return null;
    final key = id.toUpperCase();
    for (final t in _toko) {
      if (t.id.toUpperCase() == key) return t;
    }
    return null;
  }

  Widget _detailAndMap() {
    final m = _selected;
    if (m == null) return const SizedBox.shrink();
    final ke = _findToko(m['ke_lokasi']?.toString());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ke != null && ke.hasCoords)
          LogisticsLiveGoogleMap(destination: ke, height: 300)
        else
          Text(
            'Koordinat toko tujuan belum ada. Lengkapi latitude/longitude '
            'di master toko.',
            style: TextStyle(
              color: OptikAdminTokens.warning.withOpacity(0.9),
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        const SizedBox(height: 14),
        _detailCard(m),
      ],
    );
  }

  Widget _detailCard(Map<String, dynamic> m) {
    final created = DateTime.tryParse(m['created_at']?.toString() ?? '');
    final steps = LogisticsTrackingService.timeline(m);
    final verified = (m['verified_by_name'] ?? '').toString().trim();
    final st = (m['status'] ?? '').toString().toUpperCase();
    final tipe = LogisticsTrackingService.tipeLabel(m);
    final kurir = (m['kurir_nama'] ?? '').toString().trim();
    final isPrep = st == 'PREPARING' || st == 'WAITING';
    final isPending = st == 'PENDING';
    final isDo = tipe == 'DO';
    final bolehKurir = LogisticsTrackingRules.bolehAssignKurir(
      profile: widget.profile,
      dari: m['dari_lokasi']?.toString(),
      status: st,
    );

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
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              _miniBadge(tipe, OptikAdminTokens.navy),
              const SizedBox(width: 6),
              _miniBadge(
                LogisticsTrackingService.statusLabel(st),
                _statusAccent(st),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_routeLabel(m)} · ${m['jumlah'] ?? 0} pcs',
            style: const TextStyle(
              color: OptikAdminTokens.textSecondary,
              fontSize: 13,
            ),
          ),
          if (created != null)
            Text(
              'Dibuat: ${_dt.format(created.toLocal())}',
              style: const TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 12,
              ),
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
                          : OptikAdminTokens.line,
                    ),
                  ),
                _stepDot(steps[i].label, steps[i].done, steps[i].current),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            kurir.isNotEmpty ? 'Kurir: $kurir' : 'Kurir: belum ditetapkan',
            style: const TextStyle(
              color: OptikAdminTokens.textSecondary,
              fontSize: 13,
            ),
          ),
          if (verified.isNotEmpty)
            Text(
              'Diterima oleh: $verified',
              style: const TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (bolehKurir)
              FilledButton.icon(
                onPressed: _busyKurir ? null : _assignKurir,
                style: FilledButton.styleFrom(
                  backgroundColor: OptikAdminTokens.navy,
                  foregroundColor: OptikAdminTokens.bg,
                ),
                icon: _busyKurir
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: OptikAdminTokens.bg,
                        ),
                      )
                    : const Icon(Icons.person_search_rounded, size: 18),
                label: Text(
                  kurir.isNotEmpty ? 'Ganti / hapus kurir' : 'Pilih kurir',
                ),
              ),
              if (isDo && isPrep)
                OutlinedButton.icon(
                  onPressed: () => _openPreparing(m),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Buka Disiapkan'),
                ),
              if (isPending)
                OutlinedButton.icon(
                  onPressed: _openVerifikasi,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Verifikasi Terima'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Transit = status teks. Peta Google hanya setelah kurir tiba di kota '
            'tujuan, dan hanya untuk toko yang sedang giliran. Toko yang sudah '
            'verifikasi tidak melihat lagi.',
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.4),
              fontSize: 11,
              height: 1.35,
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
                : OptikAdminTokens.lineStrong,
            border: current
                ? Border.all(color: OptikAdminTokens.navy, width: 1.5)
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: current
                ? OptikAdminTokens.navy
                : OptikAdminTokens.textMuted,
            fontSize: 10,
            fontWeight: current ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
