import 'dart:convert'; // ✅ AMAN: Mengaktifkan fungsi jsonEncode untuk bundle payload barang
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart'; // ✅ AMAN: Untuk menangkap foto bukti surat jalan pengiriman
import 'package:easy_localization/easy_localization.dart';
import '../../shared/responsive.dart';
import '../../shared/logistics/do_cart_lines.dart';
import '../../shared/logistics/do_lifecycle_service.dart';
import '../../shared/logistics/product_identity.dart';
import '../../shared/logistics/restock_suggest_service.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'do_preparing_page.dart';

// Shortcut pintas client Supabase khusus file DO ini
final supabase = Supabase.instance.client;

// ============================================================================
// MODUL 6 DELIVERY ORDER & TRANSAKSI GANTUNG (FULL UNIFIED) - PART 1 OF 6
// ============================================================================
class OutgoingOperation extends StatefulWidget {
  final Map<String, dynamic> profile;
  const OutgoingOperation({super.key, required this.profile});

  @override
  State<OutgoingOperation> createState() => _OutgoingOperationState();
}

class _OutgoingOperationState extends State<OutgoingOperation> {
  String? selectedToko;
  final searchController = TextEditingController();

  List<String> listToko = [];
  List<dynamic> allProdukPusat = [];
  List<dynamic> listProdukPusat = [];
  List<dynamic> filteredProduk = [];

  bool isFiltering = false;
  bool isLoading = true;
  bool isProcessing = false;

  Map<String, int> selectedItems = {};
  Map<String, TextEditingController> qtyControllers = {};

  // Variabel penyimpan filter kategori yang sedang aktif
  Set<String> selectedCategories = {};
  /// DO = restock: default hanya tampilkan yang perlu dilengkapi (laku − stok).
  /// Set false untuk lihat semua stok Pusat.
  bool onlyNeedRestock = true;
  Map<String, RestockHint> restockHints = {};
  bool isLoadingHints = false;
  int preparingCount = 0;
  int draftCount = 0;

  static const _panelSoft = OptikAdminTokens.bgMid;

