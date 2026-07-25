// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/logistics/kurir_pick_dialog.dart';
import '../../shared/logistics/logistics_tracking_service.dart';
import '../../shared/qr/obr_codes.dart';
import '../../shared/responsive.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Halaman persiapan DO: daftar barang yang harus disiapkan + Generate QR perjalanan.
class DoPreparingPage extends StatefulWidget {
  const DoPreparingPage({
    super.key,
    required this.profile,
    required this.moveId,
  });

  final Map<String, dynamic> profile;
  final String moveId;

  @override
  State<DoPreparingPage> createState() => _DoPreparingPageState();
}

class _DoPreparingPageState extends State<DoPreparingPage> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  final Set<int> _checked = {};

  Map<String, dynamic>? _move;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await _db
          .from('stock_move_history')
          .select()
          .eq('id', widget.moveId)
          .maybeSingle();
      if (row == null) {
        throw 'Surat jalan tidak ditemukan.';
      }
      final move = Map<String, dynamic>.from(row);
      final items = _parseItems(move['keterangan']?.toString() ?? '');
      if (!mounted) return;
      setState(() {
        _move = move;
        _items = items;
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

  List<Map<String, dynamic>> _parseItems(String raw) {
    if (!raw.contains('[{')) return const [];
    try {
      final jsonPart = raw.substring(raw.indexOf('[{'));
      final decoded = jsonDecode(jsonPart);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String get _status =>
      (_move?['status'] ?? '').toString().toUpperCase();

  bool get _canReadyToSend =>
      _status == 'PREPARING' || _status == 'WAITING';

  bool get _hasPackingPhoto {
    final f = (_move?['bukti_foto_pengirim'] ?? '').toString().trim();
    return f.isNotEmpty && f != '-';
  }

  bool get _allChecked =>
      _items.isEmpty || _checked.length >= _items.length;

  int get _totalQty => _items.fold<int>(
        0,
        (s, it) => s + (int.tryParse('${it['qty'] ?? 0}') ?? 0),
      );

  Future<void> _pickKurir() async {
    final pick = await showKurirPickDialog(
      context,
      service: LogisticsTrackingService(),
      pusatOnly: true,
      title: 'Pilih kurir DO',
    );
    if (kurirPickCancelled(pick) || _move == null) return;
    setState(() => _busy = true);
    try {
      if (kurirPickSkipped(pick)) {
        await LogisticsTrackingService().clearKurir(widget.moveId);
      } else {
        await LogisticsTrackingService().assignKurir(
          moveId: widget.moveId,
          karyawanId: pick!['id'].toString(),
          nama: pick['nama']?.toString() ?? '-',
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal set kurir: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readyToSend({bool forceNewPhoto = false}) async {
    if (_move == null || !_canReadyToSend) return;

    if (!_allChecked) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Centang semua barang dulu (${_checked.length}/${_items.length}).',
        ),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _busy = true);
    try {
      var foto = (_move!['bukti_foto_pengirim'] ?? '').toString().trim();
      final needPhoto = forceNewPhoto || foto.isEmpty || foto == '-';

      // Ready to Send: foto packing WAJIB.
      if (needPhoto) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Wajib foto packing sebelum Ready to Send.'),
          backgroundColor: Color(0xFF0F766E),
        ));
        final photo = await pickImageSafe(
          picker: _picker,
          context: context,
          preferredCameraDevice: CameraDevice.rear,
          imageQuality: 50,
        );
        if (photo == null) {
          if (!mounted) return;
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Dibatalkan. Foto wajib untuk Ready to Send.'),
            backgroundColor: Colors.redAccent,
          ));
          return;
        }
        final bytes = await photo.readAsBytes();
        final path =
            'pengiriman/prep_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _db.storage.from('attendance_photos').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        foto = _db.storage.from('attendance_photos').getPublicUrl(path);
        await _db.from('stock_move_history').update({
          'bukti_foto_pengirim': foto,
        }).eq('id', widget.moveId);
        _move!['bukti_foto_pengirim'] = foto;
      }

      if (!_hasPackingPhoto && (foto.isEmpty || foto == '-')) {
        throw 'Foto packing wajib.';
      }

      final resi = (_move!['product_name'] ?? '').toString();
      final tujuan = (_move!['ke_lokasi'] ?? '').toString();
      final qr = ObrDo.encode(resi: resi, tujuan: tujuan);
      if (qr.isEmpty) throw 'Resi tidak valid untuk QR.';

      if (!mounted) return;
      await _showTravelQrDialog(resi: resi, tujuan: tujuan, qr: qr, fotoUrl: foto);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal Ready to Send: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showTravelQrDialog({
    required String resi,
    required String tujuan,
    required String qr,
    required String fotoUrl,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: R.constrainedDialog(
          context: ctx,
          preferWidth: 400,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              color: OptikAdminTokens.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'READY TO SEND',
                    style: TextStyle(
                      color: Color(0xFF2DD4BF),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'QR perjalanan untuk driver',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    resi,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Tujuan: $tujuan',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (fotoUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        fotoUrl,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: qr,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Driver scan QR ini (+ foto barang) → status TRANSIT.\n'
                    'Cabang scan QR yang sama saat menerima.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: qr));
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Payload QR disalin'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Salin payload'),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('TUTUP'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final move = _move;
    final resi = (move?['product_name'] ?? '-').toString();
    final tujuan = (move?['ke_lokasi'] ?? '-').toString();
    final kurir = (move?['kurir_nama'] ?? '').toString().trim();
    final status = _status;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Preparing DO',
        subtitle: 'Ceklis barang → Ready to Send (wajib foto) → QR driver',
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2DD4BF).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color:
                                    const Color(0xFF2DD4BF).withOpacity(0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        resi,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2DD4BF)
                                            .withOpacity(0.16),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        status.isEmpty ? '-' : status,
                                        style: const TextStyle(
                                          color: Color(0xFF2DD4BF),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tujuan: $tujuan',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Total: $_totalQty pcs · ${_items.length} SKU',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.45),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(Icons.delivery_dining_rounded,
                                        size: 16,
                                        color: Colors.white.withOpacity(0.55)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        kurir.isEmpty
                                            ? 'Kurir belum dipilih'
                                            : 'Kurir: $kurir',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.75),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _busy ? null : _pickKurir,
                                      child: Text(
                                        kurir.isEmpty ? 'Pilih' : 'Ganti',
                                        style: const TextStyle(
                                          color: Color(0xFF2DD4BF),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'DAFTAR SIAPKAN (${_checked.length}/${_items.length})',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_items.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text(
                                'Detail item tidak terbaca. Cek field keterangan surat jalan.',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          else
                            ...List.generate(_items.length, (i) {
                              final it = _items[i];
                              final nama = (it['nama'] ?? '-').toString();
                              final qty =
                                  int.tryParse('${it['qty'] ?? 0}') ?? 0;
                              final sku = (it['sku'] ?? it['barcode'] ?? '-')
                                  .toString();
                              final warna = (it['warna'] ?? '-').toString();
                              final checked = _checked.contains(i);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: OptikAdminTokens.card,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: checked
                                        ? const Color(0xFF2DD4BF)
                                            .withOpacity(0.45)
                                        : Colors.white.withOpacity(0.07),
                                  ),
                                ),
                                child: CheckboxListTile(
                                  value: checked,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _checked.add(i);
                                      } else {
                                        _checked.remove(i);
                                      }
                                    });
                                  },
                                  activeColor: const Color(0xFF2DD4BF),
                                  checkColor: Colors.black,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text(
                                    nama,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      decoration: checked
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'SKU $sku · $warna · ${qty}x',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  secondary: Text(
                                    '${qty}x',
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orangeAccent.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.photo_camera_rounded,
                                    color: Colors.orangeAccent, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _hasPackingPhoto
                                        ? 'Foto packing sudah ada. Ready to Send bisa tampilkan QR lagi, atau ganti foto.'
                                        : 'Ready to Send wajib foto packing barang. Tanpa foto, QR jalan tidak dibuat.',
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 12,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (status == 'TRANSIT') ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orangeAccent.withOpacity(0.35),
                                ),
                              ),
                              child: const Text(
                                'Status sudah TRANSIT — driver sudah scan QR perjalanan. '
                                'Cabang tujuan bisa menerima paket.',
                                style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Column(
                          children: [
                            if (_hasPackingPhoto && _canReadyToSend)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _readyToSend(forceNewPhoto: true),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orangeAccent,
                                      side: const BorderSide(
                                          color: Colors.orangeAccent),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    icon: const Icon(Icons.cameraswitch_rounded,
                                        size: 18),
                                    label: const Text(
                                      'GANTI FOTO + QR',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton.icon(
                                onPressed: _busy || !_canReadyToSend
                                    ? null
                                    : () => _readyToSend(
                                          forceNewPhoto: !_hasPackingPhoto,
                                        ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                  disabledBackgroundColor: Colors.white12,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: _busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        _hasPackingPhoto
                                            ? Icons.qr_code_2_rounded
                                            : Icons.photo_camera_rounded,
                                      ),
                                label: Text(
                                  !_canReadyToSend
                                      ? 'Hanya untuk status PREPARING'
                                      : _hasPackingPhoto
                                          ? 'READY TO SEND · TAMPILKAN QR'
                                          : 'READY TO SEND · WAJIB FOTO',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Daftar DO berstatus PREPARING / WAITING.
class DoPreparingListPage extends StatefulWidget {
  const DoPreparingListPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<DoPreparingListPage> createState() => _DoPreparingListPageState();
}

class _DoPreparingListPageState extends State<DoPreparingListPage> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _db
          .from('stock_move_history')
          .select()
          .eq('tipe', 'DELIVERY')
          .inFilter('status', ['PREPARING', 'WAITING'])
          .order('created_at', ascending: false)
          .limit(80);
      if (!mounted) return;
      setState(() {
        _rows = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal muat: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Antrian Preparing',
        subtitle: 'DO yang belum generate QR / belum dijemput kurir',
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Text(
                    'Tidak ada DO preparing.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final m = _rows[i];
                    final resi = (m['product_name'] ?? '-').toString();
                    final tujuan = (m['ke_lokasi'] ?? '-').toString();
                    final qty = m['jumlah'] ?? 0;
                    final status = (m['status'] ?? '').toString();
                    return Material(
                      color: OptikAdminTokens.card,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DoPreparingPage(
                                profile: widget.profile,
                                moveId: m['id'].toString(),
                              ),
                            ),
                          );
                          _load();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2DD4BF)
                                      .withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.inventory_2_outlined,
                                  color: Color(0xFF2DD4BF),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      resi,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$tujuan · $qty pcs · $status',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: Colors.white38),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
