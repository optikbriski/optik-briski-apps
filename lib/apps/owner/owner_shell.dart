import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import 'owner_ui.dart';
import 'pages/owner_akun_page.dart';
import 'pages/owner_alert_page.dart';
import 'pages/owner_bagi_hasil_page.dart';
import 'pages/owner_cabang_page.dart';
import 'pages/owner_laporan_page.dart';
import 'pages/owner_persetujuan_page.dart';
import 'pages/owner_ringkasan_page.dart';
import 'pages/owner_tim_page.dart';

class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key});

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  int _index = 0;

  static const _tabs = [
    _TabSpec('Ringkas', Icons.insights_outlined, Icons.insights_rounded),
    _TabSpec('Lapor', Icons.assessment_outlined, Icons.assessment_rounded),
    _TabSpec('Cabang', Icons.storefront_outlined, Icons.storefront_rounded),
    _TabSpec('Tim', Icons.groups_outlined, Icons.groups_rounded),
    _TabSpec('Bagi', Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded),
    _TabSpec('Setuju', Icons.fact_check_outlined, Icons.fact_check_rounded),
    _TabSpec('Alert', Icons.notifications_none_rounded, Icons.notifications_rounded),
    _TabSpec('Akun', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = const [
      OwnerRingkasanPage(),
      OwnerLaporanPage(),
      OwnerCabangPage(),
      OwnerTimPage(),
      OwnerBagiHasilPage(),
      OwnerPersetujuanPage(),
      OwnerAlertPage(),
      OwnerAkunPage(),
    ];

    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: OptikAdminTokens.bgMid,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + (bottom > 0 ? bottom * 0.35 : 0)),
          decoration: BoxDecoration(
            color: OptikAdminTokens.snow.withOpacity(0.96),
            border: Border(
              top: BorderSide(color: OptikAdminTokens.line.withOpacity(0.9)),
            ),
            boxShadow: [
              BoxShadow(
                color: OptikAdminTokens.navy.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _OwnerNavItem(
                      spec: _tabs[i],
                      selected: _index == i,
                      onTap: () => setState(() => _index = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _OwnerNavItem extends StatelessWidget {
  const _OwnerNavItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? OptikAdminTokens.navy : OptikAdminTokens.slate.withOpacity(0.7);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? OptikAdminTokens.accentSoft.withOpacity(0.65) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? spec.selectedIcon : spec.icon,
              size: 22,
              color: color,
            ),
            const SizedBox(height: 3),
            Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OwnerUi.label(color: color).copyWith(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
