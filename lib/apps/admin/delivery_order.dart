import 'dart:convert'; // ✅ AMAN: Mengaktifkan fungsi jsonEncode untuk bundle payload barang
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart'; // ✅ AMAN: Untuk menangkap foto bukti surat jalan pengiriman
import 'package:easy_localization/easy_localization.dart';
import '../../shared/responsive.dart';
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

  static const _panel = Color(0xFF121A2B);
  static const _panelSoft = Color(0xFF1A2438);
  static const _line = Color(0xFF2A3548);

  Widget _buildCategoryChip(String category, Color badgeColor) {
    final isActive = selectedCategories.contains(category);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: isActive ? badgeColor.withOpacity(0.16) : _panelSoft,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
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
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive
                      ? badgeColor.withOpacity(0.6)
                      : _line,
                ),
              ),
              child: Text(
                category,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? badgeColor : const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
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
      MaterialPageRoute(builder: (_) => const DraftManagerPage()),
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
    var query = '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.78;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final q = query.trim().toLowerCase();
            final filtered = listToko.where((t) {
              if (q.isEmpty) return true;
              final id = t.toLowerCase();
              final label = _cabangLabel(t).toLowerCase();
              return id.contains(q) || label.contains(q);
            }).toList();

            return Container(
              height: maxH,
              decoration: const BoxDecoration(
                color: OptikAdminTokens.bgMid,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: OptikAdminTokens.lineStrong),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              colors: [
                                OptikAdminTokens.accentSoft.withOpacity(0.95),
                                OptikAdminTokens.accentDeep,
                              ],
                            ),
                            boxShadow:
                                OptikAdminTokens.glow(OptikAdminTokens.accent),
                          ),
                          child: const Icon(Icons.storefront_rounded,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pilih cabang tujuan',
                                style: TextStyle(
                                  color: OptikAdminTokens.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Restock akan dikirim ke cabang ini',
                                style: TextStyle(
                                  color: OptikAdminTokens.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded,
                              color: OptikAdminTokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                    child: TextField(
                      autofocus: true,
                      style: const TextStyle(
                          color: OptikAdminTokens.textPrimary, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'Cari nama cabang…',
                        hintStyle: const TextStyle(
                            color: OptikAdminTokens.textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: OptikAdminTokens.textMuted, size: 20),
                        filled: true,
                        fillColor: OptikAdminTokens.panel,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.lineStrong),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.accentSoft, width: 1.4),
                        ),
                      ),
                      onChanged: (v) => setModal(() => query = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${filtered.length} cabang',
                        style: const TextStyle(
                          color: OptikAdminTokens.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Tidak ada cabang cocok.',
                              style: TextStyle(
                                  color: OptikAdminTokens.textMuted),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final id = filtered[i];
                              final selected = id == selectedToko;
                              final label = _cabangLabel(id);
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.pop(ctx, id),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Ink(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: selected
                                            ? [
                                                OptikAdminTokens.accent
                                                    .withOpacity(0.22),
                                                OptikAdminTokens.panel,
                                              ]
                                            : [
                                                OptikAdminTokens.card
                                                    .withOpacity(0.95),
                                                OptikAdminTokens.panel
                                                    .withOpacity(0.98),
                                              ],
                                      ),
                                      border: Border.all(
                                        color: selected
                                            ? OptikAdminTokens.accentSoft
                                                .withOpacity(0.7)
                                            : OptikAdminTokens.lineStrong,
                                        width: selected ? 1.4 : 1,
                                      ),
                                      boxShadow: selected
                                          ? OptikAdminTokens.glow(
                                              OptikAdminTokens.accent)
                                          : null,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(13),
                                            gradient: LinearGradient(
                                              colors: selected
                                                  ? [
                                                      OptikAdminTokens
                                                          .accentSoft,
                                                      OptikAdminTokens
                                                          .accentDeep,
                                                    ]
                                                  : [
                                                      const Color(0xFF334155),
                                                      const Color(0xFF1E293B),
                                                    ],
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.store_mall_directory_rounded,
                                            color: selected
                                                ? Colors.white
                                                : OptikAdminTokens.textMuted,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                label,
                                                style: TextStyle(
                                                  color: selected
                                                      ? OptikAdminTokens
                                                          .textPrimary
                                                      : OptikAdminTokens
                                                          .textSecondary,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                id,
                                                style: const TextStyle(
                                                  color:
                                                      OptikAdminTokens.textMuted,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (selected)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: OptikAdminTokens.accent
                                                  .withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'Aktif',
                                              style: TextStyle(
                                                color:
                                                    OptikAdminTokens.accentSoft,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          )
                                        else
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: OptikAdminTokens.textMuted,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (picked == null || picked == selectedToko || !mounted) return;
    setState(() => selectedToko = picked);
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
            backgroundColor: Colors.red));
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
          backgroundColor: Colors.orange));
      return;
    }
    final qty = saran > maxStok ? maxStok : saran;
    setState(() {
      selectedItems[id] = qty;
      qtyControllers[id] ??= TextEditingController();
      qtyControllers[id]!.text = qty.toString();
    });
  }

  String _formatShareBreakdown(List<StoreShare> shares) {
    final top = shares
        .where((s) => s.allocated > 0 || s.needQty > 0 || s.inboundQty > 0)
        .take(4);
    return top.map((s) {
      final name = s.tokoId.replaceFirst('CABANG-', '');
      final extra = s.inboundQty > 0 ? '+RO${s.inboundQty}' : '';
      return '$name:${s.allocated} (laku ${s.sold30d}$extra)';
    }).join(' · ');
  }

  // 2. FUNGSI MEMILIH / MEMBATALKAN PILIHAN ITEM KE DALAM KERANJANG DO
  void _toggleItem(dynamic item) {
    if (item == null) return;
    String id = item['id'].toString();
    int stokTersedia = int.tryParse(item['stock']?.toString() ?? '0') ?? 0;

    if (stokTersedia <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("do_stok_kosong".tr()),
          backgroundColor: Colors.redAccent));
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
            backgroundColor: Colors.orange));
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
          backgroundColor: Colors.orange));
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

  // 5. BUNDLE DATA KERANJANG MENJADI PAYLOAD JSON UNTUK DISIMPAN KE SUPABASE
  String buildCartJson() {
    List<Map<String, dynamic>> detailItems = [];
    for (var entry in selectedItems.entries) {
      final prod =
          allProdukPusat.firstWhere((p) => p['id'].toString() == entry.key);
      final sku = ProductIdentity.skuOf(Map<String, dynamic>.from(prod));
      if (sku == null) {
        throw 'Produk ${prod['nama']} belum punya SKU. Lengkapi di Product Master.';
      }
      detailItems.add({
        'id_produk': prod['id'],
        'nama': prod['nama'] ?? '-',
        'kategori': prod['kategori'] ?? '-',
        'sub_kategori': prod['sub_kategori'] ?? '-',
        'warna': prod['warna'] ?? '-',
        'jenis_lensa': prod['jenis_lensa'] ?? '-',
        'sph_r': prod['sph_r'] ?? 0,
        'cyl_r': prod['cyl_r'] ?? 0,
        'add_r': prod['add_r'] ?? 0,
        'barcode': prod['barcode'] ?? sku,
        'sku': sku,
        'harga_jual': prod['harga_jual'] ?? prod['harga'] ?? 0,
        'harga_modal': prod['harga_modal'] ?? 0,
        'qty': entry.value
      });
    }
    return jsonEncode(detailItems);
  }

  // 6. MENGHITUNG TOTAL BARANG YANG AKAN MASUK SURAT JALAN PENGIRIMAN
  int _calculateTotalQty() {
    return selectedItems.values.fold(0, (sum, item) => sum + item);
  }

  // 1. FUNGSI DATABASE: VALIDASI STOK, POTONG STOK PUSAT, & SIMPAN KE DRAF GANTUNG
  Future<void> saveDraft() async {
    if (selectedToko == null || selectedItems.isEmpty) return;
    setState(() => isProcessing = true);

    try {
      final cartJson = buildCartJson();
      final mut = StockMutationService();
      final actor =
          (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString();

      final draft = await supabase
          .from('draft_pengiriman')
          .insert({
            'tujuan': selectedToko,
            'items': cartJson,
            'created_at': DateTime.now().toIso8601String()
          })
          .select('id')
          .single();

      // Step A: potong PUSAT via ledger (TRANSFER_OUT) — beralasan
      for (var entry in selectedItems.entries) {
        final prod = allProdukPusat
            .firstWhere((p) => p['id'].toString() == entry.key);
        final sku =
            ProductIdentity.skuOf(Map<String, dynamic>.from(prod));
        if (sku == null) {
          throw 'Produk ${prod['nama']} belum punya SKU.';
        }
        await mut.shipOut(
          fromToko: 'PUSAT',
          sku: sku,
          qty: entry.value,
          reason: StockReason.transferOut,
          alasanText: 'Alokasi draft DO → $selectedToko',
          refType: 'draft',
          refId: draft['id'].toString(),
          actorNama: actor,
        );
      }

      if (mounted) {
        setState(() {
          selectedItems.clear();
          qtyControllers.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("do_sukses_draf".tr()),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal menyimpan draf: $e"),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
        _fetchProduk(); // Sinkronisasi ulang tampilan stok terbaru di halaman utama
        _loadQueueCounts();
      }
    }
  }

  // Konfirmasi → buat surat jalan PREPARING → halaman siapkan barang + Generate QR
  void confirmAndSend() {
    if (selectedToko == null || selectedItems.isEmpty) return;

    final confirmMsg =
        'Pindahkan ${_calculateTotalQty()} pcs ke PREPARING untuk $selectedToko?\n\n'
        'Stok PUSAT dipotong sekarang. Di halaman Preparing Anda ceklis barang '
        'lalu Generate QR. Status jadi TRANSIT setelah kurir scan.';

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
              Icon(Icons.inventory_2_outlined, color: Color(0xFF2DD4BF)),
              Text('Ke Preparing',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15))
            ],
          ),
          content: Text(confirmMsg,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('BATAL',
                    style: TextStyle(
                        color: Colors.grey, fontWeight: FontWeight.bold))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2DD4BF)),
              onPressed: () {
                Navigator.pop(ctx);
                _createPreparingDo();
              },
              child: const Text('YA, PREPARING',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  /// Buat DO status PREPARING (belum TRANSIT). QR dibuat di halaman Preparing.
  Future<void> _createPreparingDo() async {
    if (selectedToko == null || selectedItems.isEmpty) return;
    setState(() => isProcessing = true);

    try {
      final cartJson = buildCartJson();
      final mut = StockMutationService();
      final actor =
          (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString();

      final resiDO =
          'DO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

      for (var entry in selectedItems.entries) {
        final prod =
            allProdukPusat.firstWhere((p) => p['id'].toString() == entry.key);
        final sku = ProductIdentity.skuOf(Map<String, dynamic>.from(prod));
        if (sku == null) {
          throw 'Produk ${prod['nama']} belum punya SKU.';
        }
        await mut.shipOut(
          fromToko: 'PUSAT',
          sku: sku,
          qty: entry.value,
          reason: StockReason.transferOut,
          alasanText: 'Prepare DO $resiDO → $selectedToko',
          refType: 'stock_move',
          refId: resiDO,
          actorNama: actor,
        );
      }

      final inserted = await Supabase.instance.client
          .from('stock_move_history')
          .insert({
            'product_name': resiDO,
            'dari_lokasi': 'PUSAT',
            'ke_lokasi': selectedToko,
            'jumlah': _calculateTotalQty(),
            'tipe': 'DELIVERY',
            'status': 'PREPARING',
            'keterangan': cartJson,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      final moveId = inserted['id'].toString();

      if (!mounted) return;
      setState(() {
        selectedItems.clear();
        qtyControllers.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('DO masuk PREPARING. Siapkan barang lalu Generate QR.'),
        backgroundColor: Colors.green,
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
          content: Text('Gagal membuat PREPARING: $e'),
          backgroundColor: Colors.red));
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ANTRIAN',
                  style: TextStyle(
                    color: OptikAdminTokens.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DoQueueHubCard(
                        title: 'Preparing',
                        subtitle: 'Siapkan & generate QR',
                        icon: Icons.fact_check_rounded,
                        accent: const Color(0xFF2DD4BF),
                        count: preparingCount,
                        onTap: _openPreparingQueue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DoQueueHubCard(
                        title: 'Draft',
                        subtitle: 'Transaksi tertunda',
                        icon: Icons.inventory_2_rounded,
                        accent: OptikAdminTokens.warning,
                        count: draftCount,
                        onTap: _openDraftList,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PremiumPanel(
                  padding: const EdgeInsets.all(14),
                  borderRadius: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              gradient: LinearGradient(
                                colors: [
                                  OptikAdminTokens.accentSoft.withOpacity(0.9),
                                  OptikAdminTokens.accentDeep,
                                ],
                              ),
                              boxShadow: OptikAdminTokens.glow(
                                  OptikAdminTokens.accent),
                            ),
                            child: const Icon(Icons.route_rounded,
                                color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Buat pengiriman',
                                  style: TextStyle(
                                    color: OptikAdminTokens.textPrimary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Pilih cabang, cari produk, lalu proses',
                                  style: TextStyle(
                                    color: OptikAdminTokens.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: listToko.isEmpty ? null : _openCabangPicker,
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                            decoration: BoxDecoration(
                              color: OptikAdminTokens.bg.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: OptikAdminTokens.lineStrong,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      colors: [
                                        OptikAdminTokens.accentSoft
                                            .withOpacity(0.9),
                                        OptikAdminTokens.accentDeep,
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                      Icons.storefront_rounded,
                                      color: Colors.white,
                                      size: 19),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "do_cabang_tujuan".tr(),
                                        style: const TextStyle(
                                          color: OptikAdminTokens.textMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedToko == null
                                            ? 'Pilih cabang…'
                                            : _cabangLabel(selectedToko!),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: OptikAdminTokens.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (selectedToko != null) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          selectedToko!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: OptikAdminTokens.textMuted,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: OptikAdminTokens.accent
                                        .withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: OptikAdminTokens.accentSoft
                                          .withOpacity(0.35),
                                    ),
                                  ),
                                  child: const Text(
                                    'Ganti',
                                    style: TextStyle(
                                      color: OptikAdminTokens.accentSoft,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: searchController,
                        onChanged: (v) => filterProduk(),
                        style: const TextStyle(
                            color: OptikAdminTokens.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "do_cari_produk".tr(),
                          hintStyle: const TextStyle(
                              color: OptikAdminTokens.textMuted, fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: OptikAdminTokens.textMuted, size: 20),
                          filled: true,
                          fillColor: OptikAdminTokens.bg.withOpacity(0.55),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: OptikAdminTokens.lineStrong),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: OptikAdminTokens.accentSoft, width: 1.4),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      if (isLoadingHints) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: const LinearProgressIndicator(
                            minHeight: 3,
                            color: OptikAdminTokens.warning,
                            backgroundColor: OptikAdminTokens.lineStrong,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              OptikAdminTokens.warning.withOpacity(0.14),
                              OptikAdminTokens.bg.withOpacity(0.35),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: OptikAdminTokens.warning.withOpacity(0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: OptikAdminTokens.warning
                                        .withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.local_shipping_rounded,
                                          size: 14,
                                          color: OptikAdminTokens.warning),
                                      SizedBox(width: 5),
                                      Text(
                                        'RESTOCK',
                                        style: TextStyle(
                                          color: OptikAdminTokens.warning,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.7,
                                        ),
                                      ),
                                    ],
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
                                    foregroundColor: OptikAdminTokens.textMuted,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Text(
                                    onlyNeedRestock
                                        ? 'Lihat semua'
                                        : 'Hanya restock',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              onlyNeedRestock
                                  ? 'Menampilkan produk yang perlu dilengkapi (laku − stok toko).'
                                  : 'Menampilkan seluruh katalog stok Pusat.',
                              style: const TextStyle(
                                color: OptikAdminTokens.textMuted,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildCategoryChip(
                                    'Frame', const Color(0xFF60A5FA)),
                                _buildCategoryChip(
                                    'Lensa', OptikAdminTokens.warning),
                                _buildCategoryChip(
                                    'Lainnya', const Color(0xFF4ADE80)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: OptikAdminTokens.accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: OptikAdminTokens.accentSoft.withOpacity(0.35)),
                  ),
                  child: Text(
                    '${displayList.length} produk',
                    style: const TextStyle(
                      color: OptikAdminTokens.accentSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                if (cartCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: OptikAdminTokens.warning.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: OptikAdminTokens.warning.withOpacity(0.4)),
                    ),
                    child: Text(
                      'Keranjang: $cartCount item · $cartQty pcs',
                      style: const TextStyle(
                        color: OptikAdminTokens.warning,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // --- AREA KATALOG DAFTAR STOK BARANG GUDANG PUSAT ---
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF60A5FA)))
                : displayList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: _panel,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _line),
                                ),
                                child: Icon(
                                  listProdukPusat.isEmpty
                                      ? Icons.warehouse_outlined
                                      : Icons.inventory_2_outlined,
                                  color: const Color(0xFF64748B),
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                listProdukPusat.isEmpty
                                    ? "do_stok_kosong".tr()
                                    : onlyNeedRestock
                                        ? 'Tidak ada yang perlu dilengkapi'
                                        : 'Tidak ada produk cocok filter',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                listProdukPusat.isEmpty
                                    ? 'Pastikan produk Pusat sudah terisi di Product Master.'
                                    : onlyNeedRestock
                                        ? 'Stok toko sudah cukup, ada RO jalan, atau belum ada penjualan 30 hari.\nKetuk "Lihat semua" untuk katalog Pusat.'
                                        : 'Coba ubah kategori atau kata kunci pencarian.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                              if (listProdukPusat.isNotEmpty &&
                                  onlyNeedRestock) ...[
                                const SizedBox(height: 14),
                                FilledButton(
                                  onPressed: () {
                                    setState(() => onlyNeedRestock = false);
                                    filterProduk();
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFBBF24),
                                    foregroundColor: Colors.black,
                                  ),
                                  child: const Text('Lihat semua stok Pusat',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          final item = displayList[index];
                          if (item == null) return const SizedBox.shrink();

                          String id = item['id'].toString();
                          int maxStok =
                              int.tryParse(item['stock']?.toString() ?? '0') ??
                                  0;
                          bool isSelected = selectedItems.containsKey(id);
                          final hint = restockHints[id];
                          final stockCabang = hint?.stockCabang ?? 0;
                          final inboundQty = hint?.inboundQty ?? 0;
                          final sold30d = hint?.sold30d ?? 0;
                          final saranQty = hint?.suggestedQty ?? 0;
                          final needQty = hint?.needQty ?? 0;
                          final totalNeedAll = hint?.totalNeedAll ?? 0;
                          final pusatEnough = hint?.pusatEnough ?? true;
                          final salesRank = hint?.salesRank ?? 0;
                          final cabangCount = hint?.cabangCount ?? 0;
                          final coveredQty = stockCabang + inboundQty;

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

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF2563EB).withOpacity(0.12)
                                  : saranQty > 0
                                      ? const Color(0xFFFBBF24).withOpacity(0.07)
                                      : _panel,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF60A5FA)
                                      : saranQty > 0
                                          ? const Color(0xFFFBBF24)
                                              .withOpacity(0.5)
                                          : _line,
                                  width: isSelected || saranQty > 0 ? 1.4 : 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.14),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Media Foto Item
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    color: Colors.white.withOpacity(0.05),
                                    child: (item['image_url'] != null &&
                                            item['image_url']
                                                .toString()
                                                .trim()
                                                .isNotEmpty &&
                                            item['image_url'] != '-')
                                        ? Image.network(item['image_url'],
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) =>
                                                const Icon(
                                                    Icons.image_not_supported,
                                                    color: Colors.white10,
                                                    size: 20))
                                        : const Icon(Icons.image_not_supported,
                                            color: Colors.white10, size: 20),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Deskripsi Item Metadata
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item['nama'] ?? '-',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 3),
                                      Text(kategori.toUpperCase(),
                                          style: const TextStyle(
                                              color: Colors.orangeAccent,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      if (kategori == 'frame')
                                        Text(
                                            "Bahan: $subKategori | Warna: $warna",
                                            style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.5),
                                                fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)
                                      else if (kategori == 'lensa')
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                "Jenis: $jenisLensa | Coating: $subKategori",
                                                style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.5),
                                                    fontSize: 11),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                            const SizedBox(height: 2),
                                            Text("Ukuran: $ukuranRangkuman",
                                                style: const TextStyle(
                                                    color: Colors.blueAccent,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w500),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis)
                                          ],
                                        )
                                      else
                                        Text("Detail: $warna",
                                            style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.5),
                                                fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Pusat: $maxStok · Stok toko: $stockCabang'
                                        '${inboundQty > 0 ? ' · Jalan/RO: $inboundQty' : ''}'
                                        ' · Laku 30h: $sold30d',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.55),
                                          fontSize: 10.5,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        sold30d > 0
                                            ? 'Melengkapi rata2: $sold30d − $coveredQty = butuh $needQty'
                                            : 'Belum ada penjualan 30 hari · saran 0',
                                        style: TextStyle(
                                          color: needQty > 0
                                              ? Colors.lightBlueAccent
                                              : Colors.white38,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        saranQty > 0
                                            ? 'Saran kirim: $saranQty pcs'
                                            : coveredQty >= sold30d &&
                                                    sold30d > 0
                                                ? 'Saran: 0 (stok toko sudah cukup / ada RO jalan)'
                                                : 'Saran: 0',
                                        style: TextStyle(
                                          color: saranQty > 0
                                              ? Colors.amberAccent
                                              : Colors.white38,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (cabangCount > 0) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          pusatEnough
                                              ? 'Pusat cukup untuk $cabangCount cabang (total sisa butuh $totalNeedAll)'
                                              : 'Pusat kurang: sisa butuh $totalNeedAll / ada $maxStok · bagi ke yang lebih laku${salesRank > 0 ? ' · prioritas #$salesRank' : ''}',
                                          style: TextStyle(
                                            color: pusatEnough
                                                ? Colors.greenAccent
                                                    .withOpacity(0.85)
                                                : Colors.orangeAccent
                                                    .withOpacity(0.9),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (hint != null &&
                                            hint.shares.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatShareBreakdown(hint.shares),
                                            style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.4),
                                              fontSize: 9,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                      if (saranQty > 0) ...[
                                        const SizedBox(height: 4),
                                        GestureDetector(
                                          onTap: () =>
                                              _applySuggestedQty(id, maxStok),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.amberAccent
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: Colors.amberAccent
                                                      .withOpacity(0.5)),
                                            ),
                                            child: const Text(
                                              'Isi saran',
                                              style: TextStyle(
                                                color: Colors.amberAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // Pengatur Stepper Angka Belanja DO di Sisi Kanan
                                const SizedBox(width: 10),
                                isSelected
                                    ? Row(
                                        children: [
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.remove_circle,
                                                  color: Colors.redAccent,
                                                  size: 20),
                                              onPressed: () =>
                                                  _updateQty(id, -1, maxStok)),
                                          SizedBox(
                                            width: 35,
                                            child: TextField(
                                              controller: qtyControllers[id],
                                              keyboardType:
                                                  TextInputType.number,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13),
                                              decoration: InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          vertical: 4),
                                                  enabledBorder:
                                                      UnderlineInputBorder(
                                                          borderSide: BorderSide(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                      0.1)))),
                                              onChanged: (val) => _setQtyManual(
                                                  id, val, maxStok),
                                            ),
                                          ),
                                          IconButton(
                                              icon: const Icon(Icons.add_circle,
                                                  color: Colors.greenAccent,
                                                  size: 20),
                                              onPressed: () =>
                                                  _updateQty(id, 1, maxStok)),
                                        ],
                                      )
                                    : IconButton(
                                        icon: Icon(
                                          saranQty > 0
                                              ? Icons.add_shopping_cart_rounded
                                              : Icons.add_box,
                                          color: saranQty > 0
                                              ? Colors.amberAccent
                                              : Colors.blueAccent,
                                          size: 24,
                                        ),
                                        tooltip: saranQty > 0
                                            ? 'Tambah dengan saran $saranQty'
                                            : 'Tambah',
                                        onPressed: () => _toggleItem(item)),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // --- BOTTOM DOCK: aksi simpan / buat DO ---
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  OptikAdminTokens.bg.withOpacity(0.92),
                  OptikAdminTokens.bg,
                ],
              ),
              border: const Border(
                top: BorderSide(color: OptikAdminTokens.lineStrong),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 28,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cartCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2DD4BF).withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFF2DD4BF).withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              '$cartCount SKU · $cartQty pcs siap diproses',
                              style: const TextStyle(
                                color: Color(0xFF2DD4BF),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: _DoActionButton(
                          label: 'SIMPAN',
                          subtitle: 'Jadi draft dulu',
                          icon: Icons.save_as_rounded,
                          enabled: !isProcessing && selectedItems.isNotEmpty,
                          loading: isProcessing,
                          tone: _DoActionTone.draft,
                          onTap: saveDraft,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DoActionButton(
                          label: 'BUAT DO',
                          subtitle: 'Masuk Preparing',
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

/// Kartu navigasi premium ke antrian Preparing / daftar Draft.
class _DoQueueHubCard extends StatefulWidget {
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
  State<_DoQueueHubCard> createState() => _DoQueueHubCardState();
}

class _DoQueueHubCardState extends State<_DoQueueHubCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  OptikAdminTokens.card.withOpacity(0.98),
                  OptikAdminTokens.panel.withOpacity(0.98),
                  accent.withOpacity(0.10),
                ],
              ),
              border: Border.all(color: accent.withOpacity(0.45), width: 1.3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: accent.withOpacity(0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -8,
                  top: -10,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(0.08),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent,
                              Color.lerp(accent, Colors.black, 0.28)!,
                            ],
                          ),
                          boxShadow: OptikAdminTokens.glow(accent),
                        ),
                        child: Icon(widget.icon, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: OptikAdminTokens.textPrimary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                if (widget.count > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                          color: accent.withOpacity(0.45)),
                                    ),
                                    child: Text(
                                      '${widget.count}',
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: OptikAdminTokens.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded,
                          color: accent.withOpacity(0.9), size: 14),
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
        isDraft ? const Color(0xFFFBBF24) : const Color(0xFF2DD4BF);
    final fill = !enabled
        ? Colors.white.withOpacity(0.04)
        : isDraft
            ? const Color(0xFFFBBF24).withOpacity(0.12)
            : const Color(0xFF0F766E);
    final border = !enabled
        ? Colors.white.withOpacity(0.12)
        : isDraft
            ? const Color(0xFFFBBF24)
            : const Color(0xFF2DD4BF);
    final fg = !enabled
        ? Colors.white38
        : isDraft
            ? const Color(0xFFFBBF24)
            : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled && !loading ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 64,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: enabled ? 1.6 : 1),
            boxShadow: enabled && !isDraft
                ? [
                    BoxShadow(
                      color: const Color(0xFF2DD4BF).withOpacity(0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: accent,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: enabled
                              ? accent.withOpacity(isDraft ? 0.18 : 0.22)
                              : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, color: fg, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: fg.withOpacity(enabled ? 0.75 : 0.45),
                                fontSize: 10.5,
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
  const DraftManagerPage({super.key});
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
      appBar: PremiumAppBar(title: "draf_title".tr()),
      body: Column(
        children: [
          // BAR INPUT PENCARIAN DATA DRAF
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: searchController,
              onChanged: (v) => _filterDrafts(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "draf_cari".tr(),
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.grey, size: 18),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),

          // AREA UTAMA DAFTAR GRID TRANSAKSI GANTUNG
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent))
                : filteredDrafts.isEmpty
                    ? Center(
                        child: Text("draf_kosong".tr(),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 14)))
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 5),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 320,
                                mainAxisExtent: 265,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16),
                        itemCount: filteredDrafts.length,
                        itemBuilder: (context, index) {
                          final draft = filteredDrafts[index];
                          String tujuan =
                              draft['tujuan']?.toString() ?? 'Cabang';
                          String idDraft = "DRF-${draft['id']}";
                          String tanggal = _formatDate(draft['created_at']);

                          int totalQty = 0;
                          List<String> previewItems = [];

                          if (draft['items'] != null) {
                            try {
                              List itemsList =
                                  jsonDecode(draft['items'].toString());
                              for (var itm in itemsList) {
                                totalQty +=
                                    int.tryParse(itm['qty'].toString()) ?? 0;
                                if (previewItems.length < 2) {
                                  previewItems
                                      .add("${itm['nama']} (${itm['qty']}x)");
                                }
                              }
                              if (itemsList.length > 2) {
                                // ✅ FIX TOKEN: Diganti dari '()' ke '{}' agar sinkron dengan bahasa ERP Bos
                                previewItems.add("draf_item_lainnya"
                                    .tr()
                                    .replaceFirst('{}',
                                        (itemsList.length - 2).toString()));
                              }
                            } catch (e) {
                              debugPrint("JSON Parse Error: $e");
                            }
                          }

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.06),
                                  width: 1.2),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                                color: Colors.orangeAccent
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                            child: const Icon(Icons.inventory_2,
                                                color: Colors.orangeAccent,
                                                size: 16),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withOpacity(0.04),
                                                borderRadius:
                                                    BorderRadius.circular(6)),
                                            child: Text(idDraft,
                                                style: const TextStyle(
                                                    color: Colors.orangeAccent,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                    letterSpacing: 0.5)),
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(tujuan,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 3),
                                      Text(tanggal,
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.4),
                                              fontSize: 10)),
                                      Divider(
                                          color: Colors.white.withOpacity(0.08),
                                          height: 20),
                                      Row(
                                        children: [
                                          Container(
                                              width: 5,
                                              height: 5,
                                              decoration: const BoxDecoration(
                                                  color: Colors.greenAccent,
                                                  shape: BoxShape.circle)),
                                          const SizedBox(width: 6),
                                          // ✅ FIX TOKEN: Diganti dari '()' ke '{}' agar sinkron
                                          Text(
                                              "draf_total_pcs"
                                                  .tr()
                                                  .replaceFirst('{}',
                                                      totalQty.toString()),
                                              style: const TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ...previewItems.map((str) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 3),
                                          child: Text("• $str",
                                              style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.6),
                                                  fontSize: 11,
                                                  height: 1.2),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis))),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10)),
                                    onPressed: () async {
                                      final res = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  DraftDetailPage(
                                                      draft: draft)));
                                      if (res == true) {
                                        _refreshData();
                                      }
                                    },
                                    child: Text("draf_btn_detail".tr(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11)),
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      ),
          )
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
  const DraftDetailPage({super.key, required this.draft});

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
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        content: Text(
            "draf_hapus_desc".tr().replaceFirst(
                '{}', localItems[index]['nama']?.toString() ?? '-'),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("BATAL",
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => localItems.removeAt(index));
            },
            child: Text("draf_btn_hapus".tr(),
                style: const TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "draf_batal_desc".tr(),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: alasanController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: "draf_batal_hint".tr(),
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
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
                      color: Colors.grey, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (alasanController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("draf_err_alasan".tr()),
                    backgroundColor: Colors.orange));
                return;
              }
              Navigator.pop(ctx);
              _cancelDraft(alasanController.text.trim());
            },
            child: Text("draf_bun_proses_batal".tr(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
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
      for (var itm in originalItems) {
        int qty = int.tryParse(itm['qty'].toString()) ?? 0;
        if (qty <= 0) continue;
        final sku = ProductIdentity.skuOf(Map<String, dynamic>.from(itm));
        if (sku == null) {
          throw 'Item draft tanpa SKU tidak bisa dikembalikan stoknya.';
        }
        await mut.applyDelta(
          tokoId: 'PUSAT',
          sku: sku,
          qtyDelta: qty,
          reason: StockReason.adjust,
          alasanText: 'Batal draft DO: $alasan',
          refType: 'draft',
          refId: widget.draft['id'].toString(),
          allowCreate: false,
        );
      }

      await Supabase.instance.client
          .from('draft_pengiriman')
          .delete()
          .eq('id', widget.draft['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("draf_sukses_batal".tr()),
          backgroundColor: Colors.green));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal membatalkan draf: $e"),
          backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  // 5. FUNGSI DATABASE: SINKRONISASI UPDATE SELISIH STOK & KIRIM DRAF JADI DO TRANSIT
  Future<void> sendDraft() async {
    if (localItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("draf_err_kosong".tr()),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => isProcessing = true);

    try {
      // Jepret bukti foto berkas manifest kurir
      // Desktop/web: fall back ke galeri (image_picker butuh cameraDelegate).
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
            backgroundColor: Colors.orange));
        return;
      }

      final bytes = await photo.readAsBytes();
      final path =
          'pengiriman/draft_${widget.draft['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('attendance_photos')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(upsert: true));

      final imgUrl = Supabase.instance.client.storage
          .from('attendance_photos')
          .getPublicUrl(path);

      // Rekonsiliasi qty draft vs final via ledger (stok sudah dipotong saat draft).
      final mut = StockMutationService();
      for (var ori in originalItems) {
        final idProduk = ori['id_produk'].toString();
        final oriQty = int.tryParse(ori['qty'].toString()) ?? 0;
        final localMatch = localItems
            .where((item) => item['id_produk'].toString() == idProduk)
            .toList();
        final finalQty = localMatch.isEmpty
            ? 0
            : int.tryParse(localMatch.first['qty'].toString()) ?? 0;
        final selisih = oriQty - finalQty; // + = kembalikan ke PUSAT
        if (selisih == 0) continue;
        final sku = ProductIdentity.skuOf(Map<String, dynamic>.from(ori));
        if (sku == null) throw 'Item draft tanpa SKU.';
        await mut.applyDelta(
          tokoId: 'PUSAT',
          sku: sku,
          qtyDelta: selisih,
          reason: StockReason.adjust,
          alasanText: 'Rekonsiliasi qty draft → DO',
          refType: 'draft',
          refId: widget.draft['id'].toString(),
          allowCreate: false,
        );
      }

      String resiDO =
          "DO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";
      int totalQty = 0;
      for (var itm in localItems) {
        totalQty += int.tryParse(itm['qty'].toString()) ?? 0;
      }

      // Lepas draf → PREPARING (QR di halaman Preparing setelah barang siap)
      final inserted = await Supabase.instance.client
          .from('stock_move_history')
          .insert({
            'product_name': resiDO,
            'dari_lokasi': 'PUSAT',
            'ke_lokasi': widget.draft['tujuan'],
            'jumlah': totalQty,
            'tipe': 'DELIVERY',
            'status': 'PREPARING',
            'bukti_foto_pengirim': imgUrl,
            'keterangan': jsonEncode(localItems),
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      await Supabase.instance.client
          .from('draft_pengiriman')
          .delete()
          .eq('id', widget.draft['id']);

      if (!mounted) return;
      setState(() => isProcessing = false);
      final moveId = inserted['id'].toString();
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DoPreparingPage(
            profile: const {},
            moveId: moveId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal memproses draf: $e"),
          backgroundColor: Colors.red));
      setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(title: "draf_detail_title".tr()),
      body: Column(
        children: [
          // HEADER KARTU DETAIL INFO TUJUAN CABANG
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("draf_tujuan".tr(),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11)),
                    Text(widget.draft['tujuan'] ?? '-',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text("draf_label_gantung".tr(),
                      style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                )
              ],
            ),
          ),

          // LIST VIEW EDITOR DAFTAR ITEMS DI DALAM DRAF
          Expanded(
            child: localItems.isEmpty
                ? Center(
                    child: Text("draf_item_kosong".tr(),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: localItems.length,
                    itemBuilder: (context, index) {
                      final itm = localItems[index];
                      int qty = int.tryParse(itm['qty'].toString()) ?? 0;
                      return Card(
                        color: OptikAdminTokens.card,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.03))),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(itm['nama'] ?? '-',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(
                                        "${'draf_barcode'.tr()}${itm['barcode'] ?? '-'}",
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.orangeAccent,
                                          size: 20),
                                      onPressed: () => _decreaseQty(index),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4)),
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                        color:
                                            Colors.blueAccent.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Text("$qty",
                                        style: const TextStyle(
                                            color: Colors.blueAccent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                  ),
                                  IconButton(
                                      icon: const Icon(Icons.add_circle_outline,
                                          color: Colors.greenAccent, size: 20),
                                      onPressed: () => _increaseQty(index),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4)),
                                  const SizedBox(width: 8),
                                  IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.redAccent, size: 20),
                                      onPressed: () => _confirmRemove(index),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4)),
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // PANEL ACTION PANEL ACTION UTAMA FOOTER BAR
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: OptikAdminTokens.bgMid,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, -5))
              ],
            ),
            child: R.isNarrow(context)
                ? Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: isProcessing ? null : _showCancelDialog,
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Colors.redAccent, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                          child: Text("draf_btn_batalkan".tr(),
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isProcessing ? null : sendDraft,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                          child: isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text("draf_btn_konfirmasi_kirim".tr(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isProcessing ? null : _showCancelDialog,
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Colors.redAccent, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                          child: Text("draf_btn_batalkan".tr(),
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isProcessing ? null : sendDraft,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                          child: isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text("draf_btn_konfirmasi_kirim".tr(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
          )
        ],
      ),
    );
  }
}
