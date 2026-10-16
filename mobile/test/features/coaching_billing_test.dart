import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/coaching.dart';
import 'package:gameall_club_mobile/features/coaching/coaching_billing.dart';

EnrollmentBilling billing({String kind = 'SUBSCRIPTION', String status = 'ACTIVE', int cycles = 6, int charged = 2, String? currentEnd = '2026-11-14'}) =>
    EnrollmentBilling(
      kind: kind,
      status: status,
      amountMinor: 120000,
      totalCycles: cycles,
      chargeCount: charged,
      shortUrl: null,
      currentEnd: currentEnd,
    );

void main() {
  group('chargeDates', () {
    test('is the same day each month: 14 Oct → 14 Nov → 14 Dec → 14 Jan', () {
      expect(chargeDates(DateTime(2026, 10, 14), 4), [
        DateTime(2026, 10, 14),
        DateTime(2026, 11, 14),
        DateTime(2026, 12, 14),
        DateTime(2027, 1, 14),
      ]);
    });
    test('clamps month ends without drifting: 31 Jan → 28 Feb → 31 Mar', () {
      expect(chargeDates(DateTime(2026, 1, 31), 3), [DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31)]);
    });
    test('is at least one charge', () => expect(chargeDates(DateTime(2026, 10, 14), 0), [DateTime(2026, 10, 14)]));
  });

  group('programLengthLabel', () {
    test('reads the dates in weeks and months', () {
      expect(programLengthLabel(DateTime(2026, 10, 1), DateTime(2027, 3, 17)), '24 weeks · 6 months');
      expect(programLengthLabel(DateTime(2026, 10, 1), DateTime(2026, 10, 7)), '1 week · 1 month');
    });
    test('is null without both dates', () {
      expect(programLengthLabel(DateTime(2026, 10, 1), null), isNull);
      expect(programLengthLabel(null, DateTime(2026, 10, 1)), isNull);
    });
  });

  group('perSessionMinor', () {
    test('spreads the total over the sessions', () => expect(perSessionMinor(720000, 72), 10000));
    test('is null when unknown', () {
      expect(perSessionMinor(720000, null), isNull);
      expect(perSessionMinor(0, 72), isNull);
    });
  });

  group('nextPaymentDate / chargesLeft', () {
    test('only while charging', () {
      expect(nextPaymentDate(billing()), '2026-11-14');
      expect(nextPaymentDate(billing(status: 'PENDING')), '2026-11-14');
      expect(nextPaymentDate(billing(status: 'CREATED')), isNull);
      expect(nextPaymentDate(billing(status: 'CANCELLED')), isNull);
      expect(nextPaymentDate(billing(kind: 'PAYMENT_LINK')), isNull);
      expect(nextPaymentDate(null), isNull);
    });
    test('upcoming charges run month by month and stop at the charges left', () {
      expect(upcomingCharges(billing()), [DateTime(2026, 11, 14), DateTime(2026, 12, 14), DateTime(2027, 1, 14)]);
      expect(upcomingCharges(billing(cycles: 3, charged: 2)), [DateTime(2026, 11, 14)]);
      expect(upcomingCharges(billing(cycles: 2, charged: 2)), isEmpty);
      expect(upcomingCharges(billing(status: 'CANCELLED')), isEmpty);
    });
    test('charges left never go below zero', () {
      expect(chargesLeft(billing(cycles: 6, charged: 2)), 4);
      expect(chargesLeft(billing(cycles: 3, charged: 5)), 0);
    });
  });
}
