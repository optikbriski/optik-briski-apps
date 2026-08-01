import 'dart:convert';

import 'package:http/http.dart' as http;

/// API wilayah Indonesia (Emsifa) — provinsi → kota/kab → kecamatan → kelurahan/desa.
class IndonesiaWilayahApi {
  IndonesiaWilayahApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base =
      'https://www.emsifa.com/api-wilayah-indonesia/api';

  Future<List<Map<String, dynamic>>> provinces() =>
      _getList('$_base/provinces.json');

  Future<List<Map<String, dynamic>>> regencies(String provinceId) =>
      _getList('$_base/regencies/$provinceId.json');

  Future<List<Map<String, dynamic>>> districts(String regencyId) =>
      _getList('$_base/districts/$regencyId.json');

  Future<List<Map<String, dynamic>>> villages(String districtId) =>
      _getList('$_base/villages/$districtId.json');

  Future<List<Map<String, dynamic>>> _getList(String url) async {
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat data wilayah (${response.statusCode})');
    }
    final decoded = json.decode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
