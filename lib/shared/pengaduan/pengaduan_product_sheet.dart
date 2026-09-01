import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../karyawan/pengaduan_case_flow.dart';

typedef PengaduanProductLoader = Future<List<Map<String, dynamic>>> Function(
  String query,
);

Future<PengaduanItemLine?> showPengaduanProductSheet(
  BuildContext context, {
  required String tokoId,
  PengaduanProductLoader? loader,
}) {
  return showModalBottomSheet<PengaduanItemLine>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => PengaduanProductSheet(
      tokoId: tokoId,
      loader: loader,
    ),
  );
}

class PengaduanProductSheet extends StatefulWidget {
  const PengaduanProductSheet({
    super.key,
    required this.tokoId,
    this.loader,
  });

  final String tokoId;
  final PengaduanProductLoader? loader;

  @override
  State<PengaduanProductSheet> createState() => _PengaduanProductSheetState();
}

class _PengaduanProductSheetState extends State<PengaduanProductSheet> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final gen = ++_gen;
    setState(() => _loading = true);
    try {
      final rows = widget.loader != null
          ? await widget.loader!(raw)
          : await _defaultLoader(raw);
      if (!mounted || gen != _gen) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _rows = [];
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _defaultLoader(String raw) async {
    final q = raw.trim();
    final safe = q.replaceAll(RegExp(r'[%*,()]'), '');
    var query = Supabase.instance.client
        .from('products')
        .select('id, sku, barcode, nama, stock, toko_id')
        .inFilter(
          'toko_id',
          AttendanceAdminScope.storeIdAliases(widget.tokoId),
        );
    if (safe.isNotEmpty) {
      query = query.or(
        'nama.ilike.%$safe%,sku.ilike.%$safe%,barcode.ilike.%$safe%',
      );
    }
    try {
      final rows = await query.order('nama').limit(40);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      var fallback = Supabase.instance.client
          .from('products')
          .select('id, sku, barcode, nama, toko_id')
          .inFilter(
            'toko_id',
            AttendanceAdminScope.storeIdAliases(widget.tokoId),
          );
      if (safe.isNotEmpty) {
        fallback = fallback.or(
          'nama.ilike.%$safe%,sku.ilike.%$safe%,barcode.ilike.%$safe%',
        );
      }
      final rows = await fallback.order('nama').limit(40);
      return List<Map<String, dynamic>>.from(rows as List);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'pengaduan_btn_pilih_barang'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: 'pengaduan_cari_barang'.tr(),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(child: Text('pengaduan_barang_kosong'.tr()))
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = _rows[i];
                            final sku =
                                (p['sku'] ?? p['barcode'] ?? '').toString();
                            final nama = (p['nama'] ?? sku).toString();
                            final stok = p['stock'] ?? p['available_qty'];
                            return ListTile(
                              title: Text(
                                nama,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$sku'
                                '${stok == null ? '' : ' · stok $stok'}',
                              ),
                              trailing: const Icon(Icons.add),
                              onTap: sku.trim().isEmpty
                                  ? null
                                  : () => Navigator.pop(
                                        context,
                                        PengaduanItemLine(
                                          sku: sku.trim(),
                                          nama: nama,
                                          qty: 1,
                                          barcode: (p['barcode'] ?? '')
                                              .toString()
                                              .trim(),
                                        ),
                                      ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
