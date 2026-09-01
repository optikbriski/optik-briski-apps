import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:another_flutter_usb_write/another_flutter_usb_write.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('flutter_usb_write/methods');
  const events = EventChannel('flutter_usb_write/events');

  late FlutterUsbWrite flutterUsbWrite;
  late UsbDevice device;

  setUp(() {
    device = UsbDevice(
      1046,
      20497,
      'USB Portable Printer    ',
      'STMicroelectronics',
      1002,
      'Printer',
      deviceClass: 7,
      hasPermission: true,
    );
    flutterUsbWrite = FlutterUsbWrite.private(methods, events);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, null);
  });

  group('List devices', () {
    test('listDevices parses native List', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'listDevices') {
          return [device.toJson()];
        }
        return null;
      });
      final result = await flutterUsbWrite.listDevices();
      expect(result.length, 1);
      expect(result.first.toJson(), device.toJson());
    });

    test('listDevices empty when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'listDevices') return null;
        return null;
      });
      final result = await flutterUsbWrite.listDevices();
      expect(result, isEmpty);
    });

    test('listDevices throws ListDevicesException for non-List', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'listDevices') return 'bad';
        return null;
      });
      expect(
        flutterUsbWrite.listDevices(),
        throwsA(isA<ListDevicesException>()),
      );
    });
  });

  group('Open device', () {
    test('open by deviceId', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'open') {
          expect(call.arguments['deviceId'], device.deviceId);
          return device.toJson();
        }
        return null;
      });
      final result = await flutterUsbWrite.open(deviceId: device.deviceId);
      expect(result.toJson(), device.toJson());
    });

    test('open by vid:pid', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'open') {
          expect(call.arguments['vid'], device.vid);
          expect(call.arguments['pid'], device.pid);
          return device.toJson();
        }
        return null;
      });
      final result =
          await flutterUsbWrite.open(vendorId: device.vid, productId: device.pid);
      expect(result.toJson(), device.toJson());
    });
  });

  group('Close device', () {
    test('close', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'close') return true;
        return null;
      });
      final result = await flutterUsbWrite.close();
      expect(result, true);
    });
  });

  group('Write', () {
    test('write', () async {
      final bytes = ascii.encode('Hello world');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'write') {
          expect(call.arguments['bytes'], bytes);
          return true;
        }
        return null;
      });
      final result = await flutterUsbWrite.write(bytes);
      expect(result, true);
    });
  });

  group('controlTransfer', () {
    test('controlTransfer', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'controlTransfer') return 0;
        return null;
      });
      final result =
          await flutterUsbWrite.controlTransfer(161, 1, 0, 0, null, 0, 0);
      expect(result, 0);
    });
  });
}
