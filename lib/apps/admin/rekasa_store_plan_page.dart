import 'package:flutter/material.dart';

import '../../shared/bootstrap.dart';
import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/tenant/module_catalog.dart';
import '../../shared/tenant/store_catalog.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/tenant/tenant_modules.dart';
import '../../shared/widgets/rekasa_surface.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';
import '../store/store_account.dart';
import '../store/store_account_login_page.dart';
import '../store/store_checkout_sheet.dart';
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
  StoreQuote? _remoteQuote;

  StorePlanDef get plan => widget.plan;

  StoreQuote get _localQuote => widget.catalog.quote(
        plan: plan,
        enabled: _on,
        whiteLabel: _whiteLabel,
      );

  StoreQuote get _quote => _remoteQuote ?? _localQuote;

  @override
  void initState() {
    super.initState();
    _on = {
      for (final m in widget.catalog.modules) m.key: plan.includes(m.key),
    };
    _whiteLabel = plan.whiteLabel;
    _refreshQuote();
  }

  Future<void> _refreshQuote() async {
    final next = await widget.catalog.quoteRemote(
      plan: plan,
      enabled: _on,
      whiteLabel: _whiteLabel,
    );
    if (!mounted) return;
    setState(() => _remoteQuote = next.fromServer ? next : null);
  }

  void _setOn(String key, bool v) {
    setState(() => _on[key] = v);
    _refreshQuote();
  }

  void _setWhiteLabel(bool v) {
    setState(() => _whiteLabel = v);
    _refreshQuote();
  }

  Future<void> _buy() async {
    final name = TextEditingController();
    final slug = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final signer = TextEditingController();
    final ok = await showRekasaSheet<bool>(
      context: context,
      builder: (ctx) => RekasaSheetScaffold(
        eyebrow: widget.catalog.industry?.label ?? 'Checkout',
        title: widget.isUpgrade ? 'Upgrade paket' : 'Beli paket',
        price: TenantBilling.formatRp(_quote.amountIdr),
        caption: 'Per periode. Usaha baru uji coba sampai tagihan lunas '
            'dan kontrak ditandatangani. Data tidak dicampur merek lain.',
        primaryLabel: 'Pesan',
        onPrimary: () => Navigator.pop(ctx, true),
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          children: [
            TextField(
              controller: name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nama usaha / merek'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: slug,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Kode usaha',
                hintText: 'optik-maju',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'WA / HP'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email (opsional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: signer,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Nama penandatangan kontrak',
              ),
            ),
          ],
        ),
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
      dynamic raw;
      try {
        raw = await supabase.rpc('submit_store_order', params: payload);
      } catch (_) {
        final slim = Map<String, dynamic>.from(payload)..remove('p_industry_key');
        raw = await supabase.rpc('submit_store_order', params: slim);
      }
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (map['ok'] != true) throw map['error'] ?? 'Gagal memesan';
      if (!mounted) return;
      final token = '${map['contract_token'] ?? ''}';
      final slug = '${map['slug'] ?? ''}'.trim();
      final phone = '${payload['p_phone'] ?? ''}'.trim();
      final orderEmail = '${payload['p_email'] ?? ''}'.trim();
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
      await showRekasaSheet<void>(
        context: context,
        builder: (ctx) => RekasaSheetScaffold(
          eyebrow: 'Pesanan',
          title: 'Pesanan masuk',
          price: TenantBilling.formatRp(map['amount_idr']),
          caption: 'Kode usaha $slug · ${map['invoice_no'] ?? ''}',
          primaryLabel: token.isNotEmpty ? 'Tandatangani' : 'Selesai',
          secondaryLabel: 'Akun owner',
          onPrimary: () {
            Navigator.pop(ctx);
            if (token.isEmpty) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TenantContractSignPage(token: token),
              ),
            );
          },
          onSecondary: () {
            Navigator.pop(ctx);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoreAccountLoginPage(
                  hint: StoreAccountHint(
                    slug: slug,
                    phone: phone,
                    email: orderEmail,
                    contractToken: token,
                  ),
                ),
              ),
            );
          },
          child: Text(
            'Fitur yang nyala di APK toko:\n$labels\n\n'
            '${TenantModules.installHint(whiteLabel: wl, slug: slug)}\n\n'
            'Tandatangani kontrak, buat akun owner (kode usaha + HP), '
            'transfer ke Rekasa. Setelah lunas sistem dinyalakan. '
            'Data tidak dihapus kalau telat bayar — hanya dimatikan.',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: RekasaTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      appBar: AppBar(
        title: Text(plan.label),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          RekasaPage(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RekasaEyebrow(widget.catalog.industry?.label ?? 'Usaha'),
                const SizedBox(height: 8),
                Text(plan.blurb, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  'Harga dasar ${TenantBilling.formatRp(plan.priceIdr)}. '
                  'Centang fitur yang mau dipakai. Yang di luar paket = add-on.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                RekasaSurface(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('APK & web merek sendiri'),
                    subtitle: Text(
                      plan.whiteLabel
                          ? 'Termasuk paket tertinggi.'
                          : 'Add-on ${TenantBilling.formatRp(widget.catalog.whiteLabelAddonIdr)}',
                    ),
                    value: _whiteLabel,
                    onChanged: (v) => _setWhiteLabel(v),
                  ),
                ),
                const SizedBox(height: 14),
                for (final m in widget.catalog.modules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RekasaSurface(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              m.label,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              plan.includes(m.key)
                                  ? '${m.summary}\nTermasuk paket.'
                                  : '${m.summary}\nAdd-on ${TenantBilling.formatRp(m.addOnPriceIdr)}',
                            ),
                            isThreeLine: true,
                            value: _on[m.key] ?? false,
                            onChanged: (v) => _setOn(m.key, v),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        StoreModuleDetailPage(module: m),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.play_circle_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('Detail (video + penjelasan)'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        color: RekasaTokens.paper,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: RekasaTokens.sky)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Total ${TenantBilling.formatRp(q.amountIdr)}'
                      '${q.addOnIdr > 0 ? ' · add-on ${TenantBilling.formatRp(q.addOnIdr)}' : ''}'
                      '${q.fromServer ? '' : ' · perkiraan'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: RekasaTokens.inkSoft,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _buying ? null : _buy,
                      child: Text(_buying ? 'Memesan…' : 'Beli paket ini'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
