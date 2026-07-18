import 'dart:math';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Layer toko untuk jaga coverage libur.
enum OfficeLayer { front, back }

/// Klasifikasi jabatan → Front / Back office.
OfficeLayer officeLayerOf(String? jabatan) {
  final j = (jabatan ?? '').toLowerCase().trim();
  const backHints = [
    'kepala',
    'admin',
    'lab',
    'teknisi',
    'gudang',
    'back',
    'warehouse',
    'akunting',
    'accounting',
    'finance',
    'keuangan',
    'inventori',
    'inventory',
    'office',
  ];
  for (final h in backHints) {
    if (j.contains(h)) return OfficeLayer.back;
  }
  return OfficeLayer.front;
}

String layerLabel(OfficeLayer l) =>
    l == OfficeLayer.back ? 'Back office' : 'Front office';

/// Setting 2 shift per cabang (kuota beda per toko).
/// Aturan: tiap orang libur tepat 1 hari per minggu; libur digilir per layer.
class TokoShiftSettings {
  TokoShiftSettings({
    required this.tokoId,
    this.shift1Label = 'Shift Pagi',
    this.shift1Masuk = '09:00',
    this.shift1Pulang = '17:00',
    this.shift1Kuota = 3,
    this.shift2Label = 'Shift Sore',
    this.shift2Masuk = '13:00',
    this.shift2Pulang = '21:00',
    this.shift2Kuota = 3,
    /// Deprecated: toko buka tiap hari. Selalu false (giliran libur karyawan).
    this.mingguLibur = false,
  });

  final String tokoId;
  final String shift1Label;
  final String shift1Masuk;
  final String shift1Pulang;
  final int shift1Kuota;
  final String shift2Label;
  final String shift2Masuk;
  final String shift2Pulang;
  final int shift2Kuota;
  final bool mingguLibur;

  int get totalKuotaHarian => shift1Kuota + shift2Kuota;

  factory TokoShiftSettings.fromRow(Map<String, dynamic> row) {
    String t(dynamic v, String fallback) {
      if (v == null) return fallback;
      final s = v.toString();
      return s.length >= 5 ? s.substring(0, 5) : s;
    }

    return TokoShiftSettings(
      tokoId: row['toko_id']?.toString() ?? '',
      shift1Label: row['shift1_label']?.toString() ?? 'Shift Pagi',
      shift1Masuk: t(row['shift1_masuk'], '09:00'),
      shift1Pulang: t(row['shift1_pulang'], '17:00'),
      shift1Kuota: (row['shift1_kuota'] as num?)?.toInt() ?? 3,
      shift2Label: row['shift2_label']?.toString() ?? 'Shift Sore',
      shift2Masuk: t(row['shift2_masuk'], '13:00'),
      shift2Pulang: t(row['shift2_pulang'], '21:00'),
      shift2Kuota: (row['shift2_kuota'] as num?)?.toInt() ?? 3,
      // Abaikan flag lama "semua libur Minggu" — toko buka tiap hari.
      mingguLibur: false,
    );
  }

  Map<String, dynamic> toUpsert() => {
        'toko_id': tokoId,
        'shift1_label': shift1Label,
        'shift1_masuk': '$shift1Masuk:00',
        'shift1_pulang': '$shift1Pulang:00',
        'shift1_kuota': shift1Kuota,
        'shift2_label': shift2Label,
        'shift2_masuk': '$shift2Masuk:00',
        'shift2_pulang': '$shift2Pulang:00',
        'shift2_kuota': shift2Kuota,
        'minggu_libur': false,
        'updated_at': DateTime.now().toIso8601String(),
      };

  static TokoShiftSettings defaults(String tokoId) =>
      TokoShiftSettings(tokoId: tokoId);
}

class ShiftAutoAssignResult {
  ShiftAutoAssignResult({
    required this.daysProcessed,
    required this.rowsWritten,
    required this.warnings,
  });

  final int daysProcessed;
  final int rowsWritten;
  final List<String> warnings;
}

class ShiftAutoAssignService {
  ShiftAutoAssignService({SupabaseClient? client, Random? random})
      : _client = client ?? Supabase.instance.client,
        _random = random ?? Random();

  final SupabaseClient _client;
  final Random _random;
  static final _dateKey = DateFormat('yyyy-MM-dd');

  Future<TokoShiftSettings> fetchSettings(String tokoId) async {
    final row = await _client
        .from('toko_shift_settings')
        .select()
        .eq('toko_id', tokoId)
        .maybeSingle();
    if (row == null) return TokoShiftSettings.defaults(tokoId);
    return TokoShiftSettings.fromRow(row);
  }

