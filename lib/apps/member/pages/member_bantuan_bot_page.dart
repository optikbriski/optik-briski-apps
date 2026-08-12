import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../shared/member/member_help_bot_intent.dart';
import '../../../shared/member/member_help_bot_service.dart';
import '../../../shared/member/member_help_nearest_store.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_product_detail_sheet.dart';

class _StoreChipData {
  const _StoreChipData({
    required this.tokoId,
    required this.label,
    required this.store,
  });

  final String tokoId;
  final String label;
  final Map<String, dynamic> store;
}

class _ChatMsg {
  _ChatMsg({
    required this.text,
    required this.fromUser,
    this.escalateWa = false,
    this.chipLabel,
    this.storeChips = const [],
    this.stockProducts = const [],
    this.stockVisibleCount = kMemberHelpStockUiInitial,
    this.stockTotalInStock = 0,
  });

  final String text;
  final bool fromUser;
  final bool escalateWa;
  final String? chipLabel;
  final List<_StoreChipData> storeChips;
  final List<MemberHelpStockMatch> stockProducts;
  int stockVisibleCount;
  final int stockTotalInStock;

  bool get stockCanExpandLocal =>
      stockProducts.isNotEmpty && stockVisibleCount < stockProducts.length;

  bool get stockHasMoreAtBranch =>
      stockTotalInStock > stockProducts.length;
}

/// Member Bantuan — store gate first, then chips + Gemini free-text + WA.
class MemberBantuanBotPage extends StatefulWidget {
  const MemberBantuanBotPage({super.key});

  @override
  State<MemberBantuanBotPage> createState() => _MemberBantuanBotPageState();
}

class _MemberBantuanBotPageState extends State<MemberBantuanBotPage> {
  final _service = MemberHelpBotService();
  final _input = TextEditingController();
  final _storeSearch = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMsg>[];
  bool _busy = false;
  String? _lastQuestion;

  /// After GPS fails on WA CTA — next free-text is treated as area/city.
  bool _awaitingStatedLocation = false;
  int _locationAskAttempts = 0;

