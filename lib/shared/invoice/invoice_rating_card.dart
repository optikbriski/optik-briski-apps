// ignore_for_file: deprecated_member_use
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Kartu rating bintang untuk kasir / pembuat (dipakai APK Member).
class InvoiceRatingCard extends StatefulWidget {
  const InvoiceRatingCard({
    super.key,
    required this.title,
    required this.nama,
    required this.existing,
    required this.onSubmit,
    this.dark = true,
  });

  final String title;
  final String? nama;
  final Map<String, dynamic>? existing;
  final Future<void> Function(int skor, String? komentar) onSubmit;
  final bool dark;

  @override
  State<InvoiceRatingCard> createState() => _InvoiceRatingCardState();
}

class _InvoiceRatingCardState extends State<InvoiceRatingCard> {
  int _skor = 5;
  final _komenCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _komenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nama = (widget.nama ?? '').trim();
    final done = widget.existing != null;
    final fg = widget.dark ? Colors.white : const Color(0xFF0F172A);
    final muted = widget.dark ? Colors.white54 : Colors.black54;
    final gold = const Color(0xFFE8C872);
    final teal = const Color(0xFF0F766E);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.dark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.dark ? Colors.white12 : Colors.black12,
        ),
        boxShadow: widget.dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            nama.isEmpty ? 'invoice_hub_nama_belum'.tr() : nama,
            style: TextStyle(
              color: nama.isEmpty ? Colors.orange.shade700 : muted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          if (done) ...[
            Row(
              children: List.generate(5, (i) {
                final s = (widget.existing!['skor'] as num?)?.toInt() ?? 0;
                return Icon(
                  i < s ? Icons.star_rounded : Icons.star_border_rounded,
                  color: gold,
                  size: 26,
                );
              }),
            ),
            if ((widget.existing!['komentar']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.existing!['komentar'].toString(),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
          ] else if (nama.isEmpty) ...[
            Text(
              'invoice_hub_rating_wait_assign'.tr(),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ] else ...[
            Row(
              children: List.generate(5, (i) {
                final n = i + 1;
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36),
                  onPressed: () => setState(() => _skor = n),
                  icon: Icon(
                    n <= _skor ? Icons.star_rounded : Icons.star_border_rounded,
                    color: gold,
                    size: 30,
                  ),
                );
              }),
            ),
            TextField(
              controller: _komenCtrl,
              style: TextStyle(color: fg, fontSize: 13),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'invoice_hub_rating_komen'.tr(),
                hintStyle: TextStyle(color: muted),
                filled: true,
                fillColor: widget.dark
                    ? Colors.white.withOpacity(0.04)
                    : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await widget.onSubmit(
                            _skor,
                            _komenCtrl.text.trim().isEmpty
                                ? null
                                : _komenCtrl.text.trim(),
                          );
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: widget.dark ? gold : teal,
                  foregroundColor:
                      widget.dark ? const Color(0xFF0F172A) : Colors.white,
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('invoice_hub_rating_submit'.tr()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
