import 'package:intl/intl.dart';

String formatRupiah(int nominal) {
  return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0)
      .format(nominal);
}
