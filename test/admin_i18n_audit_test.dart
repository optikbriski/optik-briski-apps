import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:optik_b_riski/shared/admin/admin_format.dart';
import 'package:optik_b_riski/shared/admin/admin_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Admin i18n infrastructure', () {
    test('AdminLanguage supports only id and en', () {
      expect(
        AdminLanguage.supported.map((l) => l.languageCode).toList(),
        ['id', 'en'],
      );
    });

    test('AdminFormat locale tags', () {
      expect(AdminFormat.localeTag(const Locale('id')), 'id_ID');
      expect(AdminFormat.localeTag(const Locale('en')), 'en_US');
      expect(AdminFormat.localeTag(const Locale('en', 'GB')), 'en_US');
    });

    test('AdminFormat currency uses distinct locale tags', () {
      final id = NumberFormat.currency(
        locale: AdminFormat.localeTag(const Locale('id')),
        symbol: 'Rp',
        decimalDigits: 0,
      );
      final en = NumberFormat.currency(
        locale: AdminFormat.localeTag(const Locale('en')),
        symbol: 'Rp',
        decimalDigits: 0,
      );
      expect(id.format(1500000), isNotEmpty);
      expect(en.format(1500000), isNotEmpty);
    });
  });

  group('Admin translation parity (id/en)', () {
    late Map<String, dynamic> idJson;
    late Map<String, dynamic> enJson;
    late Set<String> adminKeys;

    setUpAll(() {
      final root = Directory.current;
      idJson = jsonDecode(
        File('${root.path}/assets/translations/id.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      enJson = jsonDecode(
        File('${root.path}/assets/translations/en.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      adminKeys = {};
      final adminDirs = [
        Directory('${root.path}/lib/apps/admin'),
        Directory('${root.path}/lib/shared/widgets/admin'),
      ];
      final keyRe = RegExp(r'''['"]([a-z][a-z0-9_]{2,})['"]\.tr\(''');
      for (final adminDir in adminDirs) {
        if (!adminDir.existsSync()) continue;
        for (final f in adminDir.listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          final text = f.readAsStringSync();
          adminKeys.addAll(keyRe.allMatches(text).map((m) => m.group(1)!));
        }
      }
    });

    test('every admin .tr() key exists in id.json', () {
      final missing = adminKeys.where((k) => !idJson.containsKey(k)).toList()
        ..sort();
      expect(missing, isEmpty, reason: 'Missing id keys: $missing');
    });

    test('every admin .tr() key exists in en.json', () {
      final missing = adminKeys.where((k) => !enJson.containsKey(k)).toList()
        ..sort();
      expect(missing, isEmpty, reason: 'Missing en keys: $missing');
    });

    test('critical POS keys are not English typos with spaces', () {
      const critical = [
        'pos_modal_awal_sesi',
        'pos_omzet_tunai_masuk',
        'pos_kas_seharusnya',
        'pos_trip_close',
        'pos_err_load_lensa',
      ];
      for (final k in critical) {
        expect(enJson.containsKey(k), isTrue, reason: 'EN missing $k');
        expect(idJson.containsKey(k), isTrue, reason: 'ID missing $k');
        expect(enJson[k], isNot(contains('pos ')),
            reason: 'EN $k looks like raw key');
      }
    });

    test('live tr() resolves for id and en POS labels', () {
      for (final loc in AdminLanguage.supported) {
        final code = loc.languageCode;
        final idMap = idJson;
        final enMap = enJson;
        final map = code == 'en' ? enMap : idMap;
        expect(map['pos_modal_awal_sesi'], isNotNull);
        expect(map['pos_modal_awal_sesi'], isNot(equals('pos_modal_awal_sesi')));
        expect(map['admin_menu_language'], isNotEmpty);
      }
    });

    test('EN admin labels differ from ID for critical menu keys', () {
      const mustDiffer = [
        'admin_menu_language',
        'admin_logout',
        'pilihan_bahasa_judul',
        'lang_id',
        'appr_btn_batal',
        'btn_simpan',
        'pos_title',
        'pos_modal_awal_sesi',
      ];
      for (final k in mustDiffer) {
        expect(idJson[k], isNotNull, reason: 'ID missing $k');
        expect(enJson[k], isNotNull, reason: 'EN missing $k');
        expect(
          idJson[k],
          isNot(equals(enJson[k])),
          reason: '$k should differ between id and en',
        );
      }
    });
  });

  group('Admin hardcoded UI regression', () {
    test('no double .tr().tr() calls in admin dart', () {
      final dirs = [
        Directory('${Directory.current.path}/lib/apps/admin'),
        Directory('${Directory.current.path}/lib/shared/widgets/admin'),
      ];
      final doubleTr = RegExp(r"\.tr\(\)\.tr\(\)");
      final violations = <String>[];
      for (final dir in dirs) {
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          final rel = f.path.contains('lib/apps/admin/')
              ? f.path.split('lib/apps/admin/').last
              : 'shared/${f.path.split('lib/shared/widgets/admin/').last}';
          final lines = f.readAsStringSync().split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (doubleTr.hasMatch(lines[i])) {
              violations.add('$rel:${i + 1}');
            }
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Double .tr():\n${violations.join('\n')}');
    });

    test('no untranslated Indonesian UI literals in admin dart', () {
      final adminDirs = [
        Directory('${Directory.current.path}/lib/apps/admin'),
        Directory('${Directory.current.path}/lib/shared/widgets/admin'),
      ];
      final uiProp = RegExp(
        r'(Text\(|title:|subtitle:|message:|label:|tooltip:|content:|titleKey:|hintKey:|_snack\(|_showSnack\()',
      );
      final idWord = RegExp(
        r'\b(Gagal|Belum|Tambah|Hapus|Simpan|Batal|Masuk|Keluar|Jumlah|Dikirim|Pilih|Semua|Generate|Barcode|Lingkaran|tanggal|Kacamata|Antrian|Aging|Konsolidasi|piutang|hutang|Alokasi|Ukuran|Toggle|Batalkan|Rentang|lunasi|bayar|Draf|Detail|Lihat|Belum ada|Tidak ada|Menyimpan|Referensi|Disiapkan|Booking|Restock|Kirim|Surat jalan|Anggaran|Mutasi|Rekening|Sinkron|Ekspor|Periode|Laba|Beban|Stok awal|Buat tenant|Kredit|Debit|Pusat|Cabang|Setujui|Tolak|Gaji|Bonus|Lembur|Etalase|Scan produk|Per minggu|Per bulan|Header|Kartu|Pengingat|Layanan|Belanja|Janji|Resep|Rating|Inbox|Perawatan|Garansi|Pantau|Ya,|Ganti|Halaman|Paket)\b',
      );
      final stringLit = RegExp(r'''['"]([^'"]{3,})['"]''');

      final violations = <String>[];
      for (final adminDir in adminDirs) {
        if (!adminDir.existsSync()) continue;
        for (final f in adminDir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final rel = f.path.contains('lib/apps/admin/')
            ? f.path.split('lib/apps/admin/').last
            : 'shared/${f.path.split('lib/shared/widgets/admin/').last}';
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('.tr(')) continue;
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('debugPrint')) continue;
          if (!uiProp.hasMatch(line)) continue;
          if (!idWord.hasMatch(line)) continue;
          // Allow pure dynamic interpolation (no literal words outside ${})
          final stripped = line.replaceAll(RegExp(r"\$\{[^}]+\}"), '');
          if (!idWord.hasMatch(stripped)) continue;
          for (final m in stringLit.allMatches(line)) {
            final s = m.group(1)!;
            if (s.contains(r'$') || s.contains('{')) continue;
            if (RegExp(r'^[a-z][a-z0-9_]{2,}$').hasMatch(s)) continue;
            violations.add('$rel:${i + 1}: $s');
          }
        }
      }
      }
      expect(violations, isEmpty, reason: 'Hardcoded UI:\n${violations.join('\n')}');
    });

    test('no untranslated tuple row labels in admin dart', () {
      final adminDir = Directory('${Directory.current.path}/lib/apps/admin');
      final tuplePat = RegExp(r"\(\s*'([^'$\\][^']{2,})'\s*,");
      const allow = {
        'Ref', 'ID', 'Memo', 'Status', 'NPWP', 'DPP', 'PPN', 'Header', 'Nonaktif',
        'Debit', 'Kredit', 'Saldo', 'OPEN', 'CLOSED', 'APPROVED', 'REJECTED',
        'IN_PROGRESS', 'DONE', 'POS', 'Member', 'Booking', 'Catatan', 'Nama',
        'Detail', 'Total', 'Nominal', 'Periode', 'Cabang', 'Toko', 'Tanggal',
        'Kode', 'Invoice', 'Pembeli', 'Bank', 'Akun', 'Laba', 'Beban',
        'Pendapatan', 'Jenis', 'Umur', 'Sumber', 'Bulan',
      };
      final sqlCol = RegExp(r'^[a-z][a-z0-9_]*$');
      final dateFmt = RegExp(r'^E{3,4}');
      final violations = <String>[];
      for (final f in adminDir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final rel = f.path.split('lib/apps/admin/').last;
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('.tr(') || line.trimLeft().startsWith('//')) {
            continue;
          }
          for (final m in tuplePat.allMatches(line)) {
            final s = m.group(1)!;
            if (s.startsWith('admin_')) continue;
            if (allow.contains(s)) continue;
            if (sqlCol.hasMatch(s)) continue;
            if (s.contains(r'$') || s.contains(r'${')) continue;
            if (s.startsWith('CABANG-')) continue;
            if (s.startsWith('is_store_open_')) continue;
            if (dateFmt.hasMatch(s)) continue;
            if (!RegExp(r'[a-zA-ZÀ-ÿ]{3,}').hasMatch(s)) continue;
            violations.add('$rel:${i + 1}: $s');
          }
        }
      }
      expect(violations, isEmpty, reason: 'Tuple labels:\n${violations.take(40).join('\n')}');
    });

    test('no untranslated multiline snack/dialog strings in admin dart', () {
      final adminDir = Directory('${Directory.current.path}/lib/apps/admin');
      final callStart = RegExp(
        r'^\s*(_snack|_showSnack|_showSnackBar|content:\s*(?:const\s*)?Text)\s*\(',
      );
      final idWord = RegExp(
        r'\b(Gagal|Belum|Tidak|Sudah|Waktu|Buka|Silakan|Periode|Template|Draft|Payroll|Sesi|Toko|Keranjang|Voucher|Stok|Nota|Midtrans|Centang|Buat|Isi|Aturan|Setelah|Owner|Admin|Pusat|Surat|Antrian|Verifikasi|Pengaduan|Absensi|Geofence|Garansi|Mutasi|Anggaran|Ekspor|Sinkron|Generate|Barcode|Restock|Booking|Janji|Belanja|Layanan|Etalase|Bonus|Ganti|Halaman|Paket|Menu|Login|Nama|Alamat|Resep|Kacamata|Lensa|Member|Kasir|Jadwal|Libur|Cabang|Karyawan|Pelanggan|Invoice|Produk|Nominal|Persentase|Tarif|Potongan|Tunjangan|Slip|CSV|Lunas|Checkout|DP|Lunasi|Struk|Cetak|Unduh|Refresh|Detail|Lihat|Edit|Hapus|Tolak|Setujui|Pending|Ready|Open|Closed|Locked|Paid|Update|Apply|Cancel|Warning|Error|Success|Training|valid|wajib|opsional|Contoh|Kosong|Rate|berhasil|terkunci|dibayar|disimpan|dihapus|unlock|preview|hold|draft|simpan|ulang|coba|lagi|aktif|nonaktif|kosong|penuh|melebihi|invalid|hint|dialog|alert|toast|Ditandai|Akses|Format|Pastikan|Paste|Hanya|Ini|Ambil|Data|Kode|Email|Isi|Lunasi|Bisa|Gagal|⚠️|❌|✅|🛑|•|Pengajuan|Kurir|BELUM|LUNAS|Pelunasan|Email|WA|Kirim|lacak|migrasi|Stok Real|Daftar|Setelah|Bisa)\b',
        caseSensitive: false,
      );
      final strLit = RegExp(r'''['"]([^'"\n\\]{4,200})['"]''');

      final violations = <String>[];
      for (final f in adminDir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final rel = f.path.split('lib/apps/admin/').last;
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (!callStart.hasMatch(lines[i])) continue;
          final block = lines.skip(i).take(12).join('\n');
          if (block.contains('.tr(')) continue;
          for (final m in strLit.allMatches(block)) {
            final s = m.group(1)!;
            if (s.contains(r'$') || s.contains('{')) continue;
            if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(s)) continue;
            if (s.startsWith('CABANG-') || s == 'PUSAT' || s == 'MMMM yyyy') {
              continue;
            }
            if (!idWord.hasMatch(s)) continue;
            violations.add('$rel:${i + 1}: $s');
            break;
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Multiline UI:\n${violations.take(50).join('\n')}');
    });
  });

  group('Admin i18n live widget', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });

    Future<void> pumpLocale(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: AdminLanguage.supported,
          path: 'assets/translations',
          fallbackLocale: const Locale('id'),
          startLocale: locale,
          child: Builder(
            builder: (context) {
              return MaterialApp(
                locale: locale,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                home: Scaffold(
                  body: Column(
                    children: [
                      Text('pilihan_bahasa_judul'.tr()),
                      Text('appr_btn_batal'.tr()),
                      Text('pos_modal_awal_sesi'.tr()),
                      Text('admin_menu_language'.tr()),
                      Text('admin_picker_search_hint'.tr()),
                      Text('admin_picker_no_match'.tr()),
                      Text('admin_picker_apply'.tr()),
                      Text('admin_btn_close'.tr()),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('ID locale shows Indonesian strings', (tester) async {
      await pumpLocale(tester, const Locale('id'));
      expect(find.text('Pilih Bahasa Antarmuka'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);
      expect(find.textContaining('Modal Awal Sesi'), findsOneWidget);
      expect(find.text('Bahasa'), findsOneWidget);
      expect(find.text('Cari…'), findsOneWidget);
      expect(find.text('Tidak ada opsi cocok.'), findsOneWidget);
      expect(find.text('Terapkan'), findsOneWidget);
      expect(find.text('Tutup'), findsOneWidget);
    });

    testWidgets('EN locale shows English strings', (tester) async {
      await pumpLocale(tester, const Locale('en'));
      expect(find.text('Select Interface Language'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.textContaining('Session Initial Capital'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Search…'), findsOneWidget);
      expect(find.text('No matching options.'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

  });
}
