import 'dart:async';

import 'package:flutter/foundation.dart';

import '../invoice/invoice_hub_service.dart';
import 'member_home_models.dart';
import 'member_repository.dart';
import 'member_session.dart';
import 'member_status_watch.dart';

/// Orkestrasi Beranda Member — cache + refresh paralel, survive ganti tab.
class MemberHomeController extends ChangeNotifier {
  MemberHomeController._();
  static final MemberHomeController instance = MemberHomeController._();

  final _repo = MemberRepository();

  MemberHomeSnapshot? snapshot;
  bool loading = false;
  String? lastError;

  StreamSubscription<void>? _statusSub;
  bool _bound = false;
  int _loadGen = 0;
  String? _sessionFingerprint;

  /// Pendek agar Update CMS cepat terlihat setelah pull-to-refresh / balik tab.
  static const _staleAfter = Duration(seconds: 20);
  static const _maxReminders = 4;

  bool get hasData => snapshot != null;

  bool get isStale {
    final at = snapshot?.loadedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > _staleAfter;
  }

  void bind() {
    if (_bound) return;
    _bound = true;
    _sessionFingerprint = _fingerprint(MemberSession.instance);
    MemberSession.instance.addListener(_onSession);
    _statusSub = MemberStatusWatch.instance.onRefresh.listen((_) {
      unawaited(refresh(soft: true));
    });
  }

  void unbind() {
    if (!_bound) return;
    _bound = false;
    MemberSession.instance.removeListener(_onSession);
    unawaited(_statusSub?.cancel());
    _statusSub = null;
  }

  String _fingerprint(MemberSession s) {
    return [
      s.isLoggedIn ? '1' : '0',
      s.phoneForQuery,
      s.memberId ?? '',
      s.nama ?? '',
      s.preferredTokoId ?? '',
    ].join('|');
  }

  void _onSession() {
    final next = _fingerprint(MemberSession.instance);
    if (next == _sessionFingerprint) return;
    _sessionFingerprint = next;
    unawaited(refresh(force: true));
  }

  /// Muat jika belum ada / stale. [force] abaikan cache.
  Future<void> ensureLoaded({bool force = false}) async {
    bind();
    if (!force && hasData && !isStale && !loading) return;
    await refresh(force: force);
  }

  Future<void> refresh({bool force = false, bool soft = false}) async {
    bind();
    if (loading && !force) return;
    final gen = ++_loadGen;

    if (!soft || !hasData) {
      loading = true;
      lastError = null;
      notifyListeners();
    }

    try {
      final session = MemberSession.instance;
      _sessionFingerprint = _fingerprint(session);

      final bundle = await _repo.fetchHomeBundle(
        loggedIn: session.isLoggedIn,
        phone: session.phoneForQuery,
        memberId: session.memberId,
        preferredTokoId: session.preferredTokoId,
      );
      if (gen != _loadGen) return;

      final reminders = _buildReminders(
        sales: bundle.sales,
        bookings: bundle.bookings,
        onlineOrders: bundle.onlineOrders,
      );
      final pendingOnline = bundle.onlineOrders
          .where((o) => (o['status'] ?? '') == 'pending_payment')
          .length;
      final active =
          bundle.sales.where(_isActiveSale).length + pendingOnline;

      String? toko = session.preferredTokoId?.trim();
      if (toko == null || toko.isEmpty) {
        toko = bundle.highlightToko;
      }

      snapshot = MemberHomeSnapshot(
        content: bundle.content,
        points: bundle.points,
        activeOrders: active,
        garansiCount: bundle.garansiCount,
        reminders: reminders.take(_maxReminders).toList(),
        totalReminders: reminders.length,
        promos: bundle.promos,
        highlightToko: (toko != null && toko.isNotEmpty) ? toko : null,
        error: bundle.partialError,
        loadedAt: DateTime.now(),
        loggedIn: session.isLoggedIn,
      );
      lastError = bundle.partialError;
    } catch (e, st) {
      if (gen != _loadGen) return;
      lastError = 'Gagal memuat beranda. Tarik untuk coba lagi.';
      debugPrint('MemberHomeController.refresh: $e\n$st');
      final loggedIn = MemberSession.instance.isLoggedIn;
      Map<String, dynamic>? content = snapshot?.content;
      try {
        content = await _repo.homeContent() ?? content;
      } catch (_) {}
      if (gen != _loadGen) return;

      if (snapshot == null) {
        snapshot = MemberHomeSnapshot(
          content: content,
          points: 0,
          activeOrders: 0,
          garansiCount: 0,
          reminders: const [],
          totalReminders: 0,
          promos: const [],
          highlightToko: MemberSession.instance.preferredTokoId,
          error: lastError,
          loadedAt: DateTime.now(),
          loggedIn: loggedIn,
        );
      } else {
        // Epoch → isStale=true agar ensureLoaded() tidak stuck di cache gagal.
        snapshot = MemberHomeSnapshot(
          content: content ?? snapshot!.content,
          points: snapshot!.points,
          activeOrders: snapshot!.activeOrders,
          garansiCount: snapshot!.garansiCount,
          reminders: snapshot!.reminders,
          totalReminders: snapshot!.totalReminders,
          promos: snapshot!.promos,
          highlightToko: snapshot!.highlightToko,
          error: lastError,
          loadedAt: DateTime.fromMillisecondsSinceEpoch(0),
          loggedIn: loggedIn,
        );
      }
    } finally {
      if (gen == _loadGen) {
        loading = false;
        notifyListeners();
      }
    }
  }

