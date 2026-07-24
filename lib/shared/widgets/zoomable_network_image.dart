import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Thumbnail / pane foto dengan pinch-zoom, scroll wheel, dan buka layar penuh.
class ZoomableNetworkImagePane extends StatelessWidget {
  const ZoomableNetworkImagePane({
    super.key,
    required this.url,
    this.aspectRatio = 3 / 4,
    this.borderRadius = 12,
  });

  final String url;
  final double aspectRatio;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: url.trim().isEmpty
            ? Container(
                color: OptikAdminTokens.bgMid,
                alignment: Alignment.center,
                child: const Text(
                  'Foto tidak tersedia',
                  style: TextStyle(color: Colors.white38),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: OptikAdminTokens.bgMid,
                    child: _ZoomableImage(
                      url: url,
                      fit: BoxFit.contain,
                      minScale: 1,
                      maxScale: 6,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => showZoomableImageDialog(context, url),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Perbesar',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

void showZoomableImageDialog(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.92),
    builder: (_) => _ZoomableImageDialog(url: url),
  );
}

class _ZoomableImageDialog extends StatefulWidget {
  const _ZoomableImageDialog({required this.url});

  final String url;

  @override
  State<_ZoomableImageDialog> createState() => _ZoomableImageDialogState();
}

class _ZoomableImageDialogState extends State<_ZoomableImageDialog> {
  final _controller = TransformationController();
  static const _min = 0.8;
  static const _max = 8.0;
  double _scale = 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncScale() {
    final s = _controller.value.getMaxScaleOnAxis();
    if ((s - _scale).abs() < 0.01) return;
    setState(() => _scale = s);
  }

  void _setScale(double next) {
    final clamped = next.clamp(_min, _max);
    final size = MediaQuery.sizeOf(context);
    final focal = Offset(size.width / 2, size.height / 2);
    final scene = _controller.toScene(focal);
    _controller.value = Matrix4.identity()
      ..translate(focal.dx, focal.dy)
      ..scale(clamped)
      ..translate(-scene.dx, -scene.dy);
    setState(() => _scale = clamped);
  }

  void _zoomBy(double factor) => _setScale(_scale * factor);

  void _reset() {
    _controller.value = Matrix4.identity();
    setState(() => _scale = 1);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: _ZoomableImage(
              url: widget.url,
              fit: BoxFit.contain,
              minScale: _min,
              maxScale: _max,
              controller: _controller,
              onScaleChanged: (_) => _syncScale(),
              sizedBox: Size(size.width, size.height),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const Spacer(),
                  _ZoomChip(
                    icon: Icons.remove_rounded,
                    tooltip: 'Perkecil',
                    onPressed: () => _zoomBy(1 / 1.25),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${(_scale * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ZoomChip(
                    icon: Icons.add_rounded,
                    tooltip: 'Perbesar',
                    onPressed: () => _zoomBy(1.25),
                  ),
                  const SizedBox(width: 8),
                  _ZoomChip(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Reset',
                    onPressed: _reset,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: IgnorePointer(
              child: Text(
                kIsWeb
                    ? 'Scroll untuk zoom · drag untuk geser'
                    : 'Pinch untuk zoom · drag untuk geser',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white12,
        foregroundColor: Colors.white,
      ),
      icon: Icon(icon),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.url,
    required this.fit,
    required this.minScale,
    required this.maxScale,
    this.controller,
    this.onScaleChanged,
    this.sizedBox,
  });

  final String url;
  final BoxFit fit;
  final double minScale;
  final double maxScale;
  final TransformationController? controller;
  final ValueChanged<double>? onScaleChanged;
  final Size? sizedBox;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  TransformationController? _owned;
  TransformationController get _ctrl => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _owned = TransformationController();
    }
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  void _emitScale() {
    widget.onScaleChanged?.call(_ctrl.value.getMaxScaleOnAxis());
  }

  void _onScrollZoom(PointerScrollEvent event) {
    final current = _ctrl.value.getMaxScaleOnAxis();
    if (current <= 0) return;
    final factor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
    final next = (current * factor).clamp(widget.minScale, widget.maxScale);
    final focal = event.localPosition;
    final scene = _ctrl.toScene(focal);
    _ctrl.value = Matrix4.identity()
      ..translate(focal.dx, focal.dy)
      ..scale(next)
      ..translate(-scene.dx, -scene.dy);
    _emitScale();
  }

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      widget.url,
      fit: widget.fit,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, color: Colors.white38, size: 40),
      ),
    );

    final viewer = InteractiveViewer(
      transformationController: _ctrl,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      clipBehavior: Clip.hardEdge,
      boundaryMargin: const EdgeInsets.all(80),
      onInteractionUpdate: (_) => _emitScale(),
      child: widget.sizedBox == null
          ? SizedBox.expand(child: image)
          : SizedBox(
              width: widget.sizedBox!.width,
              height: widget.sizedBox!.height,
              child: image,
            ),
    );

    return Listener(
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) _onScrollZoom(signal);
      },
      child: viewer,
    );
  }
}
