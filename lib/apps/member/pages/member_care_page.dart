import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../member_widgets.dart';

class MemberCarePage extends StatelessWidget {
  const MemberCarePage({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = <(String, List<String>)>[
      (
        'Membersihkan',
        [
          'Cuci dengan air bersih dan sabun lembut khusus lensa.',
          'Keringkan dengan lap microfiber — hindari baju/tisu kasar.',
          'Lepas kacamata saat olahraga kontak atau berenang.',
        ],
      ),
      (
        'Kontrol berkala',
        [
          'Kontrol ukuran jika pandangan mulai tidak nyaman.',
          'Ambil janji kontrol di app agar diprioritaskan di toko.',
        ],
      ),
      (
        'Yang bisa membatalkan garansi',
        [
          'Kerusakan karena benturan / terjatuh / disengaja.',
          'Modifikasi sendiri di luar Optik B. Riski.',
          'Kehilangan kacamata — bukan tanggung jawab toko.',
        ],
      ),
    ];

    return MemberPremiumScaffold(
      title: 'Panduan perawatan',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final s in sections) ...[
            MemberSectionLabel(s.$1),
            ...s.$2.map(
              (t) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: OptikMemberTokens.white,
                  borderRadius:
                      BorderRadius.circular(OptikMemberTokens.radiusSm),
                  border: Border.all(color: OptikMemberTokens.lineSoft),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: OptikMemberTokens.blue, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(t,
                          style: const TextStyle(
                              height: 1.4,
                              color: OptikMemberTokens.ink,
                              fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
