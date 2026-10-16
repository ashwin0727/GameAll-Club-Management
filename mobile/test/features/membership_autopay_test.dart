import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/memberships/add_member_wizard.dart';

void main() {
  group('billing periods run in calendar months', () {
    test('14 Oct → 14 Nov → 14 Dec → 14 Jan', () {
      var d = DateTime(2026, 10, 14);
      final seen = <DateTime>[];
      for (var i = 0; i < 3; i++) {
        d = addBillingPeriod(d, 30);
        seen.add(d);
      }
      expect(seen, [DateTime(2026, 11, 14), DateTime(2026, 12, 14), DateTime(2027, 1, 14)]);
    });

    test('1, 3, 6 and 12 month intervals', () {
      final start = DateTime(2026, 9, 1);
      expect(addBillingPeriod(start, 30), DateTime(2026, 10, 1));
      expect(addBillingPeriod(start, 90), DateTime(2026, 12, 1));
      expect(addBillingPeriod(start, 180), DateTime(2027, 3, 1));
      expect(addBillingPeriod(start, 365), DateTime(2027, 9, 1));
    });

    test('month ends clamp like Razorpay: 31 Jan + 1 month = 28 Feb (29 in a leap year)', () {
      expect(addBillingPeriod(DateTime(2026, 1, 31), 30), DateTime(2026, 2, 28));
      expect(addBillingPeriod(DateTime(2028, 1, 31), 30), DateTime(2028, 2, 29));
    });

    test('a custom period under four weeks stays in days', () {
      expect(addBillingPeriod(DateTime(2026, 9, 1), 10), DateTime(2026, 9, 11));
    });

    test('the plan end date is the day before the next payment', () {
      expect(periodEndDate(DateTime(2026, 10, 14), 30), DateTime(2026, 11, 13));
      expect(periodEndDate(DateTime(2026, 10, 14), 90), DateTime(2027, 1, 13));
    });
  });

  group('membershipFeeSplit — the fee is the plan price; extras are one-time', () {
    test('the fee is always the plan price and the registration fee stays as entered', () {
      final s = membershipFeeSplit(planPriceInr: 2500, gstAmountInr: 0, registrationInr: 200, paymentAmountInr: 0);
      expect((s.feeInr, s.registrationInr), (2500, 200));
    });

    test('an amount that matches the total keeps the same extras', () {
      final s = membershipFeeSplit(planPriceInr: 2500, gstAmountInr: 450, registrationInr: 200, paymentAmountInr: 3150);
      expect((s.feeInr, s.registrationInr), (2500, 200));
    });

    test('a higher amount typed under Edit Amount becomes a one-time extra, never the recurring fee', () {
      final s = membershipFeeSplit(planPriceInr: 2500, gstAmountInr: 0, registrationInr: 200, paymentAmountInr: 3000);
      expect((s.feeInr, s.registrationInr), (2500, 500));
    });

    test('a lower amount cannot reduce the plan price', () {
      final s = membershipFeeSplit(planPriceInr: 2500, gstAmountInr: 0, registrationInr: 200, paymentAmountInr: 2000);
      expect((s.feeInr, s.registrationInr), (2500, 0));
    });
  });

  group('autoPayNextCharge', () {
    final end = DateTime(2026, 11, 14);
    test('an authorised subscription that has been charged is active and shows the next charge', () {
      expect(effectiveAutoPayStatus('authenticated', 1), 'active');
      expect(autoPayNextCharge(status: 'authenticated', chargeCount: 1, nextChargeDate: null, membershipEndDate: end), end);
    });
    test("Razorpay's own date wins", () {
      expect(autoPayNextCharge(status: 'active', chargeCount: 2, nextChargeDate: DateTime(2026, 12, 14), membershipEndDate: end), DateTime(2026, 12, 14));
    });
    test('nothing before the first charge or after AutoPay stops', () {
      expect(autoPayNextCharge(status: 'authenticated', chargeCount: 0, nextChargeDate: null, membershipEndDate: end), isNull);
      expect(autoPayNextCharge(status: 'cancelled', chargeCount: 3, nextChargeDate: DateTime(2026, 12, 14), membershipEndDate: end), isNull);
      expect(autoPayNextCharge(status: 'halted', chargeCount: 3, nextChargeDate: null, membershipEndDate: end), isNull);
    });
  });

  group('AutoPay wording', () {
    test('cadence', () {
      expect(autoPayCadence(1), 'every month');
      expect(autoPayCadence(3), 'every 3 months');
      expect(autoPayCadence(12), 'every year');
      expect(autoPayCadence(null), 'every month');
    });
    test('every status has a label', () {
      for (final s in ['created', 'authenticated', 'active', 'pending', 'halted', 'cancelled', 'completed']) {
        expect(autoPayStatusLabel(s).label, isNotEmpty);
      }
      expect(autoPayStatusLabel('active').label, 'Active');
    });
  });
}
