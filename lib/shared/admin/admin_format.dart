import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Format angka & tanggal Admin — ikuti locale UI (id / en), bukan hardcode id_ID.
abstract final class AdminFormat {
  static String localeTag(Locale locale) {
    return locale.languageCode == 'en' ? 'en_US' : 'id_ID';
  }

  static String localeTagFrom(BuildContext context) =>
      localeTag(context.locale);

  static NumberFormat currency(BuildContext context) {
    return NumberFormat.currency(
      locale: localeTagFrom(context),
      symbol: 'Rp',
      decimalDigits: 0,
    );
  }

  static String rupiah(BuildContext context, num amount) {
    return currency(context).format(amount);
  }

  static DateFormat date(BuildContext context, String pattern) {
    return DateFormat(pattern, localeTagFrom(context));
  }
}
