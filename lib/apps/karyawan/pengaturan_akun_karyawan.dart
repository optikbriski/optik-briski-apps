import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PengaturanAkunPage extends StatefulWidget {
  const PengaturanAkunPage({super.key});

  @override
  State<PengaturanAkunPage> createState() => _PengaturanAkunPageState();
}

class _PengaturanAkunPageState extends State<PengaturanAkunPage> {
  bool _notifSop = true;
  bool _notifShift = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifSop = prefs.getBool('notif_sop') ?? true;
      _notifShift = prefs.getBool('notif_shift') ?? true;
    });
  }

  Future<Map<String, dynamic>?> _fetchKaryawan() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final byId = await Supabase.instance.client
        .from('karyawan')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (byId != null) return byId;
    final email = user.email;
    if (email == null) return null;
    return Supabase.instance.client
        .from('karyawan')
        .select()
        .eq('email', email)
        .maybeSingle();
  }

  Future<void> _ubahSandi() async {
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("pengaturan_ubah_sandi_title".tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Sandi baru'),
            ),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Ulangi sandi baru'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("sop_batal".tr())),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    if (newCtrl.text.length < 6) {
      _snack('Sandi minimal 6 karakter.', Colors.orange);
      return;
    }
    if (newCtrl.text != confirmCtrl.text) {
      _snack('Konfirmasi sandi tidak sama.', Colors.orange);
      return;
    }
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: newCtrl.text));
      _snack('Sandi berhasil diubah.', Colors.green);
    } catch (e) {
      _snack('Gagal ubah sandi: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ubahPin() async {
    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("pengaturan_ubah_pin_title".tr()),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PIN baru (4–6 digit)',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("sop_batal".tr())),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    final pin = pinCtrl.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      _snack('PIN harus 4–6 digit angka.', Colors.orange);
      return;
    }
    setState(() => _busy = true);
    try {
      final karyawan = await _fetchKaryawan();
      if (karyawan == null) throw 'Data karyawan tidak ditemukan.';
      await Supabase.instance.client
          .from('karyawan')
          .update({'pin_absensi': pin}).eq('id', karyawan['id']);
      _snack('PIN absensi berhasil diubah.', Colors.green);
    } catch (e) {
      _snack('Gagal ubah PIN: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tampilkanDialogResetWajah() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text("pengaturan_reset_bio_title".tr())),
          ],
        ),
        content: Text("pengaturan reset bio desc".tr(),
            style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("sop_batal".tr(),
                style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: Text("pengaturan_btn_ya_reset".tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final karyawan = await _fetchKaryawan();
      if (karyawan == null) throw 'Data karyawan tidak ditemukan.';
      final id = karyawan['id'];
      await Supabase.instance.client.from('karyawan').update({
        'face_template': null,
        'face_photo_url': null,
        'face_enrolled_at': null,
        'aws_face_id': null,
      }).eq('id', id);

      final tokoId = karyawan['toko_id']?.toString();
      if (tokoId != null && tokoId.isNotEmpty) {
        await Supabase.instance.client.from('attendance_logs').insert({
          'karyawan_id': id,
          'toko_id': tokoId,
          'tipe': 'ENROLL',
          'liveness_ok': false,
          'device_info': 'face_reset',
          'match_score': 0,
        });
      }
      _snack("pengaturan_msg_reset_sukses".tr(), Colors.green);
    } catch (e) {
      _snack('Gagal reset wajah: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bukaNotifikasi() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("pengaturan_notif_title".tr(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                SwitchListTile(
                  title: const Text('Pengingat SOP'),
                  value: _notifSop,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('notif_sop', v);
                    setModal(() => _notifSop = v);
                    setState(() => _notifSop = v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Pengingat shift'),
                  value: _notifShift,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('notif_shift', v);
                    setModal(() => _notifShift = v);
                    setState(() => _notifShift = v);
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Preferensi disimpan di HP. Push notification cloud menyusul.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text("pengaturan title".tr(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              Text(
                "pengaturan_sec_keamanan".tr(),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    _buildMenuTile(
                      icon: Icons.lock_outline_rounded,
                      title: "pengaturan_ubah_sandi_title".tr(),
                      subtitle: "pengaturan_ubah_sandi_desc".tr(),
                      onTap: _busy ? () {} : _ubahSandi,
                    ),
                    Divider(color: Colors.grey.shade200, height: 1),
                    _buildMenuTile(
                      icon: Icons.dialpad_rounded,
                      title: "pengaturan_ubah_pin_title".tr(),
                      subtitle: "pengaturan_ubah_pin_desc".tr(),
                      onTap: _busy ? () {} : _ubahPin,
                    ),
                    Divider(color: Colors.grey.shade200, height: 1),
                    _buildMenuTile(
                      icon: Icons.face_retouching_natural_rounded,
                      title: "pengaturan_perbarui_wajah_title".tr(),
                      subtitle: "pengaturan_perbarui_wajah_desc".tr(),
                      onTap: _busy ? () {} : _tampilkanDialogResetWajah,
                      isWarning: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text(
                "pengaturan_sec_preferensi".tr(),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: _buildMenuTile(
                  icon: Icons.notifications_none_rounded,
                  title: "pengaturan_notif_title".tr(),
                  subtitle: "pengaturan_notif_desc".tr(),
                  onTap: _bukaNotifikasi,
                ),
              ),
            ],
          ),
          if (_busy)
            const ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isWarning = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isWarning
              ? Colors.orange.withOpacity(0.1)
              : Colors.blueAccent.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isWarning ? Colors.orange : Colors.blueAccent),
      ),
      title: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded,
          size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }
}
