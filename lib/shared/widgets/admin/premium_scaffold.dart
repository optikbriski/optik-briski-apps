import 'package:flutter/material.dart';
import '../../theme.dart';

/// White canvas with a quiet Frozen Lake atmosphere.
class PremiumScaffold extends StatelessWidget {
  const PremiumScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.drawer,
    this.endDrawer,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset,
    this.padding,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool extendBodyBehindAppBar;
  final bool? resizeToAvoidBottomInset;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.snow,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      drawer: drawer,
      endDrawer: endDrawer,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation:
          floatingActionButtonLocation ?? FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          const IgnorePointer(child: _PremiumBackdrop()),
          padding == null ? body : Padding(padding: padding!, child: body),
        ],
      ),
    );
  }
}

class _PremiumBackdrop extends StatelessWidget {
  const _PremiumBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: OptikAdminTokens.bgGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.9, -1.1),
                radius: 1.25,
                colors: [
                  OptikAdminTokens.ice.withOpacity(0.22),
                  OptikAdminTokens.ice.withOpacity(0.0),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.05, 1.2),
                radius: 1.1,
                colors: [
                  OptikAdminTokens.slate.withOpacity(0.04),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
