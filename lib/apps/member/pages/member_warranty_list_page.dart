import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/garansi/garansi_service.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_claim_terms_gate.dart';
import 'member_invoice_hub_page.dart';

class MemberWarrantyListPage extends StatefulWidget {
  const MemberWarrantyListPage({super.key});

  @override
  State<MemberWarrantyListPage> createState() => _MemberWarrantyListPageState();
}

class _MemberWarrantyListPageState extends State<MemberWarrantyListPage> {
  final _repo = MemberRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  Set<String> _openRequestKartuIds = const {};
  /// False = tidak bisa cek pengajuan terbuka → Klaim dinonaktifkan (fail-closed).
  bool _openRequestsKnown = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _hasOpenRequest(String? kartuId) {
    if (kartuId == null || kartuId.isEmpty) return false;
    return _openRequestKartuIds.contains(kartuId);
  }

  String _friendlyLoadError(Object e) {
    if (e is PostgrestException) {
      final m = e.message.trim();
      if (m.isNotEmpty && m.length <= 180) return m;
    }
    var s = e.toString().trim();
    s = s.replaceFirst(RegExp(r'^(Exception|PostgrestException):\s*'), '');
    if (s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection closed')) {
      return 'Tidak ada koneksi. Periksa jaringan lalu coba lagi.';
    }
    if (s.isEmpty || s.length > 180 || s.contains('{') || s.contains('code:')) {
      return 'Gagal memuat kartu garansi. Coba lagi.';
    }
    return s;
  }

  Future<void> _load() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'login';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.listGaransi(phone);
      var openKnown = true;
      var openIds = <String>{};
      try {
        final reqs = await _repo.listClaimRequests(phone);
        for (final r in reqs) {
          if (!GaransiService.isOpenClaimRequestStatus(r['status']?.toString())) {
            continue;
          }
          final kid = r['kartu_id']?.toString();
          if (kid != null && kid.isNotEmpty) openIds.add(kid);
        }
      } catch (_) {
        // Fail-closed: jangan aktifkan Klaim kalau status pengajuan tidak diketahui.
        openKnown = false;
        openIds = {};
      }
      if (!mounted) return;
      setState(() {
        _rows = list;
        _openRequestKartuIds = openIds;
        _openRequestsKnown = openKnown;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyLoadError(e);
      });
    }
  }

  String _dateRangeLabel(Map<String, dynamic> g) {
    final mulai = GaransiService.tanggalMulaiKartu(g);
    final akhir = GaransiService.tanggalAkhirKartu(g);
    final a = mulai != null
        ? GaransiService.formatDate(mulai)
        : (g['tanggal_mulai']?.toString().trim().isNotEmpty == true
            ? g['tanggal_mulai'].toString()
            : '-');
    final b = akhir != null
        ? GaransiService.formatDate(akhir)
        : (g['tanggal_akhir']?.toString().trim().isNotEmpty == true
            ? g['tanggal_akhir'].toString()
            : '-');
    return '$a → $b';
  }

  @override
  Widget build(BuildContext context) {
    return MemberPremiumScaffold(
      title: 'Kartu garansi',
      subtitle:
          'Aktif ${GaransiService.garansiHari} hari sejak diambil · lebih dari itu mati',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error == 'login'
              ? MemberEmptyState(
                  icon: Icons.lock_outline_rounded,
                  title: 'Login dulu',
                  message: 'Garansi terikat nomor HP yang dipakai saat belanja.',
                  actionLabel: 'Ke login',
                  onAction: () =>
                      Navigator.of(context).pushReplacementNamed('/login'),
                )
              : _error != null
                  ? MemberEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Gagal memuat',
                      message: _error!,
                      actionLabel: 'Coba lagi',
                      onAction: _load,
                    )
                  : _rows.isEmpty
                      ? const MemberEmptyState(
                          icon: Icons.verified_user_outlined,
                          title: 'Belum ada garansi',
                          message:
                              'Kartu muncul setelah kacamata diambil / diaktifkan toko.',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final g = _rows[i];
                              final inv = g['no_invoice']?.toString() ?? '';
                              final toko = (g['toko_id'] ?? '').toString().trim();
                              final openReq =
                                  _hasOpenRequest(g['id']?.toString());
                              final claimable = _openRequestsKnown &&
                                  GaransiService.kartuBisaDiklaim(g) &&
                                  !openReq;
                              final blocked = !_openRequestsKnown
                                  ? 'Tidak bisa cek pengajuan. Tarik refresh.'
                                  : openReq
                                      ? 'Pengajuan untuk kartu ini masih terbuka.'
                                      : GaransiService.alasanTidakBisaKlaim(g);
                              final status = GaransiService.statusLabel(g);
                              final jenis =
                                  (g['jenis_garansi'] ?? '-').toString();
                              final produk =
                                  (g['nama_produk'] ?? '-').toString();
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: OptikMemberTokens.white,
                                  borderRadius: BorderRadius.circular(
                                      OptikMemberTokens.radiusMd),
                                  border: Border.all(
                                      color: OptikMemberTokens.lineSoft),
                                  boxShadow: OptikMemberTokens.cardShadow,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$jenis · $produk',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: OptikMemberTokens.blueDeep,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Status: $status\n'
                                      '${_dateRangeLabel(g)}'
                                      '${toko.isEmpty ? '' : '\nToko: $toko'}',
                                      style: const TextStyle(
                                        color: OptikMemberTokens.inkSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                    if (!claimable && blocked != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        blocked,
                                        style: const TextStyle(
                                          color: OptikMemberTokens.inkMuted,
                                          fontSize: 12.5,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                    if (inv.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Nota: $inv',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: OptikMemberTokens.inkMuted),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        if (inv.isNotEmpty)
                                          Expanded(
                                            child: OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                  minimumSize:
                                                      const Size(0, 42)),
                                              onPressed: () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      MemberInvoiceHubPage(
                                                          noInvoice: inv),
                                                ),
                                              ),
                                              child: const Text('Lihat nota'),
                                            ),
                                          ),
                                        if (inv.isNotEmpty)
                                          const SizedBox(width: 8),
                                        Expanded(
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(
                                                minimumSize:
                                                    const Size(0, 42)),
                                            onPressed: claimable
                                                ? () => openMemberClaimPage(
                                                      context,
                                                      initialKartu: g,
                                                    )
                                                : null,
                                            child: Text(
                                              claimable
                                                  ? 'Klaim'
                                                  : 'Tidak bisa',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
    );
  }
}
