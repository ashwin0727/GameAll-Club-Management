import '../../core/utils/formatters.dart';

/// `amountMinor` (paise) → the app's INR display format. Mirrors
/// src/features/maintenance/status.ts's formatMoney.
String maintenanceAmount(int? amountMinor) {
  if (amountMinor == null) return '—';
  return Formatters.currencyInr((amountMinor / 100).round());
}

String maintenanceDateTime(DateTime? dt) {
  if (dt == null) return '—';
  final local = dt.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  final min = local.minute.toString().padLeft(2, '0');
  return '${local.day.toString().padLeft(2, '0')} ${_month(local.month)} ${local.year}, $h:$min $ampm';
}

String _month(int m) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ][m - 1];
