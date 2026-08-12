// ignore_for_file: use_build_context_synchronously
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/admin/admin_picker.dart';
import 'logistics_tracking_service.dart';

/// Pilih kurir (opsional). Return map karyawan, atau null jika batal / lewati.
Future<Map<String, dynamic>?> showKurirPickDialog(
  BuildContext context, {
  required LogisticsTrackingService service,
  String? tokoId,
  bool pusatOnly = false,
  bool allowSkip = true,
  String title = 'Pilih kurir',
}) async {
  final list = await service.listKaryawanAktif(
    tokoId: tokoId,
    pusatOnly: pusatOnly,
  );
  if (!context.mounted) return null;

  if (list.isEmpty) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.ice, width: 1.2),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        content: Text(
          'pos_duty_picker_empty'.tr(),
          style: const TextStyle(color: OptikAdminTokens.slate),
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
      ),
    );
  }

  final sel = await showAdminPicker<Map<String, dynamic>>(
    context: context,
    title: title,
    subtitle: 'Karyawan yang sedang bertugas (sudah absen masuk)',
    headerIcon: Icons.delivery_dining_rounded,
    searchHint: 'Cari nama / NIK…',
    clearLabel: allowSkip ? 'Hapus / lewati kurir' : null,
    clearSubtitle:
        allowSkip ? 'Surat jalan tanpa kurir ditetapkan' : null,
    clearIcon: Icons.skip_next_rounded,
    options: [
      for (final k in list)
        AdminPickerOption(
          value: k,
          label: k['nama']?.toString() ?? '-',
          subtitle:
              '${k['nik'] ?? '-'} · ${k['toko_id'] ?? '-'}'
              '${k['jabatan'] != null ? ' · ${k['jabatan']}' : ''}',
          icon: Icons.delivery_dining_rounded,
        ),
    ],
    filterOption: (option, query) {
      final k = option.value;
      final hay =
          '${option.label} ${option.subtitle ?? ''} ${k['nik'] ?? ''}'
          .toLowerCase();
      return hay.contains(query);
    },
  );

  if (sel == null) return null;
  if (sel.isClear) return <String, dynamic>{};
  return sel.value;
}

/// Helper: null = batal; map kosong = lewati; map berisi = kurir dipilih.
bool kurirPickCancelled(Map<String, dynamic>? result) => result == null;

bool kurirPickSkipped(Map<String, dynamic>? result) =>
    result != null && result.isEmpty;
