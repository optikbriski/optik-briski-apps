import 'package:flutter/material.dart';

import '../../../shared/bootstrap.dart';
import '../../../shared/theme.dart';
import '../../karyawan/login_karyawan_page.dart';
import '../owner_session.dart';
import '../owner_ui.dart';

/// Akun tab — profile + kontrak + logout back to Karyawan login (same APK).
class OwnerAkunPage extends StatelessWidget {
  const OwnerAkunPage({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar?'),
        content: const Text('Anda akan kembali ke layar masuk.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    OwnerSession.instance.clear();
    await supabase.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginKaryawanPage()),
      (_) => false,
    );
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '-';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  @override
  Widget build(BuildContext context) {
    final p = OwnerSession.instance.profile ?? {};
    final tokoIds = p['toko_ids'];
    final tokoLabel = tokoIds is List
        ? tokoIds.map((e) => e.toString()).join(', ')
        : '-';
    final isUtama = p['owner_type'] == 'utama';

    return OwnerPageFrame(
      title: 'Akun',
      subtitle: isUtama ? 'Owner Utama' : 'Owner Toko',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: OwnerUi.hero(),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: OptikAdminTokens.snow,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (p['nama'] ?? '-').toString(),
                        style: OwnerUi.display(22, color: OptikAdminTokens.snow),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (p['email'] ?? '-').toString(),
                        style: OwnerUi.label(color: OptikAdminTokens.ice),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const OwnerSectionLabel('Kontrak'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: OwnerUi.panel(),
            child: Column(
              children: [
                _InfoRow('Status', '${p['kontrak_status'] ?? '-'}'),
                _InfoRow('Mulai', _fmtDate(p['kontrak_mulai'])),
                _InfoRow('Selesai', _fmtDate(p['kontrak_selesai']), last: true),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const OwnerSectionLabel('Scope cabang'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: OwnerUi.panel(),
            child: Text(
              tokoLabel,
              style: OwnerUi.body(
                color: OptikAdminTokens.navy,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Masuk lewat APK Karyawan yang sama. Shell Owner tidak memakai SOP/absensi/POS harian.',
            style: OwnerUi.label(),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _logout(context),
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.danger,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.last = false});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: OptikAdminTokens.line)),
      ),
      child: Row(
        children: [
          Text(label, style: OwnerUi.label()),
          const Spacer(),
          Text(
            value,
            style: OwnerUi.body(
              color: OptikAdminTokens.navy,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
