import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';

/// Fitur 19 — klaim wajib datang ke toko + bawa barang.
class MemberClaimPage extends StatefulWidget {
  const MemberClaimPage({super.key, this.initialKartu});

  final Map<String, dynamic>? initialKartu;

  @override
  State<MemberClaimPage> createState() => _MemberClaimPageState();
}

class _MemberClaimPageState extends State<MemberClaimPage> {
  final _repo = MemberRepository();
  final _alasan = TextEditingController();
  List<Map<String, dynamic>> _kartu = const [];
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _toko = const [];
  String? _kartuId;
  String? _tokoId;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _kartuId = widget.initialKartu?['id']?.toString();
    _tokoId = widget.initialKartu?['toko_id']?.toString();
    _bootstrap();
  }

  @override
  void dispose() {
    _alasan.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final phone = MemberSession.instance.phoneForQuery;
    setState(() => _loading = true);
    try {
      final kartu =
          phone.isEmpty ? <Map<String, dynamic>>[] : await _repo.listGaransi(phone);
      final reqs = phone.isEmpty
          ? <Map<String, dynamic>>[]
          : await _repo.listClaimRequests(phone);
      List<Map<String, dynamic>> toko = [];
      try {
        final rows = await Supabase.instance.client
            .from('invoice_settings')
            .select('toko_id, shop_name')
            .order('toko_id');
        toko = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _kartu = kartu;
        _requests = reqs;
        _toko = toko;
        _kartuId ??= kartu.isNotEmpty ? kartu.first['id']?.toString() : null;
        _tokoId ??= kartu.isNotEmpty
            ? kartu.first['toko_id']?.toString()
            : (toko.isNotEmpty ? toko.first['toko_id']?.toString() : null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _submit() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login dulu.')),
      );
      return;
    }
    if (_kartuId == null || _tokoId == null || _alasan.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi kartu, cabang, dan alasan.')),
      );
      return;
    }
    Map<String, dynamic>? kartu;
    for (final g in _kartu) {
      if (g['id']?.toString() == _kartuId) {
        kartu = g;
        break;
      }
    }
    setState(() => _busy = true);
    try {
      await _repo.submitClaimRequest(
        phone: phone,
        kartuId: _kartuId!,
        tokoId: _tokoId!,
        alasan: _alasan.text.trim(),
        saleId: kartu?['sale_id']?.toString(),
        memberId: MemberSession.instance.memberId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pengajuan tersimpan. Datang ke toko membawa barang untuk dicek.',
          ),
        ),
      );
      _alasan.clear();
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$e'), backgroundColor: OptikMemberTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MemberPremiumScaffold(
      title: 'Klaim garansi',
      subtitle: 'Wajib ke toko + bawa barang',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.blueSoft,
                    borderRadius:
                        BorderRadius.circular(OptikMemberTokens.radiusMd),
                  ),
                  child: const Text(
                    'App hanya mengajukan niat klaim. Keputusan bisa/tidak '
                    'hanya setelah petugas memeriksa barang di toko.',
                    style: TextStyle(
                      color: OptikMemberTokens.blueDeep,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _kartuId,
                  decoration: const InputDecoration(labelText: 'Kartu garansi'),
                  items: _kartu
                      .map((g) => DropdownMenuItem(
                            value: g['id']?.toString(),
                            child: Text(
                              '${g['jenis_garansi']} · ${g['nama_produk']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _kartuId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _tokoId,
                  decoration:
                      const InputDecoration(labelText: 'Cabang kunjungan'),
                  items: _toko
                      .map((t) => DropdownMenuItem(
                            value: t['toko_id']?.toString(),
                            child: Text(
                              '${t['toko_id']} · ${t['shop_name'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _tokoId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _alasan,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Alasan / keluhan',
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Ajukan & siap datang ke toko'),
                ),
                const SizedBox(height: 22),
                const MemberSectionLabel('Pengajuan saya'),
                if (_requests.isEmpty)
                  const Text('Belum ada pengajuan.',
                      style: TextStyle(color: OptikMemberTokens.inkMuted))
                else
                  ..._requests.map((r) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${r['status']} · ${r['toko_id']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${r['alasan']}\n${r['created_at']}'),
                      )),
              ],
            ),
    );
  }
}
