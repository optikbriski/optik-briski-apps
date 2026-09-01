import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/admin/admin_premium.dart';

/// Pilih bahasa Admin — hanya Indonesia & English (sama seperti bootstrap).
abstract final class AdminLanguage {
  static const supported = [Locale('id'), Locale('en')];

  static void ensureSupported(BuildContext context) {
    final code = context.locale.languageCode;
    if (code != 'id' && code != 'en') {
      context.setLocale(const Locale('id'));
    }
  }

  static Future<void> showPicker(BuildContext context) async {
    ensureSupported(context);
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: OptikAdminTokens.line),
              ),
              title: Text(
                'pilihan_bahasa_judul'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _option(
                    ctx,
                    label: 'lang_id'.tr(),
                    locale: const Locale('id'),
                    onSelected: (loc) async {
                      await _applyLocale(ctx, loc);
                      setDialogState(() {});
                    },
                  ),
                  _option(
                    ctx,
                    label: 'lang_en'.tr(),
                    locale: const Locale('en'),
                    onSelected: (loc) async {
                      await _applyLocale(ctx, loc);
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _applyLocale(BuildContext context, Locale locale) async {
    if (context.locale == locale) return;
    await context.setLocale(locale);
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('notif_bahasa_sukses'.tr()),
        backgroundColor: OptikAdminTokens.navy,
      ),
    );
  }

  static Widget _option(
    BuildContext context, {
    required String label,
    required Locale locale,
    required Future<void> Function(Locale) onSelected,
  }) {
    final selected = context.locale == locale;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          color: selected
              ? OptikAdminTokens.navy
              : OptikAdminTokens.textSecondary,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: OptikAdminTokens.navy)
          : null,
      onTap: () => onSelected(locale),
    );
  }
}
