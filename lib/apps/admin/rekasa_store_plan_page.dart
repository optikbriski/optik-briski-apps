import 'package:flutter/material.dart';

import '../../shared/bootstrap.dart';
import '../../shared/tenant/module_catalog.dart';
import '../../shared/tenant/store_catalog.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/tenant/tenant_modules.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';
import 'store_module_detail_page.dart';

/// Satu paket: nyala/mati tiap fitur + beli.
class RekasaStorePlanPage extends StatefulWidget {
  const RekasaStorePlanPage({
    super.key,
    required this.catalog,
    required this.plan,
    this.isUpgrade = false,
  });

  final StoreCatalog catalog;
  final StorePlanDef plan;
  final bool isUpgrade;

  @override
  State<RekasaStorePlanPage> createState() => _RekasaStorePlanPageState();
}

class _RekasaStorePlanPageState extends State<RekasaStorePlanPage> {
  late Map<String, bool> _on;
  late bool _whiteLabel;
  bool _buying = false;

  StorePlanDef get plan => widget.plan;

  @override
  void initState() {
    super.initState();
    _on = {
      for (final m in widget.catalog.modules) m.key: plan.includes(m.key),
    };
    _whiteLabel = plan.whiteLabel;
  }

  StoreQuote get _quote => widget.catalog.quote(
        plan: plan,
        enabled: _on,
        whiteLabel: _whiteLabel,
      );

  Future<void> _buy() async {
    final name = TextEditingController();
    final slug = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final signer = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.isUpgrade ? 'Upgrade paket' : 'Beli paket'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total ${TenantBilling.formatRp(_quote.amountIdr)} / periode. '
                'Usaha baru = uji coba sampai tagihan lunas + kontrak ditandatangani. '
                'Data tidak dicampur merek lain.',
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nama usaha / merek'),
              ),
              TextField(
                controller: slug,
                decoration: const InputDecoration(
                  labelText: 'Kode usaha (slug)',
                  hintText: 'optik-maju',
                ),
              ),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'WA / HP'),
              ),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (opsional)'),
              ),
              TextField(
                controller: signer,
                decoration: const InputDecoration(
                  labelText: 'Nama penandatangan kontrak',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pesan')),
        ],
      ),
    );
    final payload = {
      'p_plan_key': plan.planKey,
      'p_modules': _on,
      'p_white_label': _whiteLabel,
      'p_display_name': name.text,
      'p_slug': slug.text,
      'p_phone': phone.text,
      'p_email': email.text,
      'p_signer_name': signer.text,
      'p_industry_key': widget.catalog.industryKey ?? 'umum',
    };
    name.dispose();
    slug.dispose();
    phone.dispose();
    email.dispose();
    signer.dispose();
    if (ok != true) return;

    setState(() => _buying = true);
    try {
      final raw = await supabase.rpc('submit_store_order', params: payload);
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (map['ok'] != true) throw map['error'] ?? 'Gagal memesan';
      if (!mounted) return;
      final token = '${map['contract_token'] ?? ''}';
      final slug = '${map['slug'] ?? ''}'.trim();
      final serverMods = map['modules'];
      final enabledKeys = <String>{};
      if (serverMods is List) {
        for (final e in serverMods) {
          if (e is! Map) continue;
          if (e['enabled'] == true) {
            final k = (e['module_key'] ?? '').toString().trim();
            if (k.isNotEmpty) enabledKeys.add(k);
          }
        }
      }
      if (enabledKeys.isEmpty) {
        enabledKeys.addAll(
          _on.entries.where((e) => e.value).map((e) => e.key),
        );
      }
      final labels = (enabledKeys.toList()..sort())
          .map(moduleLabel)
          .join(', ');
      final wl = map['white_label'] == true ||
          map['shell'] == 'white_label' ||
          _whiteLabel;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pesanan masuk'),
          content: Text(
            'Kode usaha $slug.\n'
            'Tagihan ${map['invoice_no'] ?? ''} · ${TenantBilling.formatRp(map['amount_idr'])}.\n\n'
            'Fitur yang nyala di APK toko:\n$labels\n\n'
            '${TenantModules.installHint(whiteLabel: wl, slug: slug)}\n\n'
            'Tandatangani kontrak online, transfer ke Rekasa. '
            'Setelah lunas sistem dinyalakan. Data tidak dihapus kalau telat bayar — hanya dimatikan.',
          ),
          actions: [
            if (token.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TenantContractSignPage(token: token),
                    ),
                  );
                },
                child: const Text('Tandatangani sekarang'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: Text(plan.label),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Text(
            '${widget.catalog.industry?.label ?? 'Usaha'} · ${plan.blurb}',
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.78),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Harga dasar ${TenantBilling.formatRp(plan.priceIdr)}. '
            'Centang fitur yang mau dipakai. Yang di luar paket = add-on.',
            style: const TextStyle(color: OptikAdminTokens.slate, height: 1.35),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('APK & web merek sendiri'),
            subtitle: Text(
              plan.whiteLabel
                  ? 'Termasuk paket tertinggi.'
                  : 'Add-on ${TenantBilling.formatRp(widget.catalog.whiteLabelAddonIdr)}',
            ),
            value: _whiteLabel,
            onChanged: (v) => setState(() => _whiteLabel = v),
          ),
          const Divider(),
          for (final m in widget.catalog.modules)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: PremiumPanel(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        plan.includes(m.key)
                            ? '${m.summary}\nTermasuk paket.'
                            : '${m.summary}\nAdd-on ${TenantBilling.formatRp(m.addOnPriceIdr)}',
                      ),
                      isThreeLine: true,
                      value: _on[m.key] ?? false,
                      onChanged: (v) => setState(() => _on[m.key] = v),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StoreModuleDetailPage(module: m),
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                        label: const Text('Detail (video + penjelasan)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Material(
        elevation: 8,
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total ${TenantBilling.formatRp(q.amountIdr)}'
                        '${q.addOnIdr > 0 ? ' · add-on ${TenantBilling.formatRp(q.addOnIdr)}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PremiumPrimaryButton(
                  label: _buying ? 'Memesan…' : 'Beli paket ini',
                  onPressed: _buying ? null : _buy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
