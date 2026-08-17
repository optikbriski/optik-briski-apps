import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../owner_service.dart';
import '../owner_ui.dart';

class OwnerAlertPage extends StatefulWidget {
  const OwnerAlertPage({super.key});

  @override
  State<OwnerAlertPage> createState() => _OwnerAlertPageState();
}

class _OwnerAlertPageState extends State<OwnerAlertPage> {
  final _svc = OwnerService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _svc.listAlerts();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await _svc.markAlertRead(id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Color _sev(String s) {
    switch (s) {
      case 'critical':
        return OptikAdminTokens.danger;
      case 'warning':
        return OptikAdminTokens.warning;
      default:
        return OptikAdminTokens.accentDeep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _rows.where((a) => a['is_read'] != true).length;

    return OwnerPageFrame(
      title: 'Alert',
      subtitle: unread > 0 ? '$unread belum dibaca' : 'Semua sudah dibaca',
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: OptikAdminTokens.navy))
          : _error != null
              ? OwnerEmptyState(_error!, icon: Icons.error_outline_rounded)
              : _rows.isEmpty
                  ? const OwnerEmptyState(
                      'Belum ada alert untuk cabang Anda.',
                      icon: Icons.notifications_none_rounded,
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      children: [
                        for (final a in _rows)
                          OwnerListCard(
                            accent: _sev((a['severity'] ?? 'info').toString()),
                            title: (a['title'] ?? '-').toString(),
                            subtitle:
                                '${a['toko_id'] ?? 'Semua'} · ${a['category'] ?? '-'}\n${a['body'] ?? ''}',
                            onTap: a['is_read'] == true || '${a['id']}'.isEmpty
                                ? null
                                : () => _markRead('${a['id']}'),
                            trailing: a['is_read'] == true
                                ? null
                                : Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: OptikAdminTokens.danger,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                          ),
                      ],
                    ),
    );
  }
}
