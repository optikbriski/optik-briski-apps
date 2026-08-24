import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/export/export_report_rules.dart';

void main() {
  group('ExportReportRules', () {
    test('filename prefix from slug, not OptikBRiski hardcode', () {
      expect(
        ExportReportRules.fileBrandPrefix(slug: 'optik-briski'),
        'OptikBriski',
      );
      expect(
        ExportReportRules.fileBrandPrefix(slug: 'warung-sari'),
        'WarungSari',
      );
      expect(
        ExportReportRules.fileBrandPrefix(displayName: 'Toko Baru'),
        'TokoBaru',
      );
      expect(ExportReportRules.fileBrandPrefix(), 'Laporan');
      expect(
        ExportReportRules.fileBrandPrefix(slug: 'optik-briski'),
        isNot('OptikBRiski'),
      );
    });

    test('pusat gate: PUSAT/CABANG-PUSAT and pusat roles', () {
      expect(
        ExportReportRules.canExportPusat(tokoId: 'PUSAT', role: 'admin_toko'),
        isTrue,
      );
      expect(
        ExportReportRules.canExportPusat(
          tokoId: 'CABANG-PUSAT',
          role: 'kasir',
        ),
        isTrue,
      );
      expect(
        ExportReportRules.canExportPusat(tokoId: 'CABANG-A', role: 'owner'),
        isTrue,
      );
      expect(
        ExportReportRules.canExportPusat(
          tokoId: 'CABANG-A',
          role: 'admin_pusat',
        ),
        isTrue,
      );
      expect(
        ExportReportRules.canExportPusat(
          tokoId: 'CABANG-A',
          role: 'super_admin',
        ),
        isTrue,
      );
      expect(
        ExportReportRules.canExportPusat(tokoId: 'CABANG-A', role: 'admin_toko'),
        isFalse,
      );
    });

    test('versi_app snapshot stays on the same slug', () {
      expect(
        ExportReportRules.versiAppBelongsToSlug(null, 'optik-briski'),
        isTrue,
      );
      expect(
        ExportReportRules.versiAppBelongsToSlug('optik-briski', 'optik-briski'),
        isTrue,
      );
      expect(
        ExportReportRules.versiAppBelongsToSlug('rekasa', 'optik-briski'),
        isFalse,
      );
      expect(
        ExportReportRules.versiAppBelongsToSlug('warung-sari', 'warung-sari'),
        isTrue,
      );
      expect(
        ExportReportRules.versiAppBelongsToSlug(null, 'warung-sari'),
        isFalse,
      );
      expect(
        ExportReportRules.versiAppBelongsToSlug('optik-briski', ''),
        isFalse,
      );
    });

    test('money JSON 150000.0 is not Rp0', () {
      expect(ExportReportRules.moneyOf('150000.0'), 150000);
      expect(ExportReportRules.moneyOf(150000.0), 150000);
      expect(ExportReportRules.countOf('7.0'), 7);
    });

    test('sales_items and versi_app have no tenant_id column', () {
      expect(ExportReportRules.tableUsesTenantId('sales'), isTrue);
      expect(ExportReportRules.tableUsesTenantId('sales_items'), isFalse);
      expect(ExportReportRules.tableUsesTenantId('versi_app'), isFalse);
    });
  });
}
