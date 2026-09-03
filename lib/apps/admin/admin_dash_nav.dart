import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/admin_approval_page.dart';
import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/config.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/tenant/tenant_modules.dart';
import '../../shared/theme.dart';
import '../../shared/training/training_curriculum.dart';
import '../../shared/app_update/app_software_update_page.dart';
import 'absensi_toko_page.dart';
import 'attendance_monitor_page.dart';
import 'buku_besar.dart';
import 'garansi_page.dart';
import 'etalase_stock_sim_page.dart';
import 'inventory.dart';
import 'admin_document_ocr_page.dart';
import 'invoice_config_page.dart';
import 'jadwal_kerja_page.dart';
import 'member_home_content_page.dart';
import 'monthly_export_page.dart';
import 'online_orders_page.dart';
import 'payroll_workspace_page.dart';
import 'pengaduan_inbox_page.dart';
import 'work_summary_page.dart';
import 'product_master.dart';
import 'reimburse_inbox_page.dart';
import 'lembur_inbox_page.dart';
import 'rekasa_store_orders_page.dart';
import 'riwayat_transaksi_page.dart';
import 'sales_page.dart';
import 'tenant_admin_page.dart';
import 'tinjauan_mencurigakan_page.dart';
import 'toko_geofence_page.dart';
import '../karyawan/toko_chat_page.dart';

class AdminDashNavItem {
  const AdminDashNavItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    this.onOpen,
    this.buildPage,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  /// Aksi tanpa halaman (scan QR, mode latihan).
  final VoidCallback? onOpen;

  /// Halaman yang dibuka di panel kanan (sidebar tetap).
  final WidgetBuilder? buildPage;
}

class AdminDashNavGroup {
  const AdminDashNavGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.items,
    this.directItem = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<AdminDashNavItem> items;

  /// Satu item di paling atas — diklik langsung, bukan folder.
  final bool directItem;
}

bool _isPlatform(Map<String, dynamic> profile) {
  return isRekasaControlPlane &&
      (profile['is_platform'] == true ||
          profile['is_platform'] == 'true' ||
          profile['role'] == 'platform');
}

WidgetBuilder _page(Widget page) => (_) => page;

