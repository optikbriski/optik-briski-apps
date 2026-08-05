import 'package:flutter/material.dart';

import '../../../shared/member/member_session.dart';
import '../../../shared/member/member_status_watch.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';

class MemberNotificationsPage extends StatefulWidget {
  const MemberNotificationsPage({super.key});

  @override
  State<MemberNotificationsPage> createState() =>
      _MemberNotificationsPageState();
}

class _MemberNotificationsPageState extends State<MemberNotificationsPage> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    if (MemberSession.instance.isLoggedIn && _enabled) {
      MemberStatusWatch.instance.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MemberPremiumScaffold(
      title: 'Notifikasi',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: OptikMemberTokens.blue,
            title: const Text('Pantau perubahan status',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text(
              'Realtime saat admin update status / kirim nota. '
              'Poll jadi cadangan jika koneksi broadcast putus.',
            ),
            value: _enabled,
            onChanged: (v) async {
              setState(() => _enabled = v);
              if (v && MemberSession.instance.isLoggedIn) {
                await MemberStatusWatch.instance.start();
              } else {
                MemberStatusWatch.instance.stop();
              }
            },
          ),
          const SizedBox(height: 12),
          const MemberSectionLabel('Yang dikirim'),
          ...const [
            'Pesanan diproses / dikemas (termasuk Belanja Online)',
            'Siap diambil atau siap dikirim',
            'Dalam pengiriman / resi kurir',
            'Sudah diambil / pesanan selesai',
            'Reminder janji kontrol (jadwal booking)',
            'Info garansi dari data asli sistem',
          ].map(
            (t) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OptikMemberTokens.white,
                borderRadius:
                    BorderRadius.circular(OptikMemberTokens.radiusSm),
                border: Border.all(color: OptikMemberTokens.lineSoft),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_outlined,
                      color: OptikMemberTokens.blue, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tidak ada reminder “DP jatuh tempo” — barang hanya bisa diambil setelah lunas.',
            style: TextStyle(
              color: OptikMemberTokens.inkMuted,
              height: 1.4,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
