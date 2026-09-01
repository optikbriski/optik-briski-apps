import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/invoice/invoice_document_builder.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_resep_helpers.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/ocr/document_ocr_flow.dart';
import '../../../shared/ocr/google_vision_ocr_service.dart';
import '../../../shared/ocr/vision_rx_draft.dart';
import '../../../shared/theme.dart';
import '../../../shared/whatsapp_launcher.dart';
import '../member_widgets.dart';
import 'member_invoice_hub_page.dart';
import '../../../shared/brand/brand_service.dart';

/// Fitur 9 — riwayat resep dari nota + scan resep dokter (draf, kirim WA).
class MemberReorderPage extends StatefulWidget {
  const MemberReorderPage({super.key});

  @override
  State<MemberReorderPage> createState() => _MemberReorderPageState();
}

class _MemberReorderPageState extends State<MemberReorderPage> {
  final _repo = MemberRepository();
  final _scanText = TextEditingController();
  bool _loading = true;
  bool _scanBusy = false;
  String? _error;
  final List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _scanText.addListener(_onScanText);
    _load();
  }

  void _onScanText() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scanText.removeListener(_onScanText);
    _scanText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (!MemberSession.instance.isLoggedIn || phone.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'login';
        _rows.clear();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.listResep(phone);
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(list);
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

  Future<void> _scanRx() async {
    if (!MemberSession.instance.isLoggedIn) {
      await Navigator.of(context).pushNamed('/login');
      return;
    }
    setState(() => _scanBusy = true);
    try {
      final bytes = await scanDocumentPreviewBytes(context: context);
      if (bytes == null || !mounted) return;
      final draft = await GoogleVisionOcrService().readDocument(
        bytes: bytes,
        kind: 'rx',
        memberId: MemberSession.instance.memberId,
        phone: MemberSession.instance.phoneForQuery,
      );
      if (!mounted) return;
      final rx = VisionRxDraft.parse(draft.text);
      _scanText.text = rx.displayText;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rx.displayText.trim().isEmpty
                ? 'Resep tidak terbaca. Isi manual atau foto ulang.'
                : 'Teks resep sudah diisi — cek SPH/CYL sebelum kirim.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membaca resep: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _scanBusy = false);
    }
  }

  Future<void> _waScanned() async {
    final resep = _scanText.text.trim();
    if (resep.isEmpty) return;
    var toko = (MemberSession.instance.preferredTokoId ?? '').trim();
    if (toko.isEmpty && _rows.isNotEmpty) {
      toko = (_rows.first['toko_id'] ?? 'PUSAT').toString();
    }
    if (toko.isEmpty) toko = 'PUSAT';
    final settings = await _repo.storeSettings(toko);
    final phone = (settings?['phone'] ?? '').toString();
    final msg =
        'Halo ${BrandService.name}, saya kirim scan resep dokter (mohon dicek di toko):\n$resep';
    if (phone.trim().isEmpty) {
      await openAdminWhatsApp(message: msg);
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/${normalizeWaNumber(phone)}?text=${Uri.encodeComponent(msg)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _waReorder(Map<String, dynamic> row) async {
    final toko = (row['toko_id'] ?? 'PUSAT').toString();
    final settings = await _repo.storeSettings(toko);
    final phone = (settings?['phone'] ?? '').toString();
    final msg =
        'Halo ${BrandService.name}, saya ingin pesan ulang mirip nota ${row['no_invoice']}: '
        '${row['nama_produk']}. Resep: ${row['detail_resep'] ?? '-'}';
    if (phone.trim().isEmpty) {
      await openAdminWhatsApp(message: msg);
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/${normalizeWaNumber(phone)}?text=${Uri.encodeComponent(msg)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _resepBody(Map<String, dynamic> r) {
    final resep = (r['detail_resep'] ?? '').toString();
    if (MemberResepHelpers.isStructuredResep(resep)) {
      return InvoiceDocumentBuilder.lensTableUi(resep);
    }
    return Text(
      resep,
      style: const TextStyle(
        color: OptikMemberTokens.inkSecondary,
        height: 1.35,
        fontSize: 13,
      ),
    );
  }

  Widget _fotoHasil(Map<String, dynamic> r) {
    final url = (r['foto_hasil_url'] ?? '').toString().trim();
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: OptikMemberTokens.blueSoft,
              alignment: Alignment.center,
              child: const Text(
                'Foto hasil tidak bisa dimuat',
                style: TextStyle(
                  color: OptikMemberTokens.inkMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MemberPremiumScaffold(
      title: 'Resep & pesan ulang',
      actions: [
        if (MemberSession.instance.isLoggedIn)
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Muat ulang',
          ),
      ],
      body: _error == 'login'
          ? MemberEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Login dulu',
              message: 'Riwayat resep terikat nomor HP belanja.',
              actionLabel: 'Ke login',
              onAction: () =>
                  Navigator.of(context).pushReplacementNamed('/login'),
            )
          : Column(
              children: [
                _scanCard(),
                Expanded(child: _historyBody()),
              ],
            ),
    );
  }

  Widget _scanCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: OptikMemberTokens.white,
          borderRadius:
              BorderRadius.circular(OptikMemberTokens.radiusMd),
          border: Border.all(color: OptikMemberTokens.lineSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Scan resep dokter',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: OptikMemberTokens.blueDeep,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Bingkai diluruskan dulu, lalu teks diisi sebagai draf. Cek SPH/CYL sebelum kirim ke toko.',
              style: TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            if (_scanBusy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _scanBusy ? null : _scanRx,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan resep'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _scanText,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Draf resep',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _scanBusy || _scanText.text.trim().isEmpty
                  ? null
                  : _waScanned,
              child: const Text('Kirim ke toko (WA)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return MemberEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Gagal memuat',
        message: _error!,
        actionLabel: 'Coba lagi',
        onAction: _load,
      );
    }
    if (_rows.isEmpty) {
      return MemberEmptyState(
        icon: Icons.history_edu_outlined,
        title: 'Belum ada resep di nota',
        message:
            'Resep dari belanja toko muncul di sini. Resep dokter bisa di-scan di atas.',
        actionLabel: 'Muat ulang',
        onAction: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _rows[i];
          final nama = (r['nama_produk'] ?? 'Produk').toString();
          final inv = (r['no_invoice'] ?? '').toString();
          final toko = (r['toko_id'] ?? '').toString();
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OptikMemberTokens.white,
              borderRadius:
                  BorderRadius.circular(OptikMemberTokens.radiusMd),
              border: Border.all(color: OptikMemberTokens.lineSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: OptikMemberTokens.blueDeep,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nota $inv · $toko',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: OptikMemberTokens.inkMuted,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 8),
                _resepBody(r),
                _fotoHasil(r),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                        ),
                        onPressed: inv.isEmpty
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MemberInvoiceHubPage(
                                      noInvoice: inv,
                                    ),
                                  ),
                                ),
                        child: const Text('Nota'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 42),
                        ),
                        onPressed: () => _waReorder(r),
                        child: const Text('WA pesan ulang'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
