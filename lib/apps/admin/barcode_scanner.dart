// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/responsive.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'sales_page.dart';

// ============================================================================
// MODUL 13: BARCODE SCANNER AI (MOBILE SCANNER OPTIMIZED) - PART 1 OF 2
// ============================================================================

class OptikBRiskiScanner extends StatefulWidget {
  final Function(String) onDetect;
  const OptikBRiskiScanner({super.key, required this.onDetect});

  @override
  State<OptikBRiskiScanner> createState() => _OptikBRiskiScannerState();
}

class _OptikBRiskiScannerState extends State<OptikBRiskiScanner> {
  // 1. KUNCI CONTROLLER: Memaksa kamera menggunakan sensor belakang dengan auto-focus tajam (NON-MIRROR)
  final MobileScannerController cameraController = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isScanComplete =
      false; // Pengaman siber agar kamera tidak menembak data berkali-kali

  @override
  void dispose() {
    cameraController
        .dispose(); // Wajib dimatikan demi mencegah overheat sensor kamera HP cabang
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "scan_title".tr(),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // LIVE FEED VIEWPORT KAMERA UTAMA
          MobileScanner(
            controller: cameraController,
            onDetect: (capture) {
              if (_isScanComplete)
                return; // Jika barcode sudah terbaca, kunci total jalur callback

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                _isScanComplete = true; // Tandai pemindaian sukses
                String code = barcodes.first.rawValue!;

                Navigator.pop(context); // Tutup overlay gerbang kamera
                widget.onDetect(
                    code); // Alirkan string barcode langsung ke modul kasir / manajemen gudang
              }
            },
          ),

          // BINGKAI LASER SCANNER SIGHT (UI Kotak Bidik Animasi Biru)
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blueAccent, width: 3),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blueAccent.withOpacity(0.1),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ],
            ),
          ),

          // PANEL TEKS INSTRUKSI FLUIDA BAWAH
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: R.widthOf(context) - 48),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      "scan_instruksi".tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class RiwayatTransaksiPage extends StatefulWidget {
  final Map<String, dynamic>?
      profile; // Menerima manifes enkripsi hak akses dari Dashboard
  const RiwayatTransaksiPage({super.key, this.profile});

  @override
  State<RiwayatTransaksiPage> createState() => _RiwayatTransaksiPageState();
}

class _RiwayatTransaksiPageState extends State<RiwayatTransaksiPage> {
  List<dynamic> listTransaksi = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRiwayat();
  }

  // --- TARIK DATA NOTA DARI DATABASE (DYNAMIC FILTERING SYSTEM) ---
  Future<void> _fetchRiwayat() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      var query =
          Supabase.instance.client.from('sales').select('*, sales_items(*)');

      // Kebijakan Otoritas: Jika Cabang, batasi data. Jika PUSAT, buka gerbang data masal seluruh cabang.
      if (widget.profile?['toko_id'] != 'PUSAT') {
        query = query.eq('toko_id', widget.profile?['toko_id'] ?? 'KOSONG');
      }

      final res = await query.order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          listTransaksi = res;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fatal Error Fetch Riwayat Sales: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- INTERFACE POP-UP: MODAL AUDIT DETAIL INTERNAL KHUSUS TIM PUSAT ---
  Future<void> _showDetailKhususPusat(
      BuildContext context, Map<String, dynamic> trx) async {
    showDialog(
      context: context,
      builder: (c) => R.constrainedDialog(
        context: c,
        child: AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings,
                color: Colors.orangeAccent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text("Detail Audit Pusat",
                  style: TextStyle(
                      color: Colors.orangeAccent.shade200,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _rowDetail("No Invoice", trx['no_invoice']),
              _rowDetail(
                  "Tanggal Nota",
                  trx['created_at'] != null
                      ? trx['created_at'].toString().split('T')[0]
                      : '-'),
              const Divider(color: Colors.white24, height: 20),
              _rowDetail("Cabang / Toko", trx['toko_id'],
                  isHighlight: true, color: Colors.amberAccent),
              _rowDetail("Nama Kasir", trx['nama_kasir']),
              _rowDetail("Nama Pelanggan", trx['nama_pelanggan']),
              _rowDetail("Status Bayar", trx['status_pembayaran']),
              const Divider(color: Colors.white24, height: 20),
              _rowDetail(
                  "Total Transaksi",
                  formatRupiah(
                      int.tryParse(trx['total_harga']?.toString() ?? '0') ?? 0),
                  isHighlight: true,
                  color: Colors.blueAccent),
              _rowDetail(
                  "Tunai Masuk",
                  formatRupiah(
                      int.tryParse(trx['dibayarkan']?.toString() ?? '0') ?? 0),
                  isHighlight: true,
                  color: Colors.greenAccent),
              _rowDetail(
                  "Sisa Piutang (DP)",
                  formatRupiah(
                      int.tryParse(trx['sisa_tagihan']?.toString() ?? '0') ??
                          0),
                  isHighlight: true,
                  color: Colors.redAccent),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("Tutup",
                  style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)))
        ],
      ),
      ),
    );
  }

  Widget _rowDetail(String label, dynamic value,
      {bool isHighlight = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              value?.toString() ?? "-",
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 12,
                  fontWeight:
                      isHighlight ? FontWeight.bold : FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }

  // --- CORE UI GENERATOR ---
  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: const PremiumAppBar(title: 'Riwayat Transaksi Kasir'),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.accentSoft))
          : listTransaksi.isEmpty
              ? const PremiumEmptyState(
                  message: 'Belum ada transaksi di database',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: listTransaksi.length,
                  itemBuilder: (context, index) {
                    final trx = listTransaksi[index];
                    int totalHarga =
                        int.tryParse(trx['total_harga']?.toString() ?? '0') ??
                            0;
                    String formattedDate = trx['created_at'] != null
                        ? trx['created_at'].toString().split('T')[0]
                        : '-';

                    return Card(
                      color: OptikAdminTokens.card,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 6),
                        title: Text(trx['no_invoice'] ?? '-',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 5),
                            Text(
                                "${trx['nama_pelanggan'] ?? 'Pasien Tanpa Nama'} • ${formatRupiah(totalHarga)}",
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(formattedDate,
                                style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        trailing: Wrap(
                          spacing: 0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.receipt_long,
                                  color: Colors.blueAccent, size: 22),
                              tooltip: "Cetak / Bagikan Struk",
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => InvoiceDetailPage(
                                        saleId: trx['id'].toString()),
                                  ),
                                );
                              },
                            ),
                            if (widget.profile?['toko_id'] == 'PUSAT')
                              IconButton(
                                icon: const Icon(Icons.admin_panel_settings,
                                    color: Colors.orangeAccent, size: 22),
                                tooltip: "Detail Internal Pusat",
                                onPressed: () =>
                                    _showDetailKhususPusat(context, trx),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
