import 'package:flutter/material.dart';
import '../../shared/bootstrap.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Rekasa: daftar UMKM (tenant) + buat usaha baru. Bukan menu toko Optik.
class TenantAdminPage extends StatefulWidget {
  const TenantAdminPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<TenantAdminPage> createState() => _TenantAdminPageState();
}

class _TenantAdminPageState extends State<TenantAdminPage> {
  final _slug = TextEditingController();
  final _name = TextEditingController();
  final _short = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  bool get _isPlatform {
    final v = widget.profile['is_platform'];
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    return v == true || v == 'true' || role == 'platform';
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _slug.dispose();
    _name.dispose();
    _short.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await supabase.rpc('platform_list_tenants');
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    if (!_isPlatform) return;
    final slug = _slug.text.trim();
    final name = _name.text.trim();
    if (slug.length < 3 || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kode usaha (≥3) dan nama merek wajib.'),
          backgroundColor: OptikAdminTokens.warning,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await supabase.rpc('platform_create_tenant', params: {
        'p_slug': slug,
        'p_display_name': name,
        'p_short_name': _short.text.trim().isEmpty ? null : _short.text.trim(),
      });
      if (!mounted) return;
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] != true) {
        throw map['error'] ?? 'Gagal buat tenant';
      }
      _slug.clear();
      _name.clear();
      _short.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'UMKM siap. Kode ${map['slug']} · toko pusat ${map['pusat_toko_id']}. '
            'Buat akun owner di tenant itu, jangan jadi cabang Optik.',
          ),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      await _boot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: const Text('UMKM / Tenant'),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Setiap UMKM punya merek, cabang, nota, dan member sendiri. '
                  'Jangan masukkan usaha lain sebagai CABANG Optik B. Riski.',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.75),
                    height: 1.35,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: OptikAdminTokens.danger)),
                ],
                const SizedBox(height: 20),
                const PremiumSectionHeader(label: 'Usaha terdaftar'),
                const SizedBox(height: 8),
                if (_rows.isEmpty)
                  const Text('Belum ada tenant (jalankan migrasi tenants).'),
                for (final r in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PremiumPanel(
                      child: ListTile(
                        title: Text(
                          '${r['display_name'] ?? r['legal_name'] ?? r['slug']}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${r['slug']} · pusat ${r['pusat_toko_id'] ?? '-'} · ${r['status'] ?? ''}',
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                const PremiumSectionHeader(label: 'Buat UMKM baru'),
                const SizedBox(height: 8),
                TextField(
                  controller: _slug,
                  decoration: const InputDecoration(
                    labelText: 'Kode usaha (slug)',
                    hintText: 'optik-maju',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nama merek di app / struk',
                    hintText: 'Optik Maju',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _short,
                  decoration: const InputDecoration(
                    labelText: 'Singkatan (opsional)',
                    hintText: 'OM',
                  ),
                ),
                const SizedBox(height: 16),
                PremiumPrimaryButton(
                  label: _saving ? 'Menyimpan…' : 'Buat tenant',
                  onPressed: _saving || !_isPlatform ? null : _create,
                ),
                if (!_isPlatform) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Akun ini bukan Rekasa. Di Table Editor → profiles, '
                    'set is_platform = true pada akun operator Rekasa.',
                    style: TextStyle(color: OptikAdminTokens.warning),
                  ),
                ],
              ],
            ),
    );
  }
}
