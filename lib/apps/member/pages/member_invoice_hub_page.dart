import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';

import '../../../shared/garansi/garansi_service.dart';
import '../../../shared/invoice/invoice_document_builder.dart';
import '../../../shared/invoice/invoice_hub_service.dart';
import '../../../shared/invoice/invoice_link.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/member/member_status_watch.dart';
import '../../../shared/qr/obr_codes.dart';
import '../../../shared/theme.dart';
import '../../../shared/whatsapp_launcher.dart';
import '../member_rating_page.dart';
import '../member_widgets.dart';
import 'member_claim_terms_gate.dart';
import 'member_survey_page.dart';

/// Detail nota + status + QR fase + foto + review + garansi (fitur 1,2,11,16,17).
/// Layout nota = kit yang sama dengan Adjust Invoice / POS / PDF.
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
  InvoiceDocumentModel? _doc;
  bool _loading = true;
  String? _error;
  Set<String> _openRequestKartuIds = const {};
  /// False = status pengajuan tidak diketahui → Klaim dinonaktifkan.
  bool _openRequestsKnown = true;
  StreamSubscription<void>? _watchSub;

  @override
  void initState() {
    super.initState();
    _load();
    _watchSub = MemberStatusWatch.instance.onRefresh.listen((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _hub = null;
      _doc = null;
    });
    final phone = MemberSession.instance.phoneForQuery;
    if (!MemberSession.instance.isLoggedIn || phone.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'login';
      });
      return;
    }
    try {
      final hub = await _hubSvc.loadByInvoice(
        widget.noInvoice,
        phone: phone,
      );
      if (!mounted) return;
      if (hub == null) {
        setState(() {
          _loading = false;
          _error = 'not_found';
          _doc = null;
        });
        return;
      }
      // Wajib milik nomor HP akun yang login (selaras rating / resep).
      if (hub['qr_owner_verified'] != true) {
        setState(() {
          _loading = false;
          _error = 'not_owner';
          _doc = null;
          _hub = null;
        });
        return;
      }
      hub['role_view'] = 'member';
      final items = (hub['items'] as List?) ?? const [];
      final doc = await InvoiceDocumentBuilder.fromSale(
        sale: Map<String, dynamic>.from(hub),
        items: items,
      );

      var openKnown = true;
      var openIds = <String>{};
      try {
        final reqs = await _repo.listClaimRequests(phone);
        for (final r in reqs) {
          if (!GaransiService.isOpenClaimRequestStatus(
              r['status']?.toString())) {
            continue;
          }
          final kid = r['kartu_id']?.toString();
          if (kid != null && kid.isNotEmpty) openIds.add(kid);
        }
      } catch (_) {
        openKnown = false;
        openIds = {};
      }

      if (!mounted) return;
      setState(() {
        _hub = hub;
        _doc = doc;
        _openRequestKartuIds = openIds;
        _openRequestsKnown = openKnown;
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

  bool _hasOpenRequest(String? kartuId) {
    if (kartuId == null || kartuId.isEmpty) return false;
    return _openRequestKartuIds.contains(kartuId);
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
                  icon: _error == 'login'
                      ? Icons.lock_outline_rounded
                      : Icons.receipt_long_outlined,
                  title: _error == 'login'
                      ? 'member_invoice_login_title'.tr()
                      : _error == 'not_found'
                          ? 'invoice_hub_not_found'.tr()
                          : _error == 'not_owner'
                              ? 'member_invoice_not_owner_title'.tr()
                              : 'Gagal memuat',
                  message: _error == 'login'
                      ? 'member_invoice_login_msg'.tr()
                      : _error == 'not_found'
                          ? 'Nota mungkin sudah dihapus atau nomor salah. '
                              'Cek lagi dari daftar Pesanan.'
                          : _error == 'not_owner'
                              ? 'member_rating_not_owner'.tr()
                              : _error!,
                  actionLabel: _error == 'login'
                      ? 'member_invoice_go_login'.tr()
                      : (_error == 'not_found' || _error == 'not_owner')
                          ? 'Kembali'
                          : 'Coba lagi',
                  onAction: _error == 'login'
                      ? () => Navigator.of(context)
                          .pushReplacementNamed('/login')
                      : (_error == 'not_found' || _error == 'not_owner')
                          ? () => Navigator.of(context).maybePop()
                          : _load,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    if (_doc != null) ...[
                      Center(
                        child: InvoiceDocumentBuilder.buildUi(
                          _doc!,
                          width: 420,
                          qrOverride: _memberQrPayload(h!),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _phaseCard(h!),
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

  /// QR di nota: lifecycle bila aktif, else link hub.
  String? _memberQrPayload(Map<String, dynamic> h) {
    final raw = (h['qr_payload'] ?? '').toString().trim();
    if (InvoiceLink.isCustomerLifecycleQr(raw)) return raw;
    final inv = h['no_invoice']?.toString() ?? widget.noInvoice;
    return InvoiceLink.encodeHttps(inv);
  }

  Widget _phaseCard(Map<String, dynamic> h) {
    final tracking =
        (h['tracking_status'] ?? '').toString().trim().toUpperCase();
    final lunasPending = InvoiceHubService.isLunas(h) &&
        !InvoiceHubService.sudahDiambil(h) &&
        tracking != 'SIAP_DIAMBIL' &&
        tracking != 'CLEAR';
    final phaseKey = (h['qr_phase'] ?? '').toString().toUpperCase();
    final rawPayload = (h['qr_payload'] ?? '').toString().trim();
    final hasQr = InvoiceLink.isCustomerLifecycleQr(rawPayload);
    final dpWaiting = InvoiceHubService.isDpOpen(h) && !hasQr;
    String phase;
    String tip;
    if (dpWaiting) {
      // Selaras label Pesanan / Beranda — jangan bilang "menunggu ready"
      // kalau tracking sudah SIAP_DIAMBIL / CLEAR.
      phase = InvoiceHubService.statusLabel(h);
      if (tracking == 'SIAP_DIAMBIL' ||
          tracking == 'CLEAR' ||
          tracking == 'SIAP_PELUNASAN') {
        tip =
            'Barang ready / siap pelunasan. Lunasi sisa tagihan di kasir '
            'sebelum ambil. Tunjukkan nota ini ke staf.';
      } else {
        tip =
            'Pembayaran DP dikonfirmasi (nota tanpa QR). '
            'QR pelunasan dikirim ke email, WA, dan di sini setelah admin '
            'menandai barang ready.';
      }
    } else if (phaseKey == 'DP' || InvoiceHubService.isDpOpen(h)) {
      phase = 'QR fase DP · pelunasan';
      tip =
          'QR DP dipegang Anda. Tunjukkan ke kasir untuk pelunasan. '
          'Setelah lunas, QR pengambilan aktif bila barang sudah ready.';
    } else if (phaseKey == 'CLAIM' || InvoiceHubService.sudahDiambil(h)) {
      phase = 'QR fase CLAIM · garansi';
      tip =
          'QR CLAIM dipegang Anda. Bawa barang + QR ini saat klaim.';
    } else if (lunasPending) {
      phase = 'Lunas pending · menunggu barang ready';
      tip =
          'Pembayaran lunas dikonfirmasi (nota tanpa QR). '
          'QR pengambilan muncul di sini (juga email & WA) setelah admin '
          'menandai barang ready.';
    } else {
      phase = 'QR fase LUNAS ready · pengambilan';
      tip =
          'QR ini dipegang Anda. Tunjukkan saat ambil barang untuk '
          'serah terima + aktifkan kartu garansi.';
    }

    final payload = (dpWaiting || lunasPending) ? '' : rawPayload;
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
              // Hub RPC kadang tanpa no_invoice — isi dari nota ini.
              g.putIfAbsent('no_invoice', () => widget.noInvoice);
              g.putIfAbsent('sale_id', () => h['sale_id'] ?? h['id']);
              g.putIfAbsent('toko_id', () => h['toko_id']);
              final openReq = _hasOpenRequest(g['id']?.toString());
              final claimable = _openRequestsKnown &&
                  GaransiService.kartuBisaDiklaim(g) &&
                  !openReq;
              final blocked = !_openRequestsKnown
                  ? 'Tidak bisa cek pengajuan. Refresh halaman.'
                  : openReq
                      ? 'Pengajuan untuk kartu ini masih terbuka.'
                      : GaransiService.alasanTidakBisaKlaim(g);
              final mulai = GaransiService.tanggalMulaiKartu(g);
              final akhir = GaransiService.tanggalAkhirKartu(g);
              final range =
                  '${mulai != null ? GaransiService.formatDate(mulai) : (g['tanggal_mulai'] ?? '-')}'
                  ' → '
                  '${akhir != null ? GaransiService.formatDate(akhir) : (g['tanggal_akhir'] ?? '-')}';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${g['jenis_garansi']} · ${g['nama_produk']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      'Status: ${GaransiService.statusLabel(g)}\n'
                      '$range'
                      '${blocked == null || claimable ? '' : '\n$blocked'}',
                    ),
                  ),
                  if (claimable)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => openMemberClaimPage(
                          context,
                          initialKartu: g,
                        ),
                        icon: const Icon(Icons.storefront_outlined, size: 18),
                        label: const Text('Ajukan klaim'),
                      ),
                    ),
                ],
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
          label: Text('member_rating_cta'.tr()),
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


}
