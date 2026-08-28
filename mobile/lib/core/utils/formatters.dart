import 'package:intl/intl.dart';

/// Money/time formatting shared across the app — never string-concatenate
/// a currency symbol inline in a widget (item 45/46).
class Formatters {
  const Formatters._();

  static final NumberFormat _inrWhole = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// `amountInr` is already whole rupees (matches the `payments.amount_inr`
  /// / pricing display convention used on web) — never a float computed
  /// from paise here.
  static String currencyInr(num amountInr) => _inrWhole.format(amountInr);

  /// "06:00" (24h, as stored) -> "6:00 AM".
  static String time12h(String time24) {
    final parts = time24.split(':');
    if (parts.length < 2) return time24;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final meridiem = hour < 12 ? 'AM' : 'PM';
    return '$hour12:${minute.toString().padLeft(2, '0')} $meridiem';
  }

  static String dateShort(DateTime date) =>
      DateFormat('d MMM yyyy').format(date);

  /// "27 Aug 2026, 3:30 PM" — a timestamp with its time of day, for
  /// traceability views (Finance transaction details) where "which day" is
  /// not precise enough. Converted to the device's local zone first, since
  /// Supabase hands back UTC instants.
  static String dateTimeShort(DateTime timestamp) =>
      DateFormat('d MMM yyyy, h:mm a').format(timestamp.toLocal());
}