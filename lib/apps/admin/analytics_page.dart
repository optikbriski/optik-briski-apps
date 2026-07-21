import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

class AnalyticsDashboard extends StatefulWidget {
  final Map<String, dynamic> profile;
  const AnalyticsDashboard({super.key, required this.profile});

  @override
  State<AnalyticsDashboard> createState() => _AnalyticsDashboardState();
}

class _AnalyticsDashboardState extends State<AnalyticsDashboard> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  int _totalOmzet = 0;
  int _stokKritis = 0;

  String _formatRupiah(int nominal) {
    return NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp', decimalDigits: 0)
        .format(nominal);
  }

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final String myToko = widget.profile['toko_id'] ?? 'PUSAT';
      final bool isSuper = widget.profile['role'] == 'super_admin';

      var salesQ = _supabase.from('sales').select('total_harga');
      if (!isSuper) salesQ = salesQ.eq('toko_id', myToko);
      final salesData = await salesQ;

      var stockQ = _supabase.from('products').select('id');
      if (!isSuper) stockQ = stockQ.eq('toko_id', myToko);
      final lowStock = await stockQ.lt('stock', 5);

      int total = 0;
      for (var row in salesData) {
        total += (row['total_harga'] as num).toInt();
      }

      if (mounted) {
        setState(() {
          _totalOmzet = total;
          _stokKritis = lowStock.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(title: "analytics_title".tr()),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.accentSoft))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statCard("analytics_omzet".tr(), _formatRupiah(_totalOmzet),
                      Icons.account_balance_wallet_rounded, Colors.greenAccent),
                  const SizedBox(height: 15),
                  _statCard(
                      "analytics_stok_kritis".tr(),
                      "analytics_produk".tr(args: [_stokKritis.toString()]),
                      Icons.warning_amber_rounded,
                      Colors.orangeAccent),
                  const SizedBox(height: 40),
                  Text("analytics_performa".tr(),
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 10, letterSpacing: 2)),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        barGroups: [
                          BarChartGroupData(
                            x: 0,
                            barRods: [
                              BarChartRodData(
                                  toY: 8, color: Colors.blueAccent, width: 12)
                            ],
                          ),
                          BarChartGroupData(
                            x: 1,
                            barRods: [
                              BarChartRodData(
                                  toY: 18, color: Colors.blueAccent, width: 12)
                            ],
                          ),
                          BarChartGroupData(
                            x: 2,
                            barRods: [
                              BarChartRodData(
                                  toY: 12, color: Colors.blueAccent, width: 12)
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // WIDGET PEMBANTU: KARTU STATISTIK
  Widget _statCard(String t, String v, IconData i, Color c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: c.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(i, color: c),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 5),
              Text(
                v,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
            ],
          )
        ],
      ),
    );
  }
}
