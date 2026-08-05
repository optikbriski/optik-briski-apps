import 'package:flutter/material.dart';

import '../theme.dart';
import 'sale_fulfillment_service.dart';

/// Pilih item mana yang diambil + garansi diaktifkan sekarang.
/// - READY → bisa dicentang (tidak wajib ambil semua)
/// - PENDING_RO / DIAMBIL → tampil, tidak bisa dipilih
Future<List<String>?> showPickupItemPickerDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
}) async {
  final ready = <Map<String, dynamic>>[];
  final blocked = <Map<String, dynamic>>[];
  for (final raw in items) {
    final it = Map<String, dynamic>.from(raw);
    final st = SaleFulfillmentService.normalizeLineStatus(
      it['fulfillment_status'],
    );
    if (st == SaleFulfillmentService.statusReady) {
      ready.add(it);
    } else {
      blocked.add(it);
    }
  }

  if (ready.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text(
          'Tidak ada item READY',
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        content: const Text(
          'Semua item masih RO pending atau sudah diambil. '
          'Tunggu stok RO / konfirmasi barang ready dulu.',
          style: TextStyle(color: OptikAdminTokens.slate, height: 1.35),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.snow,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
    return null;
  }

  final selected = <String>{
    for (final it in ready) it['id'].toString(),
  };

  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: OptikAdminTokens.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
              side: const BorderSide(color: OptikAdminTokens.lineStrong),
            ),
            title: const Text(
              'Pilih item diambil sekarang',
              style: TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Centang produk yang diserahkan + garansi diaktifkan. '
                      'Item READY lain bisa diambil belakangan (scan QR lagi). '
                      'RO pending tidak bisa dipilih.',
                      style: TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...ready.map((it) {
                      final id = it['id'].toString();
                      final name = (it['nama_produk'] ?? '-').toString();
                      final tipe = (it['tipe_produk'] ?? '').toString();
                      final qty = it['qty'] ?? 1;
                      final checked = selected.contains(id);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: OptikAdminTokens.navy,
                        value: checked,
                        onChanged: (v) {
                          setLocal(() {
                            if (v == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          });
                        },
                        title: Text(
                          name,
                          style: const TextStyle(
                            color: OptikAdminTokens.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '$tipe × $qty · READY',
                          style: const TextStyle(
                            color: OptikAdminTokens.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        secondary: Icon(
                          checked
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: checked
                              ? OptikAdminTokens.navy
                              : OptikAdminTokens.slate,
                          size: 22,
                        ),
                      );
                    }),
                    if (blocked.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(color: OptikAdminTokens.line),
                      const SizedBox(height: 4),
                      const Text(
                        'Belum bisa diambil',
                        style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...blocked.map((it) {
                        final st = SaleFulfillmentService.normalizeLineStatus(
                          it['fulfillment_status'],
                        );
                        final label = st == SaleFulfillmentService.statusDiambil
                            ? 'Sudah diambil'
                            : 'RO pending';
                        final color = st == SaleFulfillmentService.statusDiambil
                            ? OptikAdminTokens.success
                            : OptikAdminTokens.warning;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.lock_outline,
                              size: 18, color: color),
                          title: Text(
                            (it['nama_produk'] ?? '-').toString(),
                            style: TextStyle(
                              color: OptikAdminTokens.slate.withOpacity(0.85),
                              fontSize: 12.5,
                            ),
                          ),
                          subtitle: Text(
                            '${it['tipe_produk'] ?? ''} × ${it['qty'] ?? 1} · $label',
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Batal',
                  style: TextStyle(color: OptikAdminTokens.slate),
                ),
              ),
              TextButton(
                onPressed: () {
                  setLocal(() {
                    selected
                      ..clear()
                      ..addAll(ready.map((e) => e['id'].toString()));
                  });
                },
                child: const Text(
                  'Pilih semua READY',
                  style: TextStyle(color: OptikAdminTokens.navy),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: OptikAdminTokens.navy,
                  foregroundColor: OptikAdminTokens.snow,
                ),
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, selected.toList()),
                child: Text(
                  'Ambil ${selected.length} item',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
