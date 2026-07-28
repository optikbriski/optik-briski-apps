import 'package:flutter/material.dart';

import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';

class MemberSurveyPage extends StatefulWidget {
  const MemberSurveyPage({
    super.key,
    required this.saleId,
    required this.noInvoice,
  });

  final String saleId;
  final String noInvoice;

  @override
  State<MemberSurveyPage> createState() => _MemberSurveyPageState();
}

class _MemberSurveyPageState extends State<MemberSurveyPage> {
  final _repo = MemberRepository();
  final _komentar = TextEditingController();
  int _nyaman = 5;
  int _cocok = 5;
  int _pelayanan = 5;
  bool _busy = false;

  @override
  void dispose() {
    _komentar.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty || widget.saleId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login dulu untuk mengirim survei.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _repo.submitSurvey(
        saleId: widget.saleId,
        phone: phone,
        nyaman: _nyaman,
        cocok: _cocok,
        pelayanan: _pelayanan,
        komentar: _komentar.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Terima kasih! Survei tersimpan.')),
      );
      Navigator.pop(context);
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

  Widget _stars(String label, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: OptikMemberTokens.blueDeep)),
        Row(
          children: List.generate(5, (i) {
            final n = i + 1;
            return IconButton(
              onPressed: () => onChanged(n),
              icon: Icon(
                n <= value ? Icons.star_rounded : Icons.star_border_rounded,
                color: OptikMemberTokens.blue,
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MemberPremiumScaffold(
      title: 'Survei singkat',
      subtitle: widget.noInvoice,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Bantu kami tingkatkan layanan (terpisah dari rating karyawan).',
            style: TextStyle(color: OptikMemberTokens.inkSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          _stars('Nyaman dipakai?', _nyaman, (v) => setState(() => _nyaman = v)),
          _stars('Cocok / sesuai harapan?', _cocok, (v) => setState(() => _cocok = v)),
          _stars('Pelayanan toko?', _pelayanan,
              (v) => setState(() => _pelayanan = v)),
          TextField(
            controller: _komentar,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Komentar (opsional)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Kirim survei'),
          ),
        ],
      ),
    );
  }
}
