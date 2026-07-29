// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Antrian pesanan online Member untuk cabang / pusat.
class OnlineOrdersPage extends StatefulWidget {
  const OnlineOrdersPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<OnlineOrdersPage> createState() => _OnlineOrdersPageState();
}

class _OnlineOrdersPageState extends State<OnlineOrdersPage> {
  final _db = Supabase.instance.client;
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  String get _tokoId =>
      (widget.profile['toko_id'] ?? 'PUSAT').toString().toUpperCase();

  bool get _isPusat {
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    return role == 'owner' ||
        role == 'admin_pusat' ||
        role == 'super_admin' ||
        _tokoId == 'PUSAT' ||
        _tokoId == 'CABANG-PUSAT';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = _isPusat
          ? await _db
              .from('online_orders')
              .select()
              .order('created_at', ascending: false)
              .limit(100)
          : await _db
              .from('online_orders')
              .select()
              .eq('toko_id', _tokoId)
              .order('created_at', ascending: false)
              .limit(100);
      if (!mounted) return;
      setState(() {
        _rows = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> order, String status) async {
    final tracking = TextEditingController(
        text: (order['courier_tracking'] ?? '').toString());
    final note =
        TextEditingController(text: (order['store_note'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update → $status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tracking,
              decoration:
                  const InputDecoration(labelText: 'No. resi / tracking kurir'),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Catatan toko'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _db.rpc('update_online_order_fulfillment', params: {
      'p_order_id': order['id'],
      'p_status': status,
      'p_courier_tracking': tracking.text.trim(),
      'p_store_note': note.text.trim(),
    });
    if (!mounted) return;
    if (res is Map && res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${res['error'] ?? 'Gagal'}'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnlineDeliverySettingsPage(profile: widget.profile),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: const Text('Pesanan Online'),
        actions: [
          IconButton(
            tooltip: 'Ongkir & jual online',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _rows.isEmpty
                  ? const Center(
                      child: Text(
                        'Belum ada pesanan online.',
                        style: TextStyle(color: OptikAdminTokens.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final o = _rows[i];
                        final status = (o['status'] ?? '').toString();
                        final fulfill = (o['fulfillment'] ?? '').toString();
                        final items = o['items'];
                        final itemCount = items is List ? items.length : 0;
                        return PremiumPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (o['customer_name'] ??
                                              o['phone_e164'] ??
                                              '-')
                                          .toString(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  _statusChip(status),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${o['toko_id']} · $fulfill'
                                '${o['courier'] != null ? ' · ${o['courier']}' : ''}'
                                ' · $itemCount item',
                                style: const TextStyle(
                                  color: OptikAdminTokens.textMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _money.format(
                                    int.tryParse('${o['total'] ?? 0}') ?? 0),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: OptikAdminTokens.accentSoft,
                                  fontSize: 16,
                                ),
                              ),
                              if ((o['address_text'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  o['address_text'].toString(),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: OptikAdminTokens.textSecondary,
                                  ),
                                ),
                              ],
                              if ((o['courier_tracking'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Resi: ${o['courier_tracking']}',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (status == 'paid')
                                    _action('packing', o, 'Dikemas'),
                                  if (status == 'paid' || status == 'packing')
                                    _action(
                                      fulfill == 'delivery' ? 'shipped' : 'ready',
                                      o,
                                      fulfill == 'delivery'
                                          ? 'Diserahkan kurir'
                                          : 'Siap diambil',
                                    ),
                                  if (status == 'ready' ||
                                      status == 'shipped' ||
                                      status == 'packing')
                                    _action('fulfilled', o, 'Selesai'),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _action(String status, Map<String, dynamic> o, String label) {
    return OutlinedButton(
      onPressed: () => _updateStatus(o, status),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _statusChip(String status) {
    Color c = OptikAdminTokens.textMuted;
    if (status == 'paid' || status == 'packing') c = OptikAdminTokens.warning;
    if (status == 'ready' || status == 'shipped') c = OptikAdminTokens.accentSoft;
    if (status == 'fulfilled') c = OptikAdminTokens.success;
    if (status == 'pending_payment') c = OptikAdminTokens.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class OnlineDeliverySettingsPage extends StatefulWidget {
  const OnlineDeliverySettingsPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<OnlineDeliverySettingsPage> createState() =>
      _OnlineDeliverySettingsPageState();
}

class _OnlineDeliverySettingsPageState
    extends State<OnlineDeliverySettingsPage> {
  final _db = Supabase.instance.client;
  final _feeGrab = TextEditingController();
  final _feeGojek = TextEditingController();
  final _feeOther = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _online = true;
  bool _pickup = true;
  bool _delivery = true;
  String? _tokoId;

  bool get _isPusat {
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    final t = (widget.profile['toko_id'] ?? '').toString().toUpperCase();
    return role == 'owner' ||
        role == 'admin_pusat' ||
        role == 'super_admin' ||
        t == 'PUSAT';
  }

  @override
  void initState() {
    super.initState();
    _tokoId = (widget.profile['toko_id'] ?? 'PUSAT').toString();
    _load();
  }

  @override
  void dispose() {
    _feeGrab.dispose();
    _feeGojek.dispose();
    _feeOther.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_isPusat) {
        // pusat: default edit toko sendiri; bisa ganti via dropdown sederhana
      }
      final row = await _db
          .from('toko_delivery_settings')
          .select()
          .eq('toko_id', _tokoId!)
          .maybeSingle();
      if (row != null) {
        _online = row['online_selling_enabled'] != false;
        _pickup = row['pickup_enabled'] != false;
        _delivery = row['delivery_enabled'] != false;
        _feeGrab.text = '${row['fee_grab'] ?? 15000}';
        _feeGojek.text = '${row['fee_gojek'] ?? 15000}';
        _feeOther.text = '${row['fee_other'] ?? 20000}';
      } else {
        _feeGrab.text = '15000';
        _feeGojek.text = '15000';
        _feeOther.text = '20000';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _db.from('toko_delivery_settings').upsert({
        'toko_id': _tokoId,
        'online_selling_enabled': _online,
        'pickup_enabled': _pickup,
        'delivery_enabled': _delivery,
        'fee_grab': int.tryParse(_feeGrab.text) ?? 0,
        'fee_gojek': int.tryParse(_feeGojek.text) ?? 0,
        'fee_other': int.tryParse(_feeOther.text) ?? 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengaturan tersimpan'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Gagal: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(title: const Text('Pengaturan jual online')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                PremiumPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cabang: $_tokoId',
                          style:
                              const TextStyle(fontWeight: FontWeight.w800)),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Aktif jual online'),
                        value: _online,
                        onChanged: (v) => setState(() => _online = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Terima ambil di toko'),
                        value: _pickup,
                        onChanged: (v) => setState(() => _pickup = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Terima pengiriman'),
                        value: _delivery,
                        onChanged: (v) => setState(() => _delivery = v),
                      ),
                      TextField(
                        controller: _feeGrab,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Ongkir Grab (Rp)'),
                      ),
                      TextField(
                        controller: _feeGojek,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Ongkir Gojek (Rp)'),
                      ),
                      TextField(
                        controller: _feeOther,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Ongkir lainnya (Rp)'),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(_saving ? 'Menyimpan…' : 'Simpan'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
