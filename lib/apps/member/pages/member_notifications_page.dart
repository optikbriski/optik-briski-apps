import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/member/member_inbox_unread.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/member/member_status_watch.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_inbox_detail_page.dart';

enum _InboxTab { messages, promos }

/// Inbox / Notif Member — daftar alert + promo + toggle status watch.
class MemberNotificationsPage extends StatefulWidget {
  const MemberNotificationsPage({super.key});

  @override
  State<MemberNotificationsPage> createState() =>
      _MemberNotificationsPageState();
}

class _MemberNotificationsPageState extends State<MemberNotificationsPage> {
  final _repo = MemberRepository();
  _InboxTab _tab = _InboxTab.messages;
  bool _loading = true;
  bool _watchOn = true;
  String? _error;
  List<Map<String, dynamic>> _alerts = const [];
  List<Map<String, dynamic>> _promos = const [];

  @override
  void initState() {
    super.initState();
    MemberInboxUnread.instance.addListener(_onUnread);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final on = await MemberStatusWatch.instance.isEnabled();
    if (!mounted) return;
    setState(() => _watchOn = on);
    if (MemberSession.instance.isLoggedIn && on) {
      await MemberStatusWatch.instance.start();
    }
    await _load();
  }

  @override
  void dispose() {
    MemberInboxUnread.instance.removeListener(_onUnread);
    super.dispose();
  }

  void _onUnread() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final phone = MemberSession.instance.phoneForQuery;
      final alertsFut = phone.isNotEmpty
          ? _repo.listOrderAlerts(phone: phone)
          : Future.value(const <Map<String, dynamic>>[]);
      final promosFut = _repo.listPromos();

      final alerts = await alertsFut;
      final promos = await promosFut;
      await MemberInboxUnread.instance.refresh();
      MemberInboxUnread.instance.syncFromAlertIds(
        alerts.map((a) => '${a['id'] ?? ''}'),
      );
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _promos = promos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  int get _unreadAlertCount => MemberInboxUnread.instance.count;

