import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/bootstrap.dart';
import '../../shared/brand/brand_chrome.dart';
import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/widgets/rekasa_mark.dart';
import '../../shared/widgets/rekasa_surface.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';
import '../admin/rekasa_store_orders_page.dart';
import '../admin/rekasa_store_page.dart';
import '../admin/tenant_admin_page.dart';
import 'store_account.dart';
import 'store_brand_dashboard_page.dart';

/// Kulit tipis: etalase + kontrak. Tidak memuat POS / absensi / training.
class StoreApp extends StatelessWidget {
  const StoreApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    Widget home = const StoreHomePage();
    if (kIsWeb) {
      final token = TenantBilling.tokenFromUri(Uri.base);
      if (token != null) {
        home = TenantContractSignPage(token: token);
      }
    }
    return MaterialApp(
      title: BrandChrome.windowTitle,
      onGenerateTitle: (_) => BrandChrome.windowTitle,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: buildRekasaStoreTheme(),
      home: home,
    );
  }
}

class StoreHomePage extends StatefulWidget {
  const StoreHomePage({super.key});

  @override
  State<StoreHomePage> createState() => _StoreHomePageState();
}

class _StoreHomePageState extends State<StoreHomePage> {
  Map<String, dynamic>? _platformProfile;
  StoreAccountKind _kind = StoreAccountKind.none;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _restoreSession();
    _authSub = supabase.auth.onAuthStateChange.listen((_) {
      if (mounted) _restoreSession();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _platformProfile = null;
        _kind = StoreAccountKind.none;
      });
      return;
    }
    try {
      final row = await supabase.from('profiles').select().eq('id', uid).maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _platformProfile = null;
          _kind = StoreAccountKind.none;
        });
        return;
      }
      final map = Map<String, dynamic>.from(row);
      setState(() {
        _kind = StoreAuth.kind(map);
        _platformProfile = _kind == StoreAccountKind.platform ? map : null;
      });
    } catch (_) {}
  }

  bool get _isPlatform {
    final p = _platformProfile;
    if (p == null) return false;
    final v = p['is_platform'];
    final role = (p['role'] ?? '').toString().toLowerCase();
    return v == true || v == 'true' || role == 'platform';
  }

  Future<void> _login() async {
    final email = TextEditingController();
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const RekasaMark(height: 28),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masuk operator',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: RekasaTokens.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hanya akun Rekasa (is_platform). '
              'Klien toko pakai APK Admin/Karyawan yang dibeli — bukan APK ini.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Masuk'),
          ),
        ],
      ),
    );
    final e = email.text.trim();
    final p = pass.text;
    email.dispose();
    pass.dispose();
    if (ok != true) return;
    try {
      final res = await supabase.auth.signInWithPassword(email: e, password: p);
      final uid = res.user?.id;
      if (uid == null) throw 'Login gagal';
      final row = await supabase.from('profiles').select().eq('id', uid).maybeSingle();
      final plat = row != null &&
          (row['is_platform'] == true ||
              row['is_platform'] == 'true' ||
              (row['role'] ?? '').toString().toLowerCase() == 'platform');
      if (!plat) {
        await supabase.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ini APK etalase Rekasa. Akun toko masuk di APK Admin/Karyawan yang dibeli.',
            ),
            backgroundColor: RekasaTokens.warning,
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _platformProfile = Map<String, dynamic>.from(row));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$err'), backgroundColor: RekasaTokens.danger),
      );
    }
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    setState(() => _platformProfile = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      body: Column(
        children: [
          Material(
            color: RekasaTokens.paper,
            elevation: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: RekasaTokens.paper,
                border: Border(bottom: BorderSide(color: RekasaTokens.line)),
              ),
              child: SafeArea(
                bottom: false,
                child: RekasaPage(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                  child: Row(
                    children: [
                      const RekasaMark(height: 34),
                      const Spacer(),
                      if (_kind == StoreAccountKind.owner)
                        RekasaPillButton(
                          label: 'Dasbor',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const StoreBrandDashboardPage(),
                              ),
                            );
                          },
                        )
                      else if (_isPlatform) ...[
                        IconButton(
                          tooltip: 'Pesanan',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RekasaStoreOrdersPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.shopping_bag_outlined),
                          color: RekasaTokens.ink,
                        ),
                        IconButton(
                          tooltip: 'UMKM',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TenantAdminPage(profile: _platformProfile!),
                              ),
                            );
                          },
                          icon: const Icon(Icons.apartment_outlined),
                          color: RekasaTokens.ink,
                        ),
                        RekasaPillButton(label: 'Keluar', onTap: _logout),
                      ] else
                        RekasaPillButton(label: 'Operator Rekasa', onTap: _login),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Expanded(child: RekasaStorePage(embedded: true)),
        ],
      ),
    );
  }
}
