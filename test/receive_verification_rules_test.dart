import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/receive_verification_rules.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  group('siapa buka antrian terima', () {
    test('admin_toko boleh; owner/kasir tidak', () {
      expect(
        ReceiveVerificationRules.canOpenIncomingQueue(p('admin_toko', 'CABANG-A')),
        isTrue,
      );
      expect(
        ReceiveVerificationRules.canOpenIncomingQueue(p('admin_pusat', 'PUSAT')),
        isTrue,
      );
      expect(
        ReceiveVerificationRules.canOpenIncomingQueue(p('owner', 'PUSAT')),
        isFalse,
      );
      expect(
        ReceiveVerificationRules.canOpenIncomingQueue(p('kasir', 'CABANG-A')),
        isFalse,
      );
    });

    test('terima hanya tujuan + TRANSIT/PENDING', () {
      final cabang = p('admin_toko', 'CABANG-A');
      expect(
        ReceiveVerificationRules.canReceiveAtToko(cabang, 'CABANG-A', 'TRANSIT'),
        isTrue,
      );
      expect(
        ReceiveVerificationRules.canReceiveAtToko(cabang, 'CABANG-B', 'TRANSIT'),
        isFalse,
      );
      expect(
        ReceiveVerificationRules.canReceiveAtToko(cabang, 'CABANG-A', 'PREPARING'),
        isFalse,
      );
    });

    test('foto wajib; RO SUCCESS hanya setelah move SUCCESS', () {
      expect(ReceiveVerificationRules.photoRequiredForReceive, isTrue);
      expect(ReceiveVerificationRules.photoOk('https://x/foto.jpg'), isTrue);
      expect(ReceiveVerificationRules.photoOk(''), isFalse);
      expect(ReceiveVerificationRules.photoOk('-'), isFalse);
      expect(ReceiveVerificationRules.canCloseRoFromMove('SUCCESS'), isTrue);
      expect(ReceiveVerificationRules.canCloseRoFromMove('TRANSIT'), isFalse);
      expect(
        ReceiveVerificationRules.verifierIdOk('abc', 'abc'),
        isTrue,
      );
      expect(
        ReceiveVerificationRules.verifierIdOk('orang-lain', 'abc'),
        isFalse,
      );
    });
  });
}
