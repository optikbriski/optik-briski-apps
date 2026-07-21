import 'training_mode.dart';
import 'training_sandbox_store.dart';

/// Admin Training Mode curriculum — only these modules are available.
///
/// Inter-module sync happens **inside** the sandbox only (POS → history /
/// finance / garansi / stok). Never syncs to production. Exit wipes all;
/// re-enter seeds a fresh world from zero.
class TrainingCurriculum {
  TrainingCurriculum._();

  static const modules = <String>{
    'pos',
    'logistics',
    'history_dp',
    'warranty',
    'finance',
    'master_data',
  };

  static bool get isActive => TrainingMode.instance.isActive;

  static bool allows(String moduleId) {
    if (!isActive) return true; // live: all role-gated menus as usual
    return modules.contains(moduleId);
  }

  /// Populate a blank sandbox so POS / logistics / finance are operable.
  static Future<void> seedFreshWorld({
    required String tokoId,
    required Map<String, dynamic> profile,
  }) async {
    final store = TrainingSandboxStore.instance;
    final now = DateTime.now().toIso8601String();
    final authId = profile['id']?.toString() ??
        'tr_admin_${tokoId.hashCode.abs()}';

    await store.insert('toko_id', {
      'id': tokoId,
      'toko_id': tokoId,
      'nama': 'Toko Latihan $tokoId',
      'latitude': -6.9,
      'longitude': 107.6,
      'radius_meters': 200,
    });

    if (tokoId != 'PUSAT' && tokoId != 'CABANG-PUSAT') {
      await store.insert('toko_id', {
        'id': 'PUSAT',
        'toko_id': 'PUSAT',
        'nama': 'Gudang Pusat (Latihan)',
        'latitude': -6.2,
        'longitude': 106.8,
        'radius_meters': 300,
      });
    }

    await store.insert('karyawan', {
      'id': 'tr_kasir_1',
      'nik': 'TRAINING01',
      'nama': 'Kasir Latihan',
      'toko_id': tokoId,
      'jabatan': 'kasir',
      'status_approval': 'approved',
      'created_at': now,
    });

    await store.insert('invoice_settings', {
      'id': 'tr_inv_settings',
      'toko_id': tokoId,
      'nama_toko': 'Optik B. Riski — Mode Latihan',
      'alamat': 'Sandbox lokal (bukan data asli)',
      'footer_text': 'NOTA LATIHAN — tidak valid di sistem live',
      'updated_at': now,
    });

    // Catalog at this store + mirror stock at PUSAT for RO/logistics practice.
    final catalog = <Map<String, dynamic>>[
      {
        'sku': 'TR-FR-001',
        'nama': 'Frame Latihan Classic',
        'kategori': 'Frame',
        'sub_kategori': 'Metal',
        'harga': 350000,
        'harga_jual': 350000,
        'harga_modal': 150000,
        'stock': 20,
      },
      {
        'sku': 'TR-LN-001',
        'nama': 'Lensa Latihan Single Vision',
        'kategori': 'Lensa',
        'sub_kategori': 'CR39',
        'harga': 200000,
        'harga_jual': 200000,
        'harga_modal': 80000,
        'stock': 40,
      },
      {
        'sku': 'TR-LN-002',
        'nama': 'Lensa Latihan Progressive',
        'kategori': 'Lensa',
        'sub_kategori': 'Progressive',
        'harga': 750000,
        'harga_jual': 750000,
        'harga_modal': 300000,
        'stock': 15,
      },
      {
        'sku': 'TR-ACC-BOX',
        'nama': 'Kotak Kacamata',
        'kategori': 'Aksesoris',
        'sub_kategori': 'Bonus',
        'harga': 0,
        'harga_jual': 0,
        'harga_modal': 5000,
        'stock': 100,
      },
      {
        'sku': 'TR-ACC-CLOTH',
        'nama': 'Lap Kacamata',
        'kategori': 'Aksesoris',
        'sub_kategori': 'Bonus',
        'harga': 0,
        'harga_jual': 0,
        'harga_modal': 2000,
        'stock': 100,
      },
    ];

    Future<void> seedProductsFor(String destToko, {int stockFactor = 1}) async {
      for (var i = 0; i < catalog.length; i++) {
        final c = catalog[i];
        final stock = ((c['stock'] as int) * stockFactor);
        await store.insert('products', {
          'id': 'tr_prod_${destToko}_$i',
          'toko_id': destToko,
          'sku': c['sku'],
          'barcode': c['sku'],
          'nama': c['nama'],
          'kategori': c['kategori'],
          'sub_kategori': c['sub_kategori'],
          'harga': c['harga'],
          'harga_jual': c['harga_jual'],
          'harga_modal': c['harga_modal'],
          'stock': stock,
          'created_at': now,
          'updated_at': now,
        });
      }
    }

    await seedProductsFor(tokoId);
    if (tokoId != 'PUSAT') {
      await seedProductsFor('PUSAT', stockFactor: 5);
    }

    await store.insert('profiles', {
      ...Map<String, dynamic>.from(profile),
      'id': authId,
      'toko_id': tokoId,
      'training': true,
    });

    await store.insert('session_meta', {
      'id': 'tr_meta',
      'seeded_at': now,
      'toko_id': tokoId,
      'curriculum': modules.toList(),
      'note': 'Fresh training world — wiped on exit',
    });
  }
}
