import 'package:flutter/material.dart';

import '../../shared/tenant/store_catalog.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'rekasa_store_plan_page.dart';

/// Etalase Rekasa: katalog paket C → A, lalu pilih fitur.
class RekasaStorePage extends StatefulWidget {
  const RekasaStorePage({super.key, this.isUpgrade = false});

  final bool isUpgrade;

  @override
  State<RekasaStorePage> createState() => _RekasaStorePageState();
}

class _RekasaStorePageState extends State<RekasaStorePage> {
  StoreCatalog _catalog = StoreCatalog.local();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final next = await StoreCatalog.load();
    if (!mounted) return;
    setState(() {
      _catalog = next;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: const Text('Etalase Rekasa'),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Satu aplikasi, sekat per usaha. Pilih paket, nyalakan/matikan fitur, '
                  'buka Detail untuk video + penjelasan, lalu beli. '
                  'Paket A = tertinggi (semua modul + merek sendiri).',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.75),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                for (final p in _catalog.plans)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PremiumPanel(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RekasaStorePlanPage(
                              catalog: _catalog,
                              plan: p,
                              isUpgrade: widget.isUpgrade,
                            ),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: OptikAdminTokens.navy,
                                  ),
                                ),
                              ),
                              if (p.highlight.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: OptikAdminTokens.ice.withOpacity(0.45),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    p.highlight,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            TenantBilling.formatRp(p.priceIdr),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(p.blurb, style: const TextStyle(height: 1.35)),
                          const SizedBox(height: 10),
                          Text(
                            'Termasuk: ${p.moduleKeys.map((k) => _catalog.module(k)?.label ?? k).join(', ')}',
                            style: const TextStyle(
                              color: OptikAdminTokens.slate,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Pilih fitur →',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: OptikAdminTokens.navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