  Future<void> saveSettings(TokoShiftSettings s) async {
    await _client.from('toko_shift_settings').upsert(s.toUpsert());
  }

  static DateTime _mondayOf(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    return local.subtract(Duration(days: local.weekday - 1));
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Sebar 1 hari libur per orang dalam layer, tanpa mengosongkan layer
  /// (minimal 1 orang layer tetap masuk jika layer punya ≥2 orang).
  Map<String, DateTime> _assignOffDaysByLayer({
    required List<String> personIds,
    required Map<String, OfficeLayer> layers,
    required List<DateTime> weekDays,
    required List<String> warnings,
  }) {
    final result = <String, DateTime>{};
    if (weekDays.isEmpty || personIds.isEmpty) return result;

    for (final layer in OfficeLayer.values) {
      final members =
          personIds.where((id) => layers[id] == layer).toList()..shuffle(_random);
      if (members.isEmpty) continue;

      // Max libur/hari di layer ini: sisakan ≥1 masuk jika ada ≥2 orang.
      final maxOffPerDay = members.length <= 1 ? 1 : members.length - 1;
      final capacity = {for (final d in weekDays) _dateKey.format(d): maxOffPerDay};
      final dayList = List<DateTime>.from(weekDays)..shuffle(_random);

      for (final id in members) {
        DateTime? chosen;
        // Coba hari yang masih ada slot.
        for (final d in dayList) {
          final k = _dateKey.format(d);
          if ((capacity[k] ?? 0) > 0) {
            chosen = d;
            capacity[k] = capacity[k]! - 1;
            break;
          }
        }
        // Fallback (harusnya jarang): hari acak.
        chosen ??= weekDays[_random.nextInt(weekDays.length)];
        result[id] = chosen;
      }

      // Validasi: tidak boleh semua layer libur di hari yang sama (jika ≥2).
      if (members.length >= 2) {
        for (final d in weekDays) {
          final offCount = members.where((id) => _sameDay(result[id]!, d)).length;
          if (offCount >= members.length) {
            warnings.add(
              '${layerLabel(layer)}: terdeteksi risiko semua libur di '
              '${DateFormat('EEE d MMM', 'id_ID').format(d)} — diperbaiki otomatis.',
            );
            // Pindahkan satu orang ke hari lain.
            final victim = members.firstWhere((id) => _sameDay(result[id]!, d));
            final alt = weekDays.firstWhere(
              (x) => !_sameDay(x, d),
              orElse: () => d,
            );
            result[victim] = alt;
          }
        }
      }
    }
    return result;
  }

  /// Auto random: libur 1 hari/minggu digilir per layer (Front/Back tidak boleh kosong).
  Future<ShiftAutoAssignResult> autoRandom({
    required String tokoId,
    required List<Map<String, dynamic>> karyawan,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required TokoShiftSettings settings,
    bool overwriteExisting = true,
  }) async {
    final warnings = <String>[];
    final people = <({String id, String jabatan, OfficeLayer layer})>[];
    for (final k in karyawan) {
      final id = k['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final jabatan = k['jabatan']?.toString() ?? '';
      people.add((id: id, jabatan: jabatan, layer: officeLayerOf(jabatan)));
    }

    if (people.isEmpty) {
      return ShiftAutoAssignResult(
        daysProcessed: 0,
        rowsWritten: 0,
        warnings: ['Tidak ada karyawan di cabang ini.'],
      );
    }

    final ids = people.map((p) => p.id).toList();
    final layers = {for (final p in people) p.id: p.layer};
    final frontN = people.where((p) => p.layer == OfficeLayer.front).length;
    final backN = people.where((p) => p.layer == OfficeLayer.back).length;

    warnings.add('Layer: Front $frontN orang, Back $backN orang '
        '(berdasarkan jabatan).');
    if (backN == 0) {
      warnings.add(
        'Belum ada jabatan Back office (Kepala Toko / Admin / Lab / dll). '
        'Semua dianggap Front — set jabatan back office agar libur tidak bentrok.',
      );
    }
    if (backN == 1) {
      warnings.add(
        'Back office hanya 1 orang: hari liburnya toko tidak punya back office '
        '(tidak terhindarkan).',
      );
    }

    final start = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final end = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);

    final weeks = <DateTime>[];
    var cursor = _mondayOf(start);
    final lastMonday = _mondayOf(end);
    while (!cursor.isAfter(lastMonday)) {
      weeks.add(cursor);
      cursor = cursor.add(const Duration(days: 7));
    }

    final workCount = {for (final id in ids) id: 0};
    final allRows = <Map<String, dynamic>>[];
    final daysSeen = <String>{};

    for (final weekStart in weeks) {
      final weekDays = List.generate(
        7,
        (i) => weekStart.add(Duration(days: i)),
      ).where((d) => !d.isBefore(start) && !d.isAfter(end)).toList();

      if (weekDays.isEmpty) continue;

      // Toko buka tiap hari: libur = giliran karyawan (bukan tutup Minggu).
      final liburDay = _assignOffDaysByLayer(
        personIds: ids,
        layers: layers,
        weekDays: weekDays,
        warnings: warnings,
      );

      for (final day in weekDays) {
        final key = _dateKey.format(day);
        daysSeen.add(key);

        final offToday = <String>[];
        final available = <String>[];
        for (final id in ids) {
          final off = liburDay[id];
          if (off != null && _sameDay(off, day)) {
            offToday.add(id);
          } else {
            available.add(id);
          }
        }

        // Guard: jangan biarkan seluruh back/front libur di hari yang sama.
        for (final layer in OfficeLayer.values) {
          final layerIds =
              ids.where((id) => layers[id] == layer).toList();
          if (layerIds.length < 2) continue;
          final layerOff =
              offToday.where((id) => layers[id] == layer).toList();
          if (layerOff.length >= layerIds.length) {
            final moveId = layerOff.first;
            offToday.remove(moveId);
            available.add(moveId);
            final alt = weekDays.firstWhere(
              (d) {
                if (_sameDay(d, day)) return false;
                final offOnAlt = ids
                    .where((id) =>
                        layers[id] == layer &&
                        liburDay[id] != null &&
                        _sameDay(liburDay[id]!, d))
                    .length;
                return offOnAlt < layerIds.length - 1;
              },
              orElse: () => weekDays.firstWhere((d) => !_sameDay(d, day),
                  orElse: () => day),
            );
            liburDay[moveId] = alt;
            warnings.add(
              '${layerLabel(layer)}: dicegah kosong pada '
              '${DateFormat('EEE d', 'id_ID').format(day)}.',
            );
          }
        }

        for (final id in offToday) {
          allRows.add({
            'karyawan_id': id,
            'toko_id': tokoId,
            'tanggal': key,
            'jam_masuk': null,
            'jam_pulang': null,
            'is_libur': true,
            'catatan': 'Libur giliran (${layerLabel(layers[id]!)})',
          });
        }

        if (available.isEmpty) continue;

        available.shuffle(_random);
        available.sort((a, b) => workCount[a]!.compareTo(workCount[b]!));

        final shift1 = <String>[];
        final shift2 = <String>[];
        for (final id in available) {
          if (shift1.length < settings.shift1Kuota) {
            shift1.add(id);
          } else if (shift2.length < settings.shift2Kuota) {
            shift2.add(id);
          } else if (shift1.length <= shift2.length) {
            shift1.add(id);
          } else {
            shift2.add(id);
          }
        }

        for (final id in shift1) {
          workCount[id] = workCount[id]! + 1;
          allRows.add({
            'karyawan_id': id,
            'toko_id': tokoId,
            'tanggal': key,
            'jam_masuk': '${settings.shift1Masuk}:00',
            'jam_pulang': '${settings.shift1Pulang}:00',
            'is_libur': false,
            'catatan': settings.shift1Label,
          });
        }
        for (final id in shift2) {
          workCount[id] = workCount[id]! + 1;
          allRows.add({
            'karyawan_id': id,
            'toko_id': tokoId,
            'tanggal': key,
            'jam_masuk': '${settings.shift2Masuk}:00',
            'jam_pulang': '${settings.shift2Pulang}:00',
            'is_libur': false,
            'catatan': settings.shift2Label,
          });
        }
      }
    }

    if (allRows.isEmpty) {
      return ShiftAutoAssignResult(
        daysProcessed: daysSeen.length,
        rowsWritten: 0,
        warnings: warnings..add('Tidak ada baris yang dibuat.'),
      );
    }

    const chunk = 200;
    for (var i = 0; i < allRows.length; i += chunk) {
      final part = allRows.sublist(i, min(i + chunk, allRows.length));
      await _client
          .from('jadwal_kerja')
          .upsert(part, onConflict: 'karyawan_id,tanggal');
    }

    return ShiftAutoAssignResult(
      daysProcessed: daysSeen.length,
      rowsWritten: allRows.length,
      warnings: warnings,
    );
  }
}
