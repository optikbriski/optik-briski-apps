import 'package:flutter/material.dart';

import '../../shared/brand/rekasa_tokens.dart';

/// Bilah bawah etalase — pola APK HP, bukan kartu yang ikut scroll.
class StoreBottomNav extends StatelessWidget {
  const StoreBottomNav({
    super.key,
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  static const labels = ['Etalase', 'Akun', 'Kontrak', 'Bantuan'];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RekasaTokens.paper,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ColoredBox(
            color: RekasaTokens.sky,
            child: SizedBox(height: 1, width: double.infinity),
          ),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: onChanged,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront_rounded),
                label: 'Etalase',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Akun',
              ),
              NavigationDestination(
                icon: Icon(Icons.draw_outlined),
                selectedIcon: Icon(Icons.draw_rounded),
                label: 'Kontrak',
              ),
              NavigationDestination(
                icon: Icon(Icons.help_outline_rounded),
                selectedIcon: Icon(Icons.help_rounded),
                label: 'Bantuan',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
