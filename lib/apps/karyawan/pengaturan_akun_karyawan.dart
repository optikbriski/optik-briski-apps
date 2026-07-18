import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart'; // <-- Senjata Utama
import 'software_update_page.dart';

class PengaturanAkunPage extends StatefulWidget {
  const PengaturanAkunPage({super.key});

  @override
  State<PengaturanAkunPage> createState() => _PengaturanAkunPageState();
}

class _PengaturanAkunPageState extends State<PengaturanAkunPage> {
  // WIDGET PEMBANTU: DIALOG KONFIRMASI RESET WAJAH
  void _tampilkanDialogResetWajah() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text("pengaturan_reset_bio_title".tr()),
            ),
          ],
        ),
        content: Text(
          "pengaturan reset bio desc"
              .tr(), // DIPERBAIKI: Menggunakan spasi sesuai id.json
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("sop_batal".tr(),
                style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("pengaturan_msg_reset_sukses".tr()),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: Text("pengaturan_btn_ya_reset".tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text(
            "pengaturan title"
                .tr(), // DIPERBAIKI: Menggunakan spasi sesuai id.json
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B), // Tema gelap elegan
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          Text(
            "pengaturan_sec_keamanan".tr(),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 10),

          // KOTAK MENU KEAMANAN
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)
              ],
            ),
            child: Column(
              children: [
                _buildMenuTile(
                  icon: Icons.lock_outline_rounded,
                  title: "pengaturan_ubah_sandi_title".tr(),
                  subtitle: "pengaturan_ubah_sandi_desc".tr(),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("pengaturan_msg_buka_sandi".tr())),
                    );
                  },
                ),
                Divider(color: Colors.grey.shade200, height: 1),
                _buildMenuTile(
                  icon: Icons.dialpad_rounded,
                  title: "pengaturan_ubah_pin_title".tr(),
                  subtitle: "pengaturan_ubah_pin_desc".tr(),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("pengaturan_msg_buka_pin".tr())),
                    );
                  },
                ),
                Divider(color: Colors.grey.shade200, height: 1),
                _buildMenuTile(
                  icon: Icons.face_retouching_natural_rounded,
                  title: "pengaturan_perbarui_wajah_title".tr(),
                  subtitle: "pengaturan_perbarui_wajah_desc".tr(),
                  onTap: _tampilkanDialogResetWajah,
                  isWarning: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          Text(
            "pengaturan_sec_preferensi".tr(),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 10),

          // KOTAK MENU PREFERENSI
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)
              ],
            ),
            child: Column(
              children: [
                _buildMenuTile(
                  icon: Icons.notifications_none_rounded,
                  title: "pengaturan_notif_title".tr(),
                  subtitle: "pengaturan_notif_desc".tr(),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("pengaturan_msg_buka_notif".tr())),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET PEMBANTU: BARIS MENU PENGATURAN
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
      title: Text(
        title,
        style: const TextStyle(
            fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded,
          size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }
}
