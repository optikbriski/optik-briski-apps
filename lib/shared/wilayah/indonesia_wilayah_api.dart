import 'dart:convert';

import 'package:http/http.dart' as http;

/// API wilayah Indonesia (Emsifa) — provinsi → kota/kab → kecamatan → kelurahan/desa.
///
/// Beberapa edge/proxy menolak request tanpa User-Agent (403). Pakai header
/// browser-like + fallback GitHub Pages agar Data diri tetap bisa diisi.
class IndonesiaWilayahApi {
  IndonesiaWilayahApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _primary =
      'https://www.emsifa.com/api-wilayah-indonesia/api';
  static const _fallback =
      'https://emsifa.github.io/api-wilayah-indonesia/api';
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (compatible; OptikBRiskiMember/1.0; +https://optikbriski.com)',
    'Accept': 'application/json',
  };

  Future<List<Map<String, dynamic>>> provinces() =>
      _getList('provinces.json');

  Future<List<Map<String, dynamic>>> regencies(String provinceId) =>
      _getList('regencies/$provinceId.json');

  Future<List<Map<String, dynamic>>> districts(String regencyId) =>
      _getList('districts/$regencyId.json');

  Future<List<Map<String, dynamic>>> villages(String districtId) =>
      _getList('villages/$districtId.json');

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    Object? lastError;
    for (final base in [_primary, _fallback]) {
      try {
        final response = await _client.get(
          Uri.parse('$base/$path'),
          headers: _headers,
        );
        if (response.statusCode != 200) {
          lastError = Exception(
            'Gagal memuat data wilayah (${response.statusCode})',
          );
          continue;
        }
        final decoded = json.decode(response.body);
        if (decoded is! List) return const [];
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      'Gagal memuat data wilayah. Periksa koneksi lalu coba lagi. ($lastError)',
    );
  }
}
