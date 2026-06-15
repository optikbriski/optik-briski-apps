// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'sales_page.dart';

class RiwayatTransaksiPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RiwayatTransaksiPage({super.key, required this.profile});

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

  // --- FUNGSI TARIK DATA DARI SUPABASE ---
  Future<void> _fetchRiwayat() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      var query =
          Supabase.instance.client.from('sales').select('*, sales_items(*)');

      // Filter Cabang: Jika bukan PUSAT, hanya tampilkan data cabangnya sendiri
      if (widget.profile['toko_id'] != 'PUSAT') {
        query = query.eq('toko_id', widget.profile['toko_id'] ?? 'KOSONG');
      }

      final res = await query.order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          listTransaksi = res;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error Fetch Riwayat: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- POP-UP DETAIL AUDIT KHUSUS PUSAT ---
  Future<void> _showDetailKhususPusat(
      BuildContext context, Map<String, dynamic> trx) async {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings,
                color: Colors.orangeAccent, size: 22),
            SizedBox(width: 10),
            Text("Detail Audit Pusat",
                style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _rowDetail("No Invoice", trx['no_invoice']),
              _rowDetail(
                  "Tanggal",
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
                      color: Colors.grey, fontWeight: FontWeight.bold)))
        ],
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

  // --- TAMPILAN UTAMA (BERSIH DARI LOGIKA OPEN STORE) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: true,
        title: const Text("Riwayat Transaksi & DP",
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent))
          : listTransaksi.isEmpty
              ? const Center(
                  child: Text("Belum ada transaksi di database",
                      style: TextStyle(color: Colors.white70, fontSize: 13)))
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
                    String status = trx['status_pembayaran'] ?? 'Lunas';

                    return Card(
                      color: const Color(0xFF1E293B),
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
                                "${trx['nama_pelanggan'] ?? 'Pasien'} • ${formatRupiah(totalHarga)}",
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(formattedDate,
                                style: const TextStyle(
                                    color: Colors.blueAccent, fontSize: 11)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: status == 'Lunas'
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(status.toUpperCase(),
                                  style: TextStyle(
                                      color: status == 'Lunas'
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 5),
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
                            if (widget.profile['toko_id'] == 'PUSAT')
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
