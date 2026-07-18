// ignore_for_file: use_build_context_synchronously, prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoaApprovalPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const CoaApprovalPage({super.key, required this.profile});

  @override
  State<CoaApprovalPage> createState() => _CoaApprovalPageState();
}

class _CoaApprovalPageState extends State<CoaApprovalPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> pendingItems = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchPendingManualCOA();
  }

  String _formatRupiah(dynamic angka) {
    if (angka == null) return 'Rp0';
    int value = int.tryParse(angka.toString()) ?? 0;
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String hasil =
        value.toString().replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return "Rp$hasil";
  }

  Future<void> _fetchPendingManualCOA() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final response = await supabase
          .from('finance_transactions')
          .select()
          .eq('status_konfirmasi', 'PENDING')
          .order('tanggal_transaksi', ascending: false);

      final List<Map<String, dynamic>> allPending =
          List<Map<String, dynamic>>.from(response);

      setState(() {
        pendingItems = allPending.where((item) {
          final isManual = item['referensi_id'] == null;
          final kategori = (item['kategori'] ?? '').toString().toUpperCase();
          final isBukanModal = !kategori.contains('MODAL');
          final isBukanPenutupan =
              !kategori.contains('PENUTUPAN') && !kategori.contains('CLOSING');
          return isManual && isBukanModal && isBukanPenutupan;
        }).toList();
        isLoading = false;
      });
    } catch (e) {
      _showSnackBar("❌ Gagal memuat data karantina: $e", Colors.red);
    }
  }

  Future<void> _approveTransaksi(Map<String, dynamic> item) async {
    setState(() => isLoading = true);
    try {
      await supabase
          .from('finance_transactions')
          .update({'status_konfirmasi': 'APPROVED'}).eq('id', item['id']);

      _showSnackBar(
          "🎯 Transaksi ${item['kategori']} BERHASIL DI-APPROVE!", Colors.teal);
      _fetchPendingManualCOA();
    } catch (e) {
      _showSnackBar("❌ Gagal menyetujui transaksi: $e", Colors.red);
    }
  }

  Future<void> _rejectTransaksi(Map<String, dynamic> item) async {
    setState(() => isLoading = true);
    try {
      await supabase.from('finance_transactions').delete().eq('id', item['id']);

      _showSnackBar("🗑️ Transaksi ${item['kategori']} BERHASIL DI-REJECT!",
          Colors.orangeAccent);
      _fetchPendingManualCOA();
    } catch (e) {
      _showSnackBar("❌ Gagal menolak transaksi: $e", Colors.red);
    }
  }

  void _showSnackBar(String msg, Color bgColor) {
    setState(() => isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: bgColor),
      );
    }
  }

  void _showDetailDialog(Map<String, dynamic> item) {
    String deskripsiRaw = item['deskripsi'] ?? '-';
    String memo = deskripsiRaw.contains(' | URL Bukti:')
        ? deskripsiRaw.split(' | URL Bukti:').first
        : deskripsiRaw;
    String urlFoto = deskripsiRaw.contains("URL Bukti: ")
        ? deskripsiRaw.split("URL Bukti: ").last.trim()
        : "";

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 500, // Lebar maksimal pop-up
          padding: EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Pop-up
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Detail Transaksi",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    IconButton(
                        icon: Icon(Icons.close, color: Colors.white38),
                        onPressed: () => Navigator.pop(ctx))
                  ],
                ),
                Divider(color: Colors.white10),
                SizedBox(height: 10),
                _buildDetailRow("Kategori", item['kategori']),
                _buildDetailRow("Nominal", _formatRupiah(item['nominal'])),
                _buildDetailRow("Status", item['status_pembayaran']),
                _buildDetailRow("Metode", item['metode_pembayaran']),
                _buildDetailRow("Operator", item['nama_kasir'] ?? '-'),
                SizedBox(height: 16),
                Text("MEMO",
                    style: TextStyle(
                        color: Colors.blueAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(memo,
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                SizedBox(height: 16),
                if (urlFoto.isNotEmpty && urlFoto.startsWith("http")) ...[
                  Text("BUKTI FOTO",
                      style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  SizedBox(height: 8),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(urlFoto)),
                ],
                SizedBox(height: 24),
                // Tombol Aksi
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: Colors.redAccent.withOpacity(0.5)),
                          padding: EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _rejectTransaksi(item);
                        },
                        child: Text("REJECT",
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _approveTransaksi(item);
                        },
                        child: Text("APPROVE",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("$label:",
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("🏛️ COA MANUAL APPROVAL VAULT",
            style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent))
          : pendingItems.isEmpty
              ? const Center(
                  child: Text(
                      "Brankas bersih! Tidak ada antrean approval manual COA.",
                      style: TextStyle(color: Colors.white38, fontSize: 12)))
              : ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: pendingItems.length,
                  itemBuilder: (context, index) {
                    final item = pendingItems[index];
                    bool isPemasukan = item['jenis_transaksi'] == 'PEMASUKAN' ||
                        item['jenis_transaksi'] == 'PIUTANG';

                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: InkWell(
                        onLongPress: () => _showOptionDialog(item),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        "${item['toko_id']} • ${item['kategori'].toString().toUpperCase()}",
                                        style: const TextStyle(
                                            color: Colors.blueAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(
                                        "${isPemasukan ? '+' : '-'} ${_formatRupiah(item['nominal'])} • Oleh: ${item['nama_kasir'] ?? 'Staff'}",
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 70,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.blueGrey.withOpacity(0.2),
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () => _showDetailDialog(item),
                                  child: const Text("DETAIL",
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showOptionDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Tindakan Cepat",
            style: TextStyle(color: Colors.white, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: Icon(Icons.check, color: Colors.teal),
                title: Text("Approve", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _approveTransaksi(item);
                }),
            ListTile(
                leading: Icon(Icons.close, color: Colors.red),
                title: Text("Reject", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _rejectTransaksi(item);
                }),
          ],
        ),
      ),
    );
  }
}
