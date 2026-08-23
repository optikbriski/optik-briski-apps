import 'package:flutter/material.dart';

import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/widgets/rekasa_surface.dart';

class StoreHelpPage extends StatelessWidget {
  const StoreHelpPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = ListView(
        children: [
          RekasaPage(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
            child: Column(
              children: [
                const RekasaSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Satu mesin, banyak bidang',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: RekasaTokens.ink,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Pilih bidang dan paket di etalase, lalu bayar via Midtrans '
                        '(bentukannya sama dengan situs: bidang → paket → Midtrans). '
                        'Setelah itu buka Akun: daftar/masuk dengan email, '
                        'kode usaha, dan HP yang sama — usaha terikat ke merek Anda.',
                        style: TextStyle(height: 1.45),
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Portal Akun di sini = pembayaran langganan, kontrak, paket. '
                        'Bukan kasir.',
                        style: TextStyle(height: 1.45),
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Kasir / stok / absensi / member: install APK Admin atau '
                        'Karyawan yang dibeli, login isi kode usaha '
                        '(atau APK merek sendiri paket A).',
                        style: TextStyle(height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  decoration: BoxDecoration(
                    color: RekasaTokens.inkDeep,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RekasaEyebrow('Identitas hukum'),
                      SizedBox(height: 12),
                      Text(
                        'REKASA KARYA INDONESIA',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Perseroan Perorangan. Keputusan Menteri Hukum Republik '
                        'Indonesia Nomor AHU-A011645.AH.01.31.Tahun 2026 tentang '
                        'Perubahan Badan Hukum Perseroan Perorangan REKASA KARYA INDONESIA.',
                        style: TextStyle(height: 1.45, color: Color(0xFFD6E5F7)),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Pemilik: Natanael Demetrius Riscton. Bentuk badan: '
                        'Perseroan Perorangan.',
                        style: TextStyle(height: 1.45, color: Color(0xFFD6E5F7)),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Produk: perangkat lunak sebagai layanan (SaaS). '
                        'Tidak ada gudang barang, tidak ada pengiriman fisik.',
                        style: TextStyle(height: 1.45, color: Color(0xFFD6E5F7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
    );
    if (embedded) return body;
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      appBar: AppBar(title: const Text('Bantuan')),
      body: body,
    );
  }
}
