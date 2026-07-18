import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart'; // <-- Senjata Utama

class PengingatPage extends StatelessWidget {
  const PengingatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text("pengingat_title".tr(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B), // Tema gelap elegan
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip:
                "pengingat tooltip tandai".tr(), // Menyesuaikan dengan id.json
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("pengingat_msg_tandai_sukses".tr()),
                ),
              );
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          Text(
            "pengingat_hari_ini".tr(),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 10),

          // 1. PENGINGAT PENTING (MERAH) SOP BELUM KELAR
          _buildReminderCard(
            icon: Icons.warning_rounded,
            iconColor: Colors.redAccent,
            title: "pengingat_sop_title".tr(),
            description: "pengingat_sop_desc".tr(),
            waktu: "pengingat_1_jam_lalu".tr(),
            isUrgent: true,
          ),
          const SizedBox(height: 20),

          Text(
            "pengingat_akan_datang".tr(),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 10),

          // 2. PENGINGAT JADWAL (BIRU) SHIFT BESOK
          _buildReminderCard(
            icon: Icons.calendar_month_rounded,
            iconColor: Colors.blueAccent,
            title: "pengingat_shift_title".tr(),
            description: "pengingat_shift_desc".tr(),
            waktu: "pengingat_sistem_otomatis".tr(),
          ),
          const SizedBox(height: 10),

          // 3. PENGINGAT ADMINISTRASI (ORANYE) EVALUASI
          _buildReminderCard(
            icon: Icons.assignment_ind_rounded,
            iconColor: Colors.orange,
            title: "pengingat berkas title".tr(), // Menyesuaikan dengan id.json
            description: "pengingat_berkas_desc".tr(),
            waktu: "pengingat_1_hari_lalu".tr(),
          ),
        ],
      ),
    );
  }

  // WIDGET PEMBANTU: KARTU PENGINGAT
  Widget _buildReminderCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String waktu,
    bool isUrgent = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: isUrgent
            ? Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: isUrgent
                ? Colors.redAccent.withOpacity(0.05)
                : Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // IKON BULAT DI KIRI
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 15),
            // ISI TEKS DI KANAN
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isUrgent
                                ? Colors.redAccent.shade700
                                : const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        waktu,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