  List<_InboxItem> get _items {
    final out = <_InboxItem>[];
    if (_tab == _InboxTab.messages) {
      for (final a in _alerts) {
        final id = '${a['id'] ?? ''}';
        final created = DateTime.tryParse('${a['created_at'] ?? ''}');
        out.add(_InboxItem(
          kind: _InboxKind.alert,
          id: id,
          title: (a['title'] ?? 'Update pesanan').toString(),
          body: (a['body'] ?? '').toString(),
          createdAt: created,
          unread: MemberInboxUnread.instance.isUnread(id),
          imageUrl: null,
          raw: a,
        ));
      }
    } else {
      for (final p in _promos) {
        final id = 'promo-${p['id'] ?? ''}';
        final until = DateTime.tryParse('${p['valid_until'] ?? ''}');
        final created = DateTime.tryParse('${p['created_at'] ?? ''}');
        final img = (p['image_url'] ?? '').toString().trim();
        out.add(_InboxItem(
          kind: _InboxKind.promo,
          id: id,
          title: (p['title'] ?? 'Promo').toString(),
          body: (p['description'] ?? p['terms'] ?? '').toString(),
          createdAt: created ?? until,
          unread: false,
          imageUrl: img.isEmpty ? null : img,
          raw: p,
        ));
      }
    }
    out.sort((a, b) {
      final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
    return out;
  }

  Future<void> _openDetail(_InboxItem item) async {
    if (item.kind == _InboxKind.alert) {
      await MemberInboxUnread.instance.markRead(item.id);
    }
    if (!mounted) return;
    final p = item.raw;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberInboxDetailPage(
          title: item.title,
          body: item.body,
          imageUrl: item.imageUrl,
          createdAt: item.createdAt,
          isPromo: item.kind == _InboxKind.promo,
          voucherCode: (p['voucher_code'] ?? '').toString(),
          validUntil: (p['valid_until'] ?? '').toString(),
          terms: (p['terms'] ?? '').toString(),
          noInvoice: (p['no_invoice'] ?? '').toString(),
          onlineOrderId: (p['online_order_id'] ?? '').toString(),
          kind: (p['kind'] ?? '').toString(),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  String _fmtListDate(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('d MMM yyyy', context.locale.toString())
        .format(dt.toLocal());
  }

  Future<void> _toggleWatch() async {
    final next = !_watchOn;
    setState(() => _watchOn = next);
    await MemberStatusWatch.instance.setEnabled(next);
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = MemberSession.instance.isLoggedIn;
    final items = _items;
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topPad + 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.chevron_left_rounded, size: 32),
                  color: OptikMemberTokens.ink,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'member_inbox_refresh'.tr(),
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  color: OptikMemberTokens.inkMuted,
                ),
                IconButton(
                  tooltip: 'member_inbox_watch_title'.tr(),
                  onPressed: loggedIn ? _toggleWatch : null,
                  icon: Icon(
                    _watchOn
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_outlined,
                    color: !loggedIn
                        ? OptikMemberTokens.inkMuted.withOpacity(0.45)
                        : (_watchOn
                            ? OptikMemberTokens.blue
                            : OptikMemberTokens.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'member_inbox_title'.tr(),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: OptikMemberTokens.ink,
                height: 1.1,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              _watchOn
                  ? 'member_inbox_watch_sub'.tr()
                  : 'member_inbox_watch_title'.tr(),
              style: const TextStyle(
                fontSize: 13,
                color: OptikMemberTokens.inkMuted,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _TabLabel(
                  label: 'member_inbox_tab_messages'.tr(),
                  selected: _tab == _InboxTab.messages,
                  badge: _unreadAlertCount,
                  onTap: () => setState(() => _tab = _InboxTab.messages),
                ),
                _TabLabel(
                  label: 'member_inbox_tab_promos'.tr(),
                  selected: _tab == _InboxTab.promos,
                  badge: 0,
                  onTap: () => setState(() => _tab = _InboxTab.promos),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE8EEF5)),
          Expanded(
            child: !loggedIn && _tab == _InboxTab.messages
                ? MemberEmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'member_inbox_login_title'.tr(),
                    message: 'member_inbox_login_msg'.tr(),
                    actionLabel: 'member_inbox_login_action'.tr(),
                    onAction: () =>
                        Navigator.of(context).pushReplacementNamed('/login'),
                  )
                : _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: OptikMemberTokens.blue,
                        ),
                      )
                    : _error != null
                        ? MemberEmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: 'member_inbox_error_title'.tr(),
                            message: _error!,
                            actionLabel: 'member_inbox_retry'.tr(),
                            onAction: _load,
                          )
                        : items.isEmpty
                            ? MemberEmptyState(
                                icon: Icons.inbox_outlined,
                                title: 'member_inbox_empty_title'.tr(),
                                message: _tab == _InboxTab.messages
                                    ? 'member_inbox_empty_messages'.tr()
                                    : 'member_inbox_empty_promos'.tr(),
                                actionLabel: 'member_inbox_refresh'.tr(),
                                onAction: _load,
                              )
                            : RefreshIndicator(
                                color: OptikMemberTokens.blue,
                                onRefresh: _load,
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    28,
                                  ),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Color(0xFFF0F4F8),
                                  ),
                                  itemBuilder: (context, i) {
                                    final item = items[i];
                                    return _InboxRow(
                                      item: item,
                                      dateLabel: _fmtListDate(item.createdAt),
                                      onTap: () => _openDetail(item),
                                    );
                                  },
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}

enum _InboxKind { alert, promo }

class _InboxItem {
  const _InboxItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.unread,
    required this.imageUrl,
    required this.raw,
  });

  final _InboxKind kind;
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool unread;
  final String? imageUrl;
  final Map<String, dynamic> raw;
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? OptikMemberTokens.ink
                        : OptikMemberTokens.inkMuted,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.blue,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 3,
              width: selected ? 28 + label.length * 4.0 : 0,
              decoration: BoxDecoration(
                color: OptikMemberTokens.blue,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({
    required this.item,
    required this.dateLabel,
    required this.onTap,
  });

  final _InboxItem item;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPromo = item.kind == _InboxKind.promo;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(
              imageUrl: item.imageUrl,
              isPromo: isPromo,
              kind: (item.raw['kind'] ?? '').toString(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: item.unread
                                ? FontWeight.w800
                                : FontWeight.w400,
                            color: OptikMemberTokens.ink,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (dateLabel.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: OptikMemberTokens.inkMuted,
                            fontWeight: item.unread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: OptikMemberTokens.inkMuted,
                              fontWeight: item.unread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (item.unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: OptikMemberTokens.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ] else if (item.unread)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: OptikMemberTokens.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.imageUrl,
    required this.isPromo,
    required this.kind,
  });

  final String? imageUrl;
  final bool isPromo;
  final String kind;

  IconData get _icon {
    if (isPromo) return Icons.local_offer_rounded;
    final k = kind.toLowerCase();
    if (k.contains('ready') || k.contains('siap')) {
      return Icons.checkroom_rounded;
    }
    if (k.contains('payment') || k.contains('lunas')) {
      return Icons.payments_outlined;
    }
    if (k.contains('qr')) return Icons.qr_code_2_rounded;
    return Icons.receipt_long_rounded;
  }

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(size),
        ),
      );
    }
    return _fallback(size);
  }

  Widget _fallback(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isPromo
            ? const Color(0xFFE8F1FF)
            : OptikMemberTokens.blueMist,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _icon,
        color: OptikMemberTokens.blue,
        size: 28,
      ),
    );
  }
}