/// Menu dashboard, dikelompokkan. Gerbang role/modul sama seperti grid lama.
List<AdminDashNavGroup> buildAdminDashNavGroups({
  required BuildContext context,
  required Map<String, dynamic> profile,
  VoidCallback? onToggleTraining,
}) {
  final training = TrainingCurriculum.isActive;
  final mod = TenantModules.instance;
  final role = profile['role']?.toString() ?? '';
  final toko = profile['toko_id']?.toString() ?? '';

  final dashboard = <AdminDashNavItem>[];
  final tim = <AdminDashNavItem>[];
  final jual = <AdminDashNavItem>[];
  final stok = <AdminDashNavItem>[];
  final uang = <AdminDashNavItem>[];
  final tokoGroup = <AdminDashNavItem>[];
  final platform = <AdminDashNavItem>[];

  if (!training && AttendanceAdminScope.canOpenKaryawanManagement(profile)) {
    dashboard.add(AdminDashNavItem(
      id: 'rangkuman_kerja',
      title: 'dash_menu_rangkuman'.tr(),
      icon: Icons.dashboard_customize_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(
        AdminWorkSummaryPage(
          key: const ValueKey('admin-work-summary'),
          profile: profile,
        ),
      ),
    ));
    tim.add(AdminDashNavItem(
      id: 'karyawan',
      title: 'dash_menu_management'.tr(),
      icon: Icons.verified_user_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(
        AdminApprovalPage(
          roleAdmin: role,
          cabangAdmin: toko,
          profile: profile,
        ),
      ),
    ));
  }

  if (!training) {
    tim.add(AdminDashNavItem(
      id: 'pengaduan',
      title: 'pengaduan_admin_title'.tr(),
      icon: Icons.report_gmailerrorred_rounded,
      color: OptikAdminTokens.slate,
      buildPage: _page(PengaduanInboxPage(profile: profile)),
    ));
    tim.add(AdminDashNavItem(
      id: 'reimburse',
      title: 'ops_reimburse_admin_title'.tr(),
      icon: Icons.receipt_long_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(ReimburseInboxPage(profile: profile)),
    ));
    tim.add(AdminDashNavItem(
      id: 'lembur',
      title: 'ops_lembur_admin_title'.tr(),
      icon: Icons.more_time_rounded,
      color: OptikAdminTokens.slate,
      buildPage: _page(LemburInboxPage(profile: profile)),
    ));
    tim.add(AdminDashNavItem(
      id: 'chat_toko',
      title: 'ops_chat_admin_title'.tr(),
      icon: Icons.forum_rounded,
      color: OptikAdminTokens.navy,
      buildPage: (_) {
        final tokoId = AttendanceAdminScope.tokoOf(profile);
        final pusat = AttendanceAdminScope.canViewAllStores(profile);
        return TokoChatPage(
          adminMode: true,
          tokoId: pusat ? null : tokoId,
          senderNama:
              (profile['nama'] ?? profile['login_via_karyawan_nama'] ?? 'Admin')
                  .toString(),
        );
      },
    ));
  }

  if (!training && _isPlatform(profile)) {
    platform.add(AdminDashNavItem(
      id: 'etalase',
      title: 'admin_auto_347b2a5b77'.tr(),
      icon: Icons.shopping_bag_rounded,
      color: OptikAdminTokens.navy,
      buildPage: _page(const RekasaStoreOrdersPage()),
    ));
    platform.add(AdminDashNavItem(
      id: 'umkm',
      title: 'admin_auto_47032f87e7'.tr(),
      icon: Icons.apartment_rounded,
      color: OptikAdminTokens.navy,
      buildPage: _page(TenantAdminPage(profile: profile)),
    ));
  }

  if (!training &&
      mod.allows('attendance') &&
      AttendanceAdminScope.canOpenStoreMonitor(profile)) {
    tim.add(AdminDashNavItem(
      id: 'monitor_absensi',
      title: 'dash_menu_monitor_absensi'.tr(),
      icon: Icons.fact_check_rounded,
      color: OptikAdminTokens.slate,
      buildPage: _page(AttendanceMonitorPage(profile: profile)),
    ));
  }

  if (!training &&
      mod.allows('attendance') &&
      AttendanceAdminScope.canOpenStoreKiosk(profile)) {
    tim.add(AdminDashNavItem(
      id: 'absensi_kiosk',
      title: AttendanceAdminScope.isPusatKioskLabel(profile)
          ? 'dash_menu_absensi_pusat_kiosk'.tr()
          : 'dash_menu_absensi_kiosk'.tr(),
      icon: Icons.face_retouching_natural_rounded,
      color: OptikAdminTokens.slate,
      buildPage: _page(AbsensiTokoPage(profile: profile)),
    ));
  }

  if (!training &&
      mod.allows('attendance') &&
      AttendanceAdminScope.canOpenStoreMonitor(profile)) {
    tim.add(AdminDashNavItem(
      id: 'tinjauan',
      title: 'dash_menu_tinjauan_mencurigakan'.tr(),
      icon: Icons.warning_amber_rounded,
      color: OptikAdminTokens.warning,
      buildPage: _page(TinjauanMencurigakanPage(profile: profile)),
    ));
  }

  if (!training &&
      mod.allows('attendance') &&
      AttendanceAdminScope.canManageGeofence(profile)) {
    tim.add(AdminDashNavItem(
      id: 'geofence',
      title: 'admin_auto_923fc588a3'.tr(),
      icon: Icons.radar_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(TokoGeofencePage(profile: profile)),
    ));
  }

  if (!training &&
      mod.allows('attendance') &&
      AttendanceAdminScope.canManageJadwal(profile)) {
    tim.add(AdminDashNavItem(
      id: 'jadwal',
      title: 'admin_auto_9ada9ca79d'.tr(),
      icon: Icons.calendar_month_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(JadwalKerjaPage(profile: profile)),
    ));
  }

  if (TrainingCurriculum.allows('pos') &&
      mod.allows('pos') &&
      AttendanceAdminScope.canOpenPos(profile)) {
    jual.add(AdminDashNavItem(
      id: 'pos',
      title: 'training_mod_pos'.tr(),
      icon: Icons.point_of_sale_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(SalesPage(profile: profile)),
    ));
  }

  if (TrainingCurriculum.allows('history_dp') &&
      mod.allows('history_dp') &&
      AttendanceAdminScope.canOpenPos(profile)) {
    jual.add(AdminDashNavItem(
      id: 'dp',
      title: 'admin_auto_6b93094444'.tr(),
      icon: Icons.history_edu,
      color: OptikAdminTokens.slate,
      buildPage: _page(RiwayatTransaksiPage(profile: profile)),
    ));
  }

  if (!training && mod.allows('online_orders')) {
    jual.add(AdminDashNavItem(
      id: 'online',
      title: 'admin_auto_3d45e07997'.tr(),
      icon: Icons.shopping_bag_outlined,
      color: OptikAdminTokens.ice,
      buildPage: _page(OnlineOrdersPage(profile: profile)),
    ));
  }

  if (!training && AttendanceAdminScope.canManageInventory(profile)) {
    stok.add(AdminDashNavItem(
      id: 'denah_etalase',
      title: 'Denah etalase',
      icon: Icons.storefront_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(EtalaseStockSimPage(profile: profile)),
    ));
  }

  if (TrainingCurriculum.allows('logistics') &&
      mod.allows('logistics') &&
      AttendanceAdminScope.canOpenLogistics(profile)) {
    stok.add(AdminDashNavItem(
      id: 'logistik',
      title: 'dash_menu_logistik'.tr(),
      icon: Icons.local_shipping_rounded,
      color: OptikAdminTokens.slate,
      buildPage: _page(InventoryOverview(profile: profile)),
    ));
  }

  if (TrainingCurriculum.allows('master_data') &&
      mod.allows('master_data') &&
      (training || AttendanceAdminScope.canEditProductCatalog(profile))) {
    stok.add(AdminDashNavItem(
      id: 'master',
      title: 'dash_menu_master'.tr(),
      icon: Icons.dataset_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(ProductMasterPage(profile: profile)),
    ));
  }

  if (TrainingCurriculum.allows('warranty') && mod.allows('warranty')) {
    stok.add(AdminDashNavItem(
      id: 'garansi',
      title: 'dash_menu_garansi'.tr(),
      icon: Icons.verified_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(GaransiPage(profile: profile)),
    ));
  }

  if (TrainingCurriculum.allows('finance') && mod.allows('finance')) {
    uang.add(AdminDashNavItem(
      id: 'keuangan',
      title: 'dash_menu_keuangan'.tr(),
      icon: Icons.account_balance_wallet_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(BukuBesarPage(profile: profile)),
    ));
  }

  if (TrainingCurriculum.allows('finance') &&
      mod.allows('finance') &&
      (role == 'owner' || role == 'admin_pusat' || role == 'super_admin')) {
    uang.add(AdminDashNavItem(
      id: 'payroll',
      title: 'admin_auto_eb68630404'.tr(),
      icon: Icons.payments_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(PayrollWorkspacePage(profile: profile)),
    ));
  }

  if (!training && (role == 'owner' || role == 'admin_pusat')) {
    uang.add(AdminDashNavItem(
      id: 'invoice',
      title: 'admin_auto_519b02bbf6'.tr(),
      icon: Icons.note_alt_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(InvoiceConfigPage(profile: profile)),
    ));
  }

  if (!training &&
      (toko == 'PUSAT' ||
          toko == 'CABANG-PUSAT' ||
          role == 'owner' ||
          role == 'admin_pusat')) {
    uang.add(AdminDashNavItem(
      id: 'export',
      title: 'dash_menu_export'.tr(),
      icon: Icons.picture_as_pdf_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(MonthlyExportPage(profile: profile)),
    ));
  }

  if (!training &&
      mod.allows('member_app') &&
      (role == 'owner' || role == 'admin_pusat' || role == 'super_admin')) {
    tokoGroup.add(AdminDashNavItem(
      id: 'member_home',
      title: 'admin_auto_24868215d0'.tr(),
      icon: Icons.phone_android_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(MemberHomeContentPage(profile: profile)),
    ));
  }

  tokoGroup.add(AdminDashNavItem(
    id: 'update_apk',
    title: 'dash_menu_update_apk'.tr(),
    subtitle: 'dash_menu_update_apk_sub'.tr(),
    icon: Icons.system_update_rounded,
    color: OptikAdminTokens.navy,
    buildPage: (_) => AppSoftwareUpdatePage.admin(),
  ));

  if (!training) {
    tokoGroup.add(AdminDashNavItem(
      id: 'scan_dokumen',
      title: 'ocr_admin_title'.tr(),
      icon: Icons.document_scanner_rounded,
      color: OptikAdminTokens.ice,
      buildPage: _page(const AdminDocumentOcrPage()),
    ));
    tokoGroup.add(AdminDashNavItem(
      id: 'scan_qr',
      title: 'scan_qr'.tr(),
      icon: Icons.qr_code_scanner_rounded,
      color: OptikAdminTokens.slate,
      onOpen: () => UniversalQrNav.open(
        context,
        profile: profile,
        callerRole: UniversalQrCallerRole.admin,
      ),
    ));
  }

  return [
    if (dashboard.isNotEmpty)
      AdminDashNavGroup(
        id: 'dashboard',
        label: 'dash_menu_rangkuman'.tr(),
        icon: Icons.dashboard_customize_rounded,
        items: dashboard,
        directItem: true,
      ),
    if (tim.isNotEmpty)
      AdminDashNavGroup(
        id: 'tim',
        label: 'dash_nav_group_tim'.tr(),
        icon: Icons.groups_rounded,
        items: tim,
      ),
    if (jual.isNotEmpty)
      AdminDashNavGroup(
        id: 'jual',
        label: 'dash_nav_group_jual'.tr(),
        icon: Icons.point_of_sale_rounded,
        items: jual,
      ),
    if (stok.isNotEmpty)
      AdminDashNavGroup(
        id: 'stok',
        label: 'dash_nav_group_stok'.tr(),
        icon: Icons.inventory_2_rounded,
        items: stok,
      ),
    if (uang.isNotEmpty)
      AdminDashNavGroup(
        id: 'uang',
        label: 'dash_nav_group_uang'.tr(),
        icon: Icons.account_balance_wallet_rounded,
        items: uang,
      ),
    if (tokoGroup.isNotEmpty)
      AdminDashNavGroup(
        id: 'toko',
        label: 'dash_nav_group_toko'.tr(),
        icon: Icons.storefront_rounded,
        items: tokoGroup,
      ),
    if (platform.isNotEmpty)
      AdminDashNavGroup(
        id: 'platform',
        label: 'dash_nav_group_platform'.tr(),
        icon: Icons.hub_rounded,
        items: platform,
      ),
    if (onToggleTraining != null)
      AdminDashNavGroup(
        id: 'latihan',
        label: 'dash_nav_group_latihan'.tr(),
        icon: Icons.school_rounded,
        items: [
          AdminDashNavItem(
            id: 'training_toggle',
            title: training
                ? 'training_menu_exit'.tr()
                : 'training_menu_enter'.tr(),
            subtitle: training
                ? 'training_menu_exit_desc'.tr()
                : 'training_menu_enter_desc'.tr(),
            icon: Icons.school_rounded,
            color:
                training ? OptikAdminTokens.trainingSoft : OptikAdminTokens.ice,
            onOpen: onToggleTraining,
          ),
        ],
      ),
  ];
}
