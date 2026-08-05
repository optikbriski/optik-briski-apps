// ignore_for_file: use_build_context_synchronously, prefer_const_constructors
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/responsive.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/finance/gl_posting_service.dart';

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
      _showSnackBar("Gagal memuat data karantina: $e", OptikAdminTokens.danger);
    }
  }

  Future<void> _approveTransaksi(Map<String, dynamic> item) async {
    setState(() => isLoading = true);
    try {
      await supabase
          .from('finance_transactions')
          .update({'status_konfirmasi': 'APPROVED'}).eq('id', item['id']);

      final approved = Map<String, dynamic>.from(item);
      approved['status_konfirmasi'] = 'APPROVED';
      try {
        await GlPostingService().postManualFinance(
          ft: approved,
          createdBy: widget.profile['nama']?.toString(),
        );
      } catch (e) {
        debugPrint('GL posting approve gagal: $e');
      }

      _showSnackBar(
          "Transaksi ${item['kategori']} disetujui.", OptikAdminTokens.ice);
      _fetchPendingManualCOA();
    } catch (e) {
      _showSnackBar("Gagal menyetujui transaksi: $e", OptikAdminTokens.danger);
    }
  }

  Future<void> _rejectTransaksi(Map<String, dynamic> item) async {
    setState(() => isLoading = true);
    try {
      // Void jurnal GL terkait (jika sempat ter-post) sebelum hapus FT.
      try {
        final ref = 'FT-${item['id']}';
        final je = await supabase
            .from('journal_entries')
            .select('id')
            .eq('sumber', 'MANUAL')
            .eq('referensi_id', ref)
            .eq('status', 'POSTED')
            .maybeSingle();
        if (je != null && je['id'] != null) {
          await GlPostingService().voidEntry(
            je['id'].toString(),
            createdBy: widget.profile['nama']?.toString(),
          );
        }
      } catch (_) {}

      await supabase.from('finance_transactions').delete().eq('id', item['id']);

      _showSnackBar("Transaksi ${item['kategori']} ditolak & dihapus.",
          OptikAdminTokens.warning);
      _fetchPendingManualCOA();
    } catch (e) {
      _showSnackBar("Gagal menolak transaksi: $e", OptikAdminTokens.danger);
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
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: R.constrainedDialog(
          context: context,
          preferWidth: 500,
          child: Padding(
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
                    Expanded(
                      child: Text("Detail Transaksi",
                          style: TextStyle(
                              color: OptikAdminTokens.navy,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                        icon: Icon(Icons.close, color: OptikAdminTokens.textMuted),
                        onPressed: () => Navigator.pop(ctx))
                  ],
                ),
                Divider(color: OptikAdminTokens.line),
                SizedBox(height: 10),
                _buildDetailRow("Kategori", item['kategori']),
                _buildDetailRow("Nominal", _formatRupiah(item['nominal'])),
                _buildDetailRow("Status", item['status_pembayaran']),
                _buildDetailRow("Metode", item['metode_pembayaran']),
                _buildDetailRow("Operator", item['nama_kasir'] ?? '-'),
                SizedBox(height: 16),
                Text("Catatan",
                    style: TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: OptikAdminTokens.navy.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(memo,
                      style: TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 13)),
                ),
                SizedBox(height: 16),
                if (urlFoto.isNotEmpty && urlFoto.startsWith("http")) ...[
                  Text("Bukti foto",
                      style: TextStyle(
                          color: OptikAdminTokens.navy,
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
                              color: OptikAdminTokens.danger.withOpacity(0.5)),
                          padding: EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _rejectTransaksi(item);
                        },
                        child: Text("Tolak",
                            style: TextStyle(
                                color: OptikAdminTokens.danger,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OptikAdminTokens.navy,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _approveTransaksi(item);
                        },
                        child: Text("Setujui",
                            style: TextStyle(
                                color: OptikAdminTokens.snow,
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
              style: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 11)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = pendingItems.length;
    final totalNominal = pendingItems.fold<int>(
      0,
      (sum, item) => sum + (int.tryParse(item['nominal']?.toString() ?? '0') ?? 0),
    );
    final pemasukanCount = pendingItems.where((item) {
      final jenis = item['jenis_transaksi']?.toString() ?? '';
      return jenis == 'PEMASUKAN' || jenis == 'PIUTANG';
    }).length;

    return PremiumScaffold(
      appBar: const PremiumAppBar(
        title: 'Persetujuan COA Manual',
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.ice))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PremiumStatGrid(
                  padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
                  items: [
                    PremiumStatItem(
                      label: 'Antrean',
                      value: '$pendingCount',
                      color: OptikAdminTokens.warning,
                    ),
                    PremiumStatItem(
                      label: 'Total Nominal',
                      value: _formatRupiah(totalNominal),
                      color: OptikAdminTokens.navy,
                    ),
                    PremiumStatItem(
                      label: 'Pemasukan',
                      value: '$pemasukanCount',
                      color: OptikAdminTokens.navy,
                    ),
                    PremiumStatItem(
                      label: 'Pengeluaran',
                      value: '${pendingCount - pemasukanCount}',
                      color: OptikAdminTokens.danger,
                    ),
                  ],
                ),
                Expanded(
                  child: pendingItems.isEmpty
                      ? PremiumEmptyState(
                          message:
                              "Tidak ada antrean persetujuan COA manual.",
                          icon: Icons.account_balance_wallet_outlined,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
                          itemCount: pendingItems.length,
                          itemBuilder: (context, index) {
                            final item = pendingItems[index];
                            bool isPemasukan =
                                item['jenis_transaksi'] == 'PEMASUKAN' ||
                                    item['jenis_transaksi'] == 'PIUTANG';

                            return GestureDetector(
                              onLongPress: () => _showOptionDialog(item),
                              child: PremiumPanel(
                                padding: const EdgeInsets.all(16),
                                borderRadius: 16,
                                margin: const EdgeInsets.only(bottom: 12),
                                borderColor: isPemasukan
                                    ? OptikAdminTokens.accentSoft.withOpacity(0.28)
                                    : OptikAdminTokens.danger.withOpacity(0.28),
                                onTap: () => _showDetailDialog(item),
                                child: Row(
                                  children: [
                                    PremiumIconBadge(
                                      icon: isPemasukan
                                          ? Icons.arrow_downward_rounded
                                          : Icons.arrow_upward_rounded,
                                      color: isPemasukan
                                          ? OptikAdminTokens.navy
                                          : OptikAdminTokens.danger,
                                      size: 44,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              "${item['toko_id']} · ${item['kategori']}",
                                              style: const TextStyle(
                                                  color: OptikAdminTokens.navy,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Text(
                                              "${isPemasukan ? '+' : '-'} ${_formatRupiah(item['nominal'])} • Oleh: ${item['nama_kasir'] ?? 'Staff'}",
                                              style: const TextStyle(
                                                  color: OptikAdminTokens.textSecondary,
                                                  fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 70,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              OptikAdminTokens.slate
                                                  .withOpacity(0.2),
                                          padding: EdgeInsets.zero,
                                        ),
                                        onPressed: () =>
                                            _showDetailDialog(item),
                                        child: const Text("Detail",
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: OptikAdminTokens.navy)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  void _showOptionDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text("Tindakan Cepat",
            style: TextStyle(color: OptikAdminTokens.navy, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: Icon(Icons.check, color: OptikAdminTokens.navy),
                title: Text("Setujui", style: TextStyle(color: OptikAdminTokens.navy)),
                onTap: () {
                  Navigator.pop(ctx);
                  _approveTransaksi(item);
                }),
            ListTile(
                leading: Icon(Icons.close, color: OptikAdminTokens.danger),
                title: Text("Tolak", style: TextStyle(color: OptikAdminTokens.navy)),
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
