import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';

class MemberBookingPage extends StatefulWidget {
  const MemberBookingPage({super.key});

  @override
  State<MemberBookingPage> createState() => _MemberBookingPageState();
}

class _MemberBookingPageState extends State<MemberBookingPage> {
  final _repo = MemberRepository();
  final _catatan = TextEditingController();
  List<Map<String, dynamic>> _toko = const [];
  List<Map<String, dynamic>> _bookings = const [];
  String? _tokoId;
  DateTime _when = DateTime.now().add(const Duration(days: 1, hours: 2));
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Supabase.instance.client
          .from('invoice_settings')
          .select('toko_id, shop_name')
          .order('toko_id');
      final phone = MemberSession.instance.phoneForQuery;
      final bookings =
          phone.isEmpty ? <Map<String, dynamic>>[] : await _repo.listBookings(phone);
      if (!mounted) return;
      setState(() {
        _toko = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _tokoId ??= _toko.isNotEmpty ? _toko.first['toko_id']?.toString() : null;
        _bookings = bookings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (t == null) return;
    setState(() {
      _when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _submit() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty || _tokoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login dan pilih cabang dulu.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _repo.createBooking(
        phone: phone,
        tokoId: _tokoId!,
        scheduledAt: _when,
        catatan: _catatan.text.trim(),
        memberId: MemberSession.instance.memberId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Jadwal tersimpan. Anda akan diprioritaskan di toko.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$e'), backgroundColor: OptikMemberTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE, d MMM yyyy · HH:mm', 'id_ID');
    return MemberPremiumScaffold(
      title: 'Janji kontrol',
      subtitle: 'Prioritas yang sudah booking',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                DropdownButtonFormField<String>(
                  value: _tokoId,
                  decoration: const InputDecoration(labelText: 'Cabang'),
                  items: _toko
                      .map((t) => DropdownMenuItem(
                            value: t['toko_id']?.toString(),
                            child: Text('${t['toko_id']}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _tokoId = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(fmt.format(_when)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _catatan,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('Ambil jadwal'),
                ),
                const SizedBox(height: 22),
                const MemberSectionLabel('Jadwal saya'),
                if (_bookings.isEmpty)
                  const Text('Belum ada jadwal.',
                      style: TextStyle(color: OptikMemberTokens.inkMuted))
                else
                  ..._bookings.map((b) {
                    final at = DateTime.tryParse('${b['scheduled_at']}');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${b['status']} · ${b['toko_id']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        at == null ? '${b['scheduled_at']}' : fmt.format(at.toLocal()),
                      ),
                      trailing: b['status'] == 'booked'
                          ? TextButton(
                              onPressed: () async {
                                await _repo.cancelBooking('${b['id']}');
                                await _load();
                              },
                              child: const Text('Batal'),
                            )
                          : null,
                    );
                  }),
              ],
            ),
    );
  }
}
