import 'package:flutter/material.dart';

import '../../shared/bootstrap.dart';
import '../../shared/tenant/module_catalog.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';

/// Rekasa: pesanan etalase + isi URL video penjelasan modul.
class RekasaStoreOrdersPage extends StatefulWidget {
  const RekasaStoreOrdersPage({super.key});

  @override
  State<RekasaStoreOrdersPage> createState() => _RekasaStoreOrdersPageState();
}

class _RekasaStoreOrdersPageState extends State<RekasaStoreOrdersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await supabase.rpc('platform_list_store_orders');
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _activate(Map<String, dynamic> row) async {
    try {
      final res = await supabase.rpc(
        'platform_activate_store_order',
        params: {'p_order_id': row['id']},
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] != true) throw map['error'] ?? 'Gagal';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lunas & sistem dinyalakan.'),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      await _boot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    }
  }

  Future<void> _editVideo() async {
    StoreModuleDef pick = moduleCatalog.first;
    final url = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Video & teks fitur'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<StoreModuleDef>(
                      value: pick,
                      items: [
                        for (final m in moduleCatalog)
                          DropdownMenuItem(value: m, child: Text(m.label)),
                      ],
                      onChanged: (v) {
                        if (v != null) setLocal(() => pick = v);
                      },
                      decoration: const InputDecoration(labelText: 'Fitur'),
                    ),
                    TextField(
                      controller: url,
                      decoration: const InputDecoration(
                        labelText: 'URL YouTube / video',
                      ),
                    ),
                    TextField(
                      controller: body,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Paragraf penjelasan (opsional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
              ],
            );
          },
        );
      },
    );
    final u = url.text;
    final b = body.text;
    url.dispose();
    body.dispose();
    if (ok != true) return;
    try {
      final res = await supabase.rpc('platform_set_store_module', params: {
        'p_module_key': pick.key,
        'p_video_url': u,
        'p_body': b,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] != true) throw map['error'] ?? 'Gagal';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Penjelasan fitur disimpan.'),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: const Text('Pesanan etalase'),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
        actions: [
          IconButton(
            tooltip: 'Video / teks fitur',
            onPressed: _editVideo,
            icon: const Icon(Icons.video_library_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: OptikAdminTokens.danger)),
                if (_rows.isEmpty) const Text('Belum ada pesanan dari etalase.'),
                for (final r in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PremiumPanel(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${r['display_name']} · ${r['slug']}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${r['plan_key']} · ${TenantBilling.formatRp(r['amount_idr'])} · '
                          '${r['status']} · ${r['phone'] ?? ''}',
                        ),
                        trailing: Wrap(
                          children: [
                            if ((r['contract_token'] ?? '').toString().isNotEmpty)
                              IconButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TenantContractSignPage(
                                        token: '${r['contract_token']}',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.draw_rounded),
                              ),
                            if (r['status'] != 'paid')
                              IconButton(
                                tooltip: 'Tandai lunas + nyalakan',
                                onPressed: () => _activate(r),
                                icon: const Icon(Icons.verified_rounded),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