  Widget _buildCategoryChip(String category, Color badgeColor) {
    final isActive = selectedCategories.contains(category);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: isActive ? badgeColor.withOpacity(0.16) : _panelSoft,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                if (isActive) {
                  selectedCategories.remove(category);
                } else {
                  selectedCategories.add(category);
                }
              });
              filterProduk();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive
                      ? badgeColor.withOpacity(0.55)
                      : OptikAdminTokens.lineStrong,
                ),
              ),
              child: Text(
                category,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? badgeColor : OptikAdminTokens.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    searchController.dispose();
    for (var ctrl in qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // 1. MEMUAT DAFTAR CABANG TUJUAN dari master toko_id (bukan profiles).
  // profiles hanya menampilkan cabang yang sudah punya akun login.
  Future<void> loadData() async {
    if (mounted) setState(() => isLoading = true);
    try {
      final resToko = await supabase.from('toko_id').select('id');

      final unik = (resToko as List)
          .map((e) => e['id']?.toString().trim().toUpperCase() ?? '')
          .where((t) => t.isNotEmpty && t != 'PUSAT')
          .toSet()
          .toList()
        ..sort();

      // Cabang harus dipilih dulu agar saran restock terhitung benar.
      if (mounted) {
        setState(() {
          listToko = unik;
          if (listToko.isNotEmpty) {
            selectedToko = listToko.contains(selectedToko)
                ? selectedToko
                : listToko.first;
          }
        });
      }

      await Future.wait([_fetchProduk(), _loadQueueCounts()]);
    } catch (e) {
      debugPrint("Load Jaringan Cabang Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadQueueCounts() async {
    try {
      final results = await Future.wait([
        supabase
            .from('stock_move_history')
            .select('id')
            .eq('tipe', 'DELIVERY')
            .inFilter('status', ['PREPARING', 'WAITING']),
        supabase.from('draft_pengiriman').select('id'),
      ]);
      if (!mounted) return;
      setState(() {
        preparingCount = (results[0] as List).length;
        draftCount = (results[1] as List).length;
      });
    } catch (e) {
      debugPrint('Load queue counts: $e');
    }
  }

  Future<void> _openPreparingQueue() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoPreparingListPage(profile: widget.profile),
      ),
    );
    if (mounted) await _loadQueueCounts();
  }

  Future<void> _openDraftList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DraftManagerPage(profile: widget.profile),
      ),
    );
    if (mounted) await _loadQueueCounts();
  }

  String _cabangLabel(String id) {
    final t = id.trim().toUpperCase();
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  Future<void> _openCabangPicker() async {
    if (listToko.isEmpty) return;

    final options = listToko
        .map(
          (id) => AdminPickerOption<String>(
            value: id,
            label: _cabangLabel(id),
            subtitle: id,
            icon: Icons.store_mall_directory_rounded,
          ),
        )
        .toList();

    final result = await showAdminPicker<String>(
      context: context,
      title: 'Pilih cabang tujuan',
      subtitle: 'Restock akan dikirim ke cabang ini',
      options: options,
      selected: selectedToko,
      searchHint: 'Cari nama cabang…',
      headerIcon: Icons.storefront_rounded,
      filterOption: (o, q) =>
          o.value.toLowerCase().contains(q) ||
          o.label.toLowerCase().contains(q),
    );

    if (result == null ||
        result.value == null ||
        result.value == selectedToko ||
        !mounted) {
      return;
    }
    setState(() => selectedToko = result.value);
    await _loadRestockHints();
  }

  // 2. MENARIK ITEM INVENTORI GUDANG PUSAT SAJA
  Future<void> _fetchProduk() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        isFiltering = false;
      });
    }
    try {
      final response = await supabase
          .from('products')
          .select()
          .eq('toko_id', 'PUSAT')
          .order('nama', ascending: true);

      if (mounted) {
        setState(() {
          listProdukPusat = response as List<dynamic>;
          allProdukPusat = List.from(listProdukPusat);
          isLoading = false;
        });
      }
      await _loadRestockHints();
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal ambil data database PUSAT: $e"),
            backgroundColor: OptikAdminTokens.danger));
      }
    }
  }

  Future<void> _loadRestockHints() async {
    final toko = selectedToko;
    if (toko == null || toko.isEmpty) {
      if (mounted) setState(() => restockHints = {});
      return;
    }
    if (mounted) setState(() => isLoadingHints = true);
    try {
      final hints = await RestockSuggestService().hintsForToko(toko);
      if (mounted) {
        setState(() {
          restockHints = hints;
          isLoadingHints = false;
        });
      }
    } catch (e) {
      debugPrint('Restock hints error: $e');
      if (mounted) setState(() => isLoadingHints = false);
    }
  }

  List<dynamic> _buildDisplayList() {
    final query = searchController.text.toLowerCase().trim();
    final list = listProdukPusat.where((item) {
      final namaProduk = (item['nama'] ?? '').toString().toLowerCase();
      final matchesSearch = query.isEmpty || namaProduk.contains(query);

      final itemCat =
          (item['kategori'] ?? '').toString().toLowerCase().trim();
      final matchesCategory = selectedCategories.isEmpty ||
          selectedCategories
              .any((cat) => cat.toLowerCase().trim() == itemCat);

      final id = item['id']?.toString() ?? '';
      final saran = restockHints[id]?.suggestedQty ?? 0;
      final matchesNeed = !onlyNeedRestock || saran > 0;

      return matchesSearch && matchesCategory && matchesNeed;
    }).toList();

    list.sort((a, b) {
      final sa = restockHints[a['id']?.toString()]?.suggestedQty ?? 0;
      final sb = restockHints[b['id']?.toString()]?.suggestedQty ?? 0;
      if (sa > 0 && sb <= 0) return -1;
      if (sb > 0 && sa <= 0) return 1;
      final bySaran = sb.compareTo(sa);
      if (bySaran != 0) return bySaran;
      return (a['nama'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['nama'] ?? '').toString().toLowerCase());
    });
    return list;
  }

  // 1. FUNGSI LOGIKA FILTER & PENCARIAN MULTI-KATEGORI SECARA INSTAN
  void filterProduk() {
    setState(() {
      isFiltering = searchController.text.trim().isNotEmpty ||
          selectedCategories.isNotEmpty ||
          onlyNeedRestock;
      filteredProduk = _buildDisplayList();
    });
  }

  void _applySuggestedQty(String id, int maxStok) {
    final saran = restockHints[id]?.suggestedQty ?? 0;
    if (saran <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada saran restock untuk produk ini'),
          backgroundColor: OptikAdminTokens.warning));
      return;
    }
    final qty = saran > maxStok ? maxStok : saran;
    setState(() {
      selectedItems[id] = qty;
      qtyControllers[id] ??= TextEditingController();
      qtyControllers[id]!.text = qty.toString();
    });
  }

  // 2. FUNGSI MEMILIH / MEMBATALKAN PILIHAN ITEM KE DALAM KERANJANG DO
  void _toggleItem(dynamic item) {
    if (item == null) return;
    String id = item['id'].toString();
    int stokTersedia = StockQty.availableOf(
      Map<String, dynamic>.from(item as Map),
    );

    if (stokTersedia <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("do_stok_kosong".tr()),
          backgroundColor: OptikAdminTokens.danger));
      return;
    }

    setState(() {
      if (selectedItems.containsKey(id)) {
        selectedItems.remove(id);
      } else {
        final saran = restockHints[id]?.suggestedQty ?? 0;
        final initial =
            saran > 0 ? (saran > stokTersedia ? stokTersedia : saran) : 1;
        selectedItems[id] = initial;
        qtyControllers[id] ??= TextEditingController(text: initial.toString());
        qtyControllers[id]!.text = initial.toString();
      }
    });
  }

  // 3. FUNGSI UPDATE JUMLAH ITEM MENGGUNAKAN TOMBOL PLUS / MINUS STEPPER
  void _updateQty(String id, int delta, int maxStok) {
    setState(() {
      int current = selectedItems[id] ?? 0;
      int next = current + delta;

      if (next <= 0) {
        selectedItems.remove(id);
      } else if (next > maxStok) {
        selectedItems[id] = maxStok;
        qtyControllers[id]?.text = maxStok.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "do_maksimal_stok".tr().replaceAll('{}', maxStok.toString())),
            backgroundColor: OptikAdminTokens.warning));
      } else {
        selectedItems[id] = next;
        qtyControllers[id]?.text = next.toString();
      }
    });
  }

  // 4. FUNGSI VALIDASI AMAN UNTUK MEMASUKKAN ANGKA QUANTITY SECARA MANUAL
  void _setQtyManual(String id, String val, int maxStok) {
    if (val.isEmpty)
      return; // Biarkan kosong sejenak jika user sedang menekan backspace
    int parsed = int.tryParse(val) ?? 1;

    if (parsed > maxStok) {
      setState(() {
        selectedItems[id] = maxStok;
        qtyControllers[id]?.text = maxStok.toString();
        // Kembalikan posisi kursor teks ke bagian paling ujung kanan agar ketikan tidak patah
        qtyControllers[id]?.selection = TextSelection.fromPosition(
            TextPosition(offset: qtyControllers[id]!.text.length));
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "do_maksimal_stok".tr().replaceAll('{}', maxStok.toString())),
          backgroundColor: OptikAdminTokens.warning));
    } else if (parsed <= 0) {
      setState(() {
        selectedItems[id] = 1;
        qtyControllers[id]?.text = '1';
        qtyControllers[id]?.selection =
            TextSelection.fromPosition(const TextPosition(offset: 1));
      });
    } else {
      setState(() {
        selectedItems[id] = parsed;
      });
    }
  }

  List<Map<String, dynamic>> _cartLines() {
    final lines = <Map<String, dynamic>>[];
    for (final entry in selectedItems.entries) {
      final prod =
          allProdukPusat.firstWhere((p) => p['id'].toString() == entry.key);
      lines.add(DoCartLines.fromProduct(
        Map<String, dynamic>.from(prod as Map),
        entry.value,
      ));
    }
    return lines;
  }

  // 6. MENGHITUNG TOTAL BARANG YANG AKAN MASUK SURAT JALAN PENGIRIMAN
  int _calculateTotalQty() {
    return selectedItems.values.fold(0, (sum, item) => sum + item);
  }

  // Simpan draft: booking Pending saja (Real dipotong saat TRANSIT).
  Future<void> saveDraft() async {
    if (selectedToko == null || selectedItems.isEmpty) return;
    setState(() => isProcessing = true);

    try {
      final actor =
          (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString();
      await DoLifecycleService().createDraft(
        ke: selectedToko!,
        items: _cartLines(),
        actor: actor,
      );

      if (mounted) {
        setState(() {
          selectedItems.clear();
          qtyControllers.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("do_sukses_draf".tr()),
            backgroundColor: OptikAdminTokens.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal menyimpan draft: $e'),
            backgroundColor: OptikAdminTokens.danger));
      }
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
        _fetchProduk();
        _loadQueueCounts();
      }
    }
  }

  // Konfirmasi → buat surat jalan PREPARING → halaman siapkan barang + Generate QR
  void confirmAndSend() {
    if (selectedToko == null || selectedItems.isEmpty) return;

    final confirmMsg =
        'Buat surat jalan ${_calculateTotalQty()} pcs ke $selectedToko?\n\n'
        '• Stok Real PUSAT belum dipotong (hanya booking Pending)\n'
        '• Lanjut: siapkan barang → foto packing → QR kurir\n'
        '• Real dipotong saat kurir scan (TRANSIT)';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => R.constrainedDialog(
        context: ctx,
        child: AlertDialog(
          backgroundColor: OptikAdminTokens.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              Icon(Icons.inventory_2_outlined, color: OptikAdminTokens.navy),
              Text('Buat surat jalan',
                  style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 15))
            ],
          ),
          content: Text(confirmMsg,
              style: const TextStyle(
                  color: OptikAdminTokens.textSecondary, fontSize: 13)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('BATAL',
                    style: TextStyle(
                        color: OptikAdminTokens.textMuted,
                        fontWeight: FontWeight.bold))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: OptikAdminTokens.navy),
              onPressed: () {
                Navigator.pop(ctx);
                _createPreparingDo();
              },
              child: const Text('YA, BUAT',
                  style: TextStyle(
                      color: OptikAdminTokens.bg, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  /// Buat DO status PREPARING (belum TRANSIT). QR di halaman Disiapkan.
  Future<void> _createPreparingDo() async {
    if (selectedToko == null || selectedItems.isEmpty) return;
    setState(() => isProcessing = true);

    try {
      final actor =
          (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString();
      final resiDO =
          'DO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      final created = await DoLifecycleService().createDelivery(
        ke: selectedToko!,
        items: _cartLines(),
        resi: resiDO,
        actor: actor,
      );
      final moveId = created['id']?.toString();
      if (moveId == null || moveId.isEmpty) {
        throw 'Surat jalan tanpa id.';
      }

      if (!mounted) return;
      setState(() {
        selectedItems.clear();
        qtyControllers.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Surat jalan dibuat. Siapkan barang, foto packing, lalu tampilkan QR.'),
        backgroundColor: OptikAdminTokens.success,
      ));

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DoPreparingPage(
            profile: widget.profile,
            moveId: moveId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal buat surat jalan: $e'),
          backgroundColor: OptikAdminTokens.danger));
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
        _fetchProduk();
        _loadQueueCounts();
      }
    }
  }

  // 2. TAMPILAN ANTARMUKA LAYOUT UTAMA KARTU MUTASI BARANG PUSAT
  @override
  Widget build(BuildContext context) {
    final displayList = _buildDisplayList();
    final cartCount = selectedItems.length;
    final cartQty =
        selectedItems.values.fold<int>(0, (s, q) => s + q);

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: "do_title".tr(),
        subtitle: 'Kirim restock Pusat → cabang',
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Header (antrian + form) ikut scroll — cegah bottom overflow di viewport pendek.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PremiumSectionHeader(
                          label: 'Antrian',
                          padding: const EdgeInsets.only(bottom: 8, top: 2),
                          trailing: Text(
                            '${preparingCount + draftCount}',
                            style: const TextStyle(
                              color: OptikAdminTokens.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _DoQueueHubCard(
                                title: 'Disiapkan',
                                subtitle: 'Ceklis · foto · QR',
                                icon: Icons.fact_check_rounded,
                                accent: OptikAdminTokens.navy,
                                count: preparingCount,
                                onTap: _openPreparingQueue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DoQueueHubCard(
                                title: 'Draf',
                                subtitle: 'Belum surat jalan',
                                icon: Icons.inventory_2_rounded,
                                accent: OptikAdminTokens.warning,
                                count: draftCount,
                                onTap: _openDraftList,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        PremiumPanel(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          borderRadius: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Buat pengiriman',
                                style: TextStyle(
                                  color: OptikAdminTokens.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              AdminPickerField(
                                label: "do_cabang_tujuan".tr(),
                                valueText: selectedToko == null
                                    ? 'Pilih cabang…'
                                    : _cabangLabel(selectedToko!),
                                hint: 'Pilih cabang…',
                                icon: Icons.storefront_rounded,
                                badgeColor: OptikAdminTokens.ice,
                                enabled: listToko.isNotEmpty,
                                onTap: listToko.isEmpty
                                    ? null
                                    : _openCabangPicker,
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: searchController,
                                onChanged: (v) => filterProduk(),
                                style: const TextStyle(
                                    color: OptikAdminTokens.textPrimary,
                                    fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Cari produk…',
                                  hintStyle: const TextStyle(
                                      color: OptikAdminTokens.textMuted,
                                      fontSize: 12.5),
                                  prefixIcon: const Icon(
                                      Icons.search_rounded,
                                      color: OptikAdminTokens.textMuted,
                                      size: 20),
                                  filled: true,
                                  fillColor:
                                      OptikAdminTokens.bg.withOpacity(0.55),
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 11),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: OptikAdminTokens.lineStrong),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: OptikAdminTokens.navy,
                                        width: 1.3),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              if (isLoadingHints) ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: const LinearProgressIndicator(
                                    minHeight: 2.5,
                                    color: OptikAdminTokens.warning,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Icons.local_shipping_rounded,
                                      size: 14,
                                      color: OptikAdminTokens.warning
                                          .withOpacity(0.9)),
                                  const SizedBox(width: 6),
                                  Text(
                                    onlyNeedRestock
                                        ? 'Restock · butuh dilengkapi'
                                        : 'Semua stok Pusat',
                                    style: const TextStyle(
                                      color: OptikAdminTokens.textSecondary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () {
                                      setState(() =>
                                          onlyNeedRestock = !onlyNeedRestock);
                                      filterProduk();
                                    },
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor:
                                          OptikAdminTokens.navy,
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      onlyNeedRestock
                                          ? 'Lihat semua'
                                          : 'Hanya restock',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _buildCategoryChip(
                                      'Frame', OptikAdminTokens.ice),
                                  _buildCategoryChip(
                                      'Lensa', OptikAdminTokens.warning),
                                  _buildCategoryChip(
                                      'Lainnya', OptikAdminTokens.success),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 10, 2, 2),
                          child: Text(
                            cartCount > 0
                                ? '${displayList.length} produk · keranjang $cartCount item ($cartQty pcs)'
                                : '${displayList.length} produk',
                            style: const TextStyle(
                              color: OptikAdminTokens.textMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Katalog stok Pusat
                if (isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: OptikAdminTokens.ice),
                    ),
                  )
                else if (displayList.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: PremiumEmptyState(
                      icon: listProdukPusat.isEmpty
                          ? Icons.warehouse_outlined
                          : Icons.inventory_2_outlined,
                      message: listProdukPusat.isEmpty
                          ? 'Stok Pusat kosong. Isi dulu di Master Produk.'
                          : onlyNeedRestock
                              ? 'Tidak ada yang perlu dilengkapi.\nStok toko cukup, ada RO jalan, atau belum ada penjualan 30 hari.'
                              : 'Tidak ada produk cocok filter / pencarian.',
                      action: listProdukPusat.isNotEmpty && onlyNeedRestock
                          ? FilledButton(
                              onPressed: () {
                                setState(() => onlyNeedRestock = false);
                                filterProduk();
                              },
                              child: const Text(
                                'Lihat semua stok Pusat',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            )
                          : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = displayList[index];
                          if (item == null) return const SizedBox.shrink();

                          String id = item['id'].toString();
                          final itemMap = Map<String, dynamic>.from(item as Map);
                          int maxStok = StockQty.availableOf(itemMap);
                          bool isSelected = selectedItems.containsKey(id);
                          final hint = restockHints[id];
                          final stockCabang = hint?.stockCabang ?? 0;
                          final inboundQty = hint?.inboundQty ?? 0;
                          final sold30d = hint?.sold30d ?? 0;
                          final saranQty = hint?.suggestedQty ?? 0;

                          String kategori =
                              (item['kategori']?.toString().trim() ?? '')
                                  .toLowerCase();
                          String warnaRaw =
                              item['warna']?.toString().trim() ?? "";
                          String warna = warnaRaw.isEmpty ? '-' : warnaRaw;
                          String subKategoriRaw =
                              item['sub_kategori']?.toString().trim() ?? '';
                          String subKategori =
                              subKategoriRaw.isEmpty ? '-' : subKategoriRaw;
                          String jenisLensaRaw =
                              item['jenis_lensa']?.toString().trim() ?? '';
                          String jenisLensa =
                              jenisLensaRaw.isEmpty ? '-' : jenisLensaRaw;

                          // Ekstraksi spek matriks lensa optik
                          String rawSph = (item['sph_r'] ??
                                  item['sph_l'] ??
                                  item['sph'] ??
                                  '')
                              .toString()
                              .trim();
                          String rawCyl = (item['cyl_r'] ??
                                  item['cyl_l'] ??
                                  item['cyl'] ??
                                  '')
                              .toString()
                              .trim();
                          String rawAdd = (item['add_r'] ??
                                  item['add_l'] ??
                                  item['add'] ??
                                  '')
                              .toString()
                              .trim();
                          String ukTunggal =
                              (item['ukuran_lensa'] ?? item['ukuran'] ?? '')
                                  .toString()
                                  .trim();

                          String ukuranRangkuman = "-";
                          List<String> parts = [];
                          double? numSph = double.tryParse(rawSph);
                          double? numCyl = double.tryParse(rawCyl);
                          double? numAdd = double.tryParse(rawAdd);

                          if (numSph != null && numSph != 0.0)
                            parts.add("Sph: ${numSph.toStringAsFixed(2)}");
                          if (numCyl != null && numCyl != 0.0)
                            parts.add("Cyl: ${numCyl.toStringAsFixed(2)}");
                          if (numAdd != null && numAdd != 0.0)
                            parts.add("Add: ${numAdd.toStringAsFixed(2)}");

                          if (parts.isNotEmpty) {
                            ukuranRangkuman = parts.join(' | ');
                          } else if (ukTunggal.isNotEmpty && ukTunggal != "0") {
                            double? numTunggal = double.tryParse(ukTunggal);
                            ukuranRangkuman = numTunggal != null
                                ? numTunggal.toStringAsFixed(2)
                                : ukTunggal;
                          }

                          final metaLine = kategori == 'frame'
                              ? '$subKategori · $warna'
                              : kategori == 'lensa'
                                  ? '$jenisLensa · $ukuranRangkuman'
                                  : warna;
                          final saranLine = saranQty > 0
                              ? 'Saran $saranQty pcs'
                              : sold30d <= 0
                                  ? 'Belum laku 30 hari'
                                  : 'Saran 0 · stok cukup';

                          return Container(
                            key: ValueKey('do-item-$id'),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? OptikAdminTokens.accentDeep
                                      .withOpacity(0.10)
                                  : saranQty > 0
                                      ? OptikAdminTokens.warning
                                          .withOpacity(0.06)
                                      : OptikAdminTokens.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? OptikAdminTokens.navy
                                    : saranQty > 0
                                        ? OptikAdminTokens.warning
                                            .withOpacity(0.45)
                                        : OptikAdminTokens.ice.withOpacity(0.35),
                                width: isSelected || saranQty > 0 ? 1.3 : 1,
                              ),
                              boxShadow: OptikAdminTokens.cardShadow,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    color: OptikAdminTokens.navy
                                        .withOpacity(0.04),
                                    child: ProductIdentity.catalogImageOf(itemMap)
                                            .isNotEmpty
                                        ? Image.network(
                                            ProductIdentity.catalogImageOf(
                                                itemMap),
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) =>
                                                const Icon(
                                                    Icons.image_not_supported,
                                                    color:
                                                        OptikAdminTokens.line,
                                                    size: 18))
                                        : const Icon(Icons.image_not_supported,
                                            color: OptikAdminTokens.line,
                                            size: 18),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['nama'] ?? '-',
                                        style: const TextStyle(
                                          color: OptikAdminTokens.navy,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${kategori.toUpperCase()} · $metaLine',
                                        style: TextStyle(
                                          color: OptikAdminTokens.navy
                                              .withOpacity(0.45),
                                          fontSize: 10.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Pusat $maxStok · Toko $stockCabang'
                                        '${inboundQty > 0 ? ' · Jalan $inboundQty' : ''}'
                                        ' · Laku $sold30d · $saranLine',
                                        style: TextStyle(
                                          color: saranQty > 0
                                              ? OptikAdminTokens.warning
                                              : OptikAdminTokens.textMuted,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (saranQty > 0) ...[
                                        const SizedBox(height: 4),
                                        GestureDetector(
                                          onTap: () => _applySuggestedQty(
                                              id, maxStok),
                                          child: Text(
                                            'Isi saran $saranQty',
                                            style: const TextStyle(
                                              color: OptikAdminTokens.warning,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                isSelected
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints: const BoxConstraints(
                                                minWidth: 32, minHeight: 32),
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(
                                                Icons.remove_circle,
                                                color: OptikAdminTokens.danger,
                                                size: 20),
                                            onPressed: () =>
                                                _updateQty(id, -1, maxStok),
                                          ),
                                          SizedBox(
                                            width: 30,
                                            child: TextField(
                                              controller: qtyControllers[id],
                                              keyboardType:
                                                  TextInputType.number,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  color: OptikAdminTokens.navy,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13),
                                              decoration:
                                                  const InputDecoration(
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        vertical: 2),
                                                border: InputBorder.none,
                                              ),
                                              onChanged: (val) =>
                                                  _setQtyManual(
                                                      id, val, maxStok),
                                            ),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints: const BoxConstraints(
                                                minWidth: 32, minHeight: 32),
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(Icons.add_circle,
                                                color:
                                                    OptikAdminTokens.success,
                                                size: 20),
                                            onPressed: () =>
                                                _updateQty(id, 1, maxStok),
                                          ),
                                        ],
                                      )
                                    : IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(
                                          saranQty > 0
                                              ? Icons
                                                  .add_shopping_cart_rounded
                                              : Icons.add_circle_outline,
                                          color: saranQty > 0
                                              ? OptikAdminTokens.warning
                                              : OptikAdminTokens.navy,
                                          size: 22,
                                        ),
                                        tooltip: saranQty > 0
                                            ? 'Tambah saran $saranQty'
                                            : 'Tambah',
                                        onPressed: () => _toggleItem(item),
                                      ),
                              ],
                            ),
                          );
                        },
                        childCount: displayList.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // --- BOTTOM DOCK: aksi simpan / buat DO ---
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: OptikAdminTokens.bg,
              border: Border(
                top: BorderSide(color: OptikAdminTokens.lineStrong),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cartCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$cartCount item · $cartQty pcs siap diproses',
                          style: const TextStyle(
                            color: OptikAdminTokens.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: _DoActionButton(
                          label: 'Simpan draf',
                          subtitle: 'Booking sementara',
                          icon: Icons.save_as_rounded,
                          enabled: !isProcessing && selectedItems.isNotEmpty,
                          loading: isProcessing,
                          tone: _DoActionTone.draft,
                          onTap: saveDraft,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: _DoActionButton(
                          label: 'Buat surat jalan',
                          subtitle: 'Lanjut siapkan',
                          icon: Icons.playlist_add_check_rounded,
                          enabled: !isProcessing && selectedItems.isNotEmpty,
                          loading: isProcessing,
                          tone: _DoActionTone.preparing,
                          onTap: confirmAndSend,
                        ),
                      ),
                    ],
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

/// Kartu navigasi ringkas ke antrian Disiapkan / Draf.
class _DoQueueHubCard extends StatelessWidget {
  const _DoQueueHubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.count,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: OptikAdminTokens.card,
            border: Border.all(color: accent.withOpacity(0.4)),
            boxShadow: OptikAdminTokens.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: accent.withOpacity(0.14),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: OptikAdminTokens.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        if (count > 0) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OptikAdminTokens.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: accent.withOpacity(0.75), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DoActionTone { draft, preparing }

class _DoActionButton extends StatelessWidget {
  const _DoActionButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.loading,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final bool loading;
  final _DoActionTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDraft = tone == _DoActionTone.draft;
    final accent =
        isDraft ? OptikAdminTokens.warning : OptikAdminTokens.ice;
    final fill = !enabled
        ? OptikAdminTokens.snow.withOpacity(0.04)
        : isDraft
            ? OptikAdminTokens.warning.withOpacity(0.12)
            : OptikAdminTokens.slate;
    final border = !enabled
        ? OptikAdminTokens.snow.withOpacity(0.12)
        : isDraft
            ? OptikAdminTokens.warning
            : OptikAdminTokens.ice;
    final fg = !enabled
        ? OptikAdminTokens.textMuted
        : isDraft
            ? OptikAdminTokens.warning
            : OptikAdminTokens.snow;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled && !loading ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: enabled ? 1.4 : 1),
          ),
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: accent,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(icon, color: fg, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg.withOpacity(enabled ? 0.7 : 0.4),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class DraftManagerPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const DraftManagerPage({super.key, required this.profile});
  @override
  State<DraftManagerPage> createState() => _DraftManagerPageState();
}

class _DraftManagerPageState extends State<DraftManagerPage> {
  List<dynamic> allDrafts = [];
  List<dynamic> filteredDrafts = [];
  bool isLoading = true;
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // 1. TARIK DATA DAFTAR TRANSAKSI GANTUNG DARI DATABASE SUPABASE
  Future<void> _refreshData() async {
    setState(() => isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('draft_pengiriman')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          allDrafts = data;
          _filterDrafts();
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error Fetch Drafts: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 2. FUNGSI LOGIKA FILTER DAN PENCARIAN DRAF SECARA INSTAN
  void _filterDrafts() {
    String query = searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        filteredDrafts = List.from(allDrafts);
      } else {
        filteredDrafts = allDrafts.where((draft) {
          String tujuan = (draft['tujuan'] ?? '').toString().toLowerCase();
          String itemsStr = (draft['items'] ?? '').toString().toLowerCase();
          String idStr = "drf-${draft['id']}".toLowerCase();
          return tujuan.contains(query) ||
              itemsStr.contains(query) ||
              idStr.contains(query);
        }).toList();
      }
    });
  }

  // 3. HELPER FORMAT TANGGAL LOKAL ERP (DD/MM/YYYY HH:MM)
  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return "-";
    try {
      DateTime dt = DateTime.parse(isoString).toLocal();
      return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "-";
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Draf pengiriman',
        subtitle: 'Belum jadi surat jalan',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: searchController,
              onChanged: (v) => _filterDrafts(),
              style: const TextStyle(
                  color: OptikAdminTokens.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: "draf_cari".tr(),
                hintStyle: const TextStyle(
                    color: OptikAdminTokens.textMuted, fontSize: 12.5),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: OptikAdminTokens.textMuted, size: 20),
                filled: true,
                fillColor: OptikAdminTokens.bg.withOpacity(0.55),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: OptikAdminTokens.lineStrong),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: OptikAdminTokens.navy, width: 1.3),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: OptikAdminTokens.ice))
                : filteredDrafts.isEmpty
                    ? PremiumEmptyState(
                        message: "draf_kosong".tr(),
                        icon: Icons.inventory_2_outlined,
                        accent: OptikAdminTokens.warning,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        itemCount: filteredDrafts.length,
                        itemBuilder: (context, index) {
                          final draft = filteredDrafts[index];
                          final tujuan =
                              draft['tujuan']?.toString() ?? 'Cabang';
                          final idDraft = 'DRF-${draft['id']}';
                          final tanggal = _formatDate(draft['created_at']);

                          var totalQty = 0;
                          var itemCount = 0;
                          if (draft['items'] != null) {
                            try {
                              final itemsList =
                                  jsonDecode(draft['items'].toString())
                                      as List;
                              itemCount = itemsList.length;
                              for (final itm in itemsList) {
                                totalQty +=
                                    int.tryParse(itm['qty'].toString()) ?? 0;
                              }
                            } catch (e) {
                              debugPrint('JSON Parse Error: $e');
                            }
                          }

                          return PremiumListTile(
                            dense: true,
                            icon: Icons.inventory_2_rounded,
                            iconColor: OptikAdminTokens.warning,
                            title: tujuan,
                            subtitle:
                                '$idDraft · $tanggal · $itemCount item · $totalQty pcs',
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: OptikAdminTokens.textMuted,
                            ),
                            onTap: () async {
                              final res = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DraftDetailPage(
                                    draft: draft,
                                    profile: widget.profile,
                                  ),
                                ),
                              );
                              if (res == true) _refreshData();
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HALAMAN 2: DETAIL TRANSAKSI GANTUNG -> PROSES AKHIR (EDITABLE) - PART 6 OF 6
// ============================================================================
class DraftDetailPage extends StatefulWidget {
  final dynamic draft;
  final Map<String, dynamic> profile;
  const DraftDetailPage({
    super.key,
    required this.draft,
    required this.profile,
  });

  @override
  State<DraftDetailPage> createState() => _DraftDetailPageState();
}

class _DraftDetailPageState extends State<DraftDetailPage> {
  bool isProcessing = false;
  final ImagePicker picker = ImagePicker();
  final TextEditingController alasanController = TextEditingController();
  List<dynamic> originalItems = [];
  List<dynamic> localItems = [];

  @override
  void initState() {
    super.initState();
    try {
      String raw = widget.draft['items'].toString();
      originalItems = jsonDecode(raw);
      localItems = jsonDecode(raw);
    } catch (e) {
      debugPrint("Gagal parse items: $e");
    }
  }

  @override
  void dispose() {
    alasanController.dispose();
    super.dispose();
  }

  void _increaseQty(int index) {
    setState(() {
      int currentQty = int.tryParse(localItems[index]['qty'].toString()) ?? 0;
      localItems[index]['qty'] = currentQty + 1;
    });
  }

  void _decreaseQty(int index) {
    int currentQty = int.tryParse(localItems[index]['qty'].toString()) ?? 0;
    if (currentQty > 1) {
      setState(() {
        localItems[index]['qty'] = currentQty - 1;
      });
    } else {
      _confirmRemove(index);
    }
  }

  // 1. DIALOG KONFIRMASI PENGHAPUSAN ITEM DARI MANIFES DRAF
  void _confirmRemove(int index) {
    showDialog(
      context: context,
      builder: (ctx) => R.constrainedDialog(
        context: ctx,
        child: AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("draf_hapus_title".tr(),
            style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        content: Text(
            "draf_hapus_desc".tr().replaceFirst(
                '{}', localItems[index]['nama']?.toString() ?? '-'),
            style: const TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("BATAL",
                  style: TextStyle(
                      color: OptikAdminTokens.textMuted, fontWeight: FontWeight.bold))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => localItems.removeAt(index));
            },
            child: Text("draf_btn_hapus".tr(),
                style: const TextStyle(
                    color: OptikAdminTokens.danger, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      ),
    );
  }

  // 2. DIALOG INPUT ALASAN PEMBATALAN TRANSAKSI GANTUNG
  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => R.constrainedDialog(
        context: ctx,
        child: AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("draf_batal_title".tr(),
            style: const TextStyle(
                color: OptikAdminTokens.danger,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "draf_batal_desc".tr(),
              style: const TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: alasanController,
              style: const TextStyle(color: OptikAdminTokens.navy, fontSize: 13),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: "draf_batal_hint".tr(),
                hintStyle: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 12),
                filled: true,
                fillColor: OptikAdminTokens.snow.withOpacity(0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            )
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("draf_btn_tutup".tr(),
                  style: const TextStyle(
                      color: OptikAdminTokens.textMuted, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: OptikAdminTokens.danger),
            onPressed: () {
              if (alasanController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("draf_err_alasan".tr()),
                    backgroundColor: OptikAdminTokens.warning));
                return;
              }
              Navigator.pop(ctx);
              _cancelDraft(alasanController.text.trim());
            },
            child: Text("draf_bun_proses_batal".tr(),
                style: const TextStyle(
                    color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      ),
    );
  }

  // 3. FUNGSI DATABASE: BATALKAN DRAF & KEMBALIKAN STOK FISIK KE GUDANG PUSAT
  Future<void> _cancelDraft(String alasan) async {
    setState(() => isProcessing = true);
    try {
      final mut = StockMutationService();
      // Lepas PENDING booking (Real tidak berubah)
      await mut.releaseReservation(
        kind: StockReserveKind.doDraft,
        refType: 'draft',
        refId: widget.draft['id'].toString(),
        tokoId: 'PUSAT',
      );

      await Supabase.instance.client
          .from('draft_pengiriman')
          .delete()
          .eq('id', widget.draft['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("draf_sukses_batal".tr()),
          backgroundColor: OptikAdminTokens.success));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal membatalkan draf: $e"),
          backgroundColor: OptikAdminTokens.danger));
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  // 5. Promote draft → surat jalan PREPARING (QR setelah packing siap).
  Future<void> sendDraft() async {
    if (localItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("draf_err_kosong".tr()),
          backgroundColor: OptikAdminTokens.warning));
      return;
    }

    setState(() => isProcessing = true);
    final draftId = widget.draft['id'].toString();

    try {
      // Foto packing awal (boleh diganti lagi di halaman Disiapkan).
      final photo = await pickImageSafe(
        picker: picker,
        context: context,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 50,
      );
      if (photo == null) {
        setState(() => isProcessing = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("draf_err_foto_batal".tr()),
            backgroundColor: OptikAdminTokens.warning));
        return;
      }

      final bytes = await photo.readAsBytes();
      final path =
          'pengiriman/draft_${draftId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('attendance_photos')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(upsert: true));

      final imgUrl = Supabase.instance.client.storage
          .from('attendance_photos')
          .getPublicUrl(path);

      final resiDO =
          'DO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      final actor =
          (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString();
      final lines = localItems
          .map((itm) => DoCartLines.normalize(Map<String, dynamic>.from(itm as Map)))
          .toList();
      final created = await DoLifecycleService().promoteDraft(
        draftId: draftId,
        items: lines,
        buktiFotoPengirim: imgUrl,
        resi: resiDO,
        actor: actor,
      );
      final moveIdNew = created['id']?.toString();
      if (moveIdNew == null || moveIdNew.isEmpty) {
        throw 'Surat jalan tanpa id.';
      }

      if (!mounted) return;
      setState(() => isProcessing = false);
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DoPreparingPage(
            profile: widget.profile,
            moveId: moveIdNew,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal jadikan surat jalan: $e'),
          backgroundColor: OptikAdminTokens.danger));
      setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Detail draf',
        subtitle: 'Edit barang lalu jadikan surat jalan',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: PremiumPanel(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              borderRadius: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tujuan',
                          style: TextStyle(
                            color: OptikAdminTokens.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.draft['tujuan'] ?? '-',
                          style: const TextStyle(
                            color: OptikAdminTokens.navy,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: OptikAdminTokens.warning.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Draf',
                      style: TextStyle(
                        color: OptikAdminTokens.warning,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: localItems.isEmpty
                ? PremiumEmptyState(
                    message: "draf_item_kosong".tr(),
                    icon: Icons.remove_shopping_cart_outlined,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    itemCount: localItems.length,
                    itemBuilder: (context, index) {
                      final itm = localItems[index];
                      final qty = int.tryParse(itm['qty'].toString()) ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                        decoration: BoxDecoration(
                          color: OptikAdminTokens.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: OptikAdminTokens.ice.withOpacity(0.35),
                          ),
                          boxShadow: OptikAdminTokens.cardShadow,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    itm['nama'] ?? '-',
                                    style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Kode ${itm['barcode'] ?? '-'}',
                                    style: const TextStyle(
                                      color: OptikAdminTokens.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: OptikAdminTokens.warning, size: 20),
                              onPressed: () => _decreaseQty(index),
                            ),
                            Text(
                              '$qty',
                              style: const TextStyle(
                                color: OptikAdminTokens.navy,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add_circle_outline,
                                  color: OptikAdminTokens.success, size: 20),
                              onPressed: () => _increaseQty(index),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.delete_outline,
                                  color: OptikAdminTokens.danger, size: 20),
                              onPressed: () => _confirmRemove(index),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: OptikAdminTokens.bg,
              border: Border(
                top: BorderSide(color: OptikAdminTokens.lineStrong),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isProcessing ? null : _showCancelDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OptikAdminTokens.danger,
                        side: const BorderSide(color: OptikAdminTokens.danger),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text(
                        'Batalkan',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: FilledButton(
                      onPressed: isProcessing ? null : sendDraft,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: OptikAdminTokens.snow),
                            )
                          : const Text(
                              'Jadikan surat jalan',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 12.5),
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
