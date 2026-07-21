// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import '../../shared/responsive.dart';
import 'sales_page.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

// ============================================================================
// MODUL 17: HIGH-LEVEL CORPORATE REVENUE AUDIT, TAX, & AGING LEDGER SYSTEM
// ============================================================================
class RiwayatTransaksiPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RiwayatTransaksiPage({super.key, required this.profile});

  @override
  State<RiwayatTransaksiPage> createState() => _RiwayatTransaksiPageState();
}

class _RiwayatTransaksiPageState extends State<RiwayatTransaksiPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool isLoading = true;

  // --- STATE KONTROL MULTI-STAGE DRILL-DOWN NAVIGATION ---
  String? selectedTokoId; // Stage 1 -> Stage 2 (Kunci Cabang)
  String? selectedDateStr; // Stage 2 -> Stage 3 (Kunci Tanggal Audit)

  // --- DATA CACHE STORAGE GLOBAL SYSTEM ---
  List<Map<String, dynamic>> allSalesRaw = [];
  List<String> listCabangUnik = [];
  Map<String, List<Map<String, dynamic>>> salesGroupedByDay = {};

  // --- TOP CARDS CORE MANAGEMENT CORE MATRIX ---
  int branchTotalOmzetBruto = 0; // Gross Revenue Nota POS
  int branchTotalDuitMasuk = 0; // Cash Inflow Riil (Laci Kasir)
  int branchTotalPiutangMacet = 0; // Global Accounts Receivable
  int branchTotalNotaTerbit = 0; // Volume sirkulasi berkas transaksi

  // --- NEW CORPORATE EXTENSION 1: PAJAK & NET REVENUE STATEMENT ---
  int branchTotalDppNetto = 0; // Dasar Pengenaan Pajak (Omzet Bersih Bisnis)
  int branchTotalPpnKeluaran = 0; // PPN 11% yang wajib dilaporkan ke Negara

  // --- NEW CORPORATE EXTENSION 2: AGING ACCOUNTS RECEIVABLE LEDGER ---
  int piutangLancar30Hari = 0; // Umur nota 0 - 30 hari (Status: Aman)
  int piutangPengawasan60Hari = 0; // Umur nota 31 - 60 hari (Status: Warning)
  int piutangKritisMacet = 0; // Umur nota > 60 hari (Status: Bad Debt / Kritis)

  // --- NEW CORPORATE EXTENSION 3: PAYMENT INSTRUMENT BREAKDOWN ---
  Map<String, int> breakdownMetodeBayar = {
    'CASH': 0,
    'BCA': 0,
    'MANDIRI': 0,
    'QRIS': 0,
    'LAINNYA': 0,
  };

  @override
  void initState() {
    super.initState();
    _inisialisasiHakAksesAplikasi();
  }

  // Formatter mandiri mengubah angka integer baku menjadi teks Rupiah Mata Uang Lokal
  String formatRupiah(int nominal) {
    return NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp', decimalDigits: 0)
        .format(nominal);
  }

  // Mengubah kode tanggal mentah database menjadi format pelaporan hari nasional
  String _formatTanggalIndonesia(String dateStr) {
    try {
      DateTime parsed = DateTime.parse(dateStr);
      return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(parsed);
    } catch (e) {
      return dateStr;
    }
  }

  // --- GATEKEEPER: FILTERING OTORISASI HAK AKSES PUSAT VS CABANG ---
  void _inisialisasiHakAksesAplikasi() {
    String role = widget.profile['role']?.toString().toLowerCase() ?? 'kasir';
    String userTokoId =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';

    if (role == 'owner' || userTokoId == 'PUSAT') {
      selectedTokoId =
          null; // Owner Sesi: Mulai dari peta Stage 1 (Global Wilayah)
      _fetchSeluruhDataTransaksiOwner();
    } else {
      selectedTokoId =
          userTokoId; // Kasir Lapangan: Langsung kunci mati ke ID Cabang asal
      _fetchDataTransaksiPerCabang(userTokoId);
    }
  }

  // 🌍 ENGINE DATABASE 1: Tarik riwayat omzet sales lintas cabang (Sesi Manajemen Pusat Owner)
  Future<void> _fetchSeluruhDataTransaksiOwner() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final res = await supabase
          .from('sales')
          .select()
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> data =
          List<Map<String, dynamic>>.from(res);
      final Set<String> cabangSet = data
          .map((e) => e['toko_id']?.toString().toUpperCase() ?? 'PUSAT')
          .toSet();

      setState(() {
        allSalesRaw = data;
        listCabangUnik = cabangSet.toList();
        isLoading = false;
      });
    } catch (e) {
      _handleExceptionGagal(
          "Gagal sinkronisasi arsitektur master sales pusat: $e");
    }
  }

  // 🏢 ENGINE DATABASE 2: ENGINE KONSOLIDASI AKUNTANSI PENUH (PAJAK, METODE BAYAR, AGING LEDGER)
  Future<void> _fetchDataTransaksiPerCabang(String tokoId) async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final res = await supabase
          .from('sales')
          .select()
          .eq('toko_id', tokoId)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> data =
          List<Map<String, dynamic>>.from(res);

      int hitungOmzet = 0;
      int hitungDuitMasuk = 0;
      int hitungPiutang = 0;
      int hitungDpp = 0;
      int hitungPpn = 0;

      int aging30 = 0;
      int aging60 = 0;
      int agingMacet = 0;

      final Map<String, int> tempMetode = {
        'CASH': 0,
        'BCA': 0,
        'MANDIRI': 0,
        'QRIS': 0,
        'LAINNYA': 0
      };
      final Map<String, List<Map<String, dynamic>>> urutanHari = {};

      DateTime waktuSekarang = DateTime.now();

      for (var sale in data) {
        int total = int.tryParse(sale['total_harga']?.toString() ?? '0') ?? 0;
        int sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
        int dibayar = total - sisa;

        hitungOmzet += total;
        hitungPiutang += sisa;
        hitungDuitMasuk += dibayar;

        // A. Perhitungan Alokasi Pajak (Standard Retail Include PPN 11%)
        int dppItem = (total / 1.11).round();
        int ppnItem = total - dppItem;
        hitungDpp += dppItem;
        hitungPpn += ppnItem;

        // B. Perhitungan Matriks Penuaan Piutang Usaha (Aging AR)
        DateTime tanggalNota =
            DateTime.tryParse(sale['created_at']?.toString() ?? '') ??
                waktuSekarang;
        int umurNotaHari = waktuSekarang.difference(tanggalNota).inDays.abs();

        if (sisa > 0) {
          if (umurNotaHari <= 30) {
            aging30 += sisa;
          } else if (umurNotaHari <= 60) {
            aging60 += sisa;
          } else {
            agingMacet += sisa;
          }
        }

        // C. Audit Jalur Instrumen Pembayaran
        String metodeStr =
            sale['metode_pembayaran']?.toString().toUpperCase() ?? 'CASH';
        if (tempMetode.containsKey(metodeStr)) {
          tempMetode[metodeStr] = tempMetode[metodeStr]! + dibayar;
        } else {
          tempMetode['LAINNYA'] = tempMetode['LAINNYA']! + dibayar;
        }

        // D. Pengelompokan Kalender Harian Jurnal
        String rawDate =
            sale['created_at']?.toString() ?? waktuSekarang.toIso8601String();
        String dateKey = rawDate.split('T')[0];
        if (!urutanHari.containsKey(dateKey)) {
          urutanHari[dateKey] = [];
        }
        urutanHari[dateKey]!.add(sale);
      }

      setState(() {
        salesGroupedByDay = urutanHari;
        branchTotalOmzetBruto = hitungOmzet;
        branchTotalDuitMasuk = hitungDuitMasuk;
        branchTotalPiutangMacet = hitungPiutang;
        branchTotalNotaTerbit = data.length;

        branchTotalDppNetto = hitungDpp;
        branchTotalPpnKeluaran = hitungPpn;

        piutangLancar30Hari = aging30;
        piutangPengawasan60Hari = aging60;
        piutangKritisMacet = agingMacet;

        breakdownMetodeBayar = tempMetode;
        isLoading = false;
      });
    } catch (e) {
      _handleExceptionGagal(
          "Gagal memproses konsolidasi neraca finansial POS: $e");
    }
  }

  void _handleExceptionGagal(String msg) {
    if (mounted) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
    }
  }

  // --- POP-UP MODAL DETAIL AUDIT INTERNAL PUSAT (SINKRON PAJAK & AGING) ---
  void _showDetailKhususPusat(BuildContext context, Map<String, dynamic> trx) {
    int total = int.tryParse(trx['total_harga']?.toString() ?? '0') ?? 0;
    int sisa = int.tryParse(trx['sisa_tagihan']?.toString() ?? '0') ?? 0;
    int dpp = (total / 1.11).round();
    int ppn = total - dpp;

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
                color: Colors.orangeAccent, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text("Detail Audit Pusat",
                  style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRowAudit("No Invoice", trx['no_invoice']),
              _buildRowAudit("Cabang Wilayah", trx['toko_id'],
                  color: Colors.amberAccent),
              _buildRowAudit("Kasir Penanggung", trx['nama_kasir']),
              _buildRowAudit("Nama Pasien", trx['nama_pelanggan']),
              _buildRowAudit("Metode Bayar", trx['metode_pembayaran']),
              _buildRowAudit("Status Nota", trx['status_pembayaran']),
              const Divider(color: Colors.white12, height: 16),
              _buildRowAudit("Bruto Omzet (POS)", formatRupiah(total),
                  color: Colors.blueAccent),
              _buildRowAudit("DPP (Omzet Bersih)", formatRupiah(dpp),
                  color: Colors.white70),
              _buildRowAudit("Alokasi PPN 11%", formatRupiah(ppn),
                  color: Colors.white38),
              const Divider(color: Colors.white12, height: 16),
              _buildRowAudit("Uang Riil Diterima", formatRupiah(total - sisa),
                  color: Colors.greenAccent),
              _buildRowAudit("Sisa Piutang Pasien", formatRupiah(sisa),
                  color: Colors.redAccent),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("Tutup", style: TextStyle(color: Colors.grey)))
        ],
      ),
      ),
    );
  }

  Widget _buildRowAudit(String label, dynamic val, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              val?.toString() ?? '-',
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // CORE ROUTER ENGINE (PENGATUR ALUR PERPINDAHAN LAPISAN SCREEN)
  // ==========================================================================
  Widget _orchestrateActiveStageLayout() {
    if (selectedTokoId == null) return _buildStage1LayarCabang(); // Lapis 1
    if (selectedDateStr == null)
      return _buildStage2LayarHariHarian(); // Lapis 2
    return _buildStage3LayarDaftarInvoice(); // Lapis 3
  }

  // ==========================================================================
  // STAGE 1: SELEKSI DIVISI CABANG (MONITORING PORTFOLIO GLOBAL OWNER)
  // ==========================================================================
  Widget _buildStage1LayarCabang() {
    if (listCabangUnik.isEmpty) {
      return const Center(
          child: Text(
              "Belum mendeteksi aktivitas transaksi di cabang mana pun.",
              style: TextStyle(color: Colors.white54, fontSize: 12)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: listCabangUnik.length,
      itemBuilder: (context, index) {
        String tokoId = listCabangUnik[index];
        int hitungNota = allSalesRaw
            .where((e) =>
                (e['toko_id']?.toString().toUpperCase() ?? 'PUSAT') == tokoId)
            .length;

        return PremiumListTile(
          title: tokoId == 'PUSAT'
              ? 'OPTIK B. RISKI - PUSAT'
              : 'OPTIK B. RISKI - $tokoId',
          subtitle: 'Arsip Penjualan: $hitungNota Nota Terbit',
          icon: Icons.store_rounded,
          iconColor: Colors.blueAccent,
          onTap: () {
            setState(() {
              selectedTokoId = tokoId;
            });
            _fetchDataTransaksiPerCabang(tokoId);
          },
        );
      },
    );
  }

  // ==========================================================================
  // STAGE 2: SCREEN INTEGRATED CORPORATE STATEMENT & KALENDER NOTA HARIAN
  // ==========================================================================
  Widget _buildStage2LayarHariHarian() {
    List<String> sortedDays = salesGroupedByDay.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    // Perhitungan KPI Rasio Efektivitas Penagihan Kasir (Collection Rate)
    double collectionRate = branchTotalOmzetBruto > 0
        ? (branchTotalDuitMasuk / branchTotalOmzetBruto) * 100
        : 0.0;

    return Column(
      children: [
        PremiumStatGrid(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, OptikAdminTokens.spaceMd),
          items: [
            PremiumStatItem(
              label: '↓ Tunai Masuk',
              value: formatRupiah(branchTotalDuitMasuk),
              color: Colors.greenAccent,
            ),
            PremiumStatItem(
              label: 'Omzet Bruto',
              value: formatRupiah(branchTotalOmzetBruto),
              color: Colors.blueAccent,
            ),
            PremiumStatItem(
              label: 'Piutang Usaha',
              value: formatRupiah(branchTotalPiutangMacet),
              color: Colors.orangeAccent,
            ),
            PremiumStatItem(
              label: 'Volume Nota',
              value: '$branchTotalNotaTerbit Lembar',
              color: Colors.white,
            ),
          ],
        ),

        // 🏛️ CORE BOARD B: ADVANCED AUDIT PANEL (PAJAK, AGING RECEIVABLE & REKENING BANK)
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- SUB-PANEL 1: PAJAK & KPI STRATEGIS CORPORATE ---
                PremiumPanel(
                  padding: const EdgeInsets.all(14),
                  borderRadius: 16,
                  margin: const EdgeInsets.only(bottom: 12),
                  borderColor: Colors.amberAccent.withOpacity(0.28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PremiumSectionHeader(
                        label: 'Deklarasi Perpajakan & Efisiensi Revenue',
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: OptikAdminTokens.spaceMd),
                      _buildRowDataIntel(
                          "DPP (Dasar Pengenaan Pajak / Omzet Netto)",
                          formatRupiah(branchTotalDppNetto),
                          Colors.white70),
                      _buildRowDataIntel("Alokasi Hutang PPN Keluaran (11%)",
                          formatRupiah(branchTotalPpnKeluaran), Colors.white38),
                      const Divider(color: Colors.white10, height: 12),
                      _buildRowDataIntel(
                          "Collection Rate KPI (Efektivitas Penagihan)",
                          "${collectionRate.toStringAsFixed(1)} %",
                          collectionRate >= 75
                              ? Colors.tealAccent
                              : Colors.orangeAccent),
                    ],
                  ),
                ),

                // --- SUB-PANEL 2: AGING ACCOUNTS RECEIVABLE LEDGER (BUKU PENUAN PIUTANG) ---
                PremiumPanel(
                  padding: const EdgeInsets.all(14),
                  borderRadius: 16,
                  margin: const EdgeInsets.only(bottom: 12),
                  borderColor: Colors.orangeAccent.withOpacity(0.28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PremiumSectionHeader(
                        label: 'AR Aging Ledger (Umur Piutang Jatuh Tempo)',
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: OptikAdminTokens.spaceMd),
                      PremiumStatGrid(
                        items: [
                          PremiumStatItem(
                            label: '0-30 HARI (LANCAR)',
                            value: formatRupiah(piutangLancar30Hari),
                            color: Colors.tealAccent,
                          ),
                          PremiumStatItem(
                            label: '31-60 HARI (WATCHLIST)',
                            value: formatRupiah(piutangPengawasan60Hari),
                            color: Colors.amberAccent,
                          ),
                          PremiumStatItem(
                            label: '>60 HARI (CRITICAL)',
                            value: formatRupiah(piutangKritisMacet),
                            color: Colors.redAccent,
                          ),
                        ],
                      )
                    ],
                  ),
                ),

                // --- SUB-PANEL 3: REKONSILIASI JALUR MUTASI BANK ---
                PremiumPanel(
                  padding: const EdgeInsets.all(14),
                  borderRadius: 16,
                  margin: const EdgeInsets.only(bottom: 15),
                  borderColor: Colors.blueAccent.withOpacity(0.28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PremiumSectionHeader(
                        label: 'Audit Instrumen Rekening Bank & Setoran',
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: OptikAdminTokens.spaceMd),
                      PremiumChipWrap(
                        children: breakdownMetodeBayar.entries.map((e) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 10),
                            decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.white10, width: 0.5)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("${e.key}: ",
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 10)),
                                Text(formatRupiah(e.value),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          );
                        }).toList(),
                      )
                    ],
                  ),
                ),

                // --- LIST CALENDAR JURNAL HARIAN BAWAH ---
                const PremiumSectionHeader(
                  label: 'Arsip Jurnal Nota Harian',
                  padding: EdgeInsets.only(left: 6, bottom: 8, top: 0),
                ),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sortedDays.length,
                  itemBuilder: (context, index) {
                    String tanggalKey = sortedDays[index];
                    List<Map<String, dynamic>> listNotaHariIni =
                        salesGroupedByDay[tanggalKey] ?? [];

                    int dayOmzet = listNotaHariIni.fold(
                        0,
                        (sum, item) =>
                            sum +
                            (int.tryParse(
                                    item['total_harga']?.toString() ?? '0') ??
                                0));
                    int dayPiutang = listNotaHariIni.fold(
                        0,
                        (sum, item) =>
                            sum +
                            (int.tryParse(
                                    item['sisa_tagihan']?.toString() ?? '0') ??
                                0));
                    int dayCashIn = dayOmzet - dayPiutang;

                    return PremiumPanel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 12),
                      borderRadius: 16,
                      margin: const EdgeInsets.only(bottom: 8),
                      onTap: () {
                        setState(() {
                          selectedDateStr = tanggalKey;
                        });
                      },
                      child: Row(
                        children: [
                          PremiumIconBadge(
                            icon: Icons.calendar_today_rounded,
                            color: Colors.tealAccent,
                            size: 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatTanggalIndonesia(tanggalKey)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(height: OptikAdminTokens.spaceSm),
                                PremiumChipWrap(
                                  spacing: OptikAdminTokens.spaceSm,
                                  runSpacing: OptikAdminTokens.spaceSm,
                                  children: [
                                    Text("In: ${formatRupiah(dayCashIn)}",
                                        style: const TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 10.5)),
                                    Text("Omzet: ${formatRupiah(dayOmzet)}",
                                        style: const TextStyle(
                                            color: Colors.blueAccent,
                                            fontSize: 10.5)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("Sisa: ${formatRupiah(dayPiutang)}",
                                  style: TextStyle(
                                      color: dayPiutang > 0
                                          ? Colors.orangeAccent
                                          : Colors.white24,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold)),
                              Text("${listNotaHariIni.length} Nota",
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 9)),
                            ],
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right_rounded,
                              color: OptikAdminTokens.textMuted, size: 18),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRowDataIntel(String label, String value, Color textCol) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Flexible(
            child: Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  color: textCol, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ==========================================================================
  // STAGE 3: DAFTAR INVOICE HARIAN TERKUNCI PER CABANG (SINKRON DATA REVENUE POS)
  // ==========================================================================
  Widget _buildStage3LayarDaftarInvoice() {
    List<Map<String, dynamic>> listInvoiceHariIni =
        salesGroupedByDay[selectedDateStr] ?? [];

    if (listInvoiceHariIni.isEmpty) {
      return const Center(
          child: Text("Tidak ada transaksi ditemukan pada tanggal ini.",
              style: TextStyle(color: Colors.white54, fontSize: 12)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: listInvoiceHariIni.length,
      itemBuilder: (context, index) {
        final trx = listInvoiceHariIni[index];
        int totalHarga =
            int.tryParse(trx['total_harga']?.toString() ?? '0') ?? 0;
        int sisaTagihan =
            int.tryParse(trx['sisa_tagihan']?.toString() ?? '0') ?? 0;
        int cashCollected = totalHarga - sisaTagihan;
        String status = trx['status_pembayaran'] ?? 'Lunas';

        return Card(
          color: OptikAdminTokens.card,
          margin: const EdgeInsets.only(bottom: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
            title: R.isNarrow(context)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trx['no_invoice'] ?? '-',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(formatRupiah(totalHarga),
                          style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(trx['no_invoice'] ?? '-',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                      Text(formatRupiah(totalHarga),
                          style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 5),
                Text("Pasien: ${trx['nama_pelanggan'] ?? 'Pasien Tanpa Nama'}",
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                PremiumChipWrap(
                  spacing: OptikAdminTokens.spaceSm,
                  runSpacing: OptikAdminTokens.spaceSm,
                  children: [
                    Text("Diterima: ${formatRupiah(cashCollected)}",
                        style: const TextStyle(
                            color: Colors.greenAccent, fontSize: 11)),
                    if (sisaTagihan > 0)
                      Text("Sisa: ${formatRupiah(sisaTagihan)}",
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text("Kasir Penanggung: ${trx['nama_kasir'] ?? 'Staff Optik'}",
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
            trailing: PremiumChipWrap(
              spacing: OptikAdminTokens.spaceSm,
              runSpacing: OptikAdminTokens.spaceSm,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: status.toUpperCase() == 'LUNAS'
                        ? Colors.green.withOpacity(0.15)
                        : Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(
                          color: status.toUpperCase() == 'LUNAS'
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.receipt_long,
                      color: Colors.blueAccent, size: 20),
                  tooltip: "Buka Cetakan Struk PDF",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            InvoiceDetailPage(saleId: trx['id'].toString()),
                      ),
                    );
                  },
                ),
                if (widget.profile['toko_id']?.toString().toUpperCase() ==
                        'PUSAT' ||
                    widget.profile['role']?.toString().toLowerCase() == 'owner')
                  IconButton(
                    icon: const Icon(Icons.admin_panel_settings,
                        color: Colors.orangeAccent, size: 20),
                    tooltip: "Audit Internal Pusat",
                    onPressed: () => _showDetailKhususPusat(context, trx),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // MAIN METHOD ARSITEKTUR UI SCENE FRAMING BUILD
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    String roleUser =
        widget.profile['role']?.toString().toLowerCase() ?? 'kasir';

    return PremiumScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: OptikAdminTokens.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          onPressed: () {
            setState(() {
              if (selectedDateStr != null) {
                selectedDateStr =
                    null; // Stage 3 -> Stage 2: Balik ke Ringkasan Kalender
              } else if (selectedTokoId != null && roleUser == 'owner') {
                selectedTokoId =
                    null; // Stage 2 -> Stage 1: Balik ke Seleksi Divisi Cabang (Sesi Owner)
                _fetchSeluruhDataTransaksiOwner();
              } else {
                Navigator.pop(context); // Keluar Modul Monitor Penjualan POS
              }
            });
          },
        ),
        title: Text(
          selectedDateStr != null
              ? "📅 DAFTAR NOTA: $selectedDateStr"
              : selectedTokoId != null
                  ? "🏪 MONITORING: $selectedTokoId"
                  : "🏢 ARSIP MONITORING SALES PUSAT",
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent))
          : _orchestrateActiveStageLayout(),
    );
  }
} // 🌟 BERKAS SELESAI STERIL TOTAL 100% SINKRON TANPA OVERFLOW DI VS CODE
