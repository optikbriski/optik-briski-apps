// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/invoice/invoice_hub_service.dart';
import '../../shared/invoice/invoice_link.dart';
import '../../shared/invoice/invoice_rating_card.dart';
import '../../shared/member/member_rating_helpers.dart';
import '../../shared/member/member_repository.dart';
import '../../shared/member/member_session.dart';
import '../../shared/theme.dart';
import 'member_widgets.dart';

/// Rating kasir + pembuat — list pending/history phone-scoped + submit.
class MemberRatingPage extends StatefulWidget {
  const MemberRatingPage({super.key, this.initialInvoice});

  final String? initialInvoice;

  @override
  State<MemberRatingPage> createState() => _MemberRatingPageState();
}

class _MemberRatingPageState extends State<MemberRatingPage>
    with SingleTickerProviderStateMixin {
  final _svc = InvoiceHubService();
  final _repo = MemberRepository();
  final _invoiceCtrl = TextEditingController();
  late final TabController _tabs;

  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic>? _hub;
  bool _listLoading = true;
  bool _hubLoading = false;
  String? _listError;
  String? _hubError;
  String? _selectedInvoice;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final initial = (widget.initialInvoice ?? '').trim();
    if (initial.isNotEmpty) {
      _invoiceCtrl.text = initial;
      _selectedInvoice = initial;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadList();
      if (!mounted) return;
      if (_selectedInvoice != null && _selectedInvoice!.isNotEmpty) {
        await _loadHub(_selectedInvoice!);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _invoiceCtrl.dispose();
    super.dispose();
  }

  String get _phone => MemberSession.instance.phoneForQuery;

  Future<void> _loadList() async {
    if (!MemberSession.instance.isLoggedIn || _phone.isEmpty) {
      setState(() {
        _listLoading = false;
        _listError = 'login';
        _rows = const [];
      });
      return;
    }
    setState(() {
      _listLoading = true;
      _listError = null;
    });
    try {
      final rows = await _repo.listRatings(_phone);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _listLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listLoading = false;
        _listError = e.toString();
      });
    }
  }

  Future<void> _refreshAll() async {
    await _loadList();
    final inv = _selectedInvoice;
    if (inv != null && inv.isNotEmpty) {
      await _loadHub(inv);
    }
  }

  Future<void> _loadHub(String raw) async {
    final inv = InvoiceLink.parse(raw) ?? raw.trim();
    if (inv.isEmpty) {
      setState(() => _hubError = 'invoice_hub_not_invoice'.tr());
      return;
    }
    if (!MemberSession.instance.isLoggedIn || _phone.isEmpty) {
      setState(() {
        _hub = null;
        _hubError = 'login';
      });
      return;
    }
    setState(() {
      _hubLoading = true;
      _hubError = null;
      _selectedInvoice = inv;
      _invoiceCtrl.text = inv;
    });
    try {
      final hub = await _svc.loadByInvoice(inv, phone: _phone);
      if (!mounted) return;
      if (hub == null) {
        setState(() {
          _hubLoading = false;
          _hubError = 'invoice_hub_not_found'.tr();
          _hub = null;
        });
        return;
      }
      // Phone dikirim → wajib milik member yang login.
      if (hub['qr_owner_verified'] != true) {
        setState(() {
          _hubLoading = false;
          _hubError = 'member_rating_not_owner'.tr();
          _hub = null;
        });
        return;
      }
      hub['role_view'] = 'customer';
      setState(() {
        _hub = hub;
        _hubLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hubLoading = false;
        _hubError = e.toString();
        _hub = null;
      });
    }
  }

  Future<void> _submit(String peran, int skor, String? komentar) async {
    final inv = _hub?['no_invoice']?.toString() ?? '';
    if (inv.isEmpty || _phone.isEmpty) return;
    try {
      await _svc.submitRating(
        noInvoice: inv,
        peran: peran,
        skor: skor,
        komentar: komentar,
        phone: _phone,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('invoice_hub_rating_ok'.tr())),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = MemberSession.instance.isLoggedIn;

    return MemberPremiumScaffold(
      title: 'member_rating_title'.tr(),
      subtitle: 'member_rating_tile_sub'.tr(),
      actions: [
        IconButton(
          onPressed: (_listLoading || _hubLoading) ? null : _refreshAll,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'member_rating_refresh'.tr(),
        ),
      ],
      body: !loggedIn || _listError == 'login'
          ? MemberEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'member_rating_login_title'.tr(),
              message: 'member_rating_login_msg'.tr(),
              actionLabel: 'member_rating_go_login'.tr(),
              onAction: () =>
                  Navigator.of(context).pushReplacementNamed('/login'),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    'member_rating_desc'.tr(),
                    style: const TextStyle(
                      color: OptikMemberTokens.inkSecondary,
                      height: 1.45,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Material(
                  color: OptikMemberTokens.canvas,
                  child: TabBar(
                    controller: _tabs,
                    labelColor: OptikMemberTokens.blueDeep,
                    unselectedLabelColor: OptikMemberTokens.inkMuted,
                    indicatorColor: OptikMemberTokens.blue,
                    tabs: [
                      Tab(text: 'member_rating_tab_pending'.tr()),
                      Tab(text: 'member_rating_tab_history'.tr()),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildListPane(
                        pending: true,
                        emptyTitle: 'member_rating_empty_pending_title'.tr(),
                        emptyMsg: 'member_rating_empty_pending_msg'.tr(),
                      ),
                      _buildListPane(
                        pending: false,
                        emptyTitle: 'member_rating_empty_history_title'.tr(),
                        emptyMsg: 'member_rating_empty_history_msg'.tr(),
                      ),
                    ],
                  ),
                ),
                _buildDetailSheet(),
              ],
            ),
    );
  }

  Widget _buildListPane({
    required bool pending,
    required String emptyTitle,
    required String emptyMsg,
  }) {
    if (_listLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_listError != null && _listError != 'login') {
      return MemberEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'member_rating_error_title'.tr(),
        message: _listError!,
        actionLabel: 'member_rating_retry'.tr(),
        onAction: _loadList,
      );
    }

    final filtered = pending
        ? MemberRatingHelpers.pendingOnly(_rows)
        : MemberRatingHelpers.historyOnly(_rows);

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        children: [
          _manualLookupCard(),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: MemberEmptyState(
                icon: pending
                    ? Icons.star_border_rounded
                    : Icons.history_rounded,
                title: emptyTitle,
                message: emptyMsg,
              ),
            )
          else
            ...filtered.map(_invoiceTile),
        ],
      ),
    );
  }

  Widget _manualLookupCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OptikMemberTokens.white,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        border: Border.all(color: OptikMemberTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _invoiceCtrl,
            decoration: InputDecoration(
              labelText: 'member_rating_invoice_label'.tr(),
              prefixIcon: const Icon(Icons.qr_code_2_rounded),
            ),
            onSubmitted: (_) => _loadHub(_invoiceCtrl.text),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _hubLoading ? null : () => _loadHub(_invoiceCtrl.text),
            child: _hubLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('member_rating_load'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _invoiceTile(Map<String, dynamic> row) {
    final inv = row['no_invoice']?.toString() ?? '-';
    final toko = row['toko_id']?.toString() ?? '-';
    final selected = _selectedInvoice == inv;
    final complete = MemberRatingHelpers.isComplete(row);
    final pending = MemberRatingHelpers.isPendingToRate(row);
    final badge = complete
        ? 'member_rating_badge_done'.tr()
        : pending
            ? 'member_rating_badge_pending'.tr()
            : 'member_rating_badge_partial'.tr();
    final badgeColor = complete
        ? OptikMemberTokens.success
        : pending
            ? OptikMemberTokens.warning
            : OptikMemberTokens.blue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: OptikMemberTokens.white,
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
          onTap: () => _loadHub(inv),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
              border: Border.all(
                color: selected
                    ? OptikMemberTokens.blue
                    : OptikMemberTokens.lineSoft,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inv,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: OptikMemberTokens.blueDeep,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        toko,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: OptikMemberTokens.inkMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSheet() {
    if (_hubError == 'login') {
      return const SizedBox.shrink();
    }
    if (_hubError != null && _hub == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        color: OptikMemberTokens.canvas,
        child: Text(
          _hubError!,
          style: const TextStyle(color: OptikMemberTokens.danger, height: 1.35),
        ),
      );
    }
    final h = _hub;
    if (h == null) return const SizedBox.shrink();

    final bisa = h['bisa_rating'] == true;
    final inv = h['no_invoice']?.toString() ?? '-';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.48,
      ),
      decoration: const BoxDecoration(
        color: OptikMemberTokens.white,
        border: Border(top: BorderSide(color: OptikMemberTokens.lineSoft)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  inv,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: OptikMemberTokens.blueDeep,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _hub = null;
                  _hubError = null;
                  _selectedInvoice = null;
                }),
                icon: const Icon(Icons.close_rounded),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ],
          ),
          Text(
            '${h['nama_pelanggan'] ?? '-'} · ${h['toko_id'] ?? '-'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: OptikMemberTokens.inkMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          if (!bisa)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius:
                    BorderRadius.circular(OptikMemberTokens.radiusSm),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Text(
                'invoice_hub_rating_locked'.tr(),
                style: const TextStyle(
                  color: OptikMemberTokens.warning,
                  height: 1.4,
                ),
              ),
            )
          else ...[
            InvoiceRatingCard(
              key: ValueKey('kasir-$inv-${InvoiceHubService.ratingFor(h, 'kasir')?['skor']}'),
              dark: false,
              title: 'invoice_hub_rate_kasir'.tr(),
              nama: h['nama_kasir']?.toString(),
              existing: InvoiceHubService.ratingFor(h, 'kasir'),
              onSubmit: (s, k) => _submit('kasir', s, k),
            ),
            const SizedBox(height: 12),
            InvoiceRatingCard(
              key: ValueKey(
                'pembuat-$inv-${InvoiceHubService.ratingFor(h, 'pembuat')?['skor']}',
              ),
              dark: false,
              title: 'invoice_hub_rate_pembuat'.tr(),
              nama: h['nama_pembuat_kacamata']?.toString(),
              existing: InvoiceHubService.ratingFor(h, 'pembuat'),
              onSubmit: (s, k) => _submit('pembuat', s, k),
            ),
          ],
        ],
      ),
    );
  }
}
