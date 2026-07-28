import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';

class MemberPointsPage extends StatefulWidget {
  const MemberPointsPage({super.key});

  @override
  State<MemberPointsPage> createState() => _MemberPointsPageState();
}

class _MemberPointsPageState extends State<MemberPointsPage> {
  final _repo = MemberRepository();
  int _points = 0;
  List<Map<String, dynamic>> _promos = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final mid = MemberSession.instance.memberId;
    final promos = await _repo.listPromos();
    final pts = mid == null || mid.isEmpty ? 0 : await _repo.pointsBalance(mid);
    if (!mounted) return;
    setState(() {
      _promos = promos;
      _points = pts;
      _loading = false;
    });
  }

  String _discountLabel(Map<String, dynamic> p) {
    final type = (p['discount_type'] ?? 'nominal').toString();
    final value = int.tryParse('${p['discount_value'] ?? 0}') ?? 0;
    if (type == 'percent') return 'Diskon $value%';
    if (type == 'nominal' && value > 0) return 'Potongan Rp $value';
    return 'Promo Member';
  }

  String _qtyLabel(Map<String, dynamic> p) {
    final left = p['quantity_remaining'];
    final total = p['quantity'];
    if (left == null && total == null) return 'Kuota tanpa batas';
    if (left != null && total != null) return 'Sisa $left / $total';
    if (left != null) return 'Sisa $left';
    return 'Kuota $total';
  }

  @override
  Widget build(BuildContext context) {
    return MemberPremiumScaffold(
      title: 'Poin & promo',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        OptikMemberTokens.blueDeep,
                        OptikMemberTokens.blue
                      ],
                    ),
                    borderRadius:
                        BorderRadius.circular(OptikMemberTokens.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Saldo poin',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(
                        '$_points',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Tunjukkan kode voucher ke kasir untuk dipakai di POS.',
                        style: TextStyle(color: Colors.white70, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const MemberSectionLabel('Promo aktif'),
                if (_promos.isEmpty)
                  const Text('Belum ada promo.',
                      style: TextStyle(color: OptikMemberTokens.inkMuted))
                else
                  ..._promos.map((p) {
                    final code = (p['voucher_code'] ?? '').toString();
                    final imageUrl = (p['image_url'] ?? '').toString();
                    final terms = (p['terms'] ?? '').toString();
                    final validUntil = (p['valid_until'] ?? '').toString();
                    final pointsCost =
                        int.tryParse('${p['points_cost'] ?? 0}') ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: OptikMemberTokens.white,
                        borderRadius: BorderRadius.circular(
                            OptikMemberTokens.radiusMd),
                        border:
                            Border.all(color: OptikMemberTokens.lineSoft),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageUrl.trim().isNotEmpty)
                            AspectRatio(
                              aspectRatio: 16 / 7,
                              child: Image.network(
                                imageUrl.trim(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: OptikMemberTokens.blue.withOpacity(0.08),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.local_offer_outlined,
                                    color: OptikMemberTokens.blue,
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${p['title']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: OptikMemberTokens.blueDeep,
                                        fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(_discountLabel(p),
                                    style: const TextStyle(
                                      color: OptikMemberTokens.blue,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    )),
                                if ((p['description'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text('${p['description']}',
                                      style: const TextStyle(
                                          color: OptikMemberTokens.inkSecondary,
                                          height: 1.35)),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _chip(_qtyLabel(p)),
                                    if (pointsCost > 0)
                                      _chip('Butuh $pointsCost poin'),
                                    if (validUntil.isNotEmpty)
                                      _chip(
                                          's/d ${validUntil.length >= 10 ? validUntil.substring(0, 10) : validUntil}'),
                                  ],
                                ),
                                if (terms.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    terms.trim(),
                                    style: const TextStyle(
                                      color: OptikMemberTokens.inkMuted,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                                if (code.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text('Kode: $code',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          await Clipboard.setData(
                                              ClipboardData(text: code));
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text('Kode disalin')),
                                          );
                                        },
                                        child: const Text('Salin'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: OptikMemberTokens.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: OptikMemberTokens.blueDeep,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
