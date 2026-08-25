import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../shared/karyawan/contribution_rekap.dart';
import '../../shared/karyawan/contribution_rekap_service.dart';
import '../../shared/theme.dart';

/// Dashboard rajin vs males: % vs fair share + flag jadwal timpang.
class ContributionRekapPage extends StatefulWidget {
  const ContributionRekapPage({
    super.key,
    required this.tokoId,
    required this.jabatan,
    this.highlightKaryawanId,
  });

  final String tokoId;
  final String? jabatan;
  final String? highlightKaryawanId;

  @override
  State<ContributionRekapPage> createState() => _ContributionRekapPageState();
}

class _ContributionRekapPageState extends State<ContributionRekapPage> {
  final _svc = ContributionRekapService();
  ContributionRekap? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _svc.loadMonth(
        tokoId: widget.tokoId,
        jabatan: widget.jabatan,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final monthLabel = data == null
        ? ''
        : DateFormat('MMMM yyyy', context.locale.toString())
            .format(data.periodStart);

    return Scaffold(
      backgroundColor: OptikKaryawanTokens.bg,
      appBar: AppBar(
        backgroundColor: OptikKaryawanTokens.snow.withOpacity(0.92),
        foregroundColor: OptikKaryawanTokens.ink,
        elevation: 0,
        title: Text(
          'rekap_kontribusi_title'.tr(),
          style: GoogleFonts.fraunces(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && data == null
          ? const Center(
              child: CircularProgressIndicator(color: OptikKaryawanTokens.cyan),
            )
          : RefreshIndicator(
              color: OptikKaryawanTokens.cyan,
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'rekap_kontribusi_err'.tr(namedArgs: {'error': _error!}),
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  if (data != null) ...[
                    Text(
                      'rekap_kontribusi_sub'.tr(namedArgs: {
                        'layer': data.layerLabel,
                        'month': monthLabel,
                      }),
                      style: TextStyle(
                        color: OptikKaryawanTokens.muted.withOpacity(0.95),
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _summaryCard(data),
                    if (data.hasScheduleImbalance) ...[
                      const SizedBox(height: 12),
                      _warnSchedule(),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'rekap_kontribusi_daftar'.tr(),
                      style: GoogleFonts.fraunces(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (data.peers.isEmpty)
                      Text(
                        'rekap_kontribusi_empty'.tr(),
                        style: TextStyle(
                          color: OptikKaryawanTokens.muted.withOpacity(0.9),
                        ),
                      )
                    else
                      ...data.peers.map(_peerCard),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(ContributionRekap data) {
    final fairPct = (data.fairShare * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OptikKaryawanTokens.snow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OptikKaryawanTokens.cyan.withOpacity(0.25)),
        boxShadow: OptikKaryawanTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'rekap_kontribusi_fair'.tr(namedArgs: {'pct': '$fairPct'}),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: OptikKaryawanTokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'rekap_kontribusi_unit_tim'.tr(namedArgs: {
              'units': '${data.unitTim}',
              'days': '${data.targetHari}',
            }),
            style: TextStyle(
              color: OptikKaryawanTokens.muted.withOpacity(0.95),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'rekap_kontribusi_legend'.tr(),
            style: TextStyle(
              color: OptikKaryawanTokens.muted.withOpacity(0.85),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _warnSchedule() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8C07A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_busy_rounded, color: Color(0xFFB7791F)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'rekap_kontribusi_jadwal_warn'.tr(),
              style: const TextStyle(
                color: Color(0xFF7A4E00),
                fontWeight: FontWeight.w600,
                height: 1.35,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _peerCard(ContributionPeer p) {
    final me = p.karyawanId == widget.highlightKaryawanId;
    final tone = p.isAboveFair
        ? const Color(0xFF1B6B6A)
        : p.isBelowFair
            ? const Color(0xFFB45309)
            : OptikKaryawanTokens.ink;
    final badge = p.isAboveFair
        ? 'rekap_badge_atas'.tr()
        : p.isBelowFair
            ? 'rekap_badge_bawah'.tr()
            : 'rekap_badge_wajar'.tr();
    final delta = p.deltaPp >= 0
        ? '+${p.deltaPp.toStringAsFixed(0)}'
        : p.deltaPp.toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: OptikKaryawanTokens.snow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: me
                ? OptikKaryawanTokens.cyan.withOpacity(0.55)
                : OptikKaryawanTokens.border,
            width: me ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    me ? '${p.nama} · ${'rekap_badge_anda'.tr()}' : p.nama,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: OptikKaryawanTokens.ink,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tone.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: tone,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              p.jabatan,
              style: TextStyle(
                color: OptikKaryawanTokens.muted.withOpacity(0.9),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'rekap_peer_line'.tr(namedArgs: {
                'units': '${p.units}',
                'poin': '${p.poin}',
                'aktual': '${(p.aktualPct * 100).round()}',
                'fair': '${(p.fairShare * 100).round()}',
                'delta': delta,
              }),
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: OptikKaryawanTokens.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'rekap_peer_hari'.tr(namedArgs: {
                'hari': '${p.hariKerja}',
                'target': '${p.targetHari}',
              }),
              style: TextStyle(
                fontSize: 12,
                color: p.scheduleImbalance
                    ? const Color(0xFFB45309)
                    : OptikKaryawanTokens.muted.withOpacity(0.9),
                fontWeight:
                    p.scheduleImbalance ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
