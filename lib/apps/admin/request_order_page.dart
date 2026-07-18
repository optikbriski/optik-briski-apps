// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RequestOrderPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RequestOrderPage({super.key, required this.profile});

  @override
  State<RequestOrderPage> createState() => _RequestOrderPageState();
}

class _RequestOrderPageState extends State<RequestOrderPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> pendingRequestsList = [];
  bool isLoading = true;

  final TextEditingController trackingSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> trackingResults = [];

  @override
  void initState() {
    super.initState();
    _loadTodayRequests();
  }

  // 💡 FIX 1: Perbaikan Query Tanggal (Ganti textSearch ke Range ISO Timestamp agar SQL tidak Error)
  Future<void> _loadTodayRequests() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final tokoId = widget.profile['toko_id'] ?? 'PUSAT';
      final todayDate = DateTime.now().toIso8601String().split('T')[0];

      // Ambil batas aman awal dan akhir hari ini dalam format ISO Timestamp resmi
      final startOfDay = "${todayDate}T00:00:00.000Z";
      final endOfDay = "${todayDate}T23:59:59.999Z";

      final res = await supabase
          .from('pending_requests')
          .select()
          .eq('toko_id', tokoId)
          .eq('status', 'PENDING')
          .gte('created_at', startOfDay)
          .lte('created_at', endOfDay);

      if (mounted) {
        setState(() {
          pendingRequestsList = List<Map<String, dynamic>>.from(res);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack("Gagal memuat data request: $e", Colors.red);
      }
    }
  }

  Future<void> _kirimKePusatMassal() async {
    if (pendingRequestsList.isEmpty) {
      _showSnack("Tidak ada antrean request order hari ini.", Colors.orange);
      return;
    }

    setState(() => isLoading = true);
    try {
      final List<int> idsToUpdate =
          pendingRequestsList.map((e) => e['id'] as int).toList();

      await supabase.from('pending_requests').update({
        'status': 'SENT_TO_HQ',
        'tracking_status': 'DIKIRIM_KE_PUSAT',
      }).inFilter('id', idsToUpdate);

      _showSnack(
          "✓ Sukses mengirim ${idsToUpdate.length} Pesanan ke Gudang Pusat!",
          Colors.green);
      _loadTodayRequests();
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showSnack("Gagal mengirim ke pusat: $e", Colors.red);
    }
  }

  Future<void> _lacakStatusTransaksi(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final res = await supabase
          .from('pending_requests')
          .select()
          .or('no_invoice.ilike.%$query%,nama_pelanggan.ilike.%$query%');

      setState(() {
        trackingResults = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      _showSnack("Gagal melacak transaksi: $e", Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("LOGISTIK & REQUEST ORDER PUSAT",
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- SEKSI 1: LIVE CRM TRACKING SYSTEM ---
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("LIVE CRM TRACKING SYSTEM",
                      style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: trackingSearchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Masukkan Nomor Invoice / Nama Customer...",
                      hintStyle:
                          const TextStyle(color: Colors.grey, fontSize: 12),
                      prefixIcon: const Icon(Icons.track_changes,
                          color: Colors.blueAccent, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search,
                            color: Colors.orangeAccent, size: 18),
                        onPressed: () =>
                            _lacakStatusTransaksi(trackingSearchCtrl.text),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                    ),
                    onSubmitted: (val) => _lacakStatusTransaksi(val),
                  ),
                  if (trackingResults.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white10),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: trackingResults.length,
                      itemBuilder: (context, idx) {
                        final track = trackingResults[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              "${track['nama_produk']} (${track['qty_request']} pcs)",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              "Invoice: ${track['no_invoice']} | Pasien: ${track['nama_pelanggan']}",
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              track['tracking_status'] ?? 'DIPROSES',
                              style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      },
                    )
                  ]
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    "ANTREAN REQUEST HARI INI",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    minimumSize: const Size(150, 40),
                    maximumSize: const Size(180, 40),
                  ),
                  icon: const Icon(Icons.send_sharp,
                      size: 14, color: Colors.white),
                  label: const Text(
                    "KIRIM KE PUSAT",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  onPressed: _kirimKePusatMassal,
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Colors.blueAccent))
                  : pendingRequestsList.isEmpty
                      ? const Center(
                          child: Text(
                              "Belum ada request order masuk untuk sesi hari ini.",
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)))
                      : ListView.builder(
                          itemCount: pendingRequestsList.length,
                          itemBuilder: (context, index) {
                            final req = pendingRequestsList[index];
                            return Card(
                              color: const Color(0xFF1E293B),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      req['tipe_request'] == 'PRE_ORDER'
                                          ? Colors.orange.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                  child: Icon(Icons.shopping_basket,
                                      color: req['tipe_request'] == 'PRE_ORDER'
                                          ? Colors.orange
                                          : Colors.red,
                                      size: 18),
                                ),
                                title: Text(req['nama_produk'] ?? 'Produk',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    "Kekurangan: ${req['qty_request']} pcs | Tipe: ${req['tipe_request']}",
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 11)),
                                trailing: const Text(
                                  "PENDING",
                                  style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
            )
          ],
        ),
      ),
    );
  }
}
