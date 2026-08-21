import 'package:flutter/material.dart';

import '../../shared/tenant/industry_catalog.dart';
import '../../shared/tenant/store_catalog.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'rekasa_store_plan_page.dart';

/// Etalase: pilih bidang dulu (seperti industri Odoo), baru paket + fitur.
class RekasaStorePage extends StatefulWidget {
  const RekasaStorePage({
    super.key,
    this.isUpgrade = false,
    this.embedded = false,
  });

  final bool isUpgrade;
  final bool embedded;

  @override
  State<RekasaStorePage> createState() => _RekasaStorePageState();
}

class _RekasaStorePageState extends State<RekasaStorePage> {
  StoreCatalog _catalog = StoreCatalog.local();
  bool _loading = true;

  IconData _icon(String key) {
    switch (key) {
      case 'optik':
        return Icons.visibility_rounded;
      case 'retail':
        return Icons.storefront_rounded;
      case 'fnb':
        return Icons.restaurant_rounded;
      case 'jasa':
        return Icons.content_cut_rounded;
      case 'bengkel':
        return Icons.handyman_rounded;
      case 'klinik':
        return Icons.medical_services_rounded;
      case 'grosir':
        return Icons.warehouse_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot([String? industry]) async {
    setState(() => _loading = true);
    final next = await StoreCatalog.load(industry);
    if (!mounted) return;
    setState(() {
      _catalog = next;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _catalog.industryKey;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : selected == null
            ? _industries()
            : _plans();
    if (widget.embedded) {
      return Column(
        children: [
          if (selected != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _boot(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Ganti bidang'),
              ),
            ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: const Text('Etalase Rekasa'),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
        leading: selected != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => _boot(),
              )
            : null,
      ),
      body: body,
    );
  }

  Widget _industries() {
    final list = _catalog.industries.isEmpty ? industryCatalog : _catalog.industries;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'Bukan semua klien pakai POS optik. Pilih bidang usaha — '
          'paket C/B/A dan nama fitur menyesuaikan (satu mesin, spesifikasi beda).',
          style: TextStyle(
            color: OptikAdminTokens.navy.withOpacity(0.75),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        for (final i in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PremiumPanel(
              onTap: () => _boot(i.key),
              child: Row(
                children: [
                  Icon(_icon(i.key), color: OptikAdminTokens.navy, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: OptikAdminTokens.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          i.blurb,
                          style: const TextStyle(
                            color: OptikAdminTokens.slate,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _plans() {
    final ind = _catalog.industry;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          ind == null
              ? 'Pilih paket, nyalakan/matikan fitur, buka Detail, lalu beli.'
              : '${ind.label}. Fitur dan paket disesuaikan bidang ini. '
                  'Paket A = tertinggi untuk bidang tersebut + merek sendiri.',
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
    );
  }
}
