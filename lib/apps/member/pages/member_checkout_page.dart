import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../shared/member/member_cart.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_option_picker.dart';
import 'member_orders_list_page.dart';

class MemberCheckoutPage extends StatefulWidget {
  const MemberCheckoutPage({super.key});

  @override
  State<MemberCheckoutPage> createState() => _MemberCheckoutPageState();
}

class _MemberCheckoutPageState extends State<MemberCheckoutPage> {
  final _repo = MemberRepository();
  final _cart = MemberCart.instance;
  final _address = TextEditingController();
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  List<Map<String, dynamic>> _stores = const [];
  String? _tokoId;
  String _fulfillment = 'pickup';
  String _courier = 'grab';
  int _shippingFee = 0;
  bool _loading = true;
  bool _paying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _address.text = MemberSession.instance.alamat ?? '';
    _boot();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _cart.ensureLoaded();
    if (!MemberSession.instance.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Login dulu untuk checkout.';
      });
      return;
    }
    if (_cart.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Keranjang kosong.';
      });
      return;
    }
    try {
      final stores = await _repo.listOnlineStores();
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _tokoId = stores.isEmpty
            ? null
            : (stores.first['toko_id'] ?? '').toString();
        _loading = false;
      });
      await _refreshShipping();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Map<String, dynamic>? get _selectedStore {
    if (_tokoId == null) return null;
    for (final s in _stores) {
      if ((s['toko_id'] ?? '').toString() == _tokoId) return s;
    }
    return null;
  }

  Future<void> _refreshShipping() async {
    if (_fulfillment != 'delivery' || _tokoId == null) {
      setState(() => _shippingFee = 0);
      return;
    }
    final q = await _repo.quoteDelivery(tokoId: _tokoId!, courier: _courier);
    if (!mounted) return;
    if (q['ok'] == true) {
      setState(() {
        _shippingFee = int.tryParse('${q['shipping_fee'] ?? 0}') ?? 0;
      });
    } else {
      setState(() => _shippingFee = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${q['error'] ?? 'Gagal ongkir'}')),
      );
    }
  }

  int get _total => _cart.subtotal + _shippingFee;

  Future<void> _pay() async {
    final session = MemberSession.instance;
    if (!session.isLoggedIn) {
      Navigator.of(context).pushNamed('/login');
      return;
    }
    if (_tokoId == null || _tokoId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cabang dulu')),
      );
      return;
    }
    final store = _selectedStore;
    if (_fulfillment == 'pickup' && store?['pickup_enabled'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cabang ini tidak terima pickup')),
      );
      return;
    }
    if (_fulfillment == 'delivery') {
      if (store?['delivery_enabled'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cabang ini tidak terima pengiriman')),
        );
        return;
      }
      if (_address.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Isi alamat pengiriman')),
        );
        return;
      }
    }

    setState(() => _paying = true);
    try {
      final res = await _repo.createOnlineCheckout(
        phone: session.phoneForQuery,
        memberId: session.memberId,
        customerName: session.nama,
        tokoId: _tokoId!,
        fulfillment: _fulfillment,
        courier: _fulfillment == 'delivery' ? _courier : null,
        addressText: _fulfillment == 'delivery' ? _address.text.trim() : null,
        items: _cart.toCheckoutItems(),
      );
      if (!mounted) return;
      if (res['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${res['error'] ?? 'Checkout gagal'}'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final mock = res['mock_payment'] == true;
      final redirect = (res['redirect_url'] ?? '').toString();
      final midOrderId = (res['midtrans_order_id'] ?? '').toString();
      final onlineId = (res['online_order_id'] ?? '').toString();

      if (mock || redirect.isEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Bayar (uji / tanpa Midtrans)'),
            content: Text(
              'Order $midOrderId siap.\n'
              'Total ${_money.format(_total)}.\n\n'
              'Set MIDTRANS_SERVER_KEY di Edge untuk bayar asli. '
              'Sementara bisa lunasi uji agar masuk finance cabang.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Nanti'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Bayar uji'),
              ),
            ],
          ),
        );
        if (ok == true) {
          final paid = await _repo.mockPayOnlineOrder(midOrderId);
          if (!mounted) return;
          if (paid['ok'] == true) {
            await _cart.clear();
            await _showSuccess(onlineId);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${paid['error'] ?? 'Gagal lunasi'}'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
        return;
      }

      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => _MidtransPayPage(
            redirectUrl: redirect,
            phone: session.phoneForQuery,
            onlineOrderId: onlineId,
          ),
        ),
      );
      if (!mounted) return;
      if (paid == true) {
        await _cart.clear();
        await _showSuccess(onlineId);
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _showSuccess(String onlineId) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pembayaran berhasil'),
        content: const Text(
          'Pesanan masuk ke cabang yang dipilih dan tercatat di keuangan cabang. '
          'Lacak di menu Pesanan.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) =>
                      const MemberOrdersListPage(title: 'Pesanan saya'),
                ),
                (r) => r.isFirst,
              );
            },
            child: const Text('Lihat pesanan'),
          ),
        ],
      ),
    );
  }

  String? get _cabangLabel {
    if (_tokoId == null) return null;
    for (final s in _stores) {
      if ((s['toko_id'] ?? '').toString() == _tokoId) {
        return (s['label'] ?? s['toko_id']).toString();
      }
    }
    return _tokoId;
  }

  Future<void> _pickCabang() async {
    final picked = await showMemberOptionPicker<String>(
      context,
      title: 'Pilih cabang',
      icon: Icons.storefront_outlined,
      selected: _tokoId,
      searchHint: 'Cari cabang…',
      options: _stores
          .map(
            (s) => MemberPickerOption<String>(
              value: (s['toko_id'] ?? '').toString(),
              label: (s['label'] ?? s['toko_id']).toString(),
              icon: Icons.storefront_outlined,
            ),
          )
          .where((o) => o.value.isNotEmpty)
          .toList(),
    );
    if (picked != null && mounted) {
      setState(() => _tokoId = picked);
      await _refreshShipping();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MemberPremiumScaffold(
        title: 'Checkout',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return MemberPremiumScaffold(
        title: 'Checkout',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                if (!MemberSession.instance.isLoggedIn)
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/login'),
                    child: const Text('Login'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final store = _selectedStore;

    return MemberPremiumScaffold(
      title: 'Checkout',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          const Text(
            'Cabang pemenuhan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Stok & pembayaran masuk ke cabang ini.',
            style: TextStyle(
                color: OptikMemberTokens.inkMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          MemberPickerField(
            label: 'Pilih cabang',
            icon: Icons.storefront_outlined,
            valueLabel: _cabangLabel,
            placeholder: 'Pilih cabang',
            onTap: _pickCabang,
          ),
          const SizedBox(height: 18),
          const Text(
            'Cara terima barang',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'pickup',
                label: Text('Ambil di toko'),
                icon: Icon(Icons.storefront_outlined, size: 18),
              ),
              ButtonSegment(
                value: 'delivery',
                label: Text('Kirim'),
                icon: Icon(Icons.delivery_dining_outlined, size: 18),
              ),
            ],
            selected: {_fulfillment},
            onSelectionChanged: (s) async {
              setState(() => _fulfillment = s.first);
              await _refreshShipping();
            },
          ),
          if (_fulfillment == 'delivery') ...[
            const SizedBox(height: 14),
            const Text(
              'Kurir',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final c in [
                  ('grab', 'Grab'),
                  ('gojek', 'Gojek'),
                  ('other', 'Lainnya'),
                ])
                  ChoiceChip(
                    label: Text(c.$2),
                    selected: _courier == c.$1,
                    onSelected: (_) async {
                      setState(() => _courier = c.$1);
                      await _refreshShipping();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Alamat pengiriman lengkap',
                hintText: 'Nama jalan, RT/RW, patokan…',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ongkir flat cabang: ${_money.format(_shippingFee)} '
              '(nanti bisa diganti quote API Grab/GoSend).',
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12,
              ),
            ),
          ],
          if (store != null && _fulfillment == 'pickup') ...[
            const SizedBox(height: 10),
            Text(
              'Ambil di ${(store['label'] ?? _tokoId)} setelah status siap.',
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 12.5,
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Ringkasan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ..._cart.items.map(
            (it) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(child: Text('${it.nama} ×${it.qty}')),
                  Text(_money.format(it.lineTotal)),
                ],
              ),
            ),
          ),
          const Divider(height: 24),
          _sumRow('Subtotal', _cart.subtotal),
          if (_fulfillment == 'delivery')
            _sumRow('Ongkir ($_courier)', _shippingFee),
          const SizedBox(height: 6),
          _sumRow('Total bayar (lunas)', _total, bold: true),
          const SizedBox(height: 8),
          const Text(
            'Wajib lunas via Midtrans. Dana masuk finance cabang terpilih.',
            style: TextStyle(
              color: OptikMemberTokens.inkMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _paying ? null : _pay,
            icon: _paying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_rounded),
            label: Text(
              _paying ? 'Memproses…' : 'Bayar lunas ${_money.format(_total)}',
            ),
          ),
        ),
      ),
    );
  }

  Widget _sumRow(String label, int amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: bold
                  ? OptikMemberTokens.blueDeep
                  : OptikMemberTokens.inkSecondary,
            ),
          ),
          const Spacer(),
          Text(
            _money.format(amount),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 17 : 14,
              color: bold
                  ? OptikMemberTokens.blueDeep
                  : OptikMemberTokens.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _MidtransPayPage extends StatefulWidget {
  const _MidtransPayPage({
    required this.redirectUrl,
    required this.phone,
    required this.onlineOrderId,
  });

  final String redirectUrl;
  final String phone;
  final String onlineOrderId;

  @override
  State<_MidtransPayPage> createState() => _MidtransPayPageState();
}

class _MidtransPayPageState extends State<_MidtransPayPage> {
  late final WebViewController _controller;
  final _repo = MemberRepository();
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _pollStatus(),
        ),
      )
      ..loadRequest(Uri.parse(widget.redirectUrl));
  }

  Future<void> _pollStatus() async {
    if (_checking) return;
    _checking = true;
    try {
      final res = await _repo.getOnlineOrder(
        phone: widget.phone,
        onlineOrderId: widget.onlineOrderId,
      );
      if (!mounted) return;
      final order = res['order'];
      if (order is Map) {
        final status = (order['status'] ?? '').toString();
        if (status == 'paid' ||
            status == 'packing' ||
            status == 'ready' ||
            status == 'shipped' ||
            status == 'fulfilled') {
          Navigator.pop(context, true);
        }
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembayaran Midtrans'),
        actions: [
          TextButton(
            onPressed: () async {
              await _pollStatus();
              if (!mounted) return;
              final messenger = ScaffoldMessenger.of(this.context);
              messenger.showSnackBar(
                const SnackBar(content: Text('Status diperbarui')),
              );
            },
            child: const Text('Cek status'),
          ),
          IconButton(
            tooltip: 'Buka di browser',
            onPressed: () => launchUrl(
              Uri.parse(widget.redirectUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_browser),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
