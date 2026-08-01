import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/theme.dart';
import '../member_layout.dart';
import 'member_date_picker.dart';
import 'member_half_hour_time_picker.dart';

/// Picker jadwal standar Member (sama di klaim garansi & janji kontrol):
/// tanggal → jam scroll/ketik 09:00–20:30 per 30 menit → konfirmasi hari/tanggal/jam.
Future<DateTime?> pickMemberSchedule(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
  String dateHelpText = 'Pilih tanggal',
  String confirmTitle = 'Konfirmasi jadwal',
}) async {
  final now = DateTime.now();
  final first = firstDate ?? DateTime(now.year, now.month, now.day);
  final last = lastDate ?? now.add(const Duration(days: 90));
  var seed = initial ?? now.add(const Duration(days: 1, hours: 2));
  if (seed.isBefore(first)) seed = first;

  final date = await showMemberDatePicker(
    context,
    initialDate: seed,
    firstDate: first,
    lastDate: last,
    title: dateHelpText,
  );
  if (date == null || !context.mounted) return null;

  final time = await showMemberHalfHourTimePicker(
    context,
    initial: TimeOfDay.fromDateTime(seed),
  );
  if (time == null || !context.mounted) return null;

  final picked = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (picked.isBefore(now)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pilih jadwal yang masih akan datang.')),
    );
    return null;
  }

  final ok = await confirmMemberSchedule(
    context,
    picked,
    title: confirmTitle,
  );
  if (ok != true || !context.mounted) return null;
  return picked;
}

const _hari = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

String formatMemberSchedule(DateTime dt) {
  final hari = _hari[dt.weekday - 1];
  final tanggal = DateFormat('d MMM yyyy · HH:mm').format(dt);
  return '$hari, $tanggal';
}

Future<bool?> confirmMemberSchedule(
  BuildContext context,
  DateTime dt, {
  String title = 'Konfirmasi jadwal',
}) {
  final m = MemberLayout.of(context);
  final hari = _hari[dt.weekday - 1];
  final tanggal = DateFormat('d MMMM yyyy').format(dt);
  final jam =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Widget row(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: m.iconSize, color: OptikMemberTokens.blue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: m.menuSubtitleSize,
                  color: OptikMemberTokens.inkMuted,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: m.menuTitleSize,
                  fontWeight: FontWeight.w800,
                  color: OptikMemberTokens.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        title,
        style: TextStyle(fontSize: m.isTablet ? 20 : 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pastikan waktu berikut sudah benar:',
            style: TextStyle(
              fontSize: m.bodySize,
              color: OptikMemberTokens.inkMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          row(Icons.calendar_today_rounded, 'Hari', hari),
          const SizedBox(height: 8),
          row(Icons.event_rounded, 'Tanggal', tanggal),
          const SizedBox(height: 8),
          row(Icons.schedule_rounded, 'Jam', jam),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Ubah'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Ya, benar'),
        ),
      ],
    ),
  );
}
