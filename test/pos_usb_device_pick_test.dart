import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/print/pos_usb_device_pick.dart';
import 'package:optik_b_riski/shared/pos_print_service.dart';

void main() {
  group('PosUsbDevicePick', () {
    const pos80 = (
      vid: 1048,
      pid: 20497,
      label: 'POS-80 USB',
      deviceClass: 7,
      hasPermission: null,
    );
    const hub = (
      vid: 1234,
      pid: 5678,
      label: 'USB2.0 Hub',
      deviceClass: 9,
      hasPermission: null,
    );

    test('isLikelyHub detects class 9', () {
      expect(PosUsbDevicePick.isLikelyHub(9, 'Generic'), isTrue);
      expect(PosUsbDevicePick.isLikelyHub(7, 'POS-80'), isFalse);
    });

    test('pickPreferred skips hub when printer present', () {
      final picked = PosUsbDevicePick.pickPreferred(
        devices: [hub, pos80],
      );
      expect(picked?.vid, pos80.vid);
      expect(picked?.pid, pos80.pid);
    });

    test('pickPreferred uses saved printer not hub', () {
      final picked = PosUsbDevicePick.pickPreferred(
        devices: [hub, pos80],
        savedVid: pos80.vid,
        savedPid: pos80.pid,
      );
      expect(picked?.vid, pos80.vid);
    });

    test('needsManualPicker true for hub + printer without saved', () {
      expect(
        PosUsbDevicePick.needsManualPicker(
          devices: [hub, pos80],
          savedVid: null,
          savedPid: null,
        ),
        isTrue,
      );
      expect(
        PosUsbDevicePick.needsManualPicker(
          devices: [pos80],
          savedVid: null,
          savedPid: null,
        ),
        isFalse,
      );
    });

    test('known POS VID/PID detected', () {
      expect(PosUsbDevicePick.isKnownPosPrinter(1048, 20497), isTrue);
      expect(PosUsbDevicePick.isKnownPosPrinter(1, 2), isFalse);
    });
  });

  group('PosPrintService delegates to PosUsbDevicePick', () {
    const pos80 = (
      vid: 1048,
      pid: 20497,
      label: 'POS-80',
      deviceClass: 7,
      hasPermission: null,
    );
    const hub = (
      vid: 1,
      pid: 2,
      label: 'Hub',
      deviceClass: 9,
      hasPermission: null,
    );

    test('pickAndroidUsbDevice skips hub', () {
      final picked = PosPrintService.pickAndroidUsbDevice(
        devices: [hub, pos80],
      );
      expect(picked?.vid, 1048);
    });
  });
}
