import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class BantuanPage extends StatelessWidget {
  const BantuanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text(
          "bantuan_title".tr(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. HEADER BANTUAN
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.support_agent_rounded,
                  size: 60,
                  color: Colors.blueAccent.shade100,
                ),
                const SizedBox(height: 15),
                Text(
                  "bantuan_header".tr(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  "bantuan_desc".tr(),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 2. DAFTAR FAQ (PERTANYAAN UMUM)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  "bantuan_faq_title".tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.grey),
                ),
                const SizedBox(height: 15),
                _buildFaqItem("bantuan_ql".tr(), "bantuan_al".tr()),
                _buildFaqItem("bantuan_q2".tr(), "bantuan_a2".tr()),
                _buildFaqItem("bantuan_q3".tr(), "bantuan_a3".tr()),
                _buildFaqItem("bantuan_q4".tr(), "bantuan_a4".tr()),
                const SizedBox(height: 30),
              ],
            ),
          ),

          // 3. TOMBOL WHATSAPP ADMIN (Nempel di bawah)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                )
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600, // Warna khas WhatsApp
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("bantuan_msg_wa".tr()),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                icon: const Icon(Icons.chat_rounded, color: Colors.white),
                label: Text(
                  "bantuan_btn_wa".tr(),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET PEMBANTU: KOTAK PERTANYAAN (EXPANSION TILE)
  Widget _buildFaqItem(String tanya, String jawab) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: Text(
          tanya,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF1E293B)),
        ),
        iconColor: Colors.blueAccent,
        childrenPadding: const EdgeInsets.only(left: 15, right: 15, bottom: 15),
        children: [
          Text(
            jawab,
            style: const TextStyle(
                color: Colors.blueGrey, fontSize: 13, height: 1.5),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }
}
