import 'package:intl/intl.dart';

/// Utility class for formatting timestamps consistently in Indian Standard Time (IST, UTC+05:30).
class AppDateTime {
  /// Converts any [DateTime] to Indian Standard Time (UTC+05:30).
  static DateTime toIst(DateTime dateTime) {
    final utc = dateTime.isUtc ? dateTime : dateTime.toUtc();
    return utc.add(const Duration(hours: 5, minutes: 30));
  }

  /// Formats date and time in IST, e.g. "07 Oct 2026 · 12:25 PM IST".
  static String formatIst(DateTime dateTime, {String pattern = 'dd MMM yyyy · hh:mm a'}) {
    final ist = toIst(dateTime);
    final formatted = DateFormat(pattern).format(ist);
    return '$formatted IST';
  }

  /// Formats date only in IST, e.g. "07 Oct 2026".
  static String formatDateIst(DateTime dateTime) {
    final ist = toIst(dateTime);
    return DateFormat('dd MMM yyyy').format(ist);
  }

  /// Formats short date in IST, e.g. "07 Oct".
  static String formatShortDateIst(DateTime dateTime) {
    final ist = toIst(dateTime);
    return DateFormat('dd MMM').format(ist);
  }

  /// Formats short date and time in IST, e.g. "07 Oct · 12:25 PM IST".
  static String formatShortDateTimeIst(DateTime dateTime) {
    final ist = toIst(dateTime);
    return '${DateFormat('dd MMM · hh:mm a').format(ist)} IST';
  }

  /// Formats time only in IST, e.g. "12:25 PM IST".
  static String formatTimeIst(DateTime dateTime) {
    final ist = toIst(dateTime);
    return '${DateFormat('hh:mm a').format(ist)} IST';
  }
}
