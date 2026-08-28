/// Presentation-only helpers for the Finance module — the mobile counterpart
/// of the `statusTone`/label helpers that live inline in the web's
/// finance-dashboard.tsx and transactions-list.tsx.
///
/// Nothing in this file computes a monetary figure. [financeAmount] only
/// FORMATS a server-provided minor-unit value; there is deliberately no
/// helper here that adds, subtracts, or aggregates amounts, because every
/// total the Finance UI displays must come from a backend RPC response field
/// (spec §"Core Finance Principle").
library;

import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/models/payment.dart';
import '../../shared/widgets/misc.dart';

/// Formats a server-computed minor-unit (paise) amount for display, reusing
/// the app's single currency formatter rather than introducing a second one.
/// The `/100` here is a unit conversion for display only — the value being
/// shown is still exactly what the server returned.
String financeAmount(int amountMinor) => Formatters.currencyInr((amountMinor / 100).round());

/// Mirrors web's `statusTone` in transactions-list.tsx / finance-dashboard.tsx.
StatusTone transactionStatusTone(TransactionStatus status) {
  switch (status) {
    case TransactionStatus.paid:
      return StatusTone.success;
    case TransactionStatus.failed:
      return StatusTone.danger;
    case TransactionStatus.refunded:
      return StatusTone.neutral;
    case TransactionStatus.created:
      return StatusTone.warning;
  }
}

/// The web renders the raw enum value with a `capitalize` class; this is the
/// same idea in Dart — the backend's own vocabulary, made readable.
String transactionStatusLabel(TransactionStatus status) {
  final raw = status.toJson();
  return raw[0].toUpperCase() + raw.substring(1);
}

/// "GUEST_BOOKING" -> "GUEST BOOKING", matching web's
/// `sourceType.replace("_", " ")`.
String sourceTypeLabel(PaymentSourceType sourceType) => sourceType.toJson().replaceAll('_', ' ');

/// Title-cased source label for filter menus ("Guest Booking").
String sourceTypeMenuLabel(PaymentSourceType sourceType) {
  return sourceType
      .toJson()
      .split('_')
      .map((word) => word[0] + word.substring(1).toLowerCase())
      .join(' ');
}