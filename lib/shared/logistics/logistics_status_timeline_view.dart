import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme.dart';
import 'logistics_status_timeline.dart';

/// Timeline vertikal: status terbaru di atas, hijau = langkah aktif.
class LogisticsStatusTimelineView extends StatelessWidget {
  LogisticsStatusTimelineView({
    super.key,
    required this.resi,
    required this.subtitle,
    required this.nodes,
    this.trailing,
  });

  final String resi;
  final String subtitle;
  final List<LogisticsTimelineNode> nodes;
  final Widget? trailing;

  final _when = DateFormat('dd MMM yyyy • HH:mm', 'id_ID');

  static const _green = Color(0xFF00AA5B);
  static const _titleGrey = Color(0xFF3D3D3D);
  static const _bodyGrey = Color(0xFF6B6B6B);
  static const _timeGrey = Color(0xFF9A9A9A);
  static const _line = Color(0xFFE4E4E4);

  String _fmt(DateTime t) => '${_when.format(t.toLocal())} WIB';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                resi,
                style: const TextStyle(
                  color: OptikAdminTokens.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.2,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Salin nomor',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: resi));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nomor disalin.')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        Text(
          subtitle,
          style: const TextStyle(
            color: _bodyGrey,
            fontSize: 13.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < nodes.length; i++)
          _node(nodes[i], last: i == nodes.length - 1),
        const SizedBox(height: 8),
        const Text(
          'Waktu ditampilkan dalam zona waktu lokal',
          style: TextStyle(color: _timeGrey, fontSize: 11),
        ),
      ],
    );
  }

  Widget _node(LogisticsTimelineNode n, {required bool last}) {
    final active = n.current;
    final titleColor = active ? _green : _titleGrey;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? _green : const Color(0xFFC8C8C8),
                  ),
                ),
                if (!last)
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Center(
                        child: SizedBox(
                          width: 2,
                          child: ColoredBox(color: _line),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (n.detail != null && n.detail!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      n.detail!,
                      style: const TextStyle(
                        color: _bodyGrey,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (n.at != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _fmt(n.at!),
                      style: const TextStyle(
                        color: _timeGrey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (n.photoUrl != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        n.photoUrl!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Gambar dari kurir / toko',
                      style: TextStyle(color: _timeGrey, fontSize: 11),
                    ),
                  ],
                  for (final c in n.children) _child(c),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _child(LogisticsTimelineLine c) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.title,
            style: const TextStyle(
              color: _titleGrey,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (c.detail != null && c.detail!.isNotEmpty)
            Text(
              c.detail!,
              style: const TextStyle(color: _bodyGrey, fontSize: 12.5),
            ),
          if (c.at != null)
            Text(
              _fmt(c.at!),
              style: const TextStyle(color: _timeGrey, fontSize: 11.5),
            ),
        ],
      ),
    );
  }
}
