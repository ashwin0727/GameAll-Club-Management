import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/finance/money.dart';

/// Finance rework — Phase 11: the one piece of client-side finance logic that
/// is ported rather than left to the server. Mirrors
/// src/features/finance/money.ts / money.test.ts (`canRecordPayment`).
///
/// The database enforces the same two rules — this exists so the Record
/// Payment form can say "no" before the round trip, and so the rule is
/// testable. Every amount is integer minor units; money never touches a float.
void main() {
  group('canRecordPayment', () {
    test('accepts a payment up to the amount outstanding', () {
      expect(canRecordPayment(amountMinor: 50000, outstandingMinor: 80000), isA<RecordPaymentOk>());
      expect(canRecordPayment(amountMinor: 80000, outstandingMinor: 80000), isA<RecordPaymentOk>());
    });

    test('rejects a zero or negative amount', () {
      final check = canRecordPayment(amountMinor: 0, outstandingMinor: 80000);
      expect(check, isA<RecordPaymentInvalid>());
      expect((check as RecordPaymentInvalid).reason, 'Enter an amount greater than zero.');
      expect(canRecordPayment(amountMinor: -100, outstandingMinor: 80000), isA<RecordPaymentInvalid>());
    });

    test('rejects a payment against something already settled', () {
      final check = canRecordPayment(amountMinor: 10000, outstandingMinor: 0);
      expect((check as RecordPaymentInvalid).reason, 'This booking has already been paid.');
    });

    test('rejects taking more than is owed', () {
      final check = canRecordPayment(amountMinor: 90000, outstandingMinor: 80000);
      expect((check as RecordPaymentInvalid).reason, "That's more than the amount outstanding.");
    });
  });

  group('toMajor', () {
    test('converts minor units to rupees for display only', () {
      expect(toMajor(80000), 800);
      expect(toMajor(12345), closeTo(123.45, 1e-9));
    });
  });
}
