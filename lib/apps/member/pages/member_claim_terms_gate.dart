import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/theme.dart';
import '../member_layout.dart';
import 'member_claim_page.dart';

/// Preferensi centang S&K klaim garansi.
enum ClaimTermsMode {
  /// Centang selalu aktif; cukup scroll ke bawah.
  alwaysAgree,

  /// Tiap kali: scroll + centang manual.
  alwaysAsk,
}

/// Buka halaman klaim setelah popup S&K disetujui.
Future<void> openMemberClaimPage(
  BuildContext context, {
  Map<String, dynamic>? initialKartu,
}) async {
  final ok = await showMemberClaimTermsDialog(context);
  if (ok != true || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MemberClaimPage(initialKartu: initialKartu),
    ),
  );
}

Future<bool?> showMemberClaimTermsDialog(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ClaimTermsSheet(),
  );
}

class ClaimTermsPrefs {
  static const _key = 'member_claim_terms_mode_v1';

  static Future<ClaimTermsMode?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return switch (raw) {
      'always_agree' => ClaimTermsMode.alwaysAgree,
      'always_ask' => ClaimTermsMode.alwaysAsk,
      _ => null,
    };
  }

  static Future<void> save(ClaimTermsMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      mode == ClaimTermsMode.alwaysAgree ? 'always_agree' : 'always_ask',
    );
  }
}

const _claimTermsText = '''
SYARAT & KETENTUAN KLAIM GARANSI
Optik B. Riski

Dengan melanjutkan, Anda menyatakan telah membaca dan menyetujui ketentuan berikut:

1. Klaim garansi WAJIB datang langsung ke toko Optik B. Riski yang ditentukan.
2. Barang yang diklaim HARUS dibawa lengkap (frame/lensa sesuai nota) untuk dicek petugas.
3. Keputusan diterima / ditolak hanya setelah pemeriksaan fisik oleh petugas toko.
4. Garansi tidak berlaku untuk kerusakan karena benturan, terjatuh, kelalaian, atau disengaja.
5. Modifikasi / perbaikan di luar Optik B. Riski membatalkan garansi.
6. Kehilangan kacamata bukan tanggung jawab toko dan tidak termasuk klaim garansi.
7. Data klaim di app hanya untuk antrean & dokumentasi; bukan jaminan ganti rugi otomatis.
8. Petugas berhak meminta nota, kartu garansi, dan identitas terkait pembelian.
9. Estimasi perbaikan / penggantian mengikuti stok dan kebijakan cabang.
10. Dengan menekan "Klaim sekarang", Anda setuju mengikuti prosedur di atas tanpa paksaan.

Scroll sampai bagian paling bawah untuk mengaktifkan persetujuan.
''';

class _ClaimTermsSheet extends StatefulWidget {
  const _ClaimTermsSheet();

  @override
  State<_ClaimTermsSheet> createState() => _ClaimTermsSheetState();
}

