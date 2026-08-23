/// Kota untuk jalur surat jalan.
///
/// [besar] = boleh tampil sebagai kota yang dilewati.
/// Yang tidak besar hanya untuk menamai gudang/tujuan (mis. Batang),
/// supaya list tidak penuh kabupaten.
class IndonesiaCity {
  const IndonesiaCity({
    required this.name,
    required this.lat,
    required this.lng,
    this.besar = true,
  });

  final String name;
  final double lat;
  final double lng;
  final bool besar;
}

/// Ibu kota / kota madya besar. Bukan kecamatan atau kabupaten kecil.
const kIndonesiaMajorCities = <IndonesiaCity>[
  // Jawa — kota besar
  IndonesiaCity(name: 'Jakarta', lat: -6.2088, lng: 106.8456),
  IndonesiaCity(name: 'Tangerang', lat: -6.1783, lng: 106.6319),
  IndonesiaCity(name: 'Bekasi', lat: -6.2383, lng: 106.9756),
  IndonesiaCity(name: 'Depok', lat: -6.4025, lng: 106.7942),
  IndonesiaCity(name: 'Bogor', lat: -6.5971, lng: 106.8060),
  IndonesiaCity(name: 'Sukabumi', lat: -6.9277, lng: 106.9299),
  IndonesiaCity(name: 'Bandung', lat: -6.9175, lng: 107.6191),
  IndonesiaCity(name: 'Cimahi', lat: -6.8721, lng: 107.5425),
  IndonesiaCity(name: 'Cirebon', lat: -6.7320, lng: 108.5523),
  IndonesiaCity(name: 'Tasikmalaya', lat: -7.3274, lng: 108.2207),
  IndonesiaCity(name: 'Tegal', lat: -6.8694, lng: 109.1402),
  IndonesiaCity(name: 'Purwokerto', lat: -7.4214, lng: 109.2344),
  IndonesiaCity(name: 'Semarang', lat: -6.9667, lng: 110.4167),
  IndonesiaCity(name: 'Magelang', lat: -7.4797, lng: 110.2178),
  IndonesiaCity(name: 'Yogyakarta', lat: -7.7956, lng: 110.3695),
  IndonesiaCity(name: 'Surakarta', lat: -7.5755, lng: 110.8243),
  IndonesiaCity(name: 'Madiun', lat: -7.6298, lng: 111.5239),
  IndonesiaCity(name: 'Kediri', lat: -7.8167, lng: 112.0167),
  IndonesiaCity(name: 'Malang', lat: -7.9797, lng: 112.6304),
  IndonesiaCity(name: 'Surabaya', lat: -7.2575, lng: 112.7521),

  // Luar Jawa — ibu kota / kota besar saja
  IndonesiaCity(name: 'Bandar Lampung', lat: -5.4295, lng: 105.2610),
  IndonesiaCity(name: 'Palembang', lat: -2.9761, lng: 104.7754),
  IndonesiaCity(name: 'Jambi', lat: -1.6101, lng: 103.6131),
  IndonesiaCity(name: 'Padang', lat: -0.9471, lng: 100.4172),
  IndonesiaCity(name: 'Pekanbaru', lat: 0.5071, lng: 101.4478),
  IndonesiaCity(name: 'Medan', lat: 3.5952, lng: 98.6722),
  IndonesiaCity(name: 'Banda Aceh', lat: 5.5483, lng: 95.3238),
  IndonesiaCity(name: 'Bengkulu', lat: -3.7928, lng: 102.2608),
  IndonesiaCity(name: 'Pontianak', lat: -0.0263, lng: 109.3425),
  IndonesiaCity(name: 'Banjarmasin', lat: -3.3186, lng: 114.5944),
  IndonesiaCity(name: 'Balikpapan', lat: -1.2379, lng: 116.8529),
  IndonesiaCity(name: 'Samarinda', lat: -0.5022, lng: 117.1536),
  IndonesiaCity(name: 'Makassar', lat: -5.1477, lng: 119.4327),
  IndonesiaCity(name: 'Manado', lat: 1.4748, lng: 124.8421),
  IndonesiaCity(name: 'Denpasar', lat: -8.6705, lng: 115.2126),
  IndonesiaCity(name: 'Mataram', lat: -8.5833, lng: 116.1167),
  IndonesiaCity(name: 'Kupang', lat: -10.1772, lng: 123.6070),
  IndonesiaCity(name: 'Ambon', lat: -3.6954, lng: 128.1814),
  IndonesiaCity(name: 'Jayapura', lat: -2.5916, lng: 140.6690),

  // Hanya penanda asal/tujuan — tidak masuk jalur tengah
  IndonesiaCity(name: 'Batang', lat: -6.9080, lng: 109.7300, besar: false),
  IndonesiaCity(name: 'Pekalongan', lat: -6.8886, lng: 109.6753, besar: false),
];
