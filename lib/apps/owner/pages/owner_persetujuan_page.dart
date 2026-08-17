import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../owner_service.dart';
import '../owner_ui.dart';

class OwnerPersetujuanPage extends StatefulWidget {
  const OwnerPersetujuanPage({super.key});

  @override
  State<OwnerPersetujuanPage> createState() => _OwnerPersetujuanPageState();
}

class _OwnerPersetujuanPageState extends State<OwnerPersetujuanPage> {
  final _svc = OwnerService();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _karyawan = [];
  List<Map<String, dynamic>> _jadwal = [];
  List<Map<String, dynamic>> _finance = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _maps(dynamic res) {
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _svc.listPersetujuan();
      if (!mounted) return;
      setState(() {
        _karyawan = _maps(data['karyawan_pending']);
        _jadwal = _maps(data['jadwal_pending']);
        _finance = _maps(data['finance_pending']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _confirmDecide({
    required String title,
    required String body,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title berhasil.'),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _actions({
    required VoidCallback? onApprove,
    required VoidCallback? onReject,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundAction(
          icon: Icons.check_rounded,
          color: OptikAdminTokens.success,
          onTap: _busy ? null : onApprove,
        ),
        const SizedBox(width: 6),
        _RoundAction(
          icon: Icons.close_rounded,
          color: OptikAdminTokens.danger,
          onTap: _busy ? null : onReject,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _karyawan.length + _jadwal.length + _finance.length;

    return OwnerPageFrame(
      title: 'Persetujuan',
      subtitle: total == 0 ? 'Antrean kosong' : '$total menunggu keputusan',
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: OptikAdminTokens.navy))
          : _error != null
              ? OwnerEmptyState(_error!, icon: Icons.error_outline_rounded)
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    const OwnerSectionLabel('Karyawan'),
                    if (_karyawan.isEmpty)
                      OwnerListCard(
                        title: 'Tidak ada antrean',
                        subtitle: 'Semua pengajuan karyawan sudah diproses.',
                        accent: OptikAdminTokens.slate,
                      )
                    else
                      for (final k in _karyawan)
                        OwnerListCard(
                          accent: OptikAdminTokens.warning,
                          title: (k['nama'] ?? '-').toString(),
                          subtitle:
                              '${k['jabatan'] ?? '-'} · ${k['toko_id'] ?? '-'} · ${k['status_approval'] ?? '-'}',
                          trailing: _actions(
                            onApprove: () => _confirmDecide(
                              title: 'Setujui karyawan',
                              body: 'Aktifkan ${k['nama']}?',
                              action: () => _svc.decideKaryawan(
                                karyawanId: '${k['id']}',
                                approve: true,
                              ),
                            ),
                            onReject: () => _confirmDecide(
                              title: 'Tolak karyawan',
                              body: 'Tolak ${k['nama']}?',
                              action: () => _svc.decideKaryawan(
                                karyawanId: '${k['id']}',
                                approve: false,
                                note: 'Ditolak Owner',
                              ),
                            ),
                          ),
                        ),
                    const OwnerSectionLabel('Jadwal'),
                    if (_jadwal.isEmpty)
                      OwnerListCard(
                        title: 'Tidak ada pengajuan',
                        subtitle: 'Ijin / cuti / tukar shift kosong.',
                        accent: OptikAdminTokens.slate,
                      )
                    else
                      for (final j in _jadwal)
                        OwnerListCard(
                          accent: OptikAdminTokens.accentDeep,
                          title: (j['karyawan_nama'] ?? j['karyawan_id'] ?? '-').toString(),
                          subtitle:
                              '${j['tipe'] ?? '-'} · ${j['tanggal'] ?? '-'} · ${j['toko_id'] ?? '-'}\n${j['alasan'] ?? ''}',
                          trailing: _actions(
                            onApprove: () => _confirmDecide(
                              title: 'Setujui jadwal',
                              body: 'Setujui pengajuan ini?',
                              action: () => _svc.decideJadwal(
                                pengajuanId: '${j['id']}',
                                approve: true,
                              ),
                            ),
                            onReject: () => _confirmDecide(
                              title: 'Tolak jadwal',
                              body: 'Tolak pengajuan ini?',
                              action: () => _svc.decideJadwal(
                                pengajuanId: '${j['id']}',
                                approve: false,
                                note: 'Ditolak Owner',
                              ),
                            ),
                          ),
                        ),
                    const OwnerSectionLabel('Kas / opex'),
                    if (_finance.isEmpty)
                      OwnerListCard(
                        title: 'Tidak ada transaksi pending',
                        subtitle: 'Kas & opex sudah bersih.',
                        accent: OptikAdminTokens.slate,
                      )
                    else
                      for (final f in _finance)
                        OwnerListCard(
                          accent: OptikAdminTokens.danger,
                          title:
                              '${f['jenis_transaksi'] ?? '-'} · ${f['kategori'] ?? '-'}',
                          subtitle:
                              '${f['toko_id'] ?? '-'} · ${OwnerService.formatRp(f['nominal'])} · ${f['tanggal_transaksi'] ?? '-'}',
                          trailing: _actions(
                            onApprove: () => _confirmDecide(
                              title: 'Setujui transaksi',
                              body: 'Setujui transaksi ini?',
                              action: () => _svc.decideFinance(
                                txId: '${f['id']}',
                                approve: true,
                              ),
                            ),
                            onReject: () => _confirmDecide(
                              title: 'Tolak transaksi',
                              body: 'Tolak transaksi ini?',
                              action: () => _svc.decideFinance(
                                txId: '${f['id']}',
                                approve: false,
                                note: 'Ditolak Owner',
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
