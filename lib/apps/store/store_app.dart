import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/bootstrap.dart';
import '../../shared/brand/brand_chrome.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';
import '../admin/rekasa_store_orders_page.dart';
import '../admin/rekasa_store_page.dart';
import '../admin/tenant_admin_page.dart';

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
      theme: buildAdminTheme(),
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
        title: const Text('Masuk operator Rekasa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Hanya akun Rekasa (is_platform). '
              'Klien toko pakai APK Admin/Karyawan yang dibeli — bukan APK ini.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Masuk')),
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
            backgroundColor: OptikAdminTokens.warning,
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _platformProfile = Map<String, dynamic>.from(row));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$err'), backgroundColor: OptikAdminTokens.danger),
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
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: const Text('Rekasa'),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
        actions: [
          if (_isPlatform) ...[
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
            ),
            IconButton(
              tooltip: 'UMKM',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TenantAdminPage(profile: _platformProfile!),
                  ),
                );
              },
              icon: const Icon(Icons.apartment_outlined),
            ),
            IconButton(
              tooltip: 'Keluar',
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded),
            ),
          ] else
            TextButton(
              onPressed: _login,
              child: const Text('Operator'),
            ),
        ],
      ),
      body: const RekasaStorePage(embedded: true),
    );
  }
}
