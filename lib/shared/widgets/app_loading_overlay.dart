import 'package:flutter/material.dart';

/// Overlay loading animasi — logo brand berdenyut (breathe) saat proses lama.
class AppLoadingOverlay extends StatefulWidget {
  const AppLoadingOverlay({
    super.key,
    required this.visible,
    this.message = 'Memproses…',
    this.subtitle,
    this.barrierColor,
  });

  final bool visible;
  final String message;
  final String? subtitle;
  final Color? barrierColor;

  /// Bungkus halaman: tampilkan overlay di atas [child] saat [visible].
  static Widget gate({
    required bool visible,
    required Widget child,
    String message = 'Memproses…',
    String? subtitle,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        AppLoadingOverlay(
          visible: visible,
          message: message,
          subtitle: subtitle,
        ),
      ],
    );
  }

  @override
  State<AppLoadingOverlay> createState() => _AppLoadingOverlayState();
}

class _AppLoadingOverlayState extends State<AppLoadingOverlay>
    with SingleTickerProviderStateMixin {
  static const _logoAsset = 'assets/images/logo_briski.png';
  static const _accent = Color(0xFFC4A35A);

  late final AnimationController _breathe;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _scale = Tween<double>(begin: 0.94, end: 1.04).animate(
      CurvedAnimation(parent: _breathe, curve: Curves.easeInOut),
    );
    _fade = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _breathe, curve: Curves.easeInOut),
    );
    _glow = Tween<double>(begin: 0.18, end: 0.42).animate(
      CurvedAnimation(parent: _breathe, curve: Curves.easeInOut),
    );
    if (widget.visible) {
      _breathe.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant AppLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !_breathe.isAnimating) {
      _breathe.repeat(reverse: true);
    } else if (!widget.visible && _breathe.isAnimating) {
      _breathe.stop();
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: widget.visible
            ? Material(
                color: widget.barrierColor ??
                    const Color(0xFF0B1220).withOpacity(0.72),
                child: Center(
                  child: AnimatedBuilder(
                    animation: _breathe,
                    builder: (context, _) {
                      return Container(
                        width: 260,
                        padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _accent.withOpacity(0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.scale(
                              scale: _scale.value,
                              child: Opacity(
                                opacity: _fade.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _accent
                                            .withOpacity(_glow.value * 0.55),
                                        blurRadius: 22 + (_glow.value * 18),
                                        spreadRadius: 1,
                                      ),
                                      BoxShadow(
                                        color: Colors.white
                                            .withOpacity(_glow.value * 0.12),
                                        blurRadius: 14,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.asset(
                                      _logoAsset,
                                      width: 196,
                                      height: 72,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              widget.message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.subtitle ??
                                  'Mohon tunggu, jangan tutup aplikasi',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 11.5,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
