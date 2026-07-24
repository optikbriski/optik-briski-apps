import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/karyawan/karyawan_jabatan.dart';
import '../../shared/qr/obr_codes.dart';

/// Kode TOTP unik per karyawan untuk login web Admin (berganti tiap 10 dtk).
class AdminLoginCodePage extends StatefulWidget {
  const AdminLoginCodePage({super.key});

  @override
  State<AdminLoginCodePage> createState() => _AdminLoginCodePageState();
}

class _AdminLoginCodePageState extends State<AdminLoginCodePage>
    with TickerProviderStateMixin {
  static const _bgDeep = Color(0xFF070B14);
  static const _accent = Color(0xFF2DD4BF);
  static const _accentWarm = Color(0xFFFBBF24);
  static const _card = Color(0xFF1E293B);

  String? _code;
  String? _karyawanId;
  String? _nama;
  String? _tokoId;
  String? _jabatan;
  int _expiresIn = 0;
  int _period = 10;
  String? _error;
  bool _loading = true;
  bool _copied = false;
  Timer? _tick;
  late final AnimationController _pulse;

  String? get _karyawanQrPayload {
    final id = (_karyawanId ?? '').trim();
    final nama = (_nama ?? '').trim();
    if (id.isEmpty || nama.isEmpty) return null;
    final payload = ObrKaryawan.encode(
      karyawanId: id,
      nama: nama,
      tokoId: _tokoId,
    );
    return payload.isEmpty ? null : payload;
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _refresh();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final res = await Supabase.instance.client.rpc('get_admin_login_code');
      Map<String, dynamic>? map;
      if (res is Map<String, dynamic>) {
        map = res;
      } else if (res is Map) {
        map = Map<String, dynamic>.from(res);
      }
      if (map == null) {
        throw 'Respons kode tidak valid.';
      }
      if (!mounted) return;
      setState(() {
        _code = (map!['code'] ?? '').toString();
        _karyawanId = (map['karyawan_id'] ?? '').toString();
        _nama = (map['nama'] ?? '').toString();
        _tokoId = (map['toko_id'] ?? '').toString();
        _jabatan = (map['jabatan'] ?? '').toString();
        _expiresIn = (map['expires_in'] as num?)?.toInt() ?? 0;
        _period = (map['period'] as num?)?.toInt() ?? 10;
        _error = null;
        _loading = false;
        _copied = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _onTick() {
    if (_error != null) return;
    if (_expiresIn <= 1) {
      _refresh();
      return;
    }
    setState(() => _expiresIn -= 1);
  }

  Future<void> _copy() async {
    final code = _code;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: _accent, size: 20),
            SizedBox(width: 10),
            Text('Kode disalin — siap tempel di web Admin'),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String get _roleLabel {
    final j = (_jabatan ?? '').trim();
    if (j.isNotEmpty) return j;
    return 'Akses Admin';
  }

  String get _prefixHint {
    final p = KaryawanJabatan.loginCodePrefix(_jabatan);
    if (p == null) return 'Digit depan = posisi';
    return 'Prefix $p · $_roleLabel';
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        _period <= 0 ? 0.0 : (_expiresIn.clamp(0, _period) / _period);
    final urgent = _expiresIn <= 3;

    return Scaffold(
      backgroundColor: _bgDeep,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'Kode Login Admin',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    _refresh();
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          const _AtmosphereBackground(),
          SafeArea(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _accent),
                  )
                : _error != null
                    ? _errorView()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _identityHeader(),
                            const SizedBox(height: 22),
                            _codeVaultCard(
                              progress: progress,
                              urgent: urgent,
                            ),
                            const SizedBox(height: 18),
                            _legendChip(),
                            const SizedBox(height: 22),
                            _copyButton(),
                            const SizedBox(height: 18),
                            _identityQrCard(),
                            const SizedBox(height: 12),
                            Text(
                              'Kode berganti tiap $_period detik. '
                              'Jangan bagikan kecuali Anda sedang login web Admin.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.42),
                                fontSize: 12,
                                height: 1.4,
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

  Widget _identityQrCard() {
    final payload = _karyawanQrPayload;
    if (payload == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        color: Colors.white.withOpacity(0.04),
      ),
      child: Column(
        children: [
          const Text(
            'QR Identitas (otorisasi stok)',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Scan QR ini di web Admin saat revisi / write-off stok. '
            'Harus sama dengan akun via login.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: payload,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0F172A),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            (_nama ?? '').trim(),
            style: const TextStyle(
              color: _accent,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityHeader() {
    final nama = (_nama ?? '').trim();
    final toko = (_tokoId ?? '').trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.02),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF14B8A6), Color(0xFF0F766E)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nama.isEmpty ? 'Akses terverifikasi' : nama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        _roleLabel,
                        if (toko.isNotEmpty) toko,
                      ].join(' · '),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: _accent.withOpacity(0.12),
                  border: Border.all(color: _accent.withOpacity(0.35)),
                ),
                child: Text(
                  'LIVE',
                  style: TextStyle(
                    color: _accent.withOpacity(0.95),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeVaultCard({required double progress, required bool urgent}) {
    final digits = (_code ?? '------').padRight(6).substring(0, 6).split('');

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.18 + (_pulse.value * 0.12);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: (urgent ? _accentWarm : _accent).withOpacity(glow),
                blurRadius: 36,
                spreadRadius: 0,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 1.2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1E293B).withOpacity(0.92),
                  const Color(0xFF0F172A).withOpacity(0.96),
                  const Color(0xFF134E4A).withOpacity(0.55),
                ],
              ),
            ),
            child: Column(
              children: [
                Text(
                  'ONE-TIME ACCESS',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _prefixHint,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    for (var i = 0; i < 6; i++) ...[
                      if (i > 0) const SizedBox(width: 7),
                      Expanded(
                        child: _DigitTile(
                          digit: digits[i],
                          isPrefix: i == 0,
                          codeKey: _code ?? '',
                          urgent: urgent,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CustomPaint(
                    painter: _CountdownRingPainter(
                      progress: progress,
                      urgent: urgent,
                      trackColor: Colors.white.withOpacity(0.08),
                      activeColor: urgent ? _accentWarm : _accent,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_expiresIn',
                            style: TextStyle(
                              color: urgent ? _accentWarm : Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'detik',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  urgent ? 'Segera ganti…' : 'Berlaku sampai countdown habis',
                  style: TextStyle(
                    color: urgent
                        ? _accentWarm.withOpacity(0.9)
                        : Colors.white.withOpacity(0.5),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legendChip() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: const [
        _LegendPill(digit: '1', label: 'Owner'),
        _LegendPill(digit: '2', label: 'Admin'),
        _LegendPill(digit: '3', label: 'Kepala Area'),
        _LegendPill(digit: '4', label: 'Kepala Toko'),
      ],
    );
  }

  Widget _copyButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _copy,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: _copied
                    ? const [Color(0xFF0D9488), Color(0xFF115E59)]
                    : const [Color(0xFF2DD4BF), Color(0xFF0F766E)],
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _copied ? Icons.done_rounded : Icons.copy_all_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _copied ? 'Tersalin' : 'Salin kode',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      letterSpacing: 0.2,
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

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: _card.withOpacity(0.9),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.35)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.lock_person_rounded,
                  color: Colors.orangeAccent.withOpacity(0.95),
                  size: 52,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _bgDeep,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _refresh();
                  },
                  child: const Text(
                    'Coba lagi',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _AtmosphereBackground extends StatelessWidget {
  const _AtmosphereBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF070B14),
            Color(0xFF0F172A),
            Color(0xFF0B2E2A),
            Color(0xFF070B14),
          ],
          stops: [0.0, 0.35, 0.72, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -40,
            child: _GlowBlob(color: Color(0x332DD4BF), size: 220),
          ),
          Positioned(
            bottom: 80,
            left: -60,
            child: _GlowBlob(color: Color(0x22FBBF24), size: 200),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _DigitTile extends StatelessWidget {
  const _DigitTile({
    required this.digit,
    required this.isPrefix,
    required this.codeKey,
    required this.urgent,
  });

  final String digit;
  final bool isPrefix;
  final String codeKey;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final border = isPrefix
        ? (urgent ? const Color(0xFFFBBF24) : const Color(0xFF2DD4BF))
        : Colors.white.withOpacity(0.12);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, anim) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey('$codeKey-$digit-$isPrefix'),
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: isPrefix ? 1.6 : 1),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isPrefix
                ? [
                    const Color(0xFF134E4A).withOpacity(0.95),
                    const Color(0xFF0F172A).withOpacity(0.98),
                  ]
                : [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.04),
                  ],
          ),
          boxShadow: isPrefix
              ? [
                  BoxShadow(
                    color: (urgent
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFF2DD4BF))
                        .withOpacity(0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          digit,
          style: TextStyle(
            color: isPrefix
                ? (urgent ? const Color(0xFFFBBF24) : const Color(0xFF5EEAD4))
                : Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({required this.digit, required this.label});

  final String digit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: const Color(0xFF2DD4BF).withOpacity(0.18),
            ),
            child: Text(
              digit,
              style: const TextStyle(
                color: Color(0xFF5EEAD4),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({
    required this.progress,
    required this.urgent,
    required this.trackColor,
    required this.activeColor,
  });

  final double progress;
  final bool urgent;
  final Color trackColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 5;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        colors: [
          activeColor.withOpacity(0.35),
          activeColor,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.urgent != urgent ||
        oldDelegate.activeColor != activeColor;
  }
}
