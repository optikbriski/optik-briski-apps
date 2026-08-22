import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/bootstrap.dart';
import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/widgets/rekasa_mark.dart';
import '../../shared/widgets/rekasa_surface.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';
import 'store_account.dart';
import 'store_brand_dashboard_page.dart';

/// Daftar / masuk owner lalu klaim usaha dari pesanan etalase.
class StoreAccountLoginPage extends StatefulWidget {
  const StoreAccountLoginPage({super.key, this.hint});

  final StoreAccountHint? hint;

  @override
  State<StoreAccountLoginPage> createState() => _StoreAccountLoginPageState();
}

class _StoreAccountLoginPageState extends State<StoreAccountLoginPage> {
  late final _email = TextEditingController(text: widget.hint?.email ?? '');
  late final _pass = TextEditingController();
  late final _slug = TextEditingController(text: widget.hint?.slug ?? '');
  late final _phone = TextEditingController(text: widget.hint?.phone ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _slug.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _goDashboard() async {
    if (!mounted) return;
    final token = (widget.hint?.contractToken ?? '').trim();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const StoreBrandDashboardPage()),
    );
    if (token.isNotEmpty && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TenantContractSignPage(token: token)),
      );
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      final pass = _pass.text;
      if (email.isEmpty || pass.length < 6) {
        throw 'Email dan password (min. 6) wajib';
      }
      var uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        try {
          final res = await supabase.auth.signInWithPassword(
            email: email,
            password: pass,
          );
          uid = res.user?.id;
        } catch (_) {
          final res = await supabase.auth.signUp(email: email, password: pass);
          uid = res.user?.id;
          if (uid == null || supabase.auth.currentUser == null) {
            throw 'Cek email konfirmasi, lalu masuk lagi di sini.';
          }
        }
      }
      if (uid == null) throw 'Login gagal';

      final row =
          await supabase.from('profiles').select().eq('id', uid).maybeSingle();
      final kind =
          StoreAuth.kind(row == null ? null : Map<String, dynamic>.from(row));
      if (kind == StoreAccountKind.platform) {
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }
      if (kind == StoreAccountKind.staff) {
        await supabase.auth.signOut();
        throw StoreAuth.staffMessage;
      }
      if (kind == StoreAccountKind.owner) {
        await _goDashboard();
        return;
      }

      final snap = await StoreAccount.claim(
        slug: _slug.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!snap.ok) {
        throw snap.error ?? StoreAuth.unboundMessage;
      }
      await _goDashboard();
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
      appBar: AppBar(title: const Text('Akun owner')),
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
                      'Sudah beli: isi kode usaha + HP yang sama, lalu buat '
                      'password. Portal = tagihan dan kontrak, bukan kasir.',
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
                      decoration: const InputDecoration(
                        labelText: 'Password (buat baru atau yang sudah ada)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _slug,
                      decoration: const InputDecoration(
                        labelText: 'Kode usaha',
                        hintText: 'contoh: warung-sari',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'WA / HP saat beli',
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy ? 'Memproses…' : 'Masuk / klaim usaha'),
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