  bool _isActiveSale(Map<String, dynamic> s) {
    return !InvoiceHubService.sudahDiambil(s);
  }

  List<MemberHomeReminder> _buildReminders({
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> bookings,
    List<Map<String, dynamic>> onlineOrders = const [],
  }) {
    final reminders = <MemberHomeReminder>[];

    for (final o in onlineOrders) {
      if ((o['status'] ?? '').toString() != 'pending_payment') continue;
      final id = (o['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final mid = (o['midtrans_order_id'] ?? '').toString();
      reminders.add(MemberHomeReminder(
        kind: MemberHomeReminderKind.onlinePending,
        title: 'Belum dibayar',
        body: mid.isEmpty
            ? 'Pesanan online · bayar dalam 15 menit (stok di-hold)'
            : '$mid · bayar dalam 15 menit',
        cta: 'Bayar',
        onlineOrderId: id,
      ));
    }

    for (final s in sales) {
      if (InvoiceHubService.sudahDiambil(s)) continue;

      final label = InvoiceHubService.statusLabel({
        'tracking_status': s['tracking_status'],
        'diambil_at': s['diambil_at'],
        'sisa_tagihan': s['sisa_tagihan'],
        'status_pembayaran': s['status_pembayaran'],
      });
      final inv = (s['no_invoice'] ?? '').toString().trim();
      if (inv.isEmpty) continue;
      final st = (s['tracking_status'] ?? '').toString().toUpperCase();
      final sisa = int.tryParse('${s['sisa_tagihan'] ?? 0}') ?? 0;

      if (st == 'SIAP_DIAMBIL' || st == 'CLEAR') {
        reminders.add(MemberHomeReminder(
          kind: MemberHomeReminderKind.ready,
          title: 'Siap diambil',
          body: '$inv · $label',
          cta: 'Lihat nota',
          noInvoice: inv,
        ));
      } else if (sisa > 0 || InvoiceHubService.isDpOpen(s)) {
        reminders.add(MemberHomeReminder(
          kind: MemberHomeReminderKind.dp,
          title: 'Masih DP',
          body: '$inv · lunasi dulu sebelum ambil',
          cta: 'Detail',
          noInvoice: inv,
        ));
      } else {
        reminders.add(MemberHomeReminder(
          kind: MemberHomeReminderKind.processing,
          title: 'Dalam proses',
          body: '$inv · $label',
          cta: 'Lacak',
          noInvoice: inv,
        ));
      }
    }

    final now = DateTime.now();
    for (final b in bookings) {
      if ((b['status'] ?? '').toString() != 'booked') continue;
      final at = DateTime.tryParse('${b['scheduled_at']}');
      if (at == null) continue;
      final local = at.toLocal();
      if (local.isBefore(now.subtract(const Duration(hours: 2)))) continue;
      final toko = (b['toko_id'] ?? '').toString().trim();
      reminders.add(MemberHomeReminder(
        kind: MemberHomeReminderKind.booking,
        title: 'Janji kontrol',
        body: '${toko.isEmpty ? 'Cabang' : toko} · ${_fmtWhen(local)}',
        cta: 'Jadwal',
      ));
    }

    reminders.sort((a, b) => a.sortRank.compareTo(b.sortRank));
    return reminders;
  }

  String _fmtWhen(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }
}
