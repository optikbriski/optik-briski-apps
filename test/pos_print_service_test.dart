import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/invoice/invoice_document_builder.dart';
import 'package:optik_b_riski/shared/invoice/invoice_layout.dart';
import 'package:optik_b_riski/shared/invoice/invoice_settings_service.dart';
import 'package:optik_b_riski/shared/invoice/invoice_status_footer.dart';
import 'package:optik_b_riski/shared/pos_print_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pickAndroidUsbDevice', () {
    const pos80 = (vid: 1048, pid: 20497, label: 'POS-80 USB');
    const hub = (vid: 1234, pid: 5678, label: 'USB2.0 Hub');

    test('prefers saved VID/PID when still attached', () {
      final picked = PosPrintService.pickAndroidUsbDevice(
        devices: [hub, pos80],
        savedVid: pos80.vid,
        savedPid: pos80.pid,
      );
      expect(picked?.vid, pos80.vid);
      expect(picked?.pid, pos80.pid);
    });

    test('auto-picks POS-80 VID/PID when no saved pref', () {
      final picked = PosPrintService.pickAndroidUsbDevice(
        devices: [hub, pos80],
      );
      expect(picked?.vid, pos80.vid);
      expect(picked?.pid, pos80.pid);
    });

    test('returns null when no devices', () {
      expect(
        PosPrintService.pickAndroidUsbDevice(devices: []),
        isNull,
      );
    });
  });

  group('needsAndroidUsbDevicePicker', () {
    const pos80 = (vid: 1048, pid: 20497, label: 'POS-80');
    const hub = (vid: 1, pid: 2, label: 'Hub');

    test('false for single device', () {
      expect(
        PosPrintService.needsAndroidUsbDevicePicker(
          devices: [pos80],
          savedVid: null,
          savedPid: null,
        ),
        isFalse,
      );
    });

    test('true for multiple without saved match', () {
      expect(
        PosPrintService.needsAndroidUsbDevicePicker(
          devices: [hub, pos80],
          savedVid: null,
          savedPid: null,
        ),
        isTrue,
      );
    });

    test('false for multiple when saved still attached', () {
      expect(
        PosPrintService.needsAndroidUsbDevicePicker(
          devices: [hub, pos80],
          savedVid: pos80.vid,
          savedPid: pos80.pid,
        ),
        isFalse,
      );
    });
  });

  group('buildEscPos', () {
    test('produces cut command and non-empty payload', () async {
      final doc = InvoiceDocumentModel(
        settings: const InvoiceSettings(
          tokoId: 'TEST',
          shopName: 'Optik B. Riski',
          address: 'Jl. Test',
          phone: '081234',
          logoUrl: '',
          statusFooters: InvoiceStatusFooters(
            dp: 'DP',
            pending: 'Pending',
            ready: 'Ready',
            clear: 'Clear',
          ),
          googleReviewUrl: '',
          headerAlignment: 'CENTER',
          fontSizeHeader: 14,
          fontSizeBody: 11,
          showQrInvoice: true,
        ),
        meta: const InvoiceDocMeta(
          noInvoice: 'INV-TEST-001',
          customerName: 'Pelanggan',
          status: 'LUNAS',
          boardStatus: InvoiceFooterStatus.clear,
        ),
        lines: const [
          InvoiceDocLine(label: 'Frame A', amount: 'Rp100.000'),
        ],
        footerText: 'Terima kasih',
        footerTextPdf: '',
        totalFormatted: 'Rp100.000',
        paidLabel: 'Dibayar',
        paidFormatted: 'Rp100.000',
        remainingFormatted: 'Rp0',
        hasRemainingDebt: false,
        totalHarga: 100000,
        dibayarkan: 100000,
        sisaTagihan: 0,
        hasLensa: false,
        detailResep: '',
        qrPayload: '',
        showQr: false,
      );

      final bytes = await PosPrintService.buildEscPos(doc, paper: PaperSize.mm80);
      expect(bytes, isNotEmpty);
      // ESC/POS partial cut (GS V)
      expect(bytes.contains(0x1D), isTrue);
      expect(bytes.contains(0x56), isTrue);
    });
  });
}
