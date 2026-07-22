// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Scan barcode NIK karyawan (HID scanner web admin) sebelum aksi lifecycle.
Future<Map<String, dynamic>?> showStaffNikScanDialog(
  BuildContext context, {
  String title = 'Scan barcode karyawan',
  String subtitle =
      'Scan NIK karyawan yang menangani transaksi ini (scanner toko).',
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _StaffNikScanDialog(title: title, subtitle: subtitle),
  );
}

class _StaffNikScanDialog extends StatefulWidget {
  const _StaffNikScanDialog({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  State<_StaffNikScanDialog> createState() => _StaffNikScanDialogState();
}

class _StaffNikScanDialogState extends State<_StaffNikScanDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final nik = raw.trim();
    if (nik.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .from('karyawan')
          .select('id, nik, nama, jabatan, toko_id, status_approval')
          .eq('nik', nik)
          .maybeSingle();
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _busy = false;
          _error = 'NIK tidak ditemukan.';
          _ctrl.clear();
        });
        _focus.requestFocus();
        return;
      }
      final status = (res['status_approval'] ?? '').toString();
      if (status.isNotEmpty && status.toLowerCase() != 'aktif') {
        setState(() {
          _busy = false;
          _error = 'Karyawan tidak aktif.';
          _ctrl.clear();
        });
        _focus.requestFocus();
        return;
      }
      Navigator.pop(context, Map<String, dynamic>.from(res));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      title: Text(
        widget.title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            enabled: !_busy,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'NIK karyawan',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
              hintText: 'Arahkan scanner ke sini…',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onSubmitted: _submit,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}
