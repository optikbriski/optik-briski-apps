import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PengingatPage extends StatefulWidget {
  const PengingatPage({super.key});

  @override
  State<PengingatPage> createState() => _PengingatPageState();
}

class _PengingatPageState extends State<PengingatPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _items = [];
          _loading = false;
        });
        return;
      }
      final rows = await Supabase.instance.client
          .from('notifikasi')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal muat pengingat: $e')),
      );
    }
  }

  Future<void> _tandaiSemua() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('notifikasi')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('user_id', user.id)
          .filter('read_at', 'is', null);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("pengingat_msg_tandai_sukses".tr())),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
      );
    }
  }

  IconData _iconFor(String? tipe) {
    switch ((tipe ?? '').toUpperCase()) {
      case 'SOP':
        return Icons.warning_rounded;
      case 'SHIFT':
        return Icons.calendar_month_rounded;
      case 'ADMIN':
        return Icons.assignment_ind_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String? tipe) {
    switch ((tipe ?? '').toUpperCase()) {
      case 'SOP':
        return Colors.redAccent;
      case 'SHIFT':
        return Colors.blueAccent;
      case 'ADMIN':
        return Colors.orange;
      default:
        return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM HH:mm', 'id_ID');
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text("pengingat_title".tr(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: "pengingat tooltip tandai".tr(),
            onPressed: _items.isEmpty ? null : _tandaiSemua,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    'Belum ada pengingat.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final n = _items[i];
                      final tipe = n['tipe']?.toString();
                      final unread = n['read_at'] == null;
                      final created =
                          DateTime.tryParse(n['created_at']?.toString() ?? '');
                      return Opacity(
                        opacity: unread ? 1 : 0.65,
                        child: _buildReminderCard(
                          icon: _iconFor(tipe),
                          iconColor: _colorFor(tipe),
                          title: n['judul']?.toString() ?? '-',
                          description: n['isi']?.toString() ?? '',
                          waktu: created != null
                              ? df.format(created.toLocal())
                              : '-',
                          isUrgent: unread && tipe == 'SOP',
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildReminderCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String waktu,
    bool isUrgent = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: isUrgent
            ? Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      Text(waktu,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey, height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
