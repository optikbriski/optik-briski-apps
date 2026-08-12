import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/karyawan/lab_job_service.dart';
import '../../shared/theme.dart';

class PengingatPage extends StatefulWidget {
  const PengingatPage({super.key});

  @override
  State<PengingatPage> createState() => _PengingatPageState();
}

class _PengingatPageState extends State<PengingatPage> {
  bool _loading = true;
  bool _claimBusy = false;
  List<Map<String, dynamic>> _items = [];
  final _lab = LabJobService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Drop twin rows: prefer unique `id`, else same tipe+judul+local day.
  List<Map<String, dynamic>> _dedupe(List<Map<String, dynamic>> rows) {
    final seenIds = <String>{};
    final seenKeys = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final n in rows) {
      final id = n['id']?.toString();
      if (id != null && id.isNotEmpty) {
        if (!seenIds.add(id)) continue;
      }
      final tipe = (n['tipe'] ?? '').toString().toUpperCase();
      final judul = (n['judul'] ?? '').toString().trim();
      final created = DateTime.tryParse(n['created_at']?.toString() ?? '');
      final day = created == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(created.toLocal());
      final key = '$tipe|$judul|$day';
      if (judul.isNotEmpty && !seenKeys.add(key)) continue;
      out.add(n);
    }
    return out;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _items = [];
          _loading = false;
        });
        return;
      }
      final rows = await Supabase.instance.client
          .from('notifikasi')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _items = _dedupe(List<Map<String, dynamic>>.from(rows));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal muat pengingat: $e')),
      );
    }
  }

  Future<void> _tandaiSemua() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('notifikasi')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('user_id', user.id)
          .filter('read_at', 'is', null);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("pengingat_msg_tandai_sukses".tr())),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _onTapNotif(Map<String, dynamic> n) async {
    final tipe = (n['tipe'] ?? '').toString().toUpperCase();
    final id = n['id']?.toString();
    if (id != null && n['read_at'] == null) {
      try {
        await Supabase.instance.client.from('notifikasi').update({
          'read_at': DateTime.now().toIso8601String(),
        }).eq('id', id);
      } catch (_) {}
    }

    if (tipe != 'LAB') {
      await _load();
      return;
    }

    final jobId = LabJobService.jobIdFromNotifikasiIsi(n['isi']?.toString());
    if (jobId == null || _claimBusy) {
      await _load();
      return;
    }

    setState(() => _claimBusy = true);
    try {
      final res = await _lab.claim(jobId);
      if (!mounted) return;
      final inv = res['no_invoice']?.toString() ?? '-';
      final nama = res['nama']?.toString() ?? '-';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('lab_claim_ok_msg'.tr(args: [inv, nama])),
          backgroundColor: OptikKaryawanTokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikKaryawanTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _claimBusy = false);
      await _load();
    }
  }

  IconData _iconFor(String? tipe) {
    switch ((tipe ?? '').toUpperCase()) {
      case 'SOP':
        return Icons.warning_rounded;
      case 'SHIFT':
        return Icons.calendar_month_rounded;
      case 'ADMIN':
        return Icons.assignment_ind_rounded;
      case 'LAB':
        return Icons.engineering_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String? tipe) {
    switch ((tipe ?? '').toUpperCase()) {
      case 'SOP':
        return OptikKaryawanTokens.danger;
      case 'SHIFT':
        return OptikKaryawanTokens.ink;
      case 'ADMIN':
        return OptikKaryawanTokens.warning;
      case 'LAB':
        return OptikKaryawanTokens.cyan;
      default:
        return OptikKaryawanTokens.cyan;
    }
  }

  List<_NotifSection> _sectionsFor(List<Map<String, dynamic>> items) {
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final dayFmt = DateFormat('d MMM yyyy', 'id_ID');
    final buckets = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];

    for (final n in items) {
      final created = DateTime.tryParse(n['created_at']?.toString() ?? '');
      final local = created?.toLocal();
      final key = local == null
          ? '__unknown__'
          : DateFormat('yyyy-MM-dd').format(local);
      if (!buckets.containsKey(key)) {
        buckets[key] = [];
        order.add(key);
      }
      buckets[key]!.add(n);
    }

    return [
      for (final key in order)
        _NotifSection(
          label: key == todayKey
              ? 'pengingat_hari_ini'.tr()
              : key == '__unknown__'
                  ? 'pengingat_akan_datang'.tr()
                  : dayFmt.format(DateTime.parse(key)),
          items: buckets[key]!,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM HH:mm', 'id_ID');
    final sections = _sectionsFor(_items);

    return KaryawanPremiumScaffold(
      title: "pengingat_title".tr(),
      eyebrow: 'OPTIK B. RISKI',
      actions: [
        IconButton(
          icon: const Icon(Icons.done_all_rounded),
          tooltip: "pengingat_tooltip_tandai".tr(),
          onPressed: _items.isEmpty || _loading ? null : _tandaiSemua,
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFFF5FBFC),
                    Color(0xFFFFFFFF),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -70,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      OptikKaryawanTokens.cyan.withOpacity(0.28),
                      OptikKaryawanTokens.cyan.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 220,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikKaryawanTokens.pale.withOpacity(0.42),
                ),
              ),
            ),
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                color: OptikKaryawanTokens.cyan,
                strokeWidth: 2.6,
              ),
            )
          else if (_items.isEmpty)
            _buildEmptyState()
          else
            RefreshIndicator(
              color: OptikKaryawanTokens.cyan,
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                itemCount: _listSlotCount(sections),
                itemBuilder: (context, index) {
                  return _buildListSlot(
                    sections: sections,
                    index: index,
                    df: df,
                  );
                },
              ),
            ),
          if (_claimBusy)
            ColoredBox(
              color: OptikKaryawanTokens.ink.withOpacity(0.12),
              child: const Center(
                child: CircularProgressIndicator(
                  color: OptikKaryawanTokens.cyan,
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _listSlotCount(List<_NotifSection> sections) {
    var n = 0;
    for (final s in sections) {
      n += 1 + s.items.length; // label + rows
    }
    return n;
  }

  Widget _buildListSlot({
    required List<_NotifSection> sections,
    required int index,
    required DateFormat df,
  }) {
    var cursor = 0;
    var itemIndex = 0;
    for (final section in sections) {
      if (index == cursor) {
        return Padding(
          padding: EdgeInsets.only(top: cursor == 0 ? 4 : 18, bottom: 10),
          child: _sectionLabel(section.label),
        );
      }
      cursor += 1;
      for (final n in section.items) {
        if (index == cursor) {
          final tipe = n['tipe']?.toString();
          final unread = n['read_at'] == null;
          final created =
              DateTime.tryParse(n['created_at']?.toString() ?? '');
          final isLab = (tipe ?? '').toUpperCase() == 'LAB';
          final delay = (itemIndex.clamp(0, 8)) * 35;
          itemIndex += 1;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 420 + delay),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - t)),
                child: child,
              ),
            ),
            child: Opacity(
              opacity: unread ? 1 : 0.72,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(OptikKaryawanTokens.radiusLg),
                  onTap: _claimBusy ? null : () => _onTapNotif(n),
                  child: _buildReminderCard(
                    icon: _iconFor(tipe),
                    iconColor: _colorFor(tipe),
                    title: n['judul']?.toString() ?? '-',
                    description: n['isi']?.toString() ?? '',
                    waktu: created != null
                        ? df.format(created.toLocal())
                        : '-',
                    unread: unread,
                    isUrgent: unread &&
                        ((tipe ?? '').toUpperCase() == 'SOP' || isLab),
                    footer: isLab ? 'lab_queue_btn_kerjakan'.tr() : null,
                  ),
                ),
              ),
            ),
          );
        }
        cursor += 1;
        itemIndex += 1;
      }
    }
    return const SizedBox.shrink();
  }

  Widget _sectionLabel(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: OptikKaryawanTokens.ink,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _softSurface({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(OptikKaryawanTokens.spaceMd),
    bool emphasize = false,
    Color? borderColor,
  }) {
    final radius = BorderRadius.circular(
      emphasize ? OptikKaryawanTokens.radiusXl : OptikKaryawanTokens.radiusLg,
    );
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                OptikKaryawanTokens.snow.withOpacity(emphasize ? 0.96 : 0.92),
                OptikKaryawanTokens.cyan.withOpacity(emphasize ? 0.12 : 0.07),
                OptikKaryawanTokens.snow.withOpacity(0.94),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            border: Border.all(
              color: borderColor ??
                  OptikKaryawanTokens.cyan
                      .withOpacity(emphasize ? 0.32 : 0.18),
              width: borderColor != null ? 1.4 : 1,
            ),
            boxShadow: OptikKaryawanTokens.cardShadow,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _softSurface(
          emphasize: true,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikKaryawanTokens.cyan.withOpacity(0.16),
                  border: Border.all(
                    color: OptikKaryawanTokens.cyan.withOpacity(0.28),
                  ),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 32,
                  color: OptikKaryawanTokens.ink,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Belum ada pengingat.',
                textAlign: TextAlign.center,
                style: GoogleFonts.fraunces(
                  color: OptikKaryawanTokens.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Jadwal, SOP, dan update lab akan muncul di sini.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: OptikKaryawanTokens.muted.withOpacity(0.95),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReminderCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String waktu,
    required bool unread,
    bool isUrgent = false,
    String? footer,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _softSurface(
        emphasize: unread,
        borderColor: isUrgent
            ? OptikKaryawanTokens.danger.withOpacity(0.45)
            : unread
                ? OptikKaryawanTokens.cyan.withOpacity(0.36)
                : null,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (unread)
              Container(
                width: 3.5,
                height: 54,
                margin: const EdgeInsets.only(right: 12, top: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isUrgent
                        ? [
                            OptikKaryawanTokens.danger,
                            OptikKaryawanTokens.danger.withOpacity(0.55),
                          ]
                        : [
                            OptikKaryawanTokens.cyan,
                            OptikKaryawanTokens.pale,
                          ],
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withOpacity(0.12),
                border: Border.all(color: iconColor.withOpacity(0.22)),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight:
                                unread ? FontWeight.w800 : FontWeight.w700,
                            fontSize: 14.5,
                            letterSpacing: -0.15,
                            color: OptikKaryawanTokens.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        waktu,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: OptikKaryawanTokens.muted.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: OptikKaryawanTokens.muted.withOpacity(0.95),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (footer != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: OptikKaryawanTokens.cyan.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: OptikKaryawanTokens.cyan.withOpacity(0.28),
                        ),
                      ),
                      child: Text(
                        footer,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: OptikKaryawanTokens.ink,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifSection {
  const _NotifSection({required this.label, required this.items});
  final String label;
  final List<Map<String, dynamic>> items;
}
