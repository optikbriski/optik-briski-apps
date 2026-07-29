import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/invoice/invoice_hub_service.dart';
import '../../../shared/invoice/invoice_link.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/qr/obr_codes.dart';
import '../../../shared/theme.dart';
import '../../../shared/whatsapp_launcher.dart';
import '../member_rating_page.dart';
import '../member_widgets.dart';
import 'member_survey_page.dart';

/// Detail nota + status + QR fase + foto + review + garansi (fitur 1,2,11,16,17).
class MemberInvoiceHubPage extends StatefulWidget {
  const MemberInvoiceHubPage({super.key, required this.noInvoice});

  final String noInvoice;

  @override
  State<MemberInvoiceHubPage> createState() => _MemberInvoiceHubPageState();
}

class _MemberInvoiceHubPageState extends State<MemberInvoiceHubPage> {
  final _hubSvc = InvoiceHubService();
  final _repo = MemberRepository();
  Map<String, dynamic>? _hub;
  bool _loading = true;
  String? _error;

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
      final hub = await _hubSvc.loadByInvoice(
        widget.noInvoice,
        phone: MemberSession.instance.phoneForQuery,
      );
      if (!mounted) return;
      if (hub == null) {
        setState(() {
          _loading = false;
          _error = 'Nota tidak ditemukan';
        });
        return;
      }
      hub['role_view'] = 'customer';
      setState(() {
        _hub = hub;
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

  String _money(dynamic v) {
    final n = int.tryParse('$v') ?? 0;
    return NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(n);
  }

  Future<void> _openReview() async {
    final url = (_hub?['google_review_url'] ?? '').toString().trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link Google Review belum diset toko.')),
      );
      return;
    }
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _waToko(String template) async {
    final toko = (_hub?['toko_id'] ?? 'PUSAT').toString();
    final settings = await _repo.storeSettings(toko);
    final phone = (settings?['phone'] ?? '').toString();
    final inv = _hub?['no_invoice'] ?? widget.noInvoice;
    final msg = template.replaceAll('{inv}', '$inv');
    if (phone.isEmpty) {
      await openAdminWhatsApp(message: msg);
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/${normalizeWaNumber(phone)}?text=${Uri.encodeComponent(msg)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final h = _hub;
    return MemberPremiumScaffold(
      title: 'Nota digital',
      subtitle: widget.noInvoice,
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? MemberEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Gagal memuat',
                  message: _error!,
                  actionLabel: 'Coba lagi',
                  onAction: _load,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    _statusCard(h!),
                    const SizedBox(height: 12),
                    _moneyCard(h),
                    const SizedBox(height: 12),
                    _phaseCard(h),
                    const SizedBox(height: 12),
                    _itemsCard(h),
                    if ((h['foto_hasil_url'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _fotoCard(h),
                    ],
                    const SizedBox(height: 12),
                    _garansiCard(h),
                    const SizedBox(height: 12),
                    _actions(h),
                  ],
                ),
    );
  }

  Widget _statusCard(Map<String, dynamic> h) {
    final label = InvoiceHubService.statusLabel(h);
    final pay = InvoiceHubService.isDpOpen(h) ? 'DP' : 'LUNAS';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [OptikMemberTokens.blueDeep, OptikMemberTokens.blue],
        ),
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            h['no_invoice']?.toString() ?? '-',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${h['nama_pelanggan'] ?? '-'} · ${h['toko_id'] ?? '-'}',
            style: TextStyle(color: Colors.white.withOpacity(0.85)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(label, Colors.white, OptikMemberTokens.blueDeep),
              _chip(pay, OptikMemberTokens.blueDeep, Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }

  Widget _moneyCard(Map<String, dynamic> h) {
    return _card(
      child: Column(
        children: [
          _row('Total belanja', _money(h['total_harga'])),
          _row('Dibayar / DP', _money(h['dibayarkan'])),
          _row('Sisa', _money(h['sisa_tagihan']), bold: true),
        ],
      ),
    );
  }

  Widget _phaseCard(Map<String, dynamic> h) {
    final phaseKey = (h['qr_phase'] ?? '').toString().toUpperCase();
    String phase;
    String tip;
    if (phaseKey == 'DP' || InvoiceHubService.isDpOpen(h)) {
      phase = 'QR fase DP · pelunasan';
      tip =
          'Tunjukkan QR ini ke kasir POS untuk pelunasan. Ambil barang hanya setelah lunas.';
    } else if (phaseKey == 'CLAIM' || InvoiceHubService.sudahDiambil(h)) {
      phase = 'QR fase CLAIM · garansi';
      tip =
          'Untuk klaim, datang ke toko membawa barang + QR CLAIM. Keputusan hanya setelah dicek petugas.';
    } else {
      phase = 'QR fase LUNAS · serah terima';
      tip =
          'Saat pengambilan, petugas akan scan QR LUNAS di POS. Siapkan nota di HP Anda.';
    }

    final payload = (h['qr_payload'] ?? '').toString().trim();
    final lifecycle = InvoiceLink.isCustomerLifecycleQr(payload);
    final hubUrl = InvoiceLink.encodeHttps(
      h['no_invoice']?.toString() ?? widget.noInvoice,
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MemberSectionLabel('Scan QR fase'),
          Text(
            phase,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: OptikMemberTokens.blueDeep,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tip,
            style: const TextStyle(
              color: OptikMemberTokens.inkSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: OptikMemberTokens.blueSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Cabang nota: ${(h['toko_id'] ?? '-').toString().toUpperCase()}\n'
              'Scan di POS cabang ini (bukan cabang lain). '
              'Kode QR sama dengan yang di email & WhatsApp.',
              style: const TextStyle(
                color: OptikMemberTokens.blueDeep,
                fontWeight: FontWeight.w600,
                height: 1.35,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (lifecycle)
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      OptikMemberTokens.blueMist,
                      OptikMemberTokens.white,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: OptikMemberTokens.lineSoft),
                  boxShadow: OptikMemberTokens.cardShadow,
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: payload,
                      size: 196,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: OptikMemberTokens.blueDeep,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: OptikMemberTokens.blueDeep,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sinkron POS ${(h['toko_id'] ?? '').toString().toUpperCase()} · ${ObrInvoice.prefix}|v1',
                      style: const TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: payload),
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Kode QR disalin'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Salin kode'),
                        ),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(hubUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Link nota'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OptikMemberTokens.blueSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                h['qr_owner_verified'] == true
                    ? 'QR fase belum tersedia. Tarik refresh atau hubungi toko.'
                    : 'Login Member dengan nomor WA yang sama seperti di nota '
                        'agar QR POS tampil di sini.',
                style: const TextStyle(
                  color: OptikMemberTokens.blueDeep,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemsCard(Map<String, dynamic> h) {
    final items = (h['items'] as List?) ?? const [];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MemberSectionLabel('Item & resep'),
          if (items.isEmpty)
            const Text('Tidak ada item',
                style: TextStyle(color: OptikMemberTokens.inkMuted))
          else
            ...items.map((raw) {
              final it = Map<String, dynamic>.from(raw as Map);
              final resep = (it['detail_resep'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${it['nama_produk'] ?? '-'} × ${it['qty'] ?? 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (resep.isNotEmpty)
                      Text(resep,
                          style: const TextStyle(
                              color: OptikMemberTokens.inkSecondary,
                              fontSize: 12.5,
                              height: 1.35)),
                    Text(_money(it['subtotal']),
                        style: const TextStyle(
                            color: OptikMemberTokens.blueDeep,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _fotoCard(Map<String, dynamic> h) {
    final url = h['foto_hasil_url'].toString();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MemberSectionLabel('Foto hasil jadi'),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                      height: 120,
                      child: Center(child: Text('Gagal memuat foto')),
                    )),
          ),
        ],
      ),
    );
  }

  Widget _garansiCard(Map<String, dynamic> h) {
    final list = (h['garansi'] as List?) ?? const [];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MemberSectionLabel('Garansi'),
          if (list.isEmpty)
            const Text('Belum ada kartu garansi untuk nota ini.',
                style: TextStyle(color: OptikMemberTokens.inkMuted))
          else
            ...list.map((raw) {
              final g = Map<String, dynamic>.from(raw as Map);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${g['jenis_garansi']} · ${g['nama_produk']}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  'Status: ${g['status']}\n'
                  '${g['tanggal_mulai'] ?? '-'} → ${g['tanggal_akhir'] ?? '-'}',
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _actions(Map<String, dynamic> h) {
    final diambil = InvoiceHubService.sudahDiambil(h);
    return Column(
      children: [
        FilledButton.icon(
          onPressed: () => _waToko(
            'Halo Optik B. Riski, saya cek status nota {inv}.',
          ),
          icon: const Icon(Icons.chat_rounded),
          label: const Text('Hubungi toko (WA)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openReview,
          icon: const Icon(Icons.reviews_outlined),
          label: const Text('Review Google toko'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  MemberRatingPage(initialInvoice: h['no_invoice']?.toString()),
            ),
          ),
          icon: const Icon(Icons.star_rate_rounded),
          label: const Text('Rating karyawan'),
        ),
        if (diambil) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MemberSurveyPage(
                  saleId: h['sale_id']?.toString() ?? '',
                  noInvoice: h['no_invoice']?.toString() ?? '',
                ),
              ),
            ),
            icon: const Icon(Icons.thumb_up_alt_outlined),
            label: const Text('Survei singkat'),
          ),
        ],
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OptikMemberTokens.white,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        border: Border.all(color: OptikMemberTokens.lineSoft),
        boxShadow: OptikMemberTokens.cardShadow,
      ),
      child: child,
    );
  }

  Widget _row(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(color: OptikMemberTokens.inkMuted))),
          Text(v,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: OptikMemberTokens.blueDeep)),
        ],
      ),
    );
  }
}
