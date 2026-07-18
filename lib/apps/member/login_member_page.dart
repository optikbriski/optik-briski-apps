import 'package:flutter/material.dart';

/// Placeholder login for member app. Wire to Supabase Auth later.
class LoginMemberPage extends StatefulWidget {
  const LoginMemberPage({super.key});

  @override
  State<LoginMemberPage> createState() => _LoginMemberPageState();
}

class _LoginMemberPageState extends State<LoginMemberPage> {
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _continueAsGuest() {
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Optik B. Riski',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Member',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Poin, riwayat belanja, dan promo khusus pelanggan.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                ),
              ),
              const Spacer(),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Nomor HP',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_android),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Login member masih skeleton — lanjut sebagai tamu.',
                        ),
                      ),
                    );
                    _continueAsGuest();
                  },
                  child: const Text('Masuk'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _continueAsGuest,
                  child: const Text('Jelajahi tanpa login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
