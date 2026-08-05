import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../theme.dart';
import 'invoice_settings_service.dart';
import 'invoice_status_footer.dart';

/// Meta administratif + pelanggan untuk nota premium.
class InvoiceDocMeta {
  const InvoiceDocMeta({
    required this.noInvoice,
    required this.customerName,
    this.whatsapp,
    this.address,
    this.email,
    this.cashier,
    this.dateLabel,
    this.createdAtLabel,
    this.method,
    this.status = 'LUNAS',
    this.boardStatus,
  });

  final String noInvoice;
  final String customerName;
  final String? whatsapp;
  final String? address;
  final String? email;
  final String? cashier;
  final String? dateLabel;

  /// Waktu invoice dibuat (`sales.created_at`), format lokal presisi detik.
  final String? createdAtLabel;
  final String? method;

  /// Pembayaran: `LUNAS` atau `DP`.
  final String status;

  /// Status board: DP · PENDING · READY · CLEAR.
  final InvoiceFooterStatus? boardStatus;

  bool get isDp => status.toUpperCase() == 'DP';
}

/// Satu baris item nota (label sudah diformat caller).
class InvoiceDocLine {
  const InvoiceDocLine({
    required this.label,
    required this.amount,
    this.group,
  });

  final String label;
  final String amount;

  /// Grup tampilan: Frame / Lensa / Lainnya (opsional).
  final String? group;
}

/// Header / body / footer nota premium — satu sumber UI + PDF.
class InvoiceLayout {
  InvoiceLayout._();

  static const Color _ink = OptikAdminTokens.navy;
  static const Color _muted = OptikAdminTokens.slate;
  static const Color _soft = OptikAdminTokens.textSecondary;
  static const PdfColor _pdfInk = PdfColor.fromInt(0xFF000080);
  static const PdfColor _pdfMuted = PdfColor.fromInt(0xFF6D8196);
  static const PdfColor _pdfIce = PdfColor.fromInt(0xFFADD8E6);
  static const PdfColor _pdfLine = PdfColor.fromInt(0x4D6D8196);
  static const PdfColor _pdfWash = PdfColor.fromInt(0xFFF4FAFC);
  static const PdfColor _pdfSuccess = PdfColor.fromInt(0xFF3D8F7A);
  static const PdfColor _pdfWarning = PdfColor.fromInt(0xFF9A7B3C);
  static const PdfColor _pdfDanger = PdfColor.fromInt(0xFFA65D5D);
  static const PdfColor _pdfPending = PdfColor.fromInt(0xFFC4A35A);

