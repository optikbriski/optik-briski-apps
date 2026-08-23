import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/tenant/industry_catalog.dart';
import '../../shared/tenant/store_catalog.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/widgets/rekasa_surface.dart';
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
        ? const Center(
            child: CircularProgressIndicator(color: RekasaTokens.ink),
          )
        : selected == null
            ? _industries()
            : _plans();
    if (widget.embedded) {
      return DecoratedBox(
        decoration: const BoxDecoration(gradient: RekasaTokens.skyCanvas),
        child: Column(
          children: [
            if (selected != null)
              RekasaPage(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RekasaPillButton(
                    label: 'Ganti bidang',
                    onTap: () => _boot(),
                  ),
                ),
              ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      appBar: AppBar(
        title: const Text('Etalase Rekasa'),
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
    final list =
        _catalog.industries.isEmpty ? industryCatalog : _catalog.industries;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            RekasaPage(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const RekasaEyebrow('Etalase'),
                  const SizedBox(height: 18),
                  Text(
                    'Pilih bidang usaha',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Text(
                      'Satu mesin. Pilih bidang, pilih paket, bayar via Midtrans '
                      'dari sini — pintu yang sama dengan situs perusahaan. '
                      'Bukan semua klien pakai POS optik.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 36),
                  if (!wide)
                    for (final i in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _industryCard(i),
                      )
                  else
                    for (var i = 0; i < list.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _industryCard(list[i])),
                            const SizedBox(width: 18),
                            Expanded(
                              child: i + 1 < list.length
                                  ? _industryCard(list[i + 1])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _industryCard(StoreIndustryDef i) {
    return RekasaSurface(
      onTap: () => _boot(i.key),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RekasaIconTile(icon: _icon(i.key), size: 58),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.label, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(i.blurb, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                Text(
                  'LIHAT PAKET',
                  style: GoogleFonts.plusJakartaSans(
                    color: RekasaTokens.inkSoft,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _plans() {
    final ind = _catalog.industry;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
            RekasaPage(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RekasaEyebrow(ind?.label ?? 'Paket'),
              const SizedBox(height: 18),
              Text(
                'Pilih paket',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  ind == null
                      ? 'Nyalakan fitur yang dipakai, buka Detail, lalu bayar via Midtrans.'
                      : 'Fitur dan harga menyesuaikan bidang ini. '
                          'Paket A = tertinggi + merek sendiri.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 32),
              for (final p in _catalog.plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: RekasaSurface(
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
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (p.highlight.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: p.planKey == 'paket_a'
                                      ? RekasaTokens.inkSoft
                                      : RekasaTokens.sky,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  p.highlight,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: p.planKey == 'paket_a'
                                        ? RekasaTokens.paper
                                        : RekasaTokens.ink,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          TenantBilling.formatRp(p.priceIdr),
                          style: GoogleFonts.plusJakartaSans(
                            color: RekasaTokens.inkSoft,
                            fontWeight: FontWeight.w800,
                            fontSize: 34,
                            letterSpacing: -1.1,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(p.blurb, style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 12),
                        Text(
                          'Termasuk: ${p.moduleKeys.map((k) => _catalog.module(k)?.label ?? k).join(', ')}',
                          style: GoogleFonts.plusJakartaSans(
                            color: RekasaTokens.muted,
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'PILIH FITUR',
                          style: GoogleFonts.plusJakartaSans(
                            color: RekasaTokens.inkSoft,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8,
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
    );
  }
}
