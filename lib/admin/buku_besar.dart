// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; // 🎯 WAJIB ADA untuk pemrosesan nama hari & bulan lokalisasi Indonesia

// ============================================================================
// MODUL 16: BUKU BESAR, KAS & FINANCE (GROUPED BY DATE SYSTEM)
// ============================================================================
class BukuBesarPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const BukuBesarPage({super.key, required this.profile});

  @override
  State<BukuBesarPage> createState() => _BukuBesarPageState();
}

class _BukuBesarPageState extends State<BukuBesarPage> {
  bool isLoading = false;

  // 🎯 REVISI STRUKTUR DATA: Penampung transaksi keuangan yang terkelompok harian
  Map<String, List<Map<String, dynamic>>> groupedTransactions = {};

  int totalPemasukan = 0;
  int totalPengeluaran = 0;

  @override
  void initState() {
    super.initState();
    _fetchTransaksi();
  }

  // Formatter mandiri mengubah angka biner menjadi teks Rupiah lokal
  String _formatRupiah(dynamic angka) {
    if (angka == null) return 'Rp0';
    int value = int.tryParse(angka.toString()) ?? 0;
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String hasil =
        value.toString().replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return "Rp$hasil";
  }

  // 🎯 FORMATTER INDONESIA: Mengubah string tanggal YYYY-MM-DD menjadi Hari Lokal (e.g., Rabu, 10 Juni 2026)
  String _formatTanggalIndonesia(String dateStr) {
    try {
      DateTime parsed = DateTime.parse(dateStr);
      return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(parsed);
    } catch (e) {
      return dateStr;
    }
  }

