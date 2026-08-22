import 'package:flutter/material.dart';

import '../../../shared/garansi/garansi_service.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_warranty_list_page.dart';
import '../../../shared/brand/brand_service.dart';

class MemberCarePage extends StatelessWidget {
  const MemberCarePage({super.key});

  @override
  Widget build(BuildContext context) {
    final hari = GaransiService.garansiHari;
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
        'Masa & cara klaim garansi',
        [
          'Garansi aktif $hari hari sejak barang diambil di toko (hari diambil sampai hari ke-$hari).',
          'Lebih dari $hari hari sejak diambil → garansi mati, tidak bisa klaim.',
          'Klaim wajib datang ke toko membawa barang + nota/QR CLAIM.',
          'App hanya mengajukan niat; keputusan setelah petugas cek fisik.',
          'Maksimal 1× klaim per transaksi pembelian.',
        ],
      ),
      (
        'Yang bisa membatalkan garansi',
        [
          'Kerusakan karena benturan / terjatuh / disengaja.',
          'Modifikasi sendiri di luar ${BrandService.name}.',
          'Kehilangan kacamata — bukan tanggung jawab toko.',
        ],
      ),
    ];

    return MemberPremiumScaffold(
      title: 'Panduan perawatan',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MemberWarrantyListPage(),
              ),
            ),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Lihat kartu garansi'),
          ),
          const SizedBox(height: 16),
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
