// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/logistics/logistics_tracking_service.dart';
import '../../shared/logistics/request_order_service.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/qr/obr_codes.dart';
import '../../shared/responsive.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/zoomable_network_image.dart';
import 'do_preparing_page.dart';

/// Laporan riwayat mutasi stok (DO / RO / Retur) + aksi terima.
class StockMoveReport extends StatefulWidget {
  final Map<String, dynamic> profile;
  const StockMoveReport({super.key, required this.profile});

  @override
  State<StockMoveReport> createState() => _StockMoveReportState();
}

class _StockMoveReportState extends State<StockMoveReport> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<dynamic> allHistory = [];
  List<dynamic> filteredHistory = [];
  bool isLoading = true;
  bool _receiving = false;
  String errorLog = '';
  final searchController = TextEditingController();
  final ImagePicker picker = ImagePicker();

  /// Filter jenis: all | do | ro | retur | other
  String selectedKind = 'all';

  /// Filter status DB (PREPARING, WAITING, …). Chip "Disiapkan" = keduanya.
  Set<String> selectedStatuses = {};

  // KPI volume (pcs) — jujur; nilai Rp hanya jika harga modal ada.
  int kpiDisiapkan = 0;
  int kpiJalan = 0;
  int kpiDiterima = 0;
  int kpiBatal = 0;

  String get _myToko {
    final t = widget.profile['toko_id']?.toString().trim().toUpperCase() ?? '';
    return t == 'NULL' ? '' : t;
  }

  String get _myRole =>
      widget.profile['role']?.toString().toLowerCase().trim() ?? '';

  bool get _isPusatView =>
      _myToko == 'PUSAT' ||
      _myRole == 'super_admin' ||
      _myRole == 'owner' ||
      _myRole == 'admin_pusat';

  /// Klasifikasi: do | ro | retur | other
  String _moveKind(dynamic item) {
    final tipe = (item['tipe'] ?? '').toString().toUpperCase();
    final resi = (item['product_name'] ?? '').toString().toUpperCase();
    final ket = (item['keterangan'] ?? '').toString();

    if (tipe == 'RETUR' || resi.startsWith('RET-')) return 'retur';
    if (tipe == 'REQUEST' ||
        resi.startsWith('RO-') ||
        ket.contains('RequestOrder#')) {
      return 'ro';
    }
    if (tipe == 'DELIVERY' || resi.startsWith('DO-')) return 'do';
    return 'other';
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'ro':
        return 'RO';
      case 'retur':
        return 'Retur';
      case 'do':
        return 'DO';
      case 'other':
        return 'Lainnya';
      default:
        return 'Semua';
    }
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'ro':
        return OptikAdminTokens.ice;
      case 'retur':
        return OptikAdminTokens.slate;
      case 'do':
        return OptikAdminTokens.warning;
      case 'other':
        return OptikAdminTokens.textMuted;
      default:
        return OptikAdminTokens.textSecondary;
    }
  }

  String _statusLabel(String? status) =>
      LogisticsTrackingService.statusLabel(status);

  String _emptyMessageForKind() {
    switch (selectedKind) {
      case 'do':
        return 'smr_kosong_restock'.tr();
      case 'ro':
        return 'smr_kosong_request'.tr();
      case 'retur':
        return 'smr_kosong_retur'.tr();
      default:
        return 'smr_kosong'.tr();
    }
  }

  (int volume, int nilai) _itemTotals(dynamic item) {
    final rawItems = (item['keterangan'] ?? '').toString();
    var volume = 0;
    var nilai = 0;
    if (rawItems.contains('[{')) {
      try {
        final jsonPart = rawItems.substring(rawItems.indexOf('[{'));
        final itemsObj = jsonDecode(jsonPart) as List;
        for (final itm in itemsObj) {
          final qty = int.tryParse(itm['qty'].toString()) ?? 0;
          final harga = int.tryParse(itm['harga']?.toString() ?? '') ??
              int.tryParse(itm['harga_modal']?.toString() ?? '0') ??
              0;
          volume += qty;
          if (harga > 0) nilai += qty * harga;
        }
      } catch (_) {}
    }
    if (volume <= 0) {
      volume = int.tryParse(item['jumlah']?.toString() ?? '0') ?? 0;
    }
    return (volume, nilai);
  }

  void _recomputeKpis(List<dynamic> scope) {
    var disiapkan = 0;
    var jalan = 0;
    var diterima = 0;
    var batal = 0;

    for (final item in scope) {
      final status = (item['status'] ?? 'PENDING').toString().toUpperCase();
      final vol = _itemTotals(item).$1;

      if (status == 'PREPARING' || status == 'WAITING') {
        disiapkan += vol;
      } else if (status == 'TRANSIT' || status == 'PENDING') {
        jalan += vol;
      } else if (status == 'SUCCESS') {
        diterima += vol;
      } else if (status == 'BATAL' || status == 'REJECTED') {
        batal += vol;
      }
    }

    kpiDisiapkan = disiapkan;
    kpiJalan = jalan;
    kpiDiterima = diterima;
    kpiBatal = batal;
  }

  String? _resolveFotoUrl(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty || s == '-') return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    // Legacy typo column / storage key only.
    try {
      return supabase.storage.from('attendance_photos').getPublicUrl(s);
    } catch (_) {
      try {
        return supabase.storage.from('verification-proofs').getPublicUrl(s);
      } catch (_) {
        return s;
      }
    }
  }

  String _formatWhen(dynamic iso) {
    final raw = iso?.toString() ?? '';
    if (raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    return DateFormat('dd/MM/yy HH:mm').format(dt);
  }

  @override
  void initState() {
    super.initState();
    _fetchMoveHistory();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String _cleanKeterangan(String raw) {
    if (raw.trim().isEmpty) return '-';
    if (raw.trim().startsWith('[')) {
      try {
        final items = jsonDecode(raw) as List;
        return items.map((it) => "${it['nama']} (${it['qty']}x)").join(', ');
      } catch (e) {
        return raw;
      }
    }
    if (raw.contains('[{')) {
      try {
        final jsonPart = raw.substring(raw.indexOf('[{'));
        final items = jsonDecode(jsonPart) as List;
        return items.map((it) => "${it['nama']} (${it['qty']}x)").join(', ');
      } catch (e) {
        return raw;
      }
    }
    if (raw.contains('DATA: [')) {
      try {
        final jsonPart = raw.substring(raw.indexOf('DATA: ') + 6);
        final alasan = raw.substring(0, raw.indexOf(' DATA: '));
        final items = jsonDecode(jsonPart) as List;
        return "$alasan\n${items.map((it) => "${it['nama']} (${it['qty']}x)").join(', ')}";
      } catch (e) {
        return raw;
      }
    }
    return raw;
  }

  Future<void> _fetchMoveHistory({bool resetFilters = false}) async {
    try {
      if (mounted) setState(() => isLoading = true);

      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 90))
          .toIso8601String();

      final List response;
      if (!_isPusatView && _myToko.isNotEmpty) {
        response = await supabase
            .from('stock_move_history')
            .select()
            .gte('created_at', since)
            .or('dari_lokasi.eq.$_myToko,ke_lokasi.eq.$_myToko')
            .order('created_at', ascending: false)
            .limit(400) as List;
      } else {
        response = await supabase
            .from('stock_move_history')
            .select()
            .gte('created_at', since)
            .order('created_at', ascending: false)
            .limit(400) as List;
      }
      if (!mounted) return;

      var targetScope = List<dynamic>.from(response);
      if (!_isPusatView && _myToko.isNotEmpty) {
        targetScope = targetScope.where((item) {
          final ke = (item['ke_lokasi'] ?? '').toString().toUpperCase();
          final dari = (item['dari_lokasi'] ?? '').toString().toUpperCase();
          return ke == _myToko || dari == _myToko;
        }).toList();
      }

      setState(() {
        allHistory = targetScope;
        if (resetFilters) {
          selectedKind = 'all';
          selectedStatuses.clear();
          searchController.clear();
        }
        errorLog = '';
        isLoading = false;
      });
      _filterHistory();
    } catch (e) {
      if (mounted) {
        setState(() {
          allHistory = [];
          filteredHistory = [];
          kpiDisiapkan = 0;
          kpiJalan = 0;
          kpiDiterima = 0;
          kpiBatal = 0;
          isLoading = false;
          errorLog = e.toString();
        });
      }
    }
  }

  void _filterHistory() {
    final query = searchController.text.toLowerCase().trim();
    setState(() {
      filteredHistory = allHistory.where((item) {
        final kind = _moveKind(item);
        final matchesKind = selectedKind == 'all' || kind == selectedKind;

        final kurir = (item['kurir_nama'] ?? '').toString();
        final searchString =
            '${item['product_name']} ${item['dari_lokasi']} ${item['ke_lokasi']} ${item['keterangan']} $kurir'
                .toLowerCase();
        final matchesSearch = query.isEmpty || searchString.contains(query);

        final itemStatus =
            (item['status'] ?? 'PENDING').toString().toUpperCase();
        final matchesStatus =
            selectedStatuses.isEmpty || selectedStatuses.contains(itemStatus);

        return matchesKind && matchesSearch && matchesStatus;
      }).toList();
      _recomputeKpis(filteredHistory);
    });
  }

  void _toggleStatusGroup(List<String> codes) {
    final allOn = codes.every(selectedStatuses.contains);
    setState(() {
      if (allOn) {
        selectedStatuses.removeAll(codes);
      } else {
        selectedStatuses.addAll(codes);
      }
    });
    _filterHistory();
  }

  static const _panelSoft = OptikAdminTokens.bgMid;

  int _countKind(String kind) {
    if (kind == 'all') return allHistory.length;
    return allHistory.where((e) => _moveKind(e) == kind).length;
  }

  void _selectKind(String kind) {
    setState(() => selectedKind = kind);
    _filterHistory();
  }

  void _runSearch(String q) {
    _filterHistory();
  }

  // FUNGSI 1: KONFIRMASI TERIMA (POPUP & PERSYARATAN AKUNTANSI)
  void _confirmTerima(dynamic item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("smr_konfirmasi_terima".tr(),
            style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        content: Text(
          "smr_tanya_terima".tr(),
          style: const TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 12),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("BATAL", style: TextStyle(color: OptikAdminTokens.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: OptikAdminTokens.accent),
            onPressed: () {
              Navigator.pop(ctx);
              _prosesTerimaPaket(item);
            },
            child: Text("smr_btn_foto_terima".tr(),
                style: const TextStyle(color: OptikAdminTokens.navy, fontSize: 12)),
          )
        ],
      ),
    );
  }

  Future<void> _prosesTerimaPaket(dynamic task) async {
    if (_receiving || isLoading) return;
    final moveId = task['id'].toString();

    // Re-fetch: cegah double terima / status sudah berubah.
    final fresh = await supabase
        .from('stock_move_history')
        .select()
        .eq('id', moveId)
        .maybeSingle();
    if (fresh == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Surat jalan tidak ditemukan.'),
        backgroundColor: OptikAdminTokens.danger,
      ));
      return;
    }
    final st = (fresh['status'] ?? '').toString().toUpperCase();
    if (st == 'SUCCESS') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Paket sudah diterima sebelumnya.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      _fetchMoveHistory();
      return;
    }
    if (st != 'TRANSIT' && st != 'PENDING') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Tidak bisa terima. Status saat ini: ${_statusLabel(st)}.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      _fetchMoveHistory();
      return;
    }

    final photo = await pickImageSafe(
      picker: picker,
      context: context,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 50,
    );
    if (photo == null) return;

    setState(() {
      _receiving = true;
      isLoading = true;
    });
    try {
      final bytes = await photo.readAsBytes();
      final path =
          'konfirmasi/${moveId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage
          .from('attendance_photos')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));

      final imgUrl =
          supabase.storage.from('attendance_photos').getPublicUrl(path);

      final myToko = _myToko.isNotEmpty ? _myToko : 'PUSAT';
      final rawItems = (fresh['keterangan'] ?? '').toString();

      final verifierId = widget.profile['id']?.toString() ??
          widget.profile['user_id']?.toString() ??
          supabase.auth.currentUser?.id ??
          '';
      final verifierName = widget.profile['nama']?.toString() ??
          widget.profile['full_name']?.toString() ??
          'Admin';

      final tipe = (fresh['tipe'] ?? '').toString().toUpperCase();
      final resiName = (fresh['product_name'] ?? '').toString();
      final isReturn =
          tipe == 'RETUR' || resiName.toUpperCase().startsWith('RET-');

      await StockMutationService().receiveItemsFromMoveKeterangan(
        tokoId: myToko,
        keterangan: rawItems,
        jumlahFlat: int.tryParse(fresh['jumlah']?.toString() ?? '0') ?? 0,
        reason: StockReason.transferIn,
        refType: 'stock_move',
        refId: moveId,
        actorNama: verifierName,
        isReturn: isReturn,
      );

      await supabase.from('stock_move_history').update({
        'status': 'SUCCESS',
        'bukti_foto_penerima': imgUrl,
        'verified_by': verifierId,
        'verified_by_name': verifierName,
        'verified_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', moveId);

      try {
        await RequestOrderService().markSuccessFromMove(
          stockMoveId: moveId,
          resi: resiName,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Diterima, tapi sync Request Order gagal: $e'),
            backgroundColor: OptikAdminTokens.warning,
          ));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("smr_sukses_terima".tr()),
          backgroundColor: OptikAdminTokens.success));
      await _fetchMoveHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal terima paket: $e'),
          backgroundColor: OptikAdminTokens.danger));
      setState(() => isLoading = false);
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  // FUNGSI 3: DETAIL DRILL-DOWN — premium + foto full (contain + lightbox)
  void _showDetail(dynamic item) {
    final kind = _moveKind(item);
    final kindColor = _kindColor(kind);
    final status = (item['status'] ?? '-').toString().toUpperCase();
    final resi = (item['product_name'] ?? item['id'] ?? '-').toString();
    final dari = (item['dari_lokasi'] ?? '-').toString();
    final ke = (item['ke_lokasi'] ?? '-').toString();
    final paket = _cleanKeterangan(item['keterangan'] ?? '');
    final showQr =
        status == 'PREPARING' || status == 'WAITING' || status == 'TRANSIT';
    final verifiedName = (item['verified_by_name'] ?? '').toString().trim();
    final verifiedAtRaw = item['verified_at']?.toString();
    String verifiedAt = '-';
    if (verifiedAtRaw != null && verifiedAtRaw.isNotEmpty) {
      final dt = DateTime.tryParse(verifiedAtRaw)?.toLocal();
      verifiedAt = dt == null
          ? verifiedAtRaw
          : DateFormat('dd/MM/yyyy HH:mm').format(dt);
    }

    final kurirNama = (item['kurir_nama'] ?? '').toString().trim();
    final createdLabel = _formatWhen(item['created_at']);

    final qrData = () {
      final tujuan = item['ke_lokasi']?.toString();
      final resiCode = item['product_name']?.toString() ?? '';
      if (kind == 'ro') {
        return ObrRo.encode(resi: resiCode, tujuan: tujuan);
      }
      if (kind == 'do') {
        return ObrDo.encode(resi: resiCode, tujuan: tujuan);
      }
      // Retur / lainnya: QR by resi DO-compatible for scanners that match resi.
      return ObrDo.encode(resi: resiCode, tujuan: tujuan);
    }();
    final showQrSafe = showQr && kind != 'other' && qrData.isNotEmpty;

    showDialog(
      context: context,
      barrierColor: OptikAdminTokens.navy.withOpacity(0.72),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: R.constrainedDialog(
          context: ctx,
          preferWidth: 520,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
            ),
            decoration: BoxDecoration(
              color: OptikAdminTokens.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: OptikAdminTokens.navy.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: kindColor.withOpacity(0.12),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: kindColor.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kindColor.withOpacity(0.35)),
                        ),
                        child: Icon(Icons.local_shipping_rounded,
                            color: kindColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "smr_detail_transaksi".tr().toUpperCase(),
                              style: TextStyle(
                                color: OptikAdminTokens.navy.withOpacity(0.45),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              resi,
                              style: const TextStyle(
                                color: OptikAdminTokens.navy,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded,
                            color: OptikAdminTokens.textMuted, size: 20),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _detailBadge(_kindLabel(kind), kindColor),
                            _detailBadge(
                                _statusLabel(status), _statusAccent(status)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _detailRouteCard(dari, ke),
                        const SizedBox(height: 12),
                        _detailInfoCard(
                          label: 'Dibuat',
                          value: createdLabel,
                          icon: Icons.schedule_rounded,
                        ),
                        if (kurirNama.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _detailInfoCard(
                            label: 'Kurir',
                            value: kurirNama,
                            icon: Icons.delivery_dining_rounded,
                          ),
                        ],
                        const SizedBox(height: 8),
                        _detailInfoCard(
                          label: "smr_isi_paket".tr(),
                          value: paket.isEmpty ? '-' : paket,
                          icon: Icons.inventory_2_outlined,
                        ),
                        const SizedBox(height: 8),
                        _detailInfoCard(
                          label: "smr_id".tr(),
                          value: item['id']?.toString() ?? '-',
                          icon: Icons.tag_rounded,
                          mono: true,
                        ),
                        if (showQrSafe) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  OptikAdminTokens.warning.withOpacity(0.12),
                                  OptikAdminTokens.warning.withOpacity(0.04),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: OptikAdminTokens.warning.withOpacity(0.35),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  "smr_scan_qr_update".tr(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: OptikAdminTokens.warning,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: OptikAdminTokens.navy,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: OptikAdminTokens.warning
                                            .withOpacity(0.18),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: QrImageView(
                                    data: qrData,
                                    version: QrVersions.auto,
                                    size: 168,
                                    backgroundColor: OptikAdminTokens.snow,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        PremiumSectionHeader(
                          label: 'Bukti foto',
                          padding: const EdgeInsets.only(bottom: 10),
                        ),
                        _buildFotoSection(
                          title: "smr_bukti_pengirim".tr(),
                          url: _resolveFotoUrl(item['bukti_foto_pengirim']) ??
                              item['bukti_foto_pengirim'],
                          accent: OptikAdminTokens.navy,
                        ),
                        const SizedBox(height: 12),
                        _buildFotoSection(
                          title: 'Bukti kurir',
                          url: _resolveFotoUrl(item['bukti_foto_kurir']) ??
                              item['bukti_foto_kurir'],
                          accent: OptikAdminTokens.warning,
                        ),
                        const SizedBox(height: 12),
                        _buildFotoSection(
                          title: "smr_bukti_penerima".tr(),
                          url: _resolveFotoUrl(item['bukti_foto_penerima']) ??
                              _resolveFotoUrl(item['bukti_foto_penerim']) ??
                              item['bukti_foto_penerima'],
                          accent: OptikAdminTokens.navy,
                        ),
                        if (verifiedName.isNotEmpty ||
                            verifiedAtRaw != null) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _detailInfoCard(
                                  label: 'Diterima oleh',
                                  value: verifiedName.isEmpty
                                      ? '-'
                                      : verifiedName,
                                  icon: Icons.person_outline_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _detailInfoCard(
                                  label: 'Waktu terima',
                                  value: verifiedAt,
                                  icon: Icons.schedule_rounded,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OptikAdminTokens.navy,
                        side: BorderSide(
                            color: OptikAdminTokens.navy.withOpacity(0.25)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Tutup',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusAccent(String status) {
    switch (status.toUpperCase()) {
      case 'SUCCESS':
      case 'RECEIVED':
      case 'DONE':
        return OptikAdminTokens.success;
      case 'TRANSIT':
      case 'SHIPPING':
        return OptikAdminTokens.warning;
      case 'PREPARING':
      case 'WAITING':
        return OptikAdminTokens.ice;
      case 'CANCEL':
      case 'BATAL':
      case 'FAILED':
        return OptikAdminTokens.danger;
      default:
        return OptikAdminTokens.ice;
    }
  }

  Widget _detailBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _detailRouteCard(String dari, String ke) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OptikAdminTokens.navy.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptikAdminTokens.navy.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dari',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dari,
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: OptikAdminTokens.warning.withOpacity(0.12),
              shape: BoxShape.circle,
              border:
                  Border.all(color: OptikAdminTokens.warning.withOpacity(0.35)),
            ),
            child: const Icon(Icons.arrow_forward_rounded,
                color: OptikAdminTokens.warning, size: 18),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Ke',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ke,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailInfoCard({
    required String label,
    required String value,
    required IconData icon,
    bool mono = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OptikAdminTokens.navy.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.navy.withOpacity(0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: OptikAdminTokens.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: mono ? 11 : 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    fontFamily: mono ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoSection({
    required String title,
    required dynamic url,
    required Color accent,
  }) {
    final raw = url?.toString().trim() ?? '';
    final hasFoto = raw.isNotEmpty && raw != '-';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 16, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.replaceAll(':', ''),
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (hasFoto)
                TextButton.icon(
                  onPressed: () => showZoomableImageDialog(context, raw),
                  icon: Icon(Icons.open_in_full_rounded,
                      size: 14, color: accent),
                  label: Text(
                    'Full',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasFoto)
            Container(
              height: 160,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: OptikAdminTokens.lineStrong,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OptikAdminTokens.navy.withOpacity(0.06)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_not_supported_outlined,
                      color: OptikAdminTokens.navy.withOpacity(0.25), size: 28),
                  const SizedBox(height: 8),
                  Text(
                    "smr_belum_ada_foto".tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: OptikAdminTokens.navy.withOpacity(0.35),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            )
          else
            // Full frame: contain (bukan crop), tinggi besar, bisa pinch/full.
            ZoomableNetworkImagePane(
              url: raw,
              aspectRatio: 4 / 3,
              borderRadius: 12,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required List<String> codes,
    required Color badgeColor,
  }) {
    final isActive = codes.every(selectedStatuses.contains);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _toggleStatusGroup(codes),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? badgeColor.withOpacity(0.16) : _panelSoft,
            border: Border.all(
                color: isActive
                    ? badgeColor.withOpacity(0.7)
                    : OptikAdminTokens.lineStrong),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? badgeColor : OptikAdminTokens.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _kindTile({
    required String kind,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final active = selectedKind == kind;
    final count = _countKind(kind);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: OptikAdminTokens.spaceXs),
        child: Material(
          color: active ? color.withOpacity(0.14) : _panelSoft,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _selectKind(kind),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active ? color.withOpacity(0.55) : Colors.transparent,
                ),
              ),
              child: Column(
                children: [
                  Icon(icon,
                      size: 16,
                      color: active ? color : OptikAdminTokens.textMuted),
                  const SizedBox(height: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: active ? color : OptikAdminTokens.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? color : OptikAdminTokens.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
    );
  }

  Widget _moveCard(dynamic item) {
    final myToko = _myToko;
    final status = (item['status'] ?? 'PENDING').toString().toUpperCase();
    final kind = _moveKind(item);
    final kindColor = _kindColor(kind);
    final amITheReceiver =
        (item['ke_lokasi'] ?? '').toString().toUpperCase() == myToko;
    final amITheSender =
        (item['dari_lokasi'] ?? '').toString().toUpperCase() == myToko;
    final kurir = (item['kurir_nama'] ?? '').toString().trim();
    final when = _formatWhen(item['created_at']);
    final statusColor = _statusAccent(status);
    final canOpenPreparing = kind == 'do' &&
        (status == 'PREPARING' || status == 'WAITING') &&
        (amITheSender || _isPusatView);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: OptikAdminTokens.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.35)),
        boxShadow: OptikAdminTokens.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['product_name'] ?? '-'}',
                    style: const TextStyle(
                      color: OptikAdminTokens.navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _miniBadge(_kindLabel(kind), kindColor),
                const SizedBox(width: 5),
                _miniBadge(_statusLabel(status), statusColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${item['jumlah'] ?? 0} pcs · ${item['dari_lokasi'] ?? '-'} → ${item['ke_lokasi'] ?? '-'}',
              style: TextStyle(
                color: kindColor.withOpacity(0.95),
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              kurir.isEmpty ? when : '$when · Kurir $kurir',
              style: const TextStyle(
                fontSize: 10.5,
                color: OptikAdminTokens.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _cleanKeterangan(item['keterangan'] ?? ''),
              style: const TextStyle(
                fontSize: 11,
                color: OptikAdminTokens.textMuted,
                height: 1.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (amITheSender || amITheReceiver || _isPusatView)
                  TextButton.icon(
                    onPressed: () => _showDetail(item),
                    style: TextButton.styleFrom(
                      foregroundColor: OptikAdminTokens.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.info_outline_rounded, size: 16),
                    label: const Text('Detail',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                const Spacer(),
                if (canOpenPreparing)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DoPreparingPage(
                            profile: widget.profile,
                            moveId: item['id'].toString(),
                          ),
                        ),
                      ).then((_) => _fetchMoveHistory());
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: OptikAdminTokens.navy,
                      foregroundColor: OptikAdminTokens.snow,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.fact_check_rounded, size: 15),
                    label: const Text('Disiapkan',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
                if ((status == 'TRANSIT' || status == 'PENDING') &&
                    amITheReceiver) ...[
                  if (canOpenPreparing) const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _receiving ? null : () => _confirmTerima(item),
                    style: FilledButton.styleFrom(
                      backgroundColor: OptikAdminTokens.success,
                      foregroundColor: OptikAdminTokens.snow,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 15),
                    label: Text("smr_btn_terima".tr(),
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // VIEW SCREEN LAYOUT RENDER METHOD BUILD
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    final unitLabel =
        '${_myToko.isEmpty ? 'Unit' : _myToko} · ${filteredHistory.length} data · 90 hari';

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: "smr_title".tr(),
        subtitle: "smr_subtitle".tr(),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => _fetchMoveHistory(),
            icon: const Icon(Icons.refresh_rounded,
                size: 18, color: OptikAdminTokens.textSecondary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: PremiumPanel(
              padding: const EdgeInsets.all(8),
              borderRadius: 14,
              child: Row(
                children: [
                  _kindTile(
                    kind: 'all',
                    label: 'Semua',
                    icon: Icons.layers_rounded,
                    color: OptikAdminTokens.textSecondary,
                  ),
                  _kindTile(
                    kind: 'do',
                    label: 'DO',
                    icon: Icons.local_shipping_rounded,
                    color: OptikAdminTokens.warning,
                  ),
                  _kindTile(
                    kind: 'ro',
                    label: 'RO',
                    icon: Icons.playlist_add_check_rounded,
                    color: OptikAdminTokens.navy,
                  ),
                  _kindTile(
                    kind: 'retur',
                    label: 'Retur',
                    icon: Icons.undo_rounded,
                    color: OptikAdminTokens.slate,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PremiumSectionHeader(
                  label: 'Ringkasan (pcs)',
                  padding: EdgeInsets.only(bottom: 8, top: 2),
                ),
                PremiumStatGrid(
                  items: [
                    PremiumStatItem(
                      label: 'Disiapkan',
                      value: '$kpiDisiapkan',
                      color: OptikAdminTokens.ice,
                    ),
                    PremiumStatItem(
                      label: 'Jalan',
                      value: '$kpiJalan',
                      color: OptikAdminTokens.warning,
                    ),
                    PremiumStatItem(
                      label: 'Diterima',
                      value: '$kpiDiterima',
                      color: OptikAdminTokens.success,
                    ),
                    PremiumStatItem(
                      label: 'Batal',
                      value: '$kpiBatal',
                      color: OptikAdminTokens.danger,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: PremiumPanel(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              borderRadius: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: _runSearch,
                    style: const TextStyle(
                        color: OptikAdminTokens.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Cari resi, cabang, kurir…',
                      hintStyle: const TextStyle(
                          color: OptikAdminTokens.textMuted, fontSize: 12.5),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: OptikAdminTokens.textMuted, size: 20),
                      filled: true,
                      fillColor: OptikAdminTokens.bg.withOpacity(0.55),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: OptikAdminTokens.lineStrong),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: OptikAdminTokens.navy, width: 1.3),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          unitLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: OptikAdminTokens.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (selectedStatuses.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() => selectedStatuses.clear());
                            _filterHistory();
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: OptikAdminTokens.textMuted,
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text('Reset filter',
                              style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PremiumChipWrap(
                    children: [
                      _buildStatusChip(
                        label: 'Disiapkan',
                        codes: const ['PREPARING', 'WAITING'],
                        badgeColor: OptikAdminTokens.ice,
                      ),
                      _buildStatusChip(
                        label: 'Dalam perjalanan',
                        codes: const ['TRANSIT'],
                        badgeColor: OptikAdminTokens.warning,
                      ),
                      _buildStatusChip(
                        label: 'Menunggu',
                        codes: const ['PENDING'],
                        badgeColor: OptikAdminTokens.warning,
                      ),
                      _buildStatusChip(
                        label: 'Diterima',
                        codes: const ['SUCCESS'],
                        badgeColor: OptikAdminTokens.success,
                      ),
                      _buildStatusChip(
                        label: 'Dibatalkan',
                        codes: const ['BATAL', 'REJECTED'],
                        badgeColor: OptikAdminTokens.danger,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: OptikAdminTokens.ice))
                : errorLog.isNotEmpty
                    ? PremiumEmptyState(
                        message: 'Gagal memuat riwayat.\n$errorLog',
                        icon: Icons.error_outline_rounded,
                        accent: OptikAdminTokens.danger,
                        action: FilledButton(
                          onPressed: () => _fetchMoveHistory(),
                          child: const Text('Coba lagi'),
                        ),
                      )
                    : filteredHistory.isEmpty
                        ? PremiumEmptyState(
                            message: _emptyMessageForKind(),
                            icon: Icons.inventory_2_outlined,
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(12, 0, 12, 20),
                            itemCount: filteredHistory.length,
                            itemBuilder: (context, index) =>
                                _moveCard(filteredHistory[index]),
                          ),
          ),
        ],
      ),
    );
  }
}
