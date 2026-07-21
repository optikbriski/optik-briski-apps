import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'member_rating_page.dart';

/// Home Member: rating karyawan + placeholder fitur lain.
class HomeMemberPage extends StatelessWidget {
  const HomeMemberPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('member_home_title'.tr()),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'member_home_welcome'.tr(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'member_home_desc'.tr(),
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 24),
          _card(
            context,
            icon: Icons.star_rate_rounded,
            title: 'member_rating_title'.tr(),
            subtitle: 'member_rating_tile_sub'.tr(),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MemberRatingPage()),
            ),
          ),
          _card(
            context,
            icon: Icons.stars_outlined,
            title: 'Poin saya',
            subtitle: 'Segera hadir',
            onTap: () => _soon(context, 'Poin saya'),
          ),
          _card(
            context,
            icon: Icons.receipt_long_outlined,
            title: 'Riwayat belanja',
            subtitle: 'Segera hadir',
            onTap: () => _soon(context, 'Riwayat belanja'),
          ),
          _card(
            context,
            icon: Icons.local_offer_outlined,
            title: 'Promo',
            subtitle: 'Segera hadir',
            onTap: () => _soon(context, 'Promo'),
          ),
        ],
      ),
    );
  }

  void _soon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title masih dalam pengembangan')),
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0F766E)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
