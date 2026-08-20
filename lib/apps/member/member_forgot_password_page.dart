import 'package:flutter/material.dart';

import '../../shared/config.dart';
import '../../shared/member/member_repository.dart';
import '../../shared/member/member_status_watch.dart';
import '../../shared/tenant/tenant_service.dart';
import '../../shared/theme.dart';

class MemberForgotPasswordPage extends StatefulWidget {
  const MemberForgotPasswordPage({
    super.key,
    this.initialIdentifier,
    this.initialSlug,
  });

  final String? initialIdentifier;
  final String? initialSlug;

  @override
  State<MemberForgotPasswordPage> createState() =>
      _MemberForgotPasswordPageState();
}

class _MemberForgotPasswordPageState extends State<MemberForgotPasswordPage> {
  final _repo = MemberRepository();
  late final TextEditingController _id;
  late final TextEditingController _slug;
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;
  bool _obscure = true;
  String? _debugCode;

  @override
  void initState() {
    super.initState();
    _id = TextEditingController(text: widget.initialIdentifier ?? '');
    _slug = TextEditingController(
      text: (widget.initialSlug ?? TenantService.instance.slug).trim(),
    );
  }

  @override
  void dispose() {
    _id.dispose();
    _slug.dispose();
    _code.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _bindTenant() async {
    await TenantService.instance.requireResolved(
      slug: isBrandedStoreApk ? null : _slug.text,
    );
  }

  Future<void> _requestCode() async {
    if (_id.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi email atau nomor HP')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _bindTenant();
      final res = await _repo.requestPasswordReset(_id.text.trim());
      if (!mounted) return;
      if (res['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${res['error'] ?? 'Gagal'}'),
            backgroundColor: OptikMemberTokens.danger,
          ),
        );
        return;
      }
      setState(() {
        _codeSent = true;
        _debugCode = res['debug_code']?.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _debugCode == null
                ? 'Kode reset dikirim.'
                : 'Kode reset (sementara): $_debugCode',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$e'), backgroundColor: OptikMemberTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_pass.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password baru minimal 6 karakter')),
      );
      return;
    }
    if (_pass.text != _pass2.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konfirmasi password tidak sama')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _bindTenant();
      final res = await _repo.resetPassword(
        identifier: _id.text.trim(),
        code: _code.text.trim(),
        newPassword: _pass.text,
      );
      if (!mounted) return;
      if (res['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${res['error'] ?? 'Gagal reset'}'),
            backgroundColor: OptikMemberTokens.danger,
          ),
        );
        return;
      }
      try {
        await MemberStatusWatch.instance.start();
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password diganti. Anda sudah masuk.')),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$e'), backgroundColor: OptikMemberTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikMemberTokens.canvas,
      appBar: AppBar(title: const Text('Lupa password')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const Text(
            'Masukkan email atau nomor HP terdaftar. '
            'Kami kirim kode untuk atur password baru.',
            style: TextStyle(
              color: OptikMemberTokens.inkSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: OptikMemberTokens.white,
              borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
              border: Border.all(color: OptikMemberTokens.lineSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isBrandedStoreApk) ...[
                  TextField(
                    controller: _slug,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Kode usaha',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _id,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email atau nomor HP',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _requestCode,
                  child: const Text('Kirim kode reset'),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Kode reset',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  TextField(
                    controller: _pass,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password baru',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pass2,
                    obscureText: _obscure,
                    decoration: const InputDecoration(
                      labelText: 'Ulangi password baru',
                      prefixIcon: Icon(Icons.lock_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _busy ? null : _reset,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Simpan password & masuk'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
