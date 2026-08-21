import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/bootstrap.dart';
import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/widgets/rekasa_mark.dart';
import '../../shared/widgets/rekasa_surface.dart';
import 'store_account.dart';
import 'store_brand_dashboard_page.dart';

/// Login owner usaha (bukan operator Rekasa, bukan kasir).
class StoreAccountLoginPage extends StatefulWidget {
  const StoreAccountLoginPage({super.key});

  @override
  State<StoreAccountLoginPage> createState() => _StoreAccountLoginPageState();
}

class _StoreAccountLoginPageState extends State<StoreAccountLoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await supabase.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
      final uid = res.user?.id;
      if (uid == null) throw 'Login gagal';
      final row = await supabase.from('profiles').select().eq('id', uid).maybeSingle();
      final kind = StoreAuth.kind(row == null ? null : Map<String, dynamic>.from(row));
      if (kind == StoreAccountKind.platform) {
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }
      if (kind == StoreAccountKind.staff) {
        await supabase.auth.signOut();
        throw StoreAuth.staffMessage;
      }
      if (kind != StoreAccountKind.owner) {
        await supabase.auth.signOut();
        throw StoreAuth.unboundMessage;
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const StoreBrandDashboardPage()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: RekasaTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      appBar: AppBar(title: const Text('Masuk owner')),
      body: ListView(
        children: [
          RekasaPage(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: RekasaSurface(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RekasaMark(height: 32),
                    const SizedBox(height: 18),
                    Text(
                      'Masuk ke merek Anda',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                        letterSpacing: -0.5,
                        color: RekasaTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Portal owner: pembayaran langganan, kontrak, dan paket. '
                      'Bukan kasir toko.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy ? 'Masuk…' : 'Masuk'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
