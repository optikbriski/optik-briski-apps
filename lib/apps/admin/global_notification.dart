import 'package:flutter/material.dart';

import '../../shared/admin/admin_nav_badge_service.dart';
import '../../shared/logistics/receive_verification_rules.dart';
import '../../shared/theme.dart';
import 'verifikasi_terima.dart';

/// Lonceng logistik — sinkron dengan badge sidebar scope `logistik` (realtime).
class GlobalNotificationIcon extends StatelessWidget {
  const GlobalNotificationIcon({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    if (!ReceiveVerificationRules.canOpenIncomingQueue(profile)) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: AdminNavBadgeService.instance,
      builder: (context, _) {
        final pending =
            AdminNavBadgeService.instance.displayCount('logistik');
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_active_rounded,
                color: OptikAdminTokens.warning,
                size: 22,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => IncomingVerification(profile: profile),
                  ),
                );
              },
            ),
            if (pending > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: OptikAdminTokens.danger,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    pending > 9 ? '9+' : pending.toString(),
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
