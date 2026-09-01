import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/pengaduan_case_flow.dart';

void main() {
  test('open case is only for new OPEN complaints', () {
    expect(PengaduanCaseFlow.canOpenCase('OPEN'), isTrue);
    expect(PengaduanCaseFlow.canOpenCase(''), isTrue);
    expect(PengaduanCaseFlow.canOpenCase('IN_PROGRESS'), isFalse);
    expect(PengaduanCaseFlow.canOpenCase('DONE'), isFalse);
    expect(PengaduanCaseFlow.canOpenCase('REJECTED'), isFalse);
  });

  test('card tap copy follows open / progress / closed', () {
    expect(PengaduanCaseFlow.tapKey('OPEN'), 'pengaduan_admin_tap_pilih');
    expect(
      PengaduanCaseFlow.tapKey('IN_PROGRESS'),
      'pengaduan_admin_tap_tindakan',
    );
    expect(PengaduanCaseFlow.tapKey('DONE'), 'pengaduan_admin_tap_lihat');
    expect(PengaduanCaseFlow.tapKey('REJECTED'), 'pengaduan_admin_tap_lihat');
  });

  test('submit requires kategori, detail, foto, and items for produk', () {
    expect(
      PengaduanCaseFlow.submitBlocker(
        kategoriKode: null,
        detail: 'rusak',
        hasFoto: true,
        items: const [],
      ),
      'pengaduan_err_kategori',
    );
    expect(
      PengaduanCaseFlow.submitBlocker(
        kategoriKode: 'TOKO',
        detail: '',
        hasFoto: true,
        items: const [],
      ),
      'pengaduan_err_penjelasan',
    );
    expect(
      PengaduanCaseFlow.submitBlocker(
        kategoriKode: 'TOKO',
        detail: 'AC rusak',
        hasFoto: false,
        items: const [],
      ),
      'pengaduan_err_foto',
    );
    expect(
      PengaduanCaseFlow.canSubmit(
        kategoriKode: 'TOKO',
        detail: 'AC rusak',
        hasFoto: true,
        items: const [],
      ),
      isTrue,
    );
    expect(
      PengaduanCaseFlow.submitBlocker(
        kategoriKode: 'PRODUK',
        detail: 'frame pecah',
        hasFoto: true,
        items: const [],
      ),
      'pengaduan_err_barang',
    );
    expect(
      PengaduanCaseFlow.canSubmit(
        kategoriKode: 'PRODUK',
        detail: 'frame pecah',
        hasFoto: true,
        items: const [
          PengaduanItemLine(sku: 'A', nama: 'Frame A', qty: 2),
          PengaduanItemLine(sku: 'B', nama: 'Frame B', qty: 1),
        ],
      ),
      isTrue,
    );
  });

  test('approve produk requires buang or balik; reject only needs alasan', () {
    expect(
      PengaduanCaseFlow.decideBlocker(
        approve: true,
        alasan: 'ok buang',
        kategoriKode: 'PRODUK',
        stokTindakan: null,
        tokoPusat: false,
      ),
      'pengaduan_admin_err_stok_tindakan',
    );
    expect(
      PengaduanCaseFlow.decideBlocker(
        approve: true,
        alasan: 'balik ke gudang',
        kategoriKode: 'PRODUK',
        stokTindakan: 'BALIK',
        tokoPusat: true,
      ),
      'pengaduan_admin_err_stok_balik_pusat',
    );
    expect(
      PengaduanCaseFlow.decideBlocker(
        approve: true,
        alasan: 'buang saja',
        kategoriKode: 'PRODUK',
        stokTindakan: 'BUANG',
        tokoPusat: false,
      ),
      isNull,
    );
    expect(
      PengaduanCaseFlow.decideBlocker(
        approve: false,
        alasan: 'bukan rusak',
        kategoriKode: 'PRODUK',
        stokTindakan: null,
        tokoPusat: false,
      ),
      isNull,
    );
    expect(
      PengaduanCaseFlow.decideBlocker(
        approve: true,
        alasan: 'toko beres',
        kategoriKode: 'TOKO',
        stokTindakan: null,
        tokoPusat: false,
      ),
      isNull,
    );
  });

  test('admin form hides partner and karyawan-violation categories', () {
    expect(
      PengaduanCaseFlow.kategoriKodesPublik,
      ['PRODUK', 'TOKO', 'CUSTOMER', 'SISTEM'],
    );
    expect(PengaduanCaseFlow.isStaffPrivate('PARTNER'), isTrue);
    expect(PengaduanCaseFlow.isStaffPrivate('PELANGGARAN'), isTrue);
    expect(PengaduanCaseFlow.isStaffPrivate('PRODUK'), isFalse);
    expect(
      PengaduanCaseFlow.submitBlocker(
        kategoriKode: 'PARTNER',
        detail: 'mitra telat',
        hasFoto: true,
        items: const [],
        allowedKodes: PengaduanCaseFlow.kategoriKodesPublik,
      ),
      'pengaduan_err_kategori_privat',
    );
    expect(
      PengaduanCaseFlow.submitBlocker(
        kategoriKode: 'PELANGGARAN',
        detail: 'rahasia',
        hasFoto: true,
        items: const [],
        allowedKodes: PengaduanCaseFlow.kategoriKodesPublik,
      ),
      'pengaduan_err_kategori_privat',
    );
    expect(
      PengaduanCaseFlow.canSubmit(
        kategoriKode: 'TOKO',
        detail: 'AC rusak',
        hasFoto: true,
        items: const [],
        allowedKodes: PengaduanCaseFlow.kategoriKodesPublik,
      ),
      isTrue,
    );
    expect(
      PengaduanCaseFlow.canSubmit(
        kategoriKode: 'PARTNER',
        detail: 'mitra telat',
        hasFoto: true,
        items: const [],
      ),
      isTrue,
    );
  });

  test('admin vs karyawan source is inferred from row', () {
    expect(
      PengaduanCaseFlow.isAdminSumber({'sumber': 'ADMIN'}),
      isTrue,
    );
    expect(
      PengaduanCaseFlow.isAdminSumber({'sumber': 'KARYAWAN'}),
      isFalse,
    );
    expect(
      PengaduanCaseFlow.pelaporNama({
        'sumber': 'ADMIN',
        'pelapor_nama': 'Natanael',
      }),
      'Natanael',
    );
    expect(
      PengaduanCaseFlow.sumberLabelKey({'sumber': 'ADMIN'}),
      'pengaduan_admin_sumber_admin',
    );
    expect(
      PengaduanCaseFlow.sumberLabelKey({'sumber': 'KARYAWAN'}),
      'pengaduan_admin_sumber',
    );
  });

  test('infer produk from old kategori labels', () {
    expect(PengaduanCaseFlow.inferKode('Masalah Stok/Produk'), 'PRODUK');
    expect(PengaduanCaseFlow.inferKode('Kerusakan Alat Toko'), 'TOKO');
    expect(PengaduanCaseFlow.parseItems([
      {'sku': 'A', 'nama': 'Frame A', 'qty': 2},
      {'sku': '', 'qty': 1},
    ]).map((e) => '${e.sku}:${e.qty}').toList(), [
      'A:2',
    ]);
  });

  test('produk approve cannot fallback to reply without stock ledger', () {
    expect(
      PengaduanCaseFlow.canFallbackReplyForDecide(
        approve: true,
        kategoriKode: 'PRODUK',
      ),
      isFalse,
    );
    expect(
      PengaduanCaseFlow.canFallbackReplyForDecide(
        approve: true,
        kategoriKode: 'TOKO',
      ),
      isTrue,
    );
    expect(
      PengaduanCaseFlow.canFallbackReplyForDecide(
        approve: false,
        kategoriKode: 'PRODUK',
      ),
      isTrue,
    );
  });
}
