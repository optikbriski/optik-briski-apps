import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/invoice/invoice_settings_service.dart';
import '../../shared/tenant/tenant_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Identitas cabang di dashboard toko itu. SOP / nota / member baca dari sini.
class TokoDetailPanel extends StatefulWidget {
  const TokoDetailPanel({
    super.key,
    required this.profile,
    required this.tokoId,
    this.onSaved,
  });

  final Map<String, dynamic> profile;
  final String tokoId;
  final VoidCallback? onSaved;

  @override
  State<TokoDetailPanel> createState() => _TokoDetailPanelState();
}

class _TokoDetailPanelState extends State<TokoDetailPanel> {
  final _settings = InvoiceSettingsService();
  final _nama = TextEditingController();
  final _alamat = TextEditingController();
  final _telp = TextEditingController();
  final _ig = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _ok;
  String _loadedUsername = '';

  bool get _canEdit =>
      AttendanceAdminScope.canEditTokoGeofence(widget.profile, widget.tokoId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TokoDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tokoId != widget.tokoId) _load();
  }

  @override
  void dispose() {
    _nama.dispose();
    _alamat.dispose();
    _telp.dispose();
    _ig.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final toko = widget.tokoId.trim();
    if (toko.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _ok = null;
    });
    try {
      final settings = await _settings.fetchForToko(toko);
      var username = '';
      try {
        final keys = AttendanceAdminScope.storeIdAliases(toko);
        final rows = await Supabase.instance.client
            .from('toko_id')
            .select('ig_username')
            .inFilter('id', keys.isEmpty ? [toko] : keys);
        for (final raw in rows as List) {
          final un = (raw['ig_username'] ?? '')
              .toString()
              .trim()
              .replaceFirst(RegExp(r'^@+'), '');
          if (un.isNotEmpty) {
            username = un;
            break;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      _nama.text = settings.shopName;
      _alamat.text = settings.address;
      _telp.text = settings.phone == '-' ? '' : settings.phone;
      _ig.text = username;
      _loadedUsername = username;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_canEdit || _saving) return;
    final toko = widget.tokoId.trim();
    if (toko.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
      _ok = null;
    });
    try {
      final current = await _settings.fetchForToko(toko);
      final telp = _telp.text.trim();
      await _settings.save(
        current.copyWith(
          tokoId: toko,
          shopName: _nama.text.trim().isEmpty
              ? InvoiceSettingsService.defaultShopName(toko)
              : _nama.text.trim(),
          address: _alamat.text.trim(),
          phone: telp.isEmpty ? '-' : telp,
        ),
      );

      final un = _ig.text.trim().replaceFirst(RegExp(r'^@+'), '');
      if (un.toLowerCase() != _loadedUsername.toLowerCase() ||
          un.isNotEmpty ||
          _loadedUsername.isNotEmpty) {
        final keys = AttendanceAdminScope.storeIdAliases(toko);
        final storeKeys = keys.isEmpty ? [toko] : keys;
        final patch = <String, dynamic>{
          'ig_username': un.isEmpty ? null : un.toLowerCase(),
        };
        if (un.toLowerCase() != _loadedUsername.toLowerCase()) {
          patch['ig_user_id'] = null;
        }
        try {
          var q = Supabase.instance.client
              .from('toko_id')
              .update(patch)
              .inFilter('id', storeKeys);
          final tid = TenantService.instance.id;
          if (tid != null && tid.isNotEmpty) q = q.eq('tenant_id', tid);
          final updated = await q.select('id');
          if (List<dynamic>.from(updated).isEmpty && un.isNotEmpty) {
            throw 'Username IG tidak tersimpan. Toko bukan milik usaha ini.';
          }
        } catch (e) {
          if (un.isNotEmpty) {
            throw 'Nama/alamat tersimpan. Username IG gagal: $e';
          }
        }
      }
      _loadedUsername = un.toLowerCase();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _ok = 'work_sum_toko_ok'.tr();
      });
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: OptikAdminTokens.snow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      showAccentBar: true,
      padding: const EdgeInsets.fromLTRB(4, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PremiumSectionHeader(
            label: 'work_sum_toko_detail'.tr(),
            padding: const EdgeInsets.only(bottom: 12),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: OptikAdminTokens.navy),
              ),
            )
          else ...[
            TextField(
              controller: _nama,
              enabled: _canEdit,
              textCapitalization: TextCapitalization.words,
              decoration: _dec('work_sum_toko_nama'.tr()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _alamat,
              enabled: _canEdit,
              maxLines: 3,
              decoration: _dec('work_sum_toko_alamat'.tr()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _telp,
              enabled: _canEdit,
              keyboardType: TextInputType.phone,
              decoration: _dec('work_sum_toko_telp'.tr()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ig,
              enabled: _canEdit,
              autocorrect: false,
              decoration: _dec(
                'work_sum_toko_ig'.tr(),
                hint: 'optikbriski.cimahi',
              ),
            ),
            if ((_error ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: OptikAdminTokens.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
            if ((_ok ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _ok!,
                style: TextStyle(
                  color: OptikAdminTokens.success,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
            if (_canEdit) ...[
              const SizedBox(height: 14),
              PremiumPrimaryButton(
                label: 'work_sum_toko_simpan'.tr(),
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
