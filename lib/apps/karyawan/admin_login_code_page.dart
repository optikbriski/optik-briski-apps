import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kode TOTP unik per karyawan untuk login web Admin (berganti tiap 10 dtk).
class AdminLoginCodePage extends StatefulWidget {
  const AdminLoginCodePage({super.key});

  @override
  State<AdminLoginCodePage> createState() => _AdminLoginCodePageState();
}

class _AdminLoginCodePageState extends State<AdminLoginCodePage> {
  String? _code;
  String? _nama;
  String? _tokoId;
  String? _jabatan;
  int _expiresIn = 0;
  int _period = 10;
  String? _error;
  bool _loading = true;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _refresh();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final res = await Supabase.instance.client.rpc('get_admin_login_code');
      Map<String, dynamic>? map;
      if (res is Map<String, dynamic>) {
        map = res;
      } else if (res is Map) {
        map = Map<String, dynamic>.from(res);
      }
      if (map == null) {
        throw 'Respons kode tidak valid.';
      }
      if (!mounted) return;
      setState(() {
        _code = (map!['code'] ?? '').toString();
        _nama = (map['nama'] ?? '').toString();
        _tokoId = (map['toko_id'] ?? '').toString();
        _jabatan = (map['jabatan'] ?? '').toString();
        _expiresIn = (map['expires_in'] as num?)?.toInt() ?? 0;
        _period = (map['period'] as num?)?.toInt() ?? 10;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _onTick() {
    if (_error != null) return;
    if (_expiresIn <= 1) {
      _refresh();
      return;
    }
    setState(() => _expiresIn -= 1);
  }

  Future<void> _copy() async {
    final code = _code;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kode disalin.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        _period <= 0 ? 0.0 : (_expiresIn.clamp(0, _period) / _period);
    final who = [
      if ((_nama ?? '').trim().isNotEmpty) _nama!.trim(),
      if ((_jabatan ?? '').trim().isNotEmpty) _jabatan!.trim(),
      if ((_tokoId ?? '').trim().isNotEmpty) _tokoId!.trim(),
    ].join(' • ');

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: const Text('Kode Login Admin'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.tealAccent),
                )
              : _error != null
                  ? _errorView()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '6 digit: angka pertama = posisi Anda '
                          '(1 Owner, 2 Admin, 3 Kepala Area, 4 Kepala Toko), '
                          '5 digit berikutnya unik per orang — tidak bentrok '
                          'meski login bersamaan. Login web ter-track ke Anda.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        if (who.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            who,
                            style: const TextStyle(
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Center(
                          child: Text(
                            _code ?? '------',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 10,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.white12,
                            color: _expiresIn <= 3
                                ? Colors.orangeAccent
                                : Colors.tealAccent,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Ganti dalam $_expiresIn dtk (periode $_period dtk)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _copy,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Salin kode'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Muat ulang'),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          color: Colors.orangeAccent,
          size: 48,
        ),
        const SizedBox(height: 16),
        Text(
          _error!,
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            setState(() {
              _loading = true;
              _error = null;
            });
            _refresh();
          },
          child: const Text('Coba lagi'),
        ),
      ],
    );
  }
}