  /// Format jam invoice dibuat dari `created_at` (bukan jam buka POS).
  static String? formatInvoiceCreatedAt(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw.toLocal();
    } else {
      dt = DateTime.tryParse(text)?.toLocal();
    }
    if (dt == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  static String boardLabel(InvoiceFooterStatus status) {
    switch (status) {
      case InvoiceFooterStatus.dp:
        return 'DP';
      case InvoiceFooterStatus.pending:
        return 'PENDING';
      case InvoiceFooterStatus.ready:
        return 'READY';
      case InvoiceFooterStatus.clear:
        return 'CLEAR';
    }
  }

  static Color boardColor(InvoiceFooterStatus status) {
    switch (status) {
      case InvoiceFooterStatus.dp:
        return OptikAdminTokens.warning;
      case InvoiceFooterStatus.pending:
        return OptikAdminTokens.trainingSoft;
      case InvoiceFooterStatus.ready:
        return OptikAdminTokens.navy;
      case InvoiceFooterStatus.clear:
        return OptikAdminTokens.success;
    }
  }

  static PdfColor boardColorPdf(InvoiceFooterStatus status) {
    switch (status) {
      case InvoiceFooterStatus.dp:
        return _pdfWarning;
      case InvoiceFooterStatus.pending:
        return _pdfPending;
      case InvoiceFooterStatus.ready:
        return _pdfInk;
      case InvoiceFooterStatus.clear:
        return _pdfSuccess;
    }
  }

  /// Normalisasi grup item dari tipe/nama produk.
  static String? groupOfProduct({String? tipe, String? nama}) {
    final t = (tipe ?? '').toLowerCase();
    final n = (nama ?? '').toLowerCase();
    if (t.contains('frame') || n.startsWith('frame')) return 'Frame';
    if (t.contains('lensa') ||
        n.contains('lensa') ||
        n.contains('progresif')) {
      return 'Lensa';
    }
    if (t.contains('lain') ||
        n.contains('hardcase') ||
        n.contains('softlens') ||
        n.contains('cairan') ||
        n.contains('microfiber') ||
        n.contains('kain')) {
      return 'Lainnya';
    }
    if (t.isNotEmpty) {
      return tipe!.trim()[0].toUpperCase() + tipe.trim().substring(1);
    }
    return null;
  }

  /// Label section kecil (PELANGGAN, RINCIAN ITEM, …).
  static Widget sectionLabel(String text, {TextAlign align = TextAlign.left}) {
    return Text(
      text.toUpperCase(),
      textAlign: align,
      style: const TextStyle(
        color: _muted,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.35,
        height: 1.1,
      ),
    );
  }

  /// Bingkai kertas nota (putih, bayangan lembut).
  static Widget paper({
    required Widget child,
    double? width,
    double? height,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(22, 20, 22, 18),
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14000080)),
        boxShadow: [
          BoxShadow(
            color: _ink.withOpacity(0.07),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: _ink.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  static Widget header(
    InvoiceSettings s, {
    Color titleColor = _ink,
    Color mutedColor = _muted,
    Color phoneColor = _ink,
    double logoHeightCenter = 48,
    double logoHeightLeft = 48,
  }) {
    final nameStyle = TextStyle(
      color: titleColor,
      fontWeight: FontWeight.w900,
      fontSize: (s.fontSizeHeader + 1).clamp(13, 30),
      letterSpacing: 1.5,
      height: 1.05,
    );
    final addrStyle = TextStyle(
      color: mutedColor,
      fontSize: 9,
      height: 1.45,
      fontWeight: FontWeight.w500,
    );
    final phoneStyle = TextStyle(
      color: phoneColor,
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.25,
    );

    final textAlign = s.isCenter ? TextAlign.center : TextAlign.left;
    final cross =
        s.isCenter ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final requested = s.isCenter ? logoHeightCenter : logoHeightLeft;
    final logoH =
        (requested > 0 ? requested : s.fontSizeHeader * 2.5).clamp(42.0, 58.0);

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: cross,
        children: [
          if (s.hasLogo) ...[
            SizedBox(
              height: logoH,
              width: logoH * 1.75,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  s.logoUrl,
                  height: logoH,
                  width: logoH * 1.75,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.broken_image_outlined,
                    color: mutedColor,
                    size: logoH * 0.7,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            s.shopName.toUpperCase(),
            style: nameStyle,
            textAlign: textAlign,
          ),
          const SizedBox(height: 8),
          Container(
            width: 44,
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  OptikAdminTokens.ice.withOpacity(0.35),
                  OptikAdminTokens.ice,
                  OptikAdminTokens.ice.withOpacity(0.35),
                ],
              ),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          if (s.address.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.address, style: addrStyle, textAlign: textAlign),
          ],
          const SizedBox(height: 4),
          Text('Telp  ${s.phone}', style: phoneStyle, textAlign: textAlign),
        ],
      ),
    );
  }

