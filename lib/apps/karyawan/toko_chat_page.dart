import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/admin/admin_nav_badge_service.dart';
import '../../shared/karyawan/toko_chat_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

class TokoChatPage extends StatefulWidget {
  const TokoChatPage({
    super.key,
    this.tokoId,
    this.senderNama,
    this.karyawanId,
    this.adminMode = false,
  });

  final String? tokoId;
  final String? senderNama;
  final String? karyawanId;
  final bool adminMode;

  @override
  State<TokoChatPage> createState() => _TokoChatPageState();
}

class _TokoChatPageState extends State<TokoChatPage> {
  final _svc = TokoChatService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  RealtimeChannel? _ch;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _tokoId;
  String _nama = 'Admin';
  String? _karyawanId;
  List<Map<String, dynamic>> _tokoOptions = [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _ch?.unsubscribe();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      var toko = (widget.tokoId ?? '').trim();
      var nama = (widget.senderNama ?? '').trim();
      var kid = widget.karyawanId;
      if (toko.isEmpty || kid == null) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          var me = await Supabase.instance.client
              .from('karyawan')
              .select('id, toko_id, nama')
              .eq('id', user.id)
              .maybeSingle();
          me ??= user.email == null
              ? null
              : await Supabase.instance.client
                  .from('karyawan')
                  .select('id, toko_id, nama')
                  .eq('email', user.email!)
                  .maybeSingle();
          if (me != null) {
            toko = toko.isEmpty ? (me['toko_id']?.toString() ?? '') : toko;
            nama = nama.isEmpty ? (me['nama']?.toString() ?? '') : nama;
            kid ??= me['id']?.toString();
          }
        }
      }
      if (nama.isEmpty) nama = widget.adminMode ? 'Admin' : 'Karyawan';
      _nama = nama;
      _karyawanId = kid;
      if (toko.isEmpty && widget.adminMode) {
        final rows = await Supabase.instance.client
            .from('toko_id')
            .select('id, toko_id')
            .order('id');
        _tokoOptions = List<Map<String, dynamic>>.from(rows as List);
      }
      _tokoId = toko.isEmpty ? null : toko;
      if (_tokoId != null && _tokoId!.isNotEmpty) {
        await _bindToko(_tokoId!);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    _jump();
  }

  Future<void> _bindToko(String toko) async {
    await _ch?.unsubscribe();
    _ch = null;
    _rows = await _svc.listRecent(toko);
    _ch = _svc.subscribe(toko, (row) {
      if (!mounted) return;
      final id = row['id']?.toString();
      if (id != null && _rows.any((e) => e['id']?.toString() == id)) return;
      setState(() => _rows = [..._rows, row]);
      _jump();
    });
    if (mounted) setState(() {});
    _jump();
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _kirim() async {
    final toko = _tokoId;
    if (toko == null || toko.isEmpty) return;
    final text = _input.text;
    _input.clear();
    try {
      await _svc.send(
        tokoId: toko,
        nama: _nama,
        isi: text,
        karyawanId: _karyawanId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.adminMode;
    final body = Column(
      children: [
        if (admin && _tokoOptions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: DropdownButtonFormField<String>(
              value: _tokoId,
              decoration: InputDecoration(labelText: 'ops_chat_pilih_toko'.tr()),
              items: [
                for (final t in _tokoOptions)
                  DropdownMenuItem(
                    value: t['id']?.toString(),
                    child: Text(
                      '${t['toko_id'] ?? t['id']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) async {
                if (v == null || v.isEmpty) return;
                setState(() {
                  _tokoId = v;
                  _rows = [];
                });
                await _bindToko(v);
              },
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_tokoId == null || _tokoId!.isEmpty)
                  ? Center(child: Text('ops_chat_pilih_toko'.tr()))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        final sid = r['sender_karyawan_id']?.toString();
                        final mine = _karyawanId != null
                            ? sid == _karyawanId
                            : admin &&
                                sid == null &&
                                (r['sender_nama']?.toString() == _nama);
                        final when = DateTime.tryParse('${r['created_at']}');
                        final fromKaryawan =
                            sid != null && sid.isNotEmpty && !mine;
                        Widget bubble = Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? (admin
                                      ? OptikAdminTokens.ice.withOpacity(0.35)
                                      : OptikKaryawanTokens.cyan
                                          .withOpacity(0.22))
                                  : (admin
                                      ? OptikAdminTokens.card
                                      : OptikKaryawanTokens.surface),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: admin
                                    ? OptikAdminTokens.chromeEdge
                                    : OptikKaryawanTokens.border,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r['sender_nama'] ?? '-'}'
                                  '${when == null ? '' : ' · ${DateFormat('HH:mm').format(when.toLocal())}'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: admin
                                        ? OptikAdminTokens.slate
                                        : OptikKaryawanTokens.muted,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${r['isi'] ?? ''}',
                                  style: TextStyle(
                                    color: admin
                                        ? OptikAdminTokens.navy
                                        : OptikKaryawanTokens.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (admin && fromKaryawan) {
                          final mid = r['id']?.toString() ?? '';
                          if (mid.isNotEmpty) {
                            bubble = _AdminChatSeenMarker(
                              messageId: mid,
                              child: bubble,
                            );
                          }
                        }
                        return bubble;
                      },
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    enabled: _tokoId != null && _tokoId!.isNotEmpty,
                    decoration: InputDecoration(
                      hintText: 'ops_chat_hint'.tr(),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _kirim,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (admin) {
      return PremiumScaffold(
        appBar: PremiumAppBar(
          title: 'ops_chat_title'.tr(),
          subtitle: _tokoId,
        ),
        body: body,
      );
    }

    return Scaffold(
      backgroundColor: OptikKaryawanTokens.scaffold,
      appBar: AppBar(
        title: Text(
          _tokoId == null || _tokoId!.isEmpty
              ? 'ops_chat_title'.tr()
              : '${'ops_chat_title'.tr()} · $_tokoId',
        ),
      ),
      body: body,
    );
  }
}

class _AdminChatSeenMarker extends StatefulWidget {
  const _AdminChatSeenMarker({
    required this.messageId,
    required this.child,
  });

  final String messageId;
  final Widget child;

  @override
  State<_AdminChatSeenMarker> createState() => _AdminChatSeenMarkerState();
}

class _AdminChatSeenMarkerState extends State<_AdminChatSeenMarker> {
  @override
  void initState() {
    super.initState();
    unawaited(AdminNavBadgeService.instance
        .markEntitySeen('chat_toko', widget.messageId));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