  /// Store picker gate — chat locked until confirmed.
  bool _pickerVisible = true;
  bool _storesLoading = true;
  String? _storesError;
  List<Map<String, dynamic>> _stores = const [];
  String? _draftTokoId;
  Map<String, dynamic>? _selectedStore;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  @override
  void dispose() {
    _input.dispose();
    _storeSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _locale =>
      context.locale.languageCode.isNotEmpty
          ? context.locale.languageCode
          : MemberSession.instance.locale;

  String? get _selectedTokoId {
    final id = (_selectedStore?['toko_id'] ?? '').toString().trim().toUpperCase();
    return id.isEmpty ? null : id;
  }

  String get _selectedStoreLabel {
    final s = _selectedStore;
    if (s == null) return '';
    return _storeChipLabel(s);
  }

  Future<void> _loadStores() async {
    setState(() {
      _storesLoading = true;
      _storesError = null;
    });
    try {
      final list = await _service.loadStoreDirectory();
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _stores = const [];
          _storesLoading = false;
          _storesError = 'member_help_store_list_empty'.tr();
        });
        return;
      }
      final preferred =
          (MemberSession.instance.preferredTokoId ?? '').trim().toUpperCase();
      final preferredExists = preferred.isNotEmpty &&
          findStoreByTokoId(preferred, list) != null;
      setState(() {
        _stores = list;
        _storesLoading = false;
        _storesError = null;
        _draftTokoId = preferredExists
            ? preferred
            : (_draftTokoId != null &&
                    findStoreByTokoId(_draftTokoId, list) != null
                ? _draftTokoId
                : null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _storesLoading = false;
        _storesError = 'member_help_store_list_error'
            .tr(namedArgs: {'error': '$e'});
      });
    }
  }

  void _confirmStoreSelection() {
    final draft = (_draftTokoId ?? '').trim().toUpperCase();
    if (draft.isEmpty) return;
    final store = findStoreByTokoId(draft, _stores);
    if (store == null) return;

    setState(() {
      _selectedStore = Map<String, dynamic>.from(store);
      _pickerVisible = false;
      _awaitingStatedLocation = false;
      _locationAskAttempts = 0;
      _storeSearch.clear();
      // Fresh welcome scoped to the confirmed cabang (also on ganti cabang).
      _messages
        ..clear()
        ..add(
          _ChatMsg(
            text: 'member_help_welcome_for_store'.tr(
              namedArgs: {'store': _storeChipLabel(store)},
            ),
            fromUser: false,
          ),
        );
    });
  }

  void _openStorePicker({bool changing = false}) {
    setState(() {
      _pickerVisible = true;
      _storeSearch.clear();
      _draftTokoId = _selectedTokoId ??
          (MemberSession.instance.preferredTokoId ?? '').trim().toUpperCase();
      if (_draftTokoId != null &&
          findStoreByTokoId(_draftTokoId, _stores) == null) {
        _draftTokoId = null;
      }
      if (changing && _stores.isEmpty && !_storesLoading) {
        _loadStores();
      }
    });
  }

  void _cancelStorePicker() {
    if (_selectedStore == null) return;
    setState(() {
      _pickerVisible = false;
      _draftTokoId = _selectedTokoId;
      _storeSearch.clear();
    });
  }

  List<Map<String, dynamic>> _filteredStores() {
    final q = _storeSearch.text.trim().toLowerCase();
    if (q.isEmpty) return _stores;
    return _stores.where((s) {
      final id = (s['toko_id'] ?? '').toString().toLowerCase();
      final name = (s['shop_name'] ?? '').toString().toLowerCase();
      final addr = (s['address'] ?? '').toString().toLowerCase();
      return id.contains(q) || name.contains(q) || addr.contains(q);
    }).toList(growable: false);
  }

  String _chipLabel(MemberHelpChipId id) {
    switch (id) {
      case MemberHelpChipId.orderStatus:
        return 'member_help_chip_order'.tr();
      case MemberHelpChipId.pointsGrade:
        return 'member_help_chip_points'.tr();
      case MemberHelpChipId.storeInfo:
        return 'member_help_chip_store'.tr();
      case MemberHelpChipId.labQueue:
        return 'member_help_chip_lab_queue'.tr();
      case MemberHelpChipId.stok:
        return 'member_help_chip_stok'.tr();
      case MemberHelpChipId.careWarranty:
        return 'member_help_chip_care'.tr();
      case MemberHelpChipId.contactWa:
        return 'member_help_chip_wa'.tr();
    }
  }

  String _storeChipLabel(Map<String, dynamic> s) {
    final id = (s['toko_id'] ?? '').toString().trim();
    final name = (s['shop_name'] ?? '').toString().trim();
    if (id.isNotEmpty && name.isNotEmpty) return '$id · $name';
    if (id.isNotEmpty) return id;
    if (name.isNotEmpty) return name;
    return 'Cabang';
  }

  List<_StoreChipData> _toStoreChips(List<Map<String, dynamic>> stores) {
    return stores
        .map(
          (s) => _StoreChipData(
            tokoId: (s['toko_id'] ?? '').toString().trim(),
            label: _storeChipLabel(s),
            store: s,
          ),
        )
        .where((c) => c.tokoId.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _scrollToEnd() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _runChip(MemberHelpChipId chip) async {
    if (_busy || _selectedTokoId == null) return;
    // Starting a FAQ chip cancels pending location ask.
    if (_awaitingStatedLocation && chip != MemberHelpChipId.contactWa) {
      _awaitingStatedLocation = false;
      _locationAskAttempts = 0;
    }
    final label = _chipLabel(chip);
    setState(() {
      _busy = true;
      _messages.add(_ChatMsg(text: label, fromUser: true, chipLabel: label));
      _lastQuestion = label;
    });
    await _scrollToEnd();

    try {
      // Contact WA chip: auto-resolve XOR (selected / GPS | ask area).
      if (chip == MemberHelpChipId.contactWa) {
        await _resolveWaContactIntent(
          lastQuestion: label,
          messageForArea: '',
          manageBusy: false,
        );
        return;
      }

      final reply = await _service.handleChip(
        chip,
        locale: _locale,
        preferredTokoId: _selectedTokoId,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_botMsgFromReply(reply));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMsg(
            text: 'member_help_error'.tr(namedArgs: {'error': '$e'}),
            fromUser: false,
            escalateWa: true,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      await _scrollToEnd();
    }
  }

  _ChatMsg _botMsgFromReply(
    MemberHelpBotReply reply, {
    bool? escalateWaOverride,
  }) {
    final products = reply.stockProducts;
    final initial = products.isEmpty
        ? 0
        : (products.length < kMemberHelpStockUiInitial
            ? products.length
            : kMemberHelpStockUiInitial);
    return _ChatMsg(
      text: reply.reply,
      fromUser: false,
      escalateWa: escalateWaOverride ?? reply.escalateWa,
      stockProducts: products,
      stockVisibleCount: initial,
      stockTotalInStock: reply.stockTotalInStock,
    );
  }

  Future<void> _openStockProduct(MemberHelpStockMatch m) async {
    if (_busy) return;
    await openMemberProductDetailBySku(
      context,
      sku: m.sku,
      tokoId: _selectedTokoId,
    );
  }

  void _expandStockProducts(_ChatMsg msg) {
    if (!msg.stockCanExpandLocal) return;
    setState(() {
      final next = msg.stockVisibleCount + kMemberHelpStockUiPage;
      msg.stockVisibleCount =
          next > msg.stockProducts.length ? msg.stockProducts.length : next;
    });
    _scrollToEnd();
  }

  Future<void> _sendText() async {
    if (_busy || _selectedTokoId == null) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();

    if (_awaitingStatedLocation) {
      await _handleStatedLocation(text);
      return;
    }

    setState(() {
      _busy = true;
      _messages.add(_ChatMsg(text: text, fromUser: true));
      _lastQuestion = text;
    });
    await _scrollToEnd();

    try {
      // Free-text WA contact — client owns XOR UX (no Edge escalate bubble).
      if (memberHelpWantsWhatsAppContact(text)) {
        await _resolveWaContactIntent(
          lastQuestion: text,
          messageForArea: text,
          manageBusy: false,
        );
        return;
      }

      final reply = await _service.askFreeText(
        text,
        locale: _locale,
        preferredTokoId: _selectedTokoId,
      );
      if (!mounted) return;

      // Edge contactWa: auto-resolve without CTA (same XOR path).
      if (reply.intent == MemberHelpIntent.contactWa) {
        await _resolveWaContactIntent(
          lastQuestion: text,
          messageForArea: text,
          manageBusy: false,
        );
        return;
      }

      setState(() {
        _messages.add(
          _botMsgFromReply(
            reply,
            escalateWaOverride: memberHelpShouldShowWaEscalateCta(
              escalateWaFlag: reply.escalateWa,
              autoResolvingContactWa: false,
            ),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMsg(
            text: 'member_help_error'.tr(namedArgs: {'error': '$e'}),
            fromUser: false,
            escalateWa: true,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      await _scrollToEnd();
    }
  }

  /// Contact-WA resolve — one outcome only (XOR):
  /// explicit area chips/open → else selected-store WA → else GPS open →
  /// else ask location only.
  Future<void> _resolveWaContactIntent({
    required String lastQuestion,
    String? messageForArea,
    bool manageBusy = true,
  }) async {
    if (manageBusy) setState(() => _busy = true);
    try {
      final areaQuery = memberHelpExtractAreaQuery(messageForArea ?? '');
      if (areaQuery.isNotEmpty) {
        // Named area/cabang overrides selected store + GPS nearest.
        final result = await _service.resolveFromStatedLocation(areaQuery);
        if (!mounted) return;

        if (result.target != null) {
          setState(() {
            _awaitingStatedLocation = false;
            _locationAskAttempts = 0;
            final shop =
                result.target!.shopName ?? result.target!.tokoId ?? '';
            _messages.add(
              _ChatMsg(
                text: 'member_help_location_matched'
                    .tr(namedArgs: {'store': shop}),
                fromUser: false,
              ),
            );
          });
          await _launchTarget(result.target!);
          return;
        }

        if (!result.noTextMatch && result.candidates.isNotEmpty) {
          setState(() {
            _awaitingStatedLocation = true;
            _locationAskAttempts = 0;
            _messages.add(
              _ChatMsg(
                text: 'member_help_pick_store'.tr(),
                fromUser: false,
                storeChips: _toStoreChips(result.candidates),
              ),
            );
          });
          return;
        }

        // Explicit area named but unmatched — never fall back to GPS nearest.
        setState(() {
          _awaitingStatedLocation = true;
          _locationAskAttempts = 0;
          _messages.add(
            _ChatMsg(
              text: 'member_help_location_no_match'.tr(),
              fromUser: false,
              storeChips: _toStoreChips(result.candidates),
            ),
          );
        });
        return;
      }

      // No area name → selected store WA, else GPS nearest OR ask location.
      final prepared = await _service.tryOpenEscalationWhatsApp(
        lastQuestion: lastQuestion,
        selectedTokoId: _selectedTokoId,
      );
      if (!mounted) return;

      if (prepared.kind == MemberHelpWaPrepareKind.ready) {
        setState(() {
          _awaitingStatedLocation = false;
          _locationAskAttempts = 0;
          final shop =
              prepared.target?.shopName ?? prepared.target?.tokoId ?? '';
          if (shop.isNotEmpty) {
            _messages.add(
              _ChatMsg(
                text: 'member_help_location_matched'
                    .tr(namedArgs: {'store': shop}),
                fromUser: false,
              ),
            );
          }
        });
        return;
      }

      setState(() {
        _awaitingStatedLocation = true;
        _locationAskAttempts = 0;
        _messages.add(
          _ChatMsg(
            text: 'member_help_ask_location'.tr(),
            fromUser: false,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
    } finally {
      if (manageBusy && mounted) setState(() => _busy = false);
      await _scrollToEnd();
    }
  }

  Future<void> _handleStatedLocation(String text) async {
    setState(() {
      _busy = true;
      _messages.add(_ChatMsg(text: text, fromUser: true));
      _locationAskAttempts += 1;
    });
    await _scrollToEnd();

    try {
      final result = await _service.resolveFromStatedLocation(text);
      if (!mounted) return;

      if (result.target != null) {
        setState(() {
          _awaitingStatedLocation = false;
          _locationAskAttempts = 0;
          final shop = result.target!.shopName ?? result.target!.tokoId ?? '';
          _messages.add(
            _ChatMsg(
              text: 'member_help_location_matched'
                  .tr(namedArgs: {'store': shop}),
              fromUser: false,
            ),
          );
        });
        await _launchTarget(result.target!);
        return;
      }

      if (!result.noTextMatch && result.candidates.isNotEmpty) {
        setState(() {
          _messages.add(
            _ChatMsg(
              text: 'member_help_pick_store'.tr(),
              fromUser: false,
              storeChips: _toStoreChips(result.candidates),
            ),
          );
        });
        return;
      }

      // No text match — offer top cabang chips; after 2 tries → selected/preferred.
      if (_locationAskAttempts >= 2) {
        setState(() {
          _awaitingStatedLocation = false;
          _messages.add(
            _ChatMsg(
              text: 'member_help_location_fallback'.tr(),
              fromUser: false,
            ),
          );
        });
        final fallback = await _service.resolveFallbackWhatsAppTarget(
          preferredTokoId: _selectedTokoId,
        );
        if (!mounted) return;
        await _launchTarget(fallback);
        _locationAskAttempts = 0;
        return;
      }

      setState(() {
        _messages.add(
          _ChatMsg(
            text: 'member_help_location_no_match'.tr(),
            fromUser: false,
            storeChips: _toStoreChips(result.candidates),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMsg(
            text: 'member_help_error'.tr(namedArgs: {'error': '$e'}),
            fromUser: false,
            escalateWa: true,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      await _scrollToEnd();
    }
  }

  /// CTA tap (live escalate) — selected / GPS / ask only; no dual escalate bubble.
  Future<void> _openWa({String? lastQuestion}) async {
    await _resolveWaContactIntent(
      lastQuestion: lastQuestion ?? _lastQuestion ?? '',
      messageForArea: '',
      manageBusy: !_busy,
    );
  }

  Future<void> _onStoreChipTap(_StoreChipData chip) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _awaitingStatedLocation = false;
      _locationAskAttempts = 0;
      _messages.add(
        _ChatMsg(text: chip.label, fromUser: true, chipLabel: chip.label),
      );
    });
    await _scrollToEnd();
    try {
      final target = _service.targetFromStoreMap(chip.store);
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMsg(
            text: 'member_help_location_matched'
                .tr(namedArgs: {'store': chip.label}),
            fromUser: false,
          ),
        );
      });
      await _launchTarget(target);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      await _scrollToEnd();
    }
  }

  Future<void> _launchTarget(MemberHelpWaTarget target) async {
    await _service.openWhatsAppForTarget(
      target,
      lastQuestion: _lastQuestion,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatUnlocked = !_pickerVisible && _selectedStore != null;

    final canCancelPicker = _pickerVisible && _selectedStore != null;

    return MemberPremiumScaffold(
      title: 'member_help_title'.tr(),
      subtitle: chatUnlocked
          ? _selectedStoreLabel
          : 'member_help_subtitle'.tr(),
      resizeToAvoidBottomInset: true,
      leading: canCancelPicker
          ? IconButton(
              tooltip: 'member_help_pick_store_cancel'.tr(),
              onPressed: _cancelStorePicker,
              icon: const Icon(Icons.close_rounded),
            )
          : null,
      actions: chatUnlocked
          ? [
              TextButton(
                onPressed: _busy ? null : () => _openStorePicker(changing: true),
                child: Text(
                  'member_help_change_store'.tr(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ]
          : canCancelPicker
              ? [
                  TextButton(
                    onPressed: _cancelStorePicker,
                    child: Text(
                      'member_help_pick_store_cancel'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ]
              : null,
      body: _pickerVisible ? _buildStorePicker() : _buildChat(),
    );
  }

  Widget _buildStorePicker() {
    final preferred =
        (MemberSession.instance.preferredTokoId ?? '').trim().toUpperCase();
    final canContinue = (_draftTokoId ?? '').trim().isNotEmpty;
    final filtered = _filteredStores();
    final hasQuery = _storeSearch.text.trim().isNotEmpty;
    final searchRadius = BorderRadius.circular(OptikMemberTokens.radiusMd);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: OptikMemberTokens.white,
                  borderRadius:
                      BorderRadius.circular(OptikMemberTokens.radiusMd),
                  border: Border.all(color: OptikMemberTokens.lineSoft),
                  boxShadow: OptikMemberTokens.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'member_help_pick_store_title'.tr(),
                      style: const TextStyle(
                        color: OptikMemberTokens.blueDeep,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'member_help_pick_store_subtitle'.tr(),
                      style: const TextStyle(
                        color: OptikMemberTokens.inkSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (!_storesLoading && _storesError == null) ...[
                TextField(
                  controller: _storeSearch,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    color: OptikMemberTokens.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'member_help_pick_store_search_hint'.tr(),
                    hintStyle: const TextStyle(
                      color: OptikMemberTokens.inkMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: OptikMemberTokens.blue,
                    ),
                    suffixIcon: hasQuery
                        ? IconButton(
                            onPressed: () {
                              _storeSearch.clear();
                              setState(() {});
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                              color: OptikMemberTokens.inkMuted,
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: OptikMemberTokens.blueMist,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: searchRadius,
                      borderSide: const BorderSide(
                        color: OptikMemberTokens.lineSoft,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: searchRadius,
                      borderSide: const BorderSide(
                        color: OptikMemberTokens.lineSoft,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: searchRadius,
                      borderSide: const BorderSide(
                        color: OptikMemberTokens.blue,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_storesLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_storesError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.white,
                    borderRadius:
                        BorderRadius.circular(OptikMemberTokens.radiusMd),
                    border: Border.all(
                      color: OptikMemberTokens.danger.withOpacity(0.25),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _storesError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: OptikMemberTokens.ink,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _loadStores,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text('member_help_store_list_retry'.tr()),
                      ),
                    ],
                  ),
                )
              else if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text(
                      'member_help_pick_store_search_empty'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else
                ...filtered.map((s) {
                  final id =
                      (s['toko_id'] ?? '').toString().trim().toUpperCase();
                  final selected = id == (_draftTokoId ?? '').toUpperCase();
                  final isPreferred = preferred.isNotEmpty && id == preferred;
                  final addr = (s['address'] ?? '').toString().trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: selected
                          ? OptikMemberTokens.blueSoft
                          : OptikMemberTokens.white,
                      borderRadius:
                          BorderRadius.circular(OptikMemberTokens.radiusMd),
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(OptikMemberTokens.radiusMd),
                        onTap: () => setState(() => _draftTokoId = id),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              OptikMemberTokens.radiusMd,
                            ),
                            border: Border.all(
                              color: selected
                                  ? OptikMemberTokens.blue
                                  : OptikMemberTokens.lineSoft,
                              width: selected ? 1.6 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                size: 22,
                                color: selected
                                    ? OptikMemberTokens.blue
                                    : OptikMemberTokens.inkMuted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _storeChipLabel(s),
                                            style: TextStyle(
                                              color: OptikMemberTokens.ink,
                                              fontSize: 14,
                                              fontWeight: selected
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (isPreferred)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE6F6F3),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              'member_help_pick_store_preferred'
                                                  .tr(),
                                              style: const TextStyle(
                                                color: OptikMemberTokens.success,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (addr.isNotEmpty && addr != '-') ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        addr,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: OptikMemberTokens.inkMuted,
                                          fontSize: 12,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: OptikMemberTokens.white,
            border: Border(
              top: BorderSide(color: OptikMemberTokens.lineSoft),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: FilledButton(
                onPressed: canContinue && !_storesLoading
                    ? _confirmStoreSelection
                    : null,
                child: Text('member_help_pick_store_continue'.tr()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChat() {
    final chips = MemberHelpChipId.values;

    return Column(
      children: [
        if (_selectedStore != null)
          Material(
            color: OptikMemberTokens.blueMist,
            child: InkWell(
              onTap: _busy ? null : () => _openStorePicker(changing: true),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      size: 18,
                      color: OptikMemberTokens.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedStoreLabel,
                        style: const TextStyle(
                          color: OptikMemberTokens.blueDeep,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'member_help_change_store'.tr(),
                      style: const TextStyle(
                        color: OptikMemberTokens.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: OptikMemberTokens.blue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: _messages.length + (_busy ? 1 : 0),
            itemBuilder: (context, i) {
              if (_busy && i == _messages.length) {
                return const _TypingBubble();
              }
              final m = _messages[i];
              return _Bubble(
                msg: m,
                onWa: m.escalateWa && !m.fromUser
                    ? () => _openWa(lastQuestion: _lastQuestion)
                    : null,
                onStoreChip: _busy ? null : _onStoreChipTap,
                onStockProduct: _busy ? null : _openStockProduct,
                onStockShowMore: _busy || !m.stockCanExpandLocal
                    ? null
                    : () => _expandStockProducts(m),
              );
            },
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: OptikMemberTokens.white,
            border: Border(
              top: BorderSide(color: OptikMemberTokens.lineSoft),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    itemCount: chips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final c = chips[i];
                      final isWa = c == MemberHelpChipId.contactWa;
                      return ActionChip(
                        avatar: Icon(
                          isWa
                              ? Icons.chat_rounded
                              : Icons.auto_awesome_rounded,
                          size: 16,
                          color: isWa
                              ? OptikMemberTokens.success
                              : OptikMemberTokens.blue,
                        ),
                        label: Text(
                          _chipLabel(c),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isWa
                                ? OptikMemberTokens.success
                                : OptikMemberTokens.blueDeep,
                          ),
                        ),
                        backgroundColor: isWa
                            ? const Color(0xFFE6F6F3)
                            : OptikMemberTokens.blueSoft,
                        side: BorderSide(
                          color: isWa
                              ? OptikMemberTokens.success.withOpacity(0.35)
                              : OptikMemberTokens.lineSoft,
                        ),
                        onPressed: _busy ? null : () => _runChip(c),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendText(),
                          enabled: !_busy,
                          decoration: InputDecoration(
                            hintText: _awaitingStatedLocation
                                ? 'member_help_location_input_hint'.tr()
                                : 'member_help_input_hint'.tr(),
                            filled: true,
                            fillColor: OptikMemberTokens.blueMist,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                OptikMemberTokens.radiusMd,
                              ),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _busy ? null : _sendText,
                        style: IconButton.styleFrom(
                          backgroundColor: OptikMemberTokens.blue,
                          foregroundColor: OptikMemberTokens.white,
                        ),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.msg,
    this.onWa,
    this.onStoreChip,
    this.onStockProduct,
    this.onStockShowMore,
  });

  final _ChatMsg msg;
  final VoidCallback? onWa;
  final void Function(_StoreChipData chip)? onStoreChip;
  final void Function(MemberHelpStockMatch product)? onStockProduct;
  final VoidCallback? onStockShowMore;

  @override
  Widget build(BuildContext context) {
    final align =
        msg.fromUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = msg.fromUser
        ? OptikMemberTokens.blue
        : OptikMemberTokens.white;
    final fg = msg.fromUser
        ? OptikMemberTokens.white
        : OptikMemberTokens.ink;
    final visibleStock = msg.stockProducts.isEmpty
        ? const <MemberHelpStockMatch>[]
        : msg.stockProducts
            .take(msg.stockVisibleCount.clamp(0, msg.stockProducts.length))
            .toList(growable: false);

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(OptikMemberTokens.radiusMd),
              topRight: const Radius.circular(OptikMemberTokens.radiusMd),
              bottomLeft: Radius.circular(
                msg.fromUser ? OptikMemberTokens.radiusMd : 4,
              ),
              bottomRight: Radius.circular(
                msg.fromUser ? 4 : OptikMemberTokens.radiusMd,
              ),
            ),
            border: msg.fromUser
                ? null
                : Border.all(color: OptikMemberTokens.lineSoft),
            boxShadow: msg.fromUser ? null : OptikMemberTokens.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!msg.fromUser)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'member_help_bot_label'.tr(),
                    style: const TextStyle(
                      color: OptikMemberTokens.blueDeep,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              SelectableText(
                msg.text,
                style: TextStyle(
                  color: fg,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              if (visibleStock.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final p in visibleStock)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: OptikMemberTokens.blueMist,
                      borderRadius:
                          BorderRadius.circular(OptikMemberTokens.radiusSm),
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(OptikMemberTokens.radiusSm),
                        onTap: onStockProduct == null
                            ? null
                            : () => onStockProduct!(p),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.nama.isEmpty ? p.sku : p.nama,
                                      style: const TextStyle(
                                        color: OptikMemberTokens.ink,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if ((p.warna ?? '').trim().isNotEmpty)
                                          p.warna!.trim(),
                                        if (p.sku.isNotEmpty) p.sku,
                                        if ((p.kategori ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          p.kategori!.trim(),
                                      ].join(' · '),
                                      style: const TextStyle(
                                        color: OptikMemberTokens.inkMuted,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'member_help_stock_qty'.tr(
                                  namedArgs: {
                                    'qty':
                                        '${memberHelpClampNonNegQty(p.availableQty)}',
                                  },
                                ),
                                style: TextStyle(
                                  color: p.inStock && p.availableQty > 0
                                      ? OptikMemberTokens.success
                                      : OptikMemberTokens.inkMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: OptikMemberTokens.blue,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (onStockShowMore != null)
                  TextButton(
                    onPressed: onStockShowMore,
                    child: Text('member_help_stock_show_more'.tr()),
                  )
                else if (msg.stockHasMoreAtBranch)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'member_help_stock_refine_hint'.tr(
                        namedArgs: {
                          'count': '${msg.stockTotalInStock}',
                        },
                      ),
                      style: const TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
              if (msg.storeChips.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in msg.storeChips)
                      ActionChip(
                        avatar: const Icon(
                          Icons.storefront_rounded,
                          size: 16,
                          color: OptikMemberTokens.success,
                        ),
                        label: Text(
                          c.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: OptikMemberTokens.blueDeep,
                          ),
                        ),
                        backgroundColor: const Color(0xFFE6F6F3),
                        side: BorderSide(
                          color: OptikMemberTokens.success.withOpacity(0.35),
                        ),
                        onPressed: onStoreChip == null
                            ? null
                            : () => onStoreChip!(c),
                      ),
                  ],
                ),
              ],
              if (onWa != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onWa,
                    style: FilledButton.styleFrom(
                      backgroundColor: OptikMemberTokens.success,
                      foregroundColor: OptikMemberTokens.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: Text(
                      'member_help_cta_wa'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: OptikMemberTokens.white,
          borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
          border: Border.all(color: OptikMemberTokens.lineSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'member_help_typing'.tr(),
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