  static Widget doubleRule({
    Color thick = _ink,
    Color thin = OptikAdminTokens.lineStrong,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1.5, color: thick.withOpacity(0.85)),
          const SizedBox(height: 2.5),
          Container(height: 0.6, color: thin),
        ],
      ),
    );
  }

  static Widget hairline({Color color = OptikAdminTokens.lineStrong}) {
    return Container(height: 0.7, color: color);
  }

  static Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.42)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 8.2,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static Widget paymentChip(String status) {
    final isDp = status.toUpperCase() == 'DP';
    return _chip(
      isDp ? 'DP · SISA' : 'LUNAS',
      isDp ? OptikAdminTokens.warning : OptikAdminTokens.success,
    );
  }

  /// Alias lama.
  static Widget statusChip(String status) => paymentChip(status);

  static Widget boardChip(InvoiceFooterStatus status) {
    return _chip(boardLabel(status), boardColor(status));
  }

  /// Buang prefix "Alamat:" / "Email:" bila caller masih mengirimnya.
  static String _cleanField(String? raw, List<String> prefixes) {
    var t = (raw ?? '').trim();
    for (final p in prefixes) {
      final low = t.toLowerCase();
      final pref = p.toLowerCase();
      if (low.startsWith(pref)) {
        t = t.substring(p.length).trim();
        if (t.startsWith(':')) t = t.substring(1).trim();
      }
    }
    return t;
  }

  static Widget _metaFieldRow(
    String label,
    String value, {
    required double fontSize,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                color: _muted,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: _soft,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _metaFact(String text, {required double fontSize}) {
    return Text(
      text,
      style: TextStyle(
        color: _muted,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
  }

  static Widget metaBand(
    InvoiceDocMeta meta, {
    double fontSize = 12,
  }) {
    final f = fontSize.clamp(10.0, 18.0);
    final small = (f - 3).clamp(8.0, 13.0);
    final titleSize = (f - 0.5).clamp(11.0, 16.0);
    final wa = (meta.whatsapp ?? '').trim();
    final addr = _cleanField(meta.address, const ['Alamat', 'Address']);
    final email = _cleanField(meta.email, const ['Email']);
    final hasContact = wa.isNotEmpty || addr.isNotEmpty || email.isNotEmpty;
    final date = (meta.dateLabel ?? '').trim();
    final cashier = (meta.cashier ?? '').trim();
    final method = (meta.method ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      decoration: BoxDecoration(
        color: OptikAdminTokens.cardElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Baris atas sejajar: Pelanggan kiri ↔ Nota rata kanan
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionLabel('Pelanggan'),
                    const SizedBox(height: 4),
                    Text(
                      meta.customerName.toUpperCase(),
                      style: TextStyle(
                        color: _ink,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sectionLabel('Nota', align: TextAlign.right),
                    const SizedBox(height: 4),
                    Text(
                      meta.noInvoice,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: _ink,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.15,
                        height: 1.2,
                      ),
                    ),
                    if ((meta.createdAtLabel ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta.createdAtLabel!.trim(),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: _muted,
                          fontSize: small,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (hasContact) ...[
            const SizedBox(height: 9),
            if (wa.isNotEmpty) _metaFieldRow('WA', wa, fontSize: small),
            if (addr.isNotEmpty) _metaFieldRow('Alamat', addr, fontSize: small),
            if (email.isNotEmpty) _metaFieldRow('Email', email, fontSize: small),
          ],
          const SizedBox(height: 10),
          hairline(),
          const SizedBox(height: 9),
          // Meta transaksi + chip status di bawah metode
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (date.isNotEmpty) _metaFact(date, fontSize: small),
                    if (cashier.isNotEmpty)
                      _metaFact('Kasir $cashier', fontSize: small),
                    if (method.isNotEmpty) _metaFact(method, fontSize: small),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                alignment: WrapAlignment.end,
                children: [
                  paymentChip(meta.status),
                  if (meta.boardStatus != null) boardChip(meta.boardStatus!),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _groupRank = ['Frame', 'Lensa', 'Lainnya'];

  static List<InvoiceDocLine> _orderedLines(List<InvoiceDocLine> lines) {
    if (!lines.any((l) => (l.group ?? '').trim().isNotEmpty)) return lines;
    int rank(String? g) {
      final i = _groupRank.indexOf((g ?? '').trim());
      return i < 0 ? 50 : i;
    }
    final copy = List<InvoiceDocLine>.from(lines);
    copy.sort((a, b) => rank(a.group).compareTo(rank(b.group)));
    return copy;
  }

  static Widget itemsBlock(
    List<InvoiceDocLine> lines, {
    double fontSize = 12,
    String title = 'Rincian item',
  }) {
    final f = (fontSize - 1).clamp(9.0, 16.0);
    final ordered = _orderedLines(lines);
    final children = <Widget>[
      sectionLabel(title),
      const SizedBox(height: 8),
    ];

    String? lastGroup;
    for (final line in ordered) {
      final g = (line.group ?? '').trim();
      if (g.isNotEmpty && g != lastGroup) {
        if (lastGroup != null) children.add(const SizedBox(height: 4));
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 5, top: 2),
            child: Text(
              g.toUpperCase(),
              style: TextStyle(
                color: OptikAdminTokens.accentDeep,
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
              ),
            ),
          ),
        );
        lastGroup = g;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  line.label,
                  style: TextStyle(
                    color: _ink,
                    fontSize: f,
                    fontWeight: FontWeight.w600,
                    height: 1.28,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                line.amount,
                style: TextStyle(
                  color: _ink,
                  fontSize: f,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  static Widget totalsBlock({
    required double fontSize,
    required String totalFormatted,
    required String paidLabel,
    required String paidFormatted,
    required String remainingFormatted,
    required bool hasRemainingDebt,
    bool showQr = false,
    Widget? qrChild,
  }) {
    final f = fontSize.clamp(10.0, 18.0);
    final labelStyle = TextStyle(
      color: _muted,
      fontSize: (f - 2).clamp(8.0, 14.0),
      fontWeight: FontWeight.w500,
    );
    final valueStyle = TextStyle(
      color: _ink,
      fontSize: (f - 2).clamp(9.0, 14.0),
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget moneyRow(String label, String value, {TextStyle? vStyle}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            Expanded(child: Text(label, style: labelStyle)),
            Text(value, style: vStyle ?? valueStyle),
          ],
        ),
      );
    }

    final qr = showQr
        ? Column(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: OptikAdminTokens.ice.withOpacity(0.7),
                  ),
                ),
                child: qrChild ??
                    const Icon(Icons.qr_code_2, color: _ink, size: 48),
              ),
              const SizedBox(height: 4),
              const Text(
                'Scan invoice',
                style: TextStyle(
                  color: _muted,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          )
        : const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: OptikAdminTokens.cardElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showQr) ...[
            qr,
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                moneyRow(
                  'Total belanja',
                  totalFormatted,
                  vStyle: TextStyle(
                    color: _ink,
                    fontSize: f.clamp(11.0, 16.0),
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                moneyRow(paidLabel, paidFormatted),
                const SizedBox(height: 3),
                hairline(),
                const SizedBox(height: 4),
                moneyRow(
                  'Sisa piutang',
                  remainingFormatted,
                  vStyle: TextStyle(
                    color: hasRemainingDebt
                        ? OptikAdminTokens.danger
                        : OptikAdminTokens.success,
                    fontSize: (f - 1).clamp(10.0, 15.0),
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Dokumen UI lengkap (header → meta → items → extras → totals → footer).
  static Widget documentBody({
    required InvoiceSettings settings,
    required InvoiceDocMeta meta,
    required List<InvoiceDocLine> lines,
    required String totalFormatted,
    required String paidLabel,
    required String paidFormatted,
    required String remainingFormatted,
    required bool hasRemainingDebt,
    Widget? extras,
    Widget? qrChild,
    double logoHeight = 48,
    String itemsTitle = 'Rincian item',
    String? footerText,
  }) {
    final fBody = settings.fontSizeBody;
    final footerResolved = (footerText ?? settings.footerText).trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header(
          settings,
          logoHeightCenter: logoHeight,
          logoHeightLeft: logoHeight,
        ),
        const SizedBox(height: 14),
        doubleRule(),
        const SizedBox(height: 12),
        metaBand(meta, fontSize: fBody),
        const SizedBox(height: 14),
        itemsBlock(lines, fontSize: fBody, title: itemsTitle),
        if (extras != null) ...[
          const SizedBox(height: 10),
          extras,
        ],
        const SizedBox(height: 12),
        totalsBlock(
          fontSize: fBody,
          totalFormatted: totalFormatted,
          paidLabel: paidLabel,
          paidFormatted: paidFormatted,
          remainingFormatted: remainingFormatted,
          hasRemainingDebt: hasRemainingDebt,
          showQr: settings.showQrInvoice,
          qrChild: qrChild,
        ),
        const SizedBox(height: 14),
        footerTextWidget(footerResolved),
      ],
    );
  }

  static Widget footer(
    InvoiceSettings s, {
    Color color = _muted,
    TextAlign align = TextAlign.left,
  }) {
    return footerTextWidget(
      s.footerText,
      color: color,
      align: align,
    );
  }

  static Widget footerTextWidget(
    String text, {
    Color color = _muted,
    TextAlign align = TextAlign.left,
  }) {
    final t = text.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hairline(),
        const SizedBox(height: 10),
        Text(
          t,
          textAlign: align,
          style: TextStyle(
            color: color,
            fontSize: 9.8,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  static pw.Widget headerPdf(
    InvoiceSettings s, {
    pw.ImageProvider? logoImage,
    PdfColor titleColor = _pdfInk,
    PdfColor mutedColor = _pdfMuted,
  }) {
    final nameStyle = pw.TextStyle(
      color: titleColor,
      fontWeight: pw.FontWeight.bold,
      fontSize: s.fontSizeHeader.clamp(11, 26),
      letterSpacing: 1.15,
    );
    final small =
        pw.TextStyle(color: mutedColor, fontSize: 8.5, lineSpacing: 1.35);
    final titleAlign = s.isCenter ? pw.TextAlign.center : pw.TextAlign.left;
    final cross = s.isCenter
        ? pw.CrossAxisAlignment.center
        : pw.CrossAxisAlignment.start;

    return pw.SizedBox(
      width: double.infinity,
      child: pw.Column(
        crossAxisAlignment: cross,
        children: [
          if (logoImage != null) ...[
            pw.SizedBox(
              width: 76,
              height: 50,
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(height: 9),
          ],
          pw.Text(
            s.shopName.toUpperCase(),
            style: nameStyle,
            textAlign: titleAlign,
          ),
          pw.SizedBox(height: 6),
          pw.Container(width: 40, height: 2.4, color: _pdfIce),
          if (s.address.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(s.address, style: small, textAlign: titleAlign),
          ],
          pw.SizedBox(height: 3),
          pw.Text(
            'Telp  ${s.phone}',
            style: pw.TextStyle(
              color: titleColor,
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: titleAlign,
          ),
        ],
      ),
    );
  }

  static pw.Widget doubleRulePdf({
    PdfColor thick = _pdfInk,
    PdfColor thin = _pdfLine,
  }) {
    return pw.Column(
      children: [
        pw.Container(height: 1.35, color: thick),
        pw.SizedBox(height: 2.2),
        pw.Container(height: 0.55, color: thin),
      ],
    );
  }

  static pw.Widget _chipPdf(String label, PdfColor color, PdfColor wash) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: pw.BoxDecoration(
        color: wash,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: color, width: 0.65),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          color: color,
          fontWeight: pw.FontWeight.bold,
          fontSize: 7.5,
          letterSpacing: 0.35,
        ),
      ),
    );
  }

  static pw.Widget paymentChipPdf(String status) {
    final isDp = status.toUpperCase() == 'DP';
    return _chipPdf(
      isDp ? 'DP · SISA' : 'LUNAS',
      isDp ? _pdfWarning : _pdfSuccess,
      isDp
          ? const PdfColor.fromInt(0x1A9A7B3C)
          : const PdfColor.fromInt(0x1A3D8F7A),
    );
  }

  static pw.Widget statusChipPdf(String status) => paymentChipPdf(status);

  static pw.Widget boardChipPdf(InvoiceFooterStatus status) {
    final c = boardColorPdf(status);
    return _chipPdf(
      boardLabel(status),
      c,
      PdfColor(c.red, c.green, c.blue, 0.12),
    );
  }

  static pw.Widget _metaFieldRowPdf(
    String label,
    String value, {
    required double fontSize,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 44,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                color: _pdfMuted,
                fontSize: fontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(color: _pdfMuted, fontSize: fontSize),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget metaBandPdf(
    InvoiceDocMeta meta, {
    double fontSize = 12,
  }) {
    final small = (fontSize - 3).clamp(7.5, 11.5);
    final titleSize = (fontSize - 0.5).clamp(9.0, 14.0);
    final wa = (meta.whatsapp ?? '').trim();
    final addr = _cleanField(meta.address, const ['Alamat', 'Address']);
    final email = _cleanField(meta.email, const ['Email']);
    final hasContact = wa.isNotEmpty || addr.isNotEmpty || email.isNotEmpty;
    final date = (meta.dateLabel ?? '').trim();
    final cashier = (meta.cashier ?? '').trim();
    final method = (meta.method ?? '').trim();

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: pw.BoxDecoration(
        color: _pdfWash,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _pdfIce, width: 0.65),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'PELANGGAN',
                      style: pw.TextStyle(
                        color: _pdfMuted,
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.05,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      meta.customerName.toUpperCase(),
                      style: pw.TextStyle(
                        color: _pdfInk,
                        fontSize: titleSize,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.SizedBox(
                      width: double.infinity,
                      child: pw.Text(
                        'NOTA',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          color: _pdfMuted,
                          fontSize: 7.5,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.05,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.SizedBox(
                      width: double.infinity,
                      child: pw.Text(
                        meta.noInvoice,
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          color: _pdfInk,
                          fontSize: titleSize,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    if ((meta.createdAtLabel ?? '').trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.SizedBox(
                        width: double.infinity,
                        child: pw.Text(
                          meta.createdAtLabel!.trim(),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            color: _pdfMuted,
                            fontSize: small,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (hasContact) ...[
            pw.SizedBox(height: 7),
            if (wa.isNotEmpty)
              _metaFieldRowPdf('WA', wa, fontSize: small),
            if (addr.isNotEmpty)
              _metaFieldRowPdf('Alamat', addr, fontSize: small),
            if (email.isNotEmpty)
              _metaFieldRowPdf('Email', email, fontSize: small),
          ],
          pw.SizedBox(height: 8),
          pw.Container(height: 0.55, color: _pdfLine),
          pw.SizedBox(height: 7),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Wrap(
                  spacing: 10,
                  runSpacing: 3,
                  children: [
                    if (date.isNotEmpty)
                      pw.Text(date,
                          style: pw.TextStyle(
                              color: _pdfMuted,
                              fontSize: small,
                              fontWeight: pw.FontWeight.bold)),
                    if (cashier.isNotEmpty)
                      pw.Text('Kasir $cashier',
                          style: pw.TextStyle(
                              color: _pdfMuted,
                              fontSize: small,
                              fontWeight: pw.FontWeight.bold)),
                    if (method.isNotEmpty)
                      pw.Text(method,
                          style: pw.TextStyle(
                              color: _pdfMuted,
                              fontSize: small,
                              fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  paymentChipPdf(meta.status),
                  if (meta.boardStatus != null) ...[
                    pw.SizedBox(width: 4),
                    boardChipPdf(meta.boardStatus!),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget itemsBlockPdf(
    List<InvoiceDocLine> lines, {
    double fontSize = 12,
    String title = 'RINCIAN ITEM',
  }) {
    final f = (fontSize - 1).clamp(8.5, 14.0);
    final ordered = _orderedLines(lines);
    final children = <pw.Widget>[
      pw.Text(
        title.toUpperCase(),
        style: pw.TextStyle(
          color: _pdfMuted,
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
      pw.SizedBox(height: 6),
    ];

    String? lastGroup;
    for (final line in ordered) {
      final g = (line.group ?? '').trim();
      if (g.isNotEmpty && g != lastGroup) {
        if (lastGroup != null) children.add(pw.SizedBox(height: 3));
        children.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3, top: 1),
            child: pw.Text(
              g.toUpperCase(),
              style: pw.TextStyle(
                color: _pdfIce,
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.7,
              ),
            ),
          ),
        );
        lastGroup = g;
      }
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  line.label,
                  style: pw.TextStyle(
                    color: _pdfInk,
                    fontSize: f,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Text(
                line.amount,
                style: pw.TextStyle(
                  color: _pdfInk,
                  fontSize: f,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  static pw.Widget totalsBlockPdf({
    required double fontSize,
    required String totalFormatted,
    required String paidLabel,
    required String paidFormatted,
    required String remainingFormatted,
    required bool hasRemainingDebt,
    pw.Widget? qrChild,
  }) {
    final f = fontSize.clamp(9.0, 16.0);
    pw.Widget row(String label, String value,
        {PdfColor? valueColor, double? size, bool bold = true}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  color: _pdfMuted,
                  fontSize: (f - 2).clamp(7.5, 12),
                ),
              ),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: valueColor ?? _pdfInk,
                fontSize: size ?? (f - 2).clamp(8, 12),
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: pw.BoxDecoration(
        color: _pdfWash,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _pdfIce, width: 0.7),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (qrChild != null) ...[
            pw.Column(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _pdfIce, width: 0.7),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: qrChild,
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Scan invoice',
                  style: pw.TextStyle(
                    color: _pdfMuted,
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              children: [
                row(
                  'Total belanja',
                  totalFormatted,
                  size: f.clamp(10, 14),
                ),
                row(paidLabel, paidFormatted),
                pw.SizedBox(height: 3),
                pw.Container(height: 0.55, color: _pdfLine),
                pw.SizedBox(height: 3),
                row(
                  'Sisa piutang',
                  remainingFormatted,
                  valueColor: hasRemainingDebt ? _pdfDanger : _pdfSuccess,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget documentBodyPdf({
    required InvoiceSettings settings,
    required InvoiceDocMeta meta,
    required List<InvoiceDocLine> lines,
    required String totalFormatted,
    required String paidLabel,
    required String paidFormatted,
    required String remainingFormatted,
    required bool hasRemainingDebt,
    pw.ImageProvider? logoImage,
    pw.Widget? extras,
    pw.Widget? qrChild,
    String itemsTitle = 'RINCIAN ITEM',
    String? footerText,
  }) {
    final fBody = settings.fontSizeBody;
    final footerResolved = (footerText ?? settings.footerText).trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        headerPdf(settings, logoImage: logoImage),
        pw.SizedBox(height: 11),
        doubleRulePdf(),
        pw.SizedBox(height: 10),
        metaBandPdf(meta, fontSize: fBody),
        pw.SizedBox(height: 11),
        itemsBlockPdf(lines, fontSize: fBody, title: itemsTitle),
        if (extras != null) ...[
          pw.SizedBox(height: 7),
          extras,
        ],
        pw.SizedBox(height: 9),
        totalsBlockPdf(
          fontSize: fBody,
          totalFormatted: totalFormatted,
          paidLabel: paidLabel,
          paidFormatted: paidFormatted,
          remainingFormatted: remainingFormatted,
          hasRemainingDebt: hasRemainingDebt,
          qrChild: settings.showQrInvoice ? qrChild : null,
        ),
        pw.SizedBox(height: 11),
        footerPdfText(footerResolved),
      ],
    );
  }

  static pw.Widget footerPdf(
    InvoiceSettings s, {
    PdfColor color = _pdfMuted,
  }) {
    return footerPdfText(s.footerText, color: color);
  }

  static pw.Widget footerPdfText(
    String text, {
    PdfColor color = _pdfMuted,
  }) {
    final t = text.trim();
    if (t.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 0.6, color: _pdfLine),
        pw.SizedBox(height: 8),
        pw.Text(
          t,
          textAlign: pw.TextAlign.left,
          style: pw.TextStyle(
            color: color,
            fontSize: 9,
            lineSpacing: 1.45,
          ),
        ),
      ],
    );
  }
}