  // Sinkronisasi data mutasi keuangan real-time dari tabel Supabase
  Future<void> _fetchTransaksi() async {
    setState(() => isLoading = true);
    try {
      var q = Supabase.instance.client.from('finance_transactions').select();

      // Proteksi Multi-Cabang: Jika bukan akun PUSAT, kunci data hanya untuk cabang yang bersangkutan
      if (widget.profile['toko_id'] != null &&
          widget.profile['toko_id'] != 'PUSAT') {
        q = q.eq('toko_id', widget.profile['toko_id']);
      }
      final data = await q.order('created_at', ascending: false);
      final List<Map<String, dynamic>> rawList =
          List<Map<String, dynamic>>.from(data);

      int hitungPemasukan = 0;
      int hitungPengeluaran = 0;

      // Wadah penampung grouping sementara
      final Map<String, List<Map<String, dynamic>>> temporaryGroup = {};

      for (var item in rawList) {
        int nominal = int.tryParse(item['nominal'].toString()) ?? 0;
        if (item['jenis_transaksi'] == 'PEMASUKAN' ||
            item['jenis_transaksi'] == 'PIUTANG') {
          hitungPemasukan += nominal;
        } else if (item['jenis_transaksi'] == 'PENGELUARAN' ||
            item['jenis_transaksi'] == 'HUTANG') {
          hitungPengeluaran += nominal;
        }

        // 🎯 LOGIKA FILTERING GROUPING TANGGAL (Jangkar Utama Buku Besar)
        String tanggalKey = item['tanggal_transaksi'] ??
            item['created_at'].toString().split('T')[0];
        if (!temporaryGroup.containsKey(tanggalKey)) {
          temporaryGroup[tanggalKey] = [];
        }
        temporaryGroup[tanggalKey]!.add(item);
      }

      setState(() {
        groupedTransactions = temporaryGroup;
        totalPemasukan = hitungPemasukan;
        totalPengeluaran = hitungPengeluaran;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("❌ Gagal tarik data keuangan: $e"),
            backgroundColor: Colors.red));
      }
    }
  }

  void _showAddTransactionDialog() {
    TextEditingController nominalCtrl = TextEditingController();
    TextEditingController kategoriCtrl = TextEditingController();
    TextEditingController deskripsiCtrl = TextEditingController();
    String selectedJenis = 'PEMASUKAN';
    String selectedMetode = 'CASH';
    String selectedStatus = 'LUNAS';
    DateTime selectedDate = DateTime.now();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setInnerState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text("Catat Keuangan Manual",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: isSaving
                  ? const SizedBox(
                      height: 100,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: Colors.blueAccent)))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pilihan Tanggal Transaksi Manual
                        InkWell(
                          onTap: () async {
                            DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setInnerState(() => selectedDate = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 10),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              const Icon(Icons.calendar_today,
                                  color: Colors.blueAccent, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                  "Tanggal: ${selectedDate.toString().split(' ')[0]}",
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedJenis,
                          dropdownColor: const Color(0xFF0F172A),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: "Jenis Transaksi",
                            labelStyle: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                          ),
                          items: [
                            'PEMASUKAN',
                            'PENGELUARAN',
                            'PIUTANG',
                            'HUTANG'
                          ]
                              .map((String val) => DropdownMenuItem(
                                  value: val, child: Text(val)))
                              .toList(),
                          onChanged: (val) =>
                              setInnerState(() => selectedJenis = val!),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: kategoriCtrl,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: "Kategori / Jenis Pengeluaran",
                            labelStyle: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nominalCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                          decoration: InputDecoration(
                            labelText: "Nominal (Rp)",
                            labelStyle: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                            prefixText: "Rp ",
                            prefixStyle:
                                const TextStyle(color: Colors.greenAccent),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 🎯 FIX SAKTI: Menambahkan TextField deskripsi yang sebelumnya ke-skip dari UI layar
                        TextField(
                          controller: deskripsiCtrl,
                          maxLines: 2,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: "Deskripsi / Keterangan Tambahan",
                            labelStyle: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: DropdownButtonFormField<String>(
                            value: selectedMetode,
                            dropdownColor: const Color(0xFF0F172A),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              labelText: "Metode",
                              labelStyle: const TextStyle(
                                  color: Colors.grey, fontSize: 11),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                            ),
                            items: ['CASH', 'BCA', 'MANDIRI', 'QRIS', 'LAINNYA']
                                .map((val) => DropdownMenuItem(
                                    value: val, child: Text(val)))
                                .toList(),
                            onChanged: (val) =>
                                setInnerState(() => selectedMetode = val!),
                          )),
                          const SizedBox(width: 8),
                          Expanded(
                              child: DropdownButtonFormField<String>(
                            value: selectedStatus,
                            dropdownColor: const Color(0xFF0F172A),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              labelText: "Status",
                              labelStyle: const TextStyle(
                                  color: Colors.grey, fontSize: 11),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                            ),
                            items: ['LUNAS', 'BELUM LUNAS']
                                .map((val) => DropdownMenuItem(
                                    value: val, child: Text(val)))
                                .toList(),
                            onChanged: (val) =>
                                setInnerState(() => selectedStatus = val!),
                          )),
                        ]),
                      ],
                    ),
            ),
            actions: isSaving
                ? []
                : [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Batal",
                            style: TextStyle(color: Colors.grey))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent),
                      onPressed: () async {
                        if (nominalCtrl.text.isEmpty ||
                            kategoriCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("⚠️ Data belum lengkap!")));
                          return;
                        }
                        setInnerState(() => isSaving = true);
                        try {
                          await Supabase.instance.client
                              .from('finance_transactions')
                              .insert({
                            'toko_id': widget.profile['toko_id'] ?? 'PUSAT',
                            'tanggal_transaksi':
                                selectedDate.toIso8601String().split('T')[0],
                            'jenis_transaksi': selectedJenis,
                            'kategori': kategoriCtrl.text.trim(),
                            'deskripsi': deskripsiCtrl.text
                                .trim(), // 🎯 Otomatis ter-send dengan data riil dari form baru
                            'nominal': int.tryParse(nominalCtrl.text
                                    .replaceAll(RegExp(r'[^0-9]'), '')) ??
                                0,
                            'status_pembayaran': selectedStatus,
                            'metode_pembayaran': selectedMetode,
                            'updated_at': DateTime.now().toIso8601String(),
                          });
                          Navigator.pop(ctx);
                          _fetchTransaksi();
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text("✅ Berhasil menyimpan transaksi!")));
                        } catch (e) {
                          setInnerState(() => isSaving = false);
                          debugPrint("Error: $e");
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("❌ Gagal: $e")));
                        }
                      },
                      child: const Text("SIMPAN JURNAL"),
                    )
                  ],
          );
        });
      },
    );
  }

  // 1. DIALOG PILIHAN AKSI KEUANGAN (DENGAN LONG-PRESS PADA BARIS TRANSAKSI INDIVIDU)
  void _showOptionDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Pilih Aksi",
            style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
              title: const Text("Edit Transaksi",
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () {
                Navigator.pop(ctx);
                _editTransaction(item);
              },
            ),
            const Divider(color: Colors.white24, height: 1),
            ListTile(
              leading:
                  const Icon(Icons.delete, color: Colors.redAccent, size: 20),
              title: const Text("Hapus Transaksi",
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteTransaction(item['id']);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 2. FUNGSI DATABASE: EKSEKUSI PENGHAPUSAN ROW DATA TRANSAKSI FINANCE
  Future<void> _deleteTransaction(int id) async {
    try {
      await Supabase.instance.client
          .from('finance_transactions')
          .delete()
          .eq('id', id);
      _fetchTransaksi(); // Refresh list agar data di layar langsung sinkron

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✅ Transaksi berhasil dihapus!"),
          backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("❌ Gagal hapus transaksi: $e"),
          backgroundColor: Colors.red));
    }
  }

  // 3. SEKSI PENGEMBANGAN EDIT TRANSAKSI LANJUTAN
  void _editTransaction(Map<String, dynamic> item) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Fitur Edit siap dikembangkan sesuai alur PO Bos!"),
        backgroundColor: Colors.blue));
  }

  // 4. MAIN INTERFACE RENDERING: DASHBOARD BUKU BESAR
  @override
  Widget build(BuildContext context) {
    final List<String> daftarTanggalKey = groupedTransactions.keys.toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Buku Besar & Kas",
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent))
          : Column(
              children: [
                // PANEL KARTU ATAS: SUMMARY TOTAL MATRIX KEUANGAN TOKO (AKUMULASI GLOBAL)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
                  margin: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4))
                      ]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Blok Kolom A: Total Arus Kas Masuk
                      Expanded(
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.arrow_downward,
                                    color: Colors.greenAccent, size: 14),
                                SizedBox(width: 5),
                                Text("Pemasukan",
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(_formatRupiah(totalPemasukan),
                                style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                      Container(height: 40, width: 1, color: Colors.white24),

                      // Blok Kolom B: Saldo Bersih Riil Toko (Net Profit/Loss)
                      Expanded(
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.account_balance,
                                    color: Colors.white70, size: 14),
                                SizedBox(width: 5),
                                Text("Saldo Toko",
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                                _formatRupiah(
                                    totalPemasukan - totalPengeluaran),
                                style: TextStyle(
                                    color:
                                        (totalPemasukan - totalPengeluaran) >= 0
                                            ? Colors.white
                                            : Colors.orangeAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                      Container(height: 40, width: 1, color: Colors.white24),

                      // Blok Kolom C: Total Arus Kas Keluar
                      Expanded(
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.arrow_upward,
                                    color: Colors.redAccent, size: 14),
                                SizedBox(width: 5),
                                Text("Pengeluaran",
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(_formatRupiah(totalPengeluaran),
                                style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 18.0, vertical: 5.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Jurnal Keuangan Harian",
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1)),
                  ),
                ),

                // 🎯 REVISI PANEL LIST VIEW: GROUPED BY DAY & DATE (DENGAN DETAIL EXPANSION TILE)
                Expanded(
                  child: daftarTanggalKey.isEmpty
                      ? const Center(
                          child: Text("Belum ada transaksi tercatat.",
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 13)))
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: daftarTanggalKey.length,
                          itemBuilder: (context, index) {
                            String tanggalGroupKey = daftarTanggalKey[index];
                            List<dynamic> listSubTransaksi =
                                groupedTransactions[tanggalGroupKey] ?? [];

                            // Hitung sub-total omzet harian khusus tanggal ini saja
                            int subPemasukan = 0;
                            int subPengeluaran = 0;
                            for (var tx in listSubTransaksi) {
                              int nom =
                                  int.tryParse(tx['nominal'].toString()) ?? 0;
                              if (tx['jenis_transaksi'] == 'PEMASUKAN' ||
                                  tx['jenis_transaksi'] == 'PIUTANG') {
                                subPemasukan += nom;
                              } else {
                                subPengeluaran += nom;
                              }
                            }

                            return Card(
                              color: const Color(0xFF1E293B),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                              child: Theme(
                                data: Theme.of(context)
                                    .copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  iconColor: Colors.orangeAccent,
                                  collapsedIconColor: Colors.white60,
                                  // 🏢 HEADER UTAMA: HIGHLIGHT HARI & TANGGAL LOKAL
                                  title: Text(
                                    _formatTanggalIndonesia(tanggalGroupKey)
                                        .toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        letterSpacing: 0.5),
                                  ),
                                  // RINGKASAN SALDO HARIAN
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Row(
                                      children: [
                                        Text(
                                            "In: ${_formatRupiah(subPemasukan)}",
                                            style: const TextStyle(
                                                color: Colors.greenAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(width: 10),
                                        Text(
                                            "Out: ${_formatRupiah(subPengeluaran)}",
                                            style: const TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600)),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: Colors.black26,
                                              borderRadius:
                                                  BorderRadius.circular(4)),
                                          child: Text(
                                            "Net: ${_formatRupiah(subPemasukan - subPengeluaran)}",
                                            style: TextStyle(
                                                color: (subPemasukan -
                                                            subPengeluaran) >=
                                                        0
                                                    ? Colors.tealAccent
                                                    : Colors.orangeAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                  // 🔍 SUB-LIST JEROAN DETAIL TRANSAKSI PADA HARI TERSEBUT
                                  children: [
                                    const Divider(
                                        color: Colors.white10, height: 1),
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: listSubTransaksi.length,
                                      itemBuilder: (ctx, subIndex) {
                                        var item = listSubTransaksi[subIndex];
                                        bool isSubMasuk =
                                            item['jenis_transaksi'] ==
                                                    'PEMASUKAN' ||
                                                item['jenis_transaksi'] ==
                                                    'PIUTANG';

                                        // Format jam menit dari timestamp database
                                        String jamSesi = item['created_at']
                                                .toString()
                                                .contains('T')
                                            ? item['created_at']
                                                .toString()
                                                .split('T')[1]
                                                .substring(0, 5)
                                            : "Sesi";

                                        return ListTile(
                                          onLongPress: () =>
                                              _showOptionDialog(item),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 15, vertical: 2),
                                          leading: CircleAvatar(
                                            radius: 16,
                                            backgroundColor: item['kategori'] ==
                                                    'Modal Awal Sesi'
                                                ? Colors.blue.withOpacity(0.15)
                                                : (isSubMasuk
                                                    ? Colors.green
                                                        .withOpacity(0.12)
                                                    : Colors.red
                                                        .withOpacity(0.12)),
                                            child: Icon(
                                              item[
                                                          'kategori'] ==
                                                      'Modal Awal Sesi'
                                                  ? Icons.vpn_key_rounded
                                                  : (isSubMasuk
                                                      ? Icons
                                                          .account_balance_wallet
                                                      : Icons.money_off),
                                              color: item['kategori'] ==
                                                      'Modal Awal Sesi'
                                                  ? Colors.blueAccent
                                                  : (isSubMasuk
                                                      ? Colors.greenAccent
                                                      : Colors.redAccent),
                                              size: 14,
                                            ),
                                          ),
                                          title: Text(
                                              "[ $jamSesi ]  ${item['kategori'] ?? '-'}",
                                              style: const TextStyle(
                                                  color: Colors
                                                      .white70, // 🎯 FIX SAKTI: Ganti white90 jadi white70 agar lolos compile const
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12)),
                                          subtitle:
                                              (item['deskripsi'] != null &&
                                                      item['deskripsi']
                                                          .toString()
                                                          .trim()
                                                          .isNotEmpty)
                                                  ? Text(item['deskripsi'],
                                                      style: const TextStyle(
                                                          color: Colors.grey,
                                                          fontSize: 11,
                                                          fontStyle:
                                                              FontStyle.italic))
                                                  : null,
                                          trailing: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                "${isSubMasuk ? '+' : '-'}${_formatRupiah(item['nominal'])}",
                                                style: TextStyle(
                                                    color: isSubMasuk
                                                        ? Colors.greenAccent
                                                        : Colors.redAccent,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12),
                                              ),
                                              if (item['status_pembayaran'] ==
                                                  'BELUM LUNAS')
                                                const Text("Hutang/DP",
                                                    style: TextStyle(
                                                        color:
                                                            Colors.orangeAccent,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                )
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blueAccent,
        onPressed: _showAddTransactionDialog,
        icon: const Icon(Icons.add, color: Colors.white, size: 20),
        label: const Text("Catat Keuangan",
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      ),
    );
  }
}
