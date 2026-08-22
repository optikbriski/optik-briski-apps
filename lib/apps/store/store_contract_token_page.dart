import 'package:flutter/material.dart';

import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/widgets/rekasa_surface.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';

class StoreContractTokenPage extends StatefulWidget {
  const StoreContractTokenPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<StoreContractTokenPage> createState() => _StoreContractTokenPageState();
}

class _StoreContractTokenPageState extends State<StoreContractTokenPage> {
  final _token = TextEditingController();

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  void _go() {
    final t = _token.text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tempel kode / token kontrak'),
          backgroundColor: RekasaTokens.warning,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TenantContractSignPage(token: t)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
        children: [
          RekasaPage(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
            child: RekasaSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tanda tangan kontrak',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tempel token dari tautan Rekasa (?kontrak=…). '
                    'Atau buka tautan itu langsung di Chrome.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _token,
                    decoration: const InputDecoration(
                      labelText: 'Token kontrak',
                    ),
                    onSubmitted: (_) => _go(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _go,
                      child: const Text('Buka kontrak'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      appBar: AppBar(title: const Text('Kontrak')),
      body: body,
    );
  }
}
