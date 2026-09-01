import '../../shared/app_update/app_update_chrome.dart';
import '../../shared/app_update/app_update_coordinator.dart';

/// Kompatibel: Member memakai koordinator bersama.
class MemberUpdateCoordinator extends AppUpdateCoordinator {
  MemberUpdateCoordinator({super.onHasUpdate})
      : super(chrome: AppUpdateChrome.member);
}
