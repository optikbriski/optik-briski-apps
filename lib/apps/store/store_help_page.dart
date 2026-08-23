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
            child: const RekasaSurface(
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
                    '(pintu yang sama dengan situs perusahaan). '
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
