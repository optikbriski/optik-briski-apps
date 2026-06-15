// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'admin/login_page.dart';
import 'admin/dashboard_page.dart';
import 'admin/sales_page.dart';
import 'karyawan/main_karyawan.dart';
import 'shared/liveness_camera_page.dart';
import 'karyawan/login_karyawan_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared/admin_approval_page.dart';

// ============================================================================
// 1. CONFIGURATION & INITIALIZATION (PREMIUM GLOBAL THEME)
// ============================================================================
void main() async {
  // 1. Pastikan mesin dasar Flutter berjalan
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Inisialisasi Mesin Multi-Bahasa
  await EasyLocalization.ensureInitialized();

  // 3. Inisialisasi Database Supabase
  await Supabase.initialize(
    url: 'https://pxqjdggxhwtwfsialrtu.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB4cWpkZ2d4aHd0d2ZzaWFscnR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3MDQ1NDMsImV4cCI6MjA5MzI4MDU0M30.LcnbMEr62-OOouv1kEeCswyuSg62Rge4WZrSffY9MOM',
  );

  // 4. Jalankan Aplikasi dengan Bungkus Mesin Bahasa
  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('id'), // Indonesia
        Locale('en'), // Inggris
        Locale('ms'), // Melayu
        Locale('zh'), // Mandarin
        Locale('ja'), // Jepang
      ],
      path: 'assets/translations', // Mengarah ke folder kamus yang kita buat
      fallbackLocale: const Locale('id'), // Bahasa default jika terjadi error
      child:
          const MyApp(), // Atau MyAppKaryawan (sesuaikan dengan nama class aplikasi Bos)
    ),
  );
}

final supabase = Supabase.instance.client;

String formatRupiah(int nominal) {
  return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0)
      .format(nominal);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Optik B. Riski',
      debugShowCheckedModeBanner: false,
      // WAJIB ADA: Setup Mesin Translasi Easy Localization
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.orangeAccent,
          surface: Color(0xFF1E293B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.4),
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E2429),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blueAccent, width: 2)),
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
          prefixIconColor: Colors.grey,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            elevation: 5,
            shadowColor: Colors.blueAccent.withOpacity(0.5),
            minimumSize: const Size(double.infinity, 55),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(
                fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13),
          ),
        ),
      ),
      // ✅ SEKARANG DIUBAH KE HALAMAN LOGIN RESMI
      home: const LoginPage(),
    );
  }
}





