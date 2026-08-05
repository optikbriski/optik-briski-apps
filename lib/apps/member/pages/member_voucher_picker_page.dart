import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_shipping_voucher.dart';
import '../../../shared/theme.dart';

/// Pilih voucher: Ongkir OBR (atas) + Diskon/Cashback CMS (bawah).
class MemberVoucherPickerPage extends StatefulWidget {
  const MemberVoucherPickerPage({
    super.key,
    required this.subtotal,
    required this.shippingFee,
    required this.isObr,
    required this.shippingCategory,
    this.initial,
  });

  final int subtotal;
  final int shippingFee;
  final bool isObr;
  final String? shippingCategory;
  final MemberVoucherSelection? initial;

  @override
  State<MemberVoucherPickerPage> createState() =>
      _MemberVoucherPickerPageState();
}

class _MemberVoucherPickerPageState extends State<MemberVoucherPickerPage> {
  final _repo = MemberRepository();
  final _codeCtrl = TextEditingController();
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _loading = true;
  List<Map<String, dynamic>> _promos = const [];
  bool _useShip = false;
  Map<String, dynamic>? _productPromo;
  String? _codeError;
  bool _lookingUp = false;

  late final ObrShippingVoucherTier _tier =
      ObrShippingVoucherTier.resolve(widget.subtotal);

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _useShip = init.useShippingVoucher;
      _productPromo = init.productPromo;
    }
    _boot();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    // UI voucher ongkir tidak bergantung promo — jangan biarkan loading menggantung.
    try {
      final rows = await _repo.listPromos(forMember: true);
      if (!mounted) return;
      setState(() {
        _promos = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _promos = const [];
        _loading = false;
      });
    }
  }

  bool get _shipEligible => _tier.canApply(
        isObr: widget.isObr,
        category: widget.shippingCategory,
        shippingFee: widget.shippingFee,
      );

  int get _shipDiscount =>
      _useShip && _shipEligible ? _tier.applyDiscount(widget.shippingFee) : 0;

  int get _productDiscount {
    final p = _productPromo;
    if (p == null) return 0;
    return productPromoDiscountRp(p, widget.subtotal);
  }

  int get _selectedCount =>
      (_useShip && _shipEligible ? 1 : 0) + (_productPromo != null ? 1 : 0);

  bool _isRedeemablePromo(Map<String, dynamic> p) {
    final type = (p['discount_type'] ?? 'nominal').toString().toLowerCase();
    final code = (p['voucher_code'] ?? '').toString().trim();
    return type != 'info' && code.isNotEmpty;
  }

  List<Map<String, dynamic>> get _redeemablePromos =>
      _promos.where(_isRedeemablePromo).toList();

  List<Map<String, dynamic>> get _nonRedeemablePromos =>
      _promos.where((p) => !_isRedeemablePromo(p)).toList();

  Future<void> _applyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _lookingUp = true;
      _codeError = null;
    });
    final res = await _repo.lookupPromo(code, channel: 'online');
    if (!mounted) return;
    setState(() => _lookingUp = false);
    if (res['ok'] != true) {
      setState(() => _codeError = (res['error'] ?? 'Kode tidak valid').toString());
      return;
    }
    final dtype = (res['discount_type'] ?? 'nominal').toString().toLowerCase();
    if (dtype == 'info') {
      setState(() => _codeError = 'Voucher info tidak bisa dipakai sebagai diskon');
      return;
    }
    final promo = res['promo'] is Map
        ? Map<String, dynamic>.from(res['promo'] as Map)
        : Map<String, dynamic>.from(res)
      ..remove('ok');
    if ((promo['title'] ?? '').toString().isEmpty &&
        (promo['voucher_code'] ?? '').toString().isEmpty) {
      // RPC kadang return flat fields
      setState(() {
        _productPromo = {
          'id': res['id'],
          'title': res['title'] ?? code,
          'voucher_code': res['voucher_code'] ?? code,
          'discount_type': res['discount_type'] ?? 'nominal',
          'discount_value': res['discount_value'] ?? 0,
          'description': res['description'],
        };
        _codeError = null;
      });
      return;
    }
    setState(() {
      _productPromo = promo;
      _codeError = null;
    });
  }

  void _confirm() {
    final promo = _productPromo;
    final safePromo =
        promo != null && _isRedeemablePromo(promo) ? promo : null;
    Navigator.pop(
      context,
      MemberVoucherSelection(
        useShippingVoucher: _useShip && _shipEligible,
        shippingTierId: _useShip && _shipEligible ? _tier.id : null,
        productPromo: safePromo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final next = ObrShippingVoucherTier.nextAfter(_tier);
    final shipBlock = _tier.blockReason(
      isObr: widget.isObr,
      category: widget.shippingCategory,
      shippingFee: widget.shippingFee,
    );

    return Scaffold(
      backgroundColor: OptikMemberTokens.canvas,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(4, top + 4, 12, 12),
            decoration: const BoxDecoration(
              color: OptikMemberTokens.white,
              border: Border(
                bottom: BorderSide(color: OptikMemberTokens.lineSoft),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: OptikMemberTokens.ink,
                ),
                const Expanded(
                  child: Text(
                    'Pilih Voucher',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: OptikMemberTokens.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _codeRow(),
                if (_codeError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _codeError!,
                    style: const TextStyle(
                      color: OptikMemberTokens.danger,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Voucher Ongkir',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: OptikMemberTokens.blueDeep,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_tier.rangeLabel} · ${_tier.categoriesLabel}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: OptikMemberTokens.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _ticketCard(
                  accent: OptikMemberTokens.blue,
                  badge: 'ONGKIR',
                  badgeSub: 'OBR',
                  title: _tier.title,
                  lines: [
                    'Diskon s.d. ${_money.format(_tier.maxDiscount)}',
                    _tier.subtitle,
                    if (shipBlock != null) shipBlock,
                    if (next != null)
                      'Naik tier: belanja min. ${_money.format(next.minSubtotal)}',
                  ],
                  selected: _useShip && _shipEligible,
                  enabled: _shipEligible,
                  onTap: _shipEligible
                      ? () => setState(() => _useShip = !_useShip)
                      : null,
                ),
                const SizedBox(height: 22),
                const Text(
                  'Diskon / Cashback',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: OptikMemberTokens.blueDeep,
                  ),
                ),
                const SizedBox(height: 10),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                else if (_promos.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OptikMemberTokens.lineSoft),
                    ),
                    child: const Text(
                      'Belum ada promo diskon aktif.\n'
                      'Masukkan kode voucher di atas jika punya.',
                      style: TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        height: 1.35,
                      ),
                    ),
                  )
                else ...[
                  for (final p in _redeemablePromos) ...[
                    _promoTicket(p),
                    const SizedBox(height: 10),
                  ],
                  if (_redeemablePromos.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: OptikMemberTokens.white,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: OptikMemberTokens.lineSoft),
                      ),
                      child: const Text(
                        'Promo terdaftar belum bisa di-redeem '
                        '(butuh kode voucher + tipe Nominal/Persen).\n'
                        'Masukkan kode di atas, atau lengkapi di CMS Admin.',
                        style: TextStyle(
                          color: OptikMemberTokens.inkMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  for (final p in _nonRedeemablePromos) ...[
                    _promoTicket(p),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: OptikMemberTokens.lineSoft),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _selectedCount == 0
                        ? 'Belum ada voucher dipilih'
                        : '$_selectedCount voucher dipilih',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: OptikMemberTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (_shipDiscount > 0)
                        'Ongkir −${_money.format(_shipDiscount)}',
                      if (_productDiscount > 0)
                        'Diskon −${_money.format(_productDiscount)}',
                      if (_shipDiscount == 0 && _productDiscount == 0)
                        'Pilih voucher lalu tekan OK',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: OptikMemberTokens.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: OptikMemberTokens.blueDeep,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(fontWeight: FontWeight.w800),
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

  Widget _codeRow() {
    final can = _codeCtrl.text.trim().isNotEmpty && !_lookingUp;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _codeCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Masukkan kode voucher',
              filled: true,
              fillColor: OptikMemberTokens.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OptikMemberTokens.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OptikMemberTokens.line),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: can ? _applyCode : null,
            style: FilledButton.styleFrom(
              backgroundColor: OptikMemberTokens.blue,
              disabledBackgroundColor: OptikMemberTokens.blueSoft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _lookingUp
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Pakai', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _promoTicket(Map<String, dynamic> p) {
    final id = (p['id'] ?? '').toString();
    final selected = _productPromo != null &&
        (_productPromo!['id']?.toString() == id ||
            (_productPromo!['voucher_code']?.toString().isNotEmpty == true &&
                _productPromo!['voucher_code']?.toString() ==
                    p['voucher_code']?.toString()));
    final type = (p['discount_type'] ?? 'nominal').toString().toLowerCase();
    final val = int.tryParse('${p['discount_value'] ?? 0}') ?? 0;
    final code = (p['voucher_code'] ?? '').toString().trim();
    final redeemable = _isRedeemablePromo(p);
    final discLine = type == 'percent'
        ? 'Diskon $val%'
        : type == 'info'
            ? 'Info promo'
            : 'Diskon ${_money.format(val)}';
    final until = (p['valid_until'] ?? '').toString();
    final blockReason = type == 'info'
        ? 'Info saja — tidak bisa dipakai sebagai diskon'
        : code.isEmpty
            ? 'Belum ada kode voucher — lengkapi di CMS Admin'
            : null;
    return _ticketCard(
      accent: OptikMemberTokens.blueDeep,
      badge: 'DISKON',
      badgeSub: type == 'percent' ? '%' : (type == 'info' ? 'INFO' : 'Rp'),
      title: (p['title'] ?? 'Promo').toString(),
      lines: [
        discLine,
        if ((p['description'] ?? '').toString().isNotEmpty)
          p['description'].toString(),
        if (until.isNotEmpty) 'Berlaku s.d. $until',
        if (code.isNotEmpty) 'Kode: $code',
        if (blockReason != null) blockReason,
      ],
      selected: selected,
      enabled: redeemable,
      onTap: !redeemable
          ? null
          : () {
              setState(() {
                if (selected) {
                  _productPromo = null;
                } else {
                  _productPromo = p;
                }
              });
            },
    );
  }

  Widget _ticketCard({
    required Color accent,
    required String badge,
    required String badgeSub,
    required String title,
    required List<String> lines,
    required bool selected,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: OptikMemberTokens.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? OptikMemberTokens.blue
                    : OptikMemberTokens.lineSoft,
                width: selected ? 1.6 : 1,
              ),
              boxShadow: OptikMemberTokens.cardShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    color: accent.withValues(alpha: 0.12),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          badge,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            color: accent,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          badgeSub,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            color: accent.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 12,
                    child: CustomPaint(
                      painter: _TicketNotchPainter(
                        color: OptikMemberTokens.canvas,
                        line: OptikMemberTokens.lineSoft,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: OptikMemberTokens.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (final line in lines.where((e) => e.trim().isNotEmpty))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                  color: line == lines.last &&
                                          !enabled &&
                                          lines.length > 1
                                      ? OptikMemberTokens.warning
                                      : OptikMemberTokens.inkMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected
                            ? OptikMemberTokens.blue
                            : OptikMemberTokens.line,
                        size: 26,
                      ),
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

class _TicketNotchPainter extends CustomPainter {
  _TicketNotchPainter({required this.color, required this.line});

  final Color color;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(size.width / 2, 0), 6, fill);
    canvas.drawCircle(Offset(size.width / 2, size.height), 6, fill);
    canvas.drawLine(
      Offset(size.width / 2, 8),
      Offset(size.width / 2, size.height - 8),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
