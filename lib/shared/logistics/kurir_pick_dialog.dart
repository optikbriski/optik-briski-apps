// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

import '../theme.dart';
import 'logistics_tracking_service.dart';

/// Pilih kurir (opsional). Return map karyawan, atau null jika batal / lewati.
Future<Map<String, dynamic>?> showKurirPickDialog(
  BuildContext context, {
  required LogisticsTrackingService service,
  String? tokoId,
  bool pusatOnly = false,
  bool allowSkip = true,
  String title = 'Pilih kurir (opsional)',
}) async {
  final list = await service.listKaryawanAktif(
    tokoId: tokoId,
    pusatOnly: pusatOnly,
  );
  if (!context.mounted) return null;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: OptikAdminTokens.bgMid,
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: SizedBox(
          width: 360,
          height: 360,
          child: list.isEmpty
              ? const Center(
                  child: Text(
                    'Tidak ada karyawan aktif.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, i) {
                    final k = list[i];
                    return ListTile(
                      leading: const Icon(Icons.delivery_dining_rounded,
                          color: OptikAdminTokens.accentSoft),
                      title: Text(
                        k['nama']?.toString() ?? '-',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${k['nik'] ?? '-'} · ${k['toko_id'] ?? '-'}'
                        '${k['jabatan'] != null ? ' · ${k['jabatan']}' : ''}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                      onTap: () => Navigator.pop(ctx, k),
                    );
                  },
                ),
        ),
        actions: [
          if (allowSkip)
            TextButton(
              onPressed: () => Navigator.pop(ctx, <String, dynamic>{}),
              child: const Text('Lewati (tanpa kurir)'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
        ],
      );
    },
  );
}

/// Helper: null = batal; map kosong = lewati; map berisi = kurir dipilih.
bool kurirPickCancelled(Map<String, dynamic>? result) => result == null;

bool kurirPickSkipped(Map<String, dynamic>? result) =>
    result != null && result.isEmpty;
