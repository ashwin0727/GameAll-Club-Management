/// Finance arithmetic that the client is allowed to do: none of it computes
/// revenue. Mirrors src/features/finance/money.ts.
///
/// The database is authoritative — `record_obligation_payment` enforces these
/// same rules server-side. [canRecordPayment] exists so the Record Payment
/// form can reject a bad amount before the round trip, and so the rule is
/// testable. Everything is in integer minor units; money never touches a
/// float here (0.1 + 0.2 is not 0.3, and a rupee lost to binary rounding in a
/// ledger is a rupee somebody has to explain).
library;

/// The result of checking whether a payment may be recorded.
sealed class RecordPaymentCheck {
  const RecordPaymentCheck();
}

class RecordPaymentOk extends RecordPaymentCheck {
  const RecordPaymentOk();
}

class RecordPaymentInvalid extends RecordPaymentCheck {
  const RecordPaymentInvalid(this.reason);

  final String reason;
}

/// Whether a payment of this size may be recorded against an amount owed.
///
/// Guards the two mistakes that cost real money: taking more than is owed, and
/// recording a payment against something already settled.
RecordPaymentCheck canRecordPayment({
  required int amountMinor,
  required int outstandingMinor,
}) {
  if (amountMinor <= 0) {
    return const RecordPaymentInvalid('Enter an amount greater than zero.');
  }
  if (outstandingMinor <= 0) {
    return const RecordPaymentInvalid('This booking has already been paid.');
  }
  if (amountMinor > outstandingMinor) {
    return const RecordPaymentInvalid("That's more than the amount outstanding.");
  }
  return const RecordPaymentOk();
}

/// Rupees from minor units, for display and for prefilling the amount field —
/// never for arithmetic that feeds back into a stored figure.
double toMajor(int amountMinor) => amountMinor / 100;
