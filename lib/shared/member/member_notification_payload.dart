/// Payload lokal notifikasi Member (`inv:…` / `online:…` / fallback).
class MemberNotificationPayload {
  const MemberNotificationPayload._({
    this.invoice,
    this.onlineOrderId,
    this.openOrdersList = false,
  });

  final String? invoice;
  final String? onlineOrderId;
  final bool openOrdersList;

  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// `no_invoice` palsu dari alert online (UUID / ONLINE / kosong).
  static bool isPlaceholderInvoice(
    String? invoice, {
    String? onlineOrderId,
  }) {
    final inv = (invoice ?? '').trim();
    if (inv.isEmpty) return true;
    if (inv.toUpperCase() == 'ONLINE') return true;
    final oid = (onlineOrderId ?? '').trim();
    if (oid.isNotEmpty && inv == oid) return true;
    // Schema lama: coalesce(no_invoice, online_order_id::text).
    if (_uuidRe.hasMatch(inv)) return true;
    return false;
  }

  static MemberNotificationPayload parse(String raw) {
    final p = raw.trim();
    if (p.startsWith('inv:')) {
      final inv = p.substring(4).trim();
      if (inv.isEmpty || isPlaceholderInvoice(inv)) {
        if (_uuidRe.hasMatch(inv)) {
          return MemberNotificationPayload._(onlineOrderId: inv);
        }
        return const MemberNotificationPayload._(openOrdersList: true);
      }
      return MemberNotificationPayload._(invoice: inv);
    }
    if (p.startsWith('online:')) {
      final id = p.substring(7).trim();
      if (id.isEmpty) {
        return const MemberNotificationPayload._(openOrdersList: true);
      }
      return MemberNotificationPayload._(onlineOrderId: id);
    }
    return const MemberNotificationPayload._(openOrdersList: true);
  }

  /// Bangun payload tap-notif. Invoice palsu (UUID) → `online:`.
  static String? build({String? invoice, String? onlineOrderId}) {
    final inv = (invoice ?? '').trim();
    final oid = (onlineOrderId ?? '').trim();
    if (!isPlaceholderInvoice(inv, onlineOrderId: oid)) {
      return 'inv:$inv';
    }
    if (oid.isNotEmpty) return 'online:$oid';
    if (_uuidRe.hasMatch(inv)) return 'online:$inv';
    return null;
  }

  /// Resolve target dari baris inbox / broadcast (invoice vs online).
  static MemberNotificationPayload resolve({
    String? invoice,
    String? onlineOrderId,
  }) {
    final built = build(invoice: invoice, onlineOrderId: onlineOrderId);
    if (built == null) {
      return const MemberNotificationPayload._(openOrdersList: true);
    }
    return parse(built);
  }
}
