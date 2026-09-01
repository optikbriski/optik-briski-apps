import 'dart:async';
import 'dart:convert';

import '../../apps/karyawan/pengingat_page.dart';
import 'lab_job_service.dart';

/// Hub deep-link Karyawan: payload JSON `{dest, labJobId?}` untuk
/// OpsWatch / FCM / Pengingat → Beranda.
class KaryawanDeepLink {
  KaryawanDeepLink._();

  static PengingatNavResult? _pending;
  static final _ctrl = StreamController<PengingatNavResult>.broadcast();

  static Stream<PengingatNavResult> get stream => _ctrl.stream;

  /// Pending terakhir (tap notif sebelum home siap). [consumePending] kosongkan.
  static PengingatNavResult? get pending => _pending;

  static PengingatNavResult? consumePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  static void emit(PengingatNavResult result) {
    _pending = result;
    if (!_ctrl.isClosed) _ctrl.add(result);
  }

  static void emitFromPayload(String? raw) {
    final nav = parse(raw);
    if (nav != null) emit(nav);
  }

  static String encode({
    required PengingatDest dest,
    String? labJobId,
  }) {
    final m = <String, dynamic>{
      'dest': dest.name,
      if (labJobId != null && labJobId.trim().isNotEmpty)
        'labJobId': labJobId.trim(),
    };
    return jsonEncode(m);
  }

  /// Encode dari judul/isi/tipe notifikasi (OpsWatch / FCM data).
  static String encodeFromNotif({
    String? tipe,
    String? judul,
    String? isi,
  }) {
    final nav = destFor(tipe: tipe, judul: judul, isi: isi);
    return encode(dest: nav.dest, labJobId: nav.labJobId);
  }

  static PengingatNavResult? parse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    try {
      final m = jsonDecode(s);
      if (m is! Map) return null;
      final destName = (m['dest'] ?? '').toString().trim().toLowerCase();
      final dest = _destFromName(destName);
      if (dest == null) return null;
      final job = (m['labJobId'] ?? m['lab_job_id'] ?? '').toString().trim();
      return PengingatNavResult(
        dest: dest,
        labJobId: job.isEmpty ? null : job,
      );
    } catch (_) {
      // Fallback: plain dest name atau LAB_JOB:uuid
      final dest = _destFromName(s.toLowerCase());
      if (dest != null) return PengingatNavResult(dest: dest);
      final job = LabJobService.jobIdFromNotifikasiIsi(s);
      if (job != null) {
        return PengingatNavResult(dest: PengingatDest.lab, labJobId: job);
      }
      return null;
    }
  }

  static PengingatDest? _destFromName(String name) {
    for (final d in PengingatDest.values) {
      if (d.name == name) return d;
    }
    return null;
  }

  /// Mirror rules [PengingatPage] `_destFor` — dipakai deep-link + tests.
  static PengingatNavResult destFor({
    String? tipe,
    String? judul,
    String? isi,
  }) {
    final t = (tipe ?? '').toString().toUpperCase();
    final j = (judul ?? '').toString();
    final i = (isi ?? '').toString();
    final jl = j.toLowerCase();
    final il = i.toLowerCase();
    final jobId = LabJobService.jobIdFromNotifikasiIsi(i);

    if (jobId != null ||
        t == 'LAB' ||
        jl.contains('lab') ||
        i.contains('LAB_JOB:')) {
      return PengingatNavResult(
        dest: PengingatDest.lab,
        labJobId: jobId,
      );
    }
    if (t == 'SOP' || j.toUpperCase().contains('SOP')) {
      return const PengingatNavResult(dest: PengingatDest.sop);
    }
    if (jl.contains('pengajuan')) {
      return const PengingatNavResult(dest: PengingatDest.pengajuan);
    }
    if (t == 'SHIFT' ||
        jl.contains('jadwal') ||
        jl.contains('shift') ||
        jl.contains('sif')) {
      return const PengingatNavResult(dest: PengingatDest.shift);
    }
    if (t == 'PENGADUAN' ||
        jl.contains('pengaduan') ||
        (t == 'ADMIN' &&
            (jl.contains('balasan') || il.contains('pengaduan')))) {
      return const PengingatNavResult(dest: PengingatDest.pengaduan);
    }
    // Antrian lantai toko: order online / booking / pickup / klaim / antrian.
    if (t == 'ANTRIAN' ||
        jl.contains('order online') ||
        jl.contains('pickup') ||
        jl.contains('booking') ||
        jl.contains('antrian') ||
        jl.contains('klaim') ||
        jl.contains('garansi')) {
      return const PengingatNavResult(dest: PengingatDest.antrian);
    }
    return const PengingatNavResult(dest: PengingatDest.home);
  }
}
