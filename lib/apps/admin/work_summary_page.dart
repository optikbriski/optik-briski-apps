import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/attendance/attendance_dinas.dart';
import '../../shared/finance/omzet_masuk.dart';
import '../../shared/karyawan/contribution_rekap.dart';
import '../../shared/karyawan/shift_auto_assign.dart';
import '../../shared/karyawan/work_summary_service.dart';
import '../../shared/tenant/tenant_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'toko_detail_panel.dart';

/// Dashboard admin: jam, omzet, SOP cabang, siapa bertugas, rekap Front/Back.
class AdminWorkSummaryPage extends StatefulWidget {
  const AdminWorkSummaryPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<AdminWorkSummaryPage> createState() => _AdminWorkSummaryPageState();
}

class _AdminWorkSummaryPageState extends State<AdminWorkSummaryPage>
    with WidgetsBindingObserver {
  final _svc = WorkSummaryService();
  bool _loading = true;
  bool _omzetLoading = true;
  String? _error;
  WorkSummarySnapshot? _data;
  List<String> _tokoOptions = [];
  late String _tokoId;
  int _omzetHari = 0;
  int _omzetBulan = 0;
  Timer? _liveTick;

  @override
  void initState() {
    super.initState();
    _tokoId = AttendanceAdminScope.tokoOf(widget.profile);
    WidgetsBinding.instance.addObserver(this);
    _liveTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _loading) return;
      unawaited(_reload(silent: true));
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _liveTick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reload(silent: true));
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows =
          await Supabase.instance.client.from('toko_id').select('id').order('id');
      final all = [
        for (final r in rows) r['id']?.toString() ?? '',
      ].where((e) => e.isNotEmpty).toList();
      _tokoOptions =
          AttendanceAdminScope.filterTokoForMonitor(all, widget.profile);
      if (_tokoId.isEmpty || !_tokoOptions.contains(_tokoId)) {
        _tokoId = _tokoOptions.isEmpty ? _tokoId : _tokoOptions.first;
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _omzetLoading = false;
      });
    }
  }

  Future<void> _reload({bool silent = false, bool forceStoryRefresh = false}) async {
    if (_tokoId.trim().isEmpty) {
      setState(() {
        _loading = false;
        _omzetLoading = false;
        _error = null;
        _data = null;
        _omzetHari = 0;
        _omzetBulan = 0;
      });
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _omzetLoading = true;
        _error = null;
      });
    }
    try {
      final dataFuture = _svc.load(
        tokoId: _tokoId,
        forceStoryRefresh: forceStoryRefresh,
      );
      final omzetFuture = _fetchOmzet(_tokoId);
      final data = await dataFuture;
      var omzet = (hari: _omzetHari, bulan: _omzetBulan);
      try {
        omzet = await omzetFuture;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _data = data;
        _omzetHari = omzet.hari;
        _omzetBulan = omzet.bulan;
        _loading = false;
        _omzetLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && _data != null) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _omzetLoading = false;
      });
    }
  }

  Future<({int hari, int bulan})> _fetchOmzet(String tokoId) async {
    final bulan = omzetRangeJakartaUtc(bulanIni: true);
    final hari = omzetRangeJakartaUtc(bulanIni: false);
    final keys = AttendanceAdminScope.storeIdAliases(tokoId);
    final storeKeys = keys.isEmpty ? [tokoId.trim()] : keys;
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    final tid = TenantService.instance.id;
    while (true) {
      var q = Supabase.instance.client
          .from('sales')
          .select('total_harga, sisa_tagihan, status_pembayaran, created_at')
          .inFilter('toko_id', storeKeys)
          .gte('created_at', bulan.startUtc.toIso8601String())
          .lt('created_at', bulan.endExclusiveUtc.toIso8601String());
      if (tid != null && tid.isNotEmpty) q = q.eq('tenant_id', tid);
      final page = await q.order('created_at').range(from, from + pageSize - 1);
      final chunk = List<Map<String, dynamic>>.from(page as List);
      rows.addAll(chunk);
      if (chunk.length < pageSize) break;
      from += pageSize;
    }
    var hariIni = 0;
    var bulanIni = 0;
    for (final item in rows) {
      final masuk = uangMasukDariSale(item);
      if (masuk <= 0) continue;
      bulanIni += masuk;
      if (saleDalamRentangUtc(
        item,
        startUtc: hari.startUtc,
        endExclusiveUtc: hari.endExclusiveUtc,
      )) {
        hariIni += masuk;
      }
    }
    return (hari: hariIni, bulan: bulanIni);
  }

  Future<void> _pickToko() async {
    if (_tokoOptions.length < 2) return;
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'work_sum_toko'.tr(),
      selected: _tokoId,
      options: [
        for (final t in _tokoOptions) AdminPickerOption(value: t, label: t),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    setState(() => _tokoId = sel.value!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return PremiumScaffold(
      body: RefreshIndicator(
        color: OptikAdminTokens.navy,
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            _DashboardHero(
              omzetHari: _omzetHari,
              omzetBulan: _omzetBulan,
              omzetLoading: _omzetLoading,
              refreshing: _loading,
              onRefresh: _loading ? null : _reload,
            ),
            const SizedBox(height: 14),
            if (_tokoId.isNotEmpty) ...[
              _storeChip(),
              const SizedBox(height: 14),
              TokoDetailPanel(
                key: ValueKey('toko-detail-$_tokoId'),
                profile: widget.profile,
                tokoId: _tokoId,
                onSaved: () => unawaited(_reload(silent: true)),
              ),
              const SizedBox(height: 16),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'work_sum_err'.tr(namedArgs: {'error': _error!}),
                  style: TextStyle(color: OptikAdminTokens.warning),
                ),
              ),
            if (_loading && data == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: CircularProgressIndicator(color: OptikAdminTokens.navy),
                ),
              )
            else if (data != null) ...[
              _sopPanel(data),
              const SizedBox(height: 14),
              _counts(data),
              const SizedBox(height: 20),
              PremiumSectionHeader(label: 'work_sum_tim'.tr()),
              if (data.people.isEmpty)
                PremiumEmptyState(message: 'work_sum_empty'.tr())
              else
                ...data.people.map(_personTile),
              const SizedBox(height: 18),
              _monthBlock(
                title: 'work_sum_front_bulan'.tr(),
                unit: 'work_sum_unit_invoice'.tr(),
                rekap: data.frontMonth,
              ),
              const SizedBox(height: 12),
              _monthBlock(
                title: 'work_sum_back_bulan'.tr(),
                unit: 'work_sum_unit_kacamata'.tr(),
                rekap: data.backMonth,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _storeChip() {
    final canPick = _tokoOptions.length > 1;
    return PremiumPanel(
      onTap: canPick ? _pickToko : null,
      showAccentBar: true,
      padding: const EdgeInsets.fromLTRB(4, 12, 14, 12),
      borderRadius: 18,
      child: Row(
        children: [
          Icon(Icons.storefront_rounded, color: OptikAdminTokens.navy, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _tokoId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (canPick)
            Icon(
              Icons.expand_more_rounded,
              color: OptikAdminTokens.navy.withOpacity(0.55),
            ),
        ],
      ),
    );
  }

  Widget _sopPanel(WorkSummarySnapshot data) {
    final s = data.sop;
    return PremiumPanel(
      showAccentBar: true,
      padding: const EdgeInsets.fromLTRB(4, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PremiumSectionHeader(
            label: 'work_sum_sop'.tr(),
            padding: const EdgeInsets.only(bottom: 12),
          ),
          if (s.igConfigured) ...[
            Text(
              (s.igUsername ?? '').trim().isEmpty
                  ? 'work_sum_ig_linked'.tr()
                  : 'work_sum_ig_linked_user'.tr(
                      namedArgs: {'user': '@${s.igUsername}'},
                    ),
              style: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.75),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if ((s.storyError ?? '').trim().isNotEmpty) ...[
            Text(
              s.storyError!,
              style: TextStyle(
                color: OptikAdminTokens.warning,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (s.storyCount == 0 && data.people.any((p) => p.fatalStory)) ...[
            Text(
              'work_sum_fatal'.tr(),
              style: TextStyle(
                color: OptikAdminTokens.danger,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
          ],
          PremiumStatGrid(
            items: [
              PremiumStatItem(
                label: 'work_sum_story'.tr(),
                value: '${s.storyCount}/8',
                color: s.storyCount == 0
                    ? OptikAdminTokens.danger
                    : OptikAdminTokens.navy,
              ),
              PremiumStatItem(
                label: 'work_sum_display'.tr(),
                value: '${s.displayDone}/${s.displayRequired}',
                color: OptikAdminTokens.navy,
              ),
              PremiumStatItem(
                label: 'work_sum_sapu'.tr(),
                value: s.sapuDone ? 'work_sum_ok'.tr() : 'work_sum_no'.tr(),
                color: s.sapuDone
                    ? OptikAdminTokens.success
                    : OptikAdminTokens.warning,
              ),
              PremiumStatItem(
                label: 'work_sum_stok'.tr(),
                value: s.stokDone ? 'work_sum_ok'.tr() : 'work_sum_no'.tr(),
                color: s.stokDone
                    ? OptikAdminTokens.success
                    : OptikAdminTokens.warning,
              ),
            ],
          ),
          if (s.igConfigured) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading
                    ? null
                    : () => _reload(forceStoryRefresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('work_sum_ig_cek'.tr()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _counts(WorkSummarySnapshot data) {
    return PremiumStatGrid(
      items: [
        PremiumStatItem(
          label: 'work_sum_bertugas'.tr(),
          value: '${data.countBertugas}',
          color: OptikAdminTokens.success,
        ),
        PremiumStatItem(
          label: 'work_sum_belum'.tr(),
          value: '${data.countBelum}',
          color: OptikAdminTokens.warning,
        ),
        PremiumStatItem(
          label: 'work_sum_pulang'.tr(),
          value: '${data.countPulang}',
          color: OptikAdminTokens.slate,
        ),
        PremiumStatItem(
          label: 'work_sum_libur'.tr(),
          value: '${data.countLibur}',
          color: OptikAdminTokens.ice,
        ),
      ],
    );
  }

  Widget _personTile(WorkSummaryPerson p) {
    final layer = p.layer == OfficeLayer.back
        ? 'kpi_layer_back'.tr()
        : 'kpi_layer_front'.tr();
    final jam = (p.jamMasuk != null && p.jamPulang != null)
        ? '${p.jamMasuk}–${p.jamPulang}'
        : '';
    final sub = [
      layer,
      if (p.jabatan.trim().isNotEmpty) p.jabatan,
      if (jam.isNotEmpty) jam,
      'SOP ${p.sopPoin > 0 ? '+' : ''}${p.sopPoin}',
    ].join(' · ');
    return PremiumListTile(
      title: p.nama,
      subtitle: sub,
      icon: p.layer == OfficeLayer.front
          ? Icons.storefront_rounded
          : Icons.handyman_outlined,
      trailing: _statusChip(p.status),
    );
  }

  Widget _statusChip(WorkDutyStatus s) {
    final (label, color) = switch (s) {
      WorkDutyStatus.bertugas => (
          'work_sum_bertugas'.tr(),
          OptikAdminTokens.success
        ),
      WorkDutyStatus.belumMasuk => (
          'work_sum_belum'.tr(),
          OptikAdminTokens.warning
        ),
      WorkDutyStatus.pulang => ('work_sum_pulang'.tr(), OptikAdminTokens.slate),
      WorkDutyStatus.libur => (
          'work_sum_libur'.tr(),
          OptikAdminTokens.textMuted
        ),
      WorkDutyStatus.noJadwal => (
          'work_sum_no_jadwal'.tr(),
          OptikAdminTokens.danger
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _monthBlock({
    required String title,
    required String unit,
    required ContributionRekap rekap,
  }) {
    final fairPct = (rekap.fairShare * 100).round();
    return PremiumPanel(
      showAccentBar: true,
      padding: const EdgeInsets.fromLTRB(4, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: GoogleFonts.fraunces(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${rekap.unitTim} $unit · ${'rekap_kontribusi_fair'.tr(namedArgs: {'pct': '$fairPct'})}',
            style: TextStyle(
              color: OptikAdminTokens.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (rekap.hasScheduleImbalance) ...[
            const SizedBox(height: 6),
            Text(
              'rekap_kontribusi_jadwal_warn'.tr(),
              style: TextStyle(
                color: OptikAdminTokens.warning,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (rekap.peers.isEmpty)
            Text(
              'rekap_kontribusi_empty'.tr(),
              style: TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 13,
              ),
            )
          else
            ...rekap.peers.take(8).map((p) {
              final badge = p.isAboveFair
                  ? 'rekap_badge_atas'.tr()
                  : p.isBelowFair
                      ? 'rekap_badge_bawah'.tr()
                      : 'rekap_badge_wajar'.tr();
              final bar = rekap.unitTim <= 0
                  ? 0.0
                  : (p.units / rekap.unitTim).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.nama,
                            style: TextStyle(
                              color: OptikAdminTokens.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${p.units} $unit · ${(p.aktualPct * 100).round()}%',
                          style: TextStyle(
                            color: OptikAdminTokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          badge,
                          style: TextStyle(
                            color: p.isBelowFair
                                ? OptikAdminTokens.warning
                                : OptikAdminTokens.slate,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: bar,
                        minHeight: 4,
                        backgroundColor: OptikAdminTokens.ice.withOpacity(0.45),
                        color: p.isBelowFair
                            ? OptikAdminTokens.warning
                            : OptikAdminTokens.navy,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _DashboardHero extends StatefulWidget {
  const _DashboardHero({
    required this.omzetHari,
    required this.omzetBulan,
    required this.omzetLoading,
    required this.refreshing,
    this.onRefresh,
  });

  final int omzetHari;
  final int omzetBulan;
  final bool omzetLoading;
  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  State<_DashboardHero> createState() => _DashboardHeroState();
}

class _DashboardHeroState extends State<_DashboardHero> {
  Timer? _tick;
  DateTime _now = AttendanceDinas.nowWall();

  static String _rupiah(int val) {
    return 'Rp ${val.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        )}';
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = AttendanceDinas.nowWall());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.toString();
    final time = DateFormat('HH:mm:ss').format(_now);
    final date = DateFormat('admin_gl_row_1000bc2813'.tr(), locale).format(_now);
    return PremiumPanel(
      showAccentBar: true,
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(6, 20, 18, 20),
      child: Stack(
        children: [
          Column(
            children: [
              Text(
                time,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 48,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                date,
                textAlign: TextAlign.center,
                style: GoogleFonts.fraunces(
                  color: OptikAdminTokens.slate,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      OptikAdminTokens.ice.withOpacity(0),
                      OptikAdminTokens.chromeEdge,
                      OptikAdminTokens.ice.withOpacity(0),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _omzetCol(
                      label: 'dash_omzet_periode_hari'.tr(),
                      value: _rupiah(widget.omzetHari),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 56,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: OptikAdminTokens.chromeEdge.withOpacity(0.7),
                  ),
                  Expanded(
                    child: _omzetCol(
                      label: 'dash_omzet_periode_bulan'.tr(),
                      value: _rupiah(widget.omzetBulan),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'dash_omzet_uang_masuk'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: OptikAdminTokens.slate.withOpacity(0.9),
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              tooltip: 'work_sum_title'.tr(),
              onPressed: widget.onRefresh,
              visualDensity: VisualDensity.compact,
              icon: widget.refreshing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: OptikAdminTokens.navy,
                      ),
                    )
                  : Icon(
                      Icons.refresh_rounded,
                      color: OptikAdminTokens.navy,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _omzetCol({required String label, required String value}) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: OptikAdminTokens.slate.withOpacity(0.9),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        widget.omzetLoading
            ? SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(
                  color: OptikAdminTokens.navy,
                  strokeWidth: 2.2,
                ),
              )
            : Text(
                value,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  color: OptikAdminTokens.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  height: 1.05,
                ),
              ),
      ],
    );
  }
}