class _ClaimTermsSheetState extends State<_ClaimTermsSheet> {
  final _scroll = ScrollController();
  ClaimTermsMode? _mode;
  bool _scrolledToEnd = false;
  bool _agreed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final mode = await ClaimTermsPrefs.load();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _agreed = mode == ClaimTermsMode.alwaysAgree;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScrollEnd());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() => _checkScrollEnd();

  void _checkScrollEnd() {
    if (!_scroll.hasClients || _scrolledToEnd) return;
    final pos = _scroll.position;
    final max = pos.maxScrollExtent;
    // Konten pendek (tidak bisa scroll) = sudah "di bawah".
    // Konten panjang: wajib scroll sampai ujung.
    final atEnd = max <= 8 || pos.pixels >= max - 16;
    if (atEnd) setState(() => _scrolledToEnd = true);
  }

  bool get _canClaim => _scrolledToEnd && _agreed;
  bool get _canInteractCheckbox =>
      _scrolledToEnd && _mode != ClaimTermsMode.alwaysAgree;

  Future<void> _onAgreeTap(bool? value) async {
    // Kunci keras: tidak bisa centang sebelum scroll paling bawah.
    if (!_scrolledToEnd) return;
    final want = value ?? false;

    if (!want) {
      if (_mode == ClaimTermsMode.alwaysAgree) return;
      setState(() => _agreed = false);
      return;
    }

    // Centang pertama kali → pilih preferensi.
    if (_mode == null) {
      final picked = await _pickModeFirstTime();
      if (picked == null || !mounted) return;
      await ClaimTermsPrefs.save(picked);
      if (!mounted) return;
      setState(() => _mode = picked);
      if (picked == ClaimTermsMode.alwaysAgree) {
        setState(() => _agreed = true);
        return;
      }
      // Selalu tanyakan: lanjut konfirmasi di bawah.
    }

    // Mode selalu tanyakan: konfirmasi setiap kali mencentang.
    if (_mode == ClaimTermsMode.alwaysAsk) {
      final ok = await _confirmAgreeEveryTime();
      if (ok != true || !mounted) return;
      setState(() => _agreed = true);
      return;
    }

    setState(() => _agreed = true);
  }

  Future<ClaimTermsMode?> _pickModeFirstTime() {
    final m = MemberLayout.of(context);
    return showDialog<ClaimTermsMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Preferensi persetujuan',
          style: TextStyle(fontSize: m.isTablet ? 20 : 18),
        ),
        content: Text(
          '• Selalu setuju — centang otomatis; cukup scroll ke bawah.\n'
          '• Selalu tanyakan — tiap kali centang harus konfirmasi lagi.',
          style: TextStyle(
            fontSize: m.bodySize,
            color: OptikMemberTokens.inkMuted,
            height: 1.4,
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ClaimTermsMode.alwaysAsk),
            child: const Text('Selalu tanyakan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ClaimTermsMode.alwaysAgree),
            child: const Text('Selalu setuju'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmAgreeEveryTime() {
    final m = MemberLayout.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Konfirmasi persetujuan',
          style: TextStyle(fontSize: m.isTablet ? 20 : 18),
        ),
        content: Text(
          'Apakah Anda yakin menyetujui syarat & ketentuan klaim garansi ini?',
          style: TextStyle(fontSize: m.bodySize, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, setuju'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeMode() async {
    final m = MemberLayout.of(context);
    final picked = await showDialog<ClaimTermsMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Ubah preferensi',
          style: TextStyle(fontSize: m.isTablet ? 20 : 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Selalu setuju',
                  style: TextStyle(fontSize: m.menuTitleSize)),
              subtitle: Text(
                'Centang otomatis; cukup scroll ke bawah',
                style: TextStyle(fontSize: m.menuSubtitleSize),
              ),
              onTap: () => Navigator.pop(ctx, ClaimTermsMode.alwaysAgree),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Selalu tanyakan',
                  style: TextStyle(fontSize: m.menuTitleSize)),
              subtitle: Text(
                'Setiap kali harus centang lagi',
                style: TextStyle(fontSize: m.menuSubtitleSize),
              ),
              onTap: () => Navigator.pop(ctx, ClaimTermsMode.alwaysAsk),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await ClaimTermsPrefs.save(picked);
    if (!mounted) return;
    setState(() {
      _mode = picked;
      _agreed = picked == ClaimTermsMode.alwaysAgree;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final height = MediaQuery.sizeOf(context).height;
    final sheetH = m.isTablet ? height * 0.78 : height * 0.88;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: m.isTablet ? m.maxContentWidth : double.infinity,
          maxHeight: sheetH,
        ),
        child: Material(
          color: OptikMemberTokens.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                m.pagePadding,
                12,
                m.pagePadding,
                m.isTablet ? 18 : 12,
              ),
              child: _loading
                  ? const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: OptikMemberTokens.lineSoft,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.gavel_rounded,
                              color: OptikMemberTokens.blue,
                              size: m.iconSize,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Syarat & ketentuan klaim',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: m.isTablet ? 20 : 17,
                                  color: OptikMemberTokens.blueDeep,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Tutup',
                              onPressed: () => Navigator.pop(context, false),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        Text(
                          _scrolledToEnd
                              ? 'Sudah sampai bawah — lanjut centang persetujuan.'
                              : 'Scroll sampai paling bawah untuk melanjutkan.',
                          style: TextStyle(
                            color: _scrolledToEnd
                                ? const Color(0xFF0F766E)
                                : OptikMemberTokens.inkMuted,
                            fontSize: m.menuSubtitleSize,
                          ),
                        ),
                        SizedBox(height: m.sectionGap),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: OptikMemberTokens.blueMist,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: OptikMemberTokens.lineSoft,
                              ),
                            ),
                            child: Scrollbar(
                              controller: _scroll,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _scroll,
                                padding: EdgeInsets.all(m.isTablet ? 18 : 14),
                                child: Text(
                                  _claimTermsText.trim(),
                                  style: TextStyle(
                                    fontSize: m.bodySize,
                                    height: 1.45,
                                    color: OptikMemberTokens.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: m.sectionGap),
                        Opacity(
                          opacity: _scrolledToEnd ||
                                  _mode == ClaimTermsMode.alwaysAgree
                              ? 1
                              : 0.45,
                          child: IgnorePointer(
                            ignoring: !_canInteractCheckbox &&
                                _mode != ClaimTermsMode.alwaysAgree,
                            child: CheckboxListTile(
                              value: _agreed,
                              onChanged: _mode == ClaimTermsMode.alwaysAgree
                                  ? null
                                  : (_canInteractCheckbox ? _onAgreeTap : null),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              activeColor: OptikMemberTokens.blue,
                              title: Text(
                                'Saya menyetujui kesepakatan ini',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: m.menuTitleSize,
                                  color: _scrolledToEnd
                                      ? OptikMemberTokens.ink
                                      : OptikMemberTokens.inkMuted,
                                ),
                              ),
                              subtitle: Text(
                                !_scrolledToEnd
                                    ? 'Scroll dulu sampai paling bawah'
                                    : _mode == ClaimTermsMode.alwaysAgree
                                        ? 'Mode: Selalu setuju (centang otomatis)'
                                        : _mode == ClaimTermsMode.alwaysAsk
                                            ? 'Mode: Selalu tanyakan (konfirmasi tiap centang)'
                                            : 'Centang untuk pilih preferensi',
                                style: TextStyle(fontSize: m.menuSubtitleSize),
                              ),
                            ),
                          ),
                        ),
                        if (_mode != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _changeMode,
                              child: Text(
                                'Ubah preferensi',
                                style: TextStyle(fontSize: m.menuSubtitleSize),
                              ),
                            ),
                          ),
                        SizedBox(height: m.isTablet ? 8 : 4),
                        SizedBox(
                          width: double.infinity,
                          height: m.isTablet ? 52 : 48,
                          child: FilledButton(
                            onPressed: _canClaim
                                ? () => Navigator.pop(context, true)
                                : null,
                            child: Text(
                              'Klaim sekarang',
                              style: TextStyle(fontSize: m.bodySize),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
