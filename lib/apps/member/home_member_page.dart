import 'package:flutter/material.dart';

/// Placeholder home for member app.
class HomeMemberPage extends StatelessWidget {
  const HomeMemberPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Member'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Selamat datang',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Halaman ini akan diisi poin loyalty, riwayat transaksi, '
            'dan promo. Data akan diambil dari Supabase yang sama dengan Admin.',
          ),
          const SizedBox(height: 24),
          _placeholderCard(
            context,
            icon: Icons.stars_outlined,
            title: 'Poin saya',
            subtitle: 'Segera hadir',
          ),
          _placeholderCard(
            context,
            icon: Icons.receipt_long_outlined,
            title: 'Riwayat belanja',
            subtitle: 'Segera hadir',
          ),
          _placeholderCard(
            context,
            icon: Icons.local_offer_outlined,
            title: 'Promo',
            subtitle: 'Segera hadir',
          ),
        ],
      ),
    );
  }

  Widget _placeholderCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0F766E)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$title masih dalam pengembangan')),
          );
        },
      ),
    );
  }
}
