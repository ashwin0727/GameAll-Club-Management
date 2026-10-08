import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/coaching.dart';

/// Online billing for coaching enrollments (migration 0110): the monthly/one-time program fee model
/// and the Razorpay link / subscription row behind an enrollment.
void main() {
  Map<String, dynamic> optionJson({String? feeType, String? endDate, bool included = false}) => {
        'id': 'p1',
        'name': 'Squad',
        'default_capacity': 10,
        'default_duration_minutes': 60,
        'default_price_minor': 200000,
        'is_membership_included': included,
        'session_count': 12,
        'fee_type': ?feeType,
        'end_date': ?endDate,
      };

  group('ProgramOption fee type', () {
    test('defaults to one-time when the row carries no fee_type (pre-0110 payloads)', () {
      final o = ProgramOption.fromJson(optionJson());
      expect(o.feeType, 'ONE_TIME');
      expect(o.isMonthly, isFalse);
      expect(o.endDate, isNull);
    });

    test('reads a monthly program with its end date', () {
      final o = ProgramOption.fromJson(optionJson(feeType: 'MONTHLY', endDate: '2026-12-31'));
      expect(o.isMonthly, isTrue);
      expect(o.endDate, '2026-12-31');
      expect(o.defaultPriceMinor, 200000); // per month
    });

    test('a membership-included program is never billed monthly', () {
      final o = ProgramOption.fromJson(optionJson(feeType: 'MONTHLY', endDate: '2026-12-31', included: true));
      expect(o.isMonthly, isFalse);
    });
  });

  group('EnrollmentBilling', () {
    Map<String, dynamic> row(String kind, String status) => {
          'kind': kind,
          'status': status,
          'amount_minor': 150000,
          'total_cycles': 6,
          'charge_count': 2,
          'short_url': 'https://rzp.io/i/abc',
          'current_end': '2026-11-15',
        };

    test('maps a subscription row', () {
      final b = EnrollmentBilling.fromJson(row('SUBSCRIPTION', 'ACTIVE'));
      expect(b.isSubscription, isTrue);
      expect(b.amountMinor, 150000);
      expect(b.totalCycles, 6);
      expect(b.chargeCount, 2);
      expect(b.statusLabel, 'Active');
      expect(b.isLive, isTrue);
    });

    test('maps a payment-link row', () {
      final b = EnrollmentBilling.fromJson(row('PAYMENT_LINK', 'CREATED'));
      expect(b.isSubscription, isFalse);
      expect(b.statusLabel, 'Awaiting payment');
      expect(b.isLive, isTrue);
    });

    test('paid, cancelled, completed and expired are no longer live', () {
      for (final status in ['PAID', 'CANCELLED', 'COMPLETED', 'EXPIRED']) {
        expect(EnrollmentBilling.fromJson(row('PAYMENT_LINK', status)).isLive, isFalse, reason: status);
      }
    });

    test('a halted subscription is still live (the student can re-authorise) and labelled as failed', () {
      final b = EnrollmentBilling.fromJson(row('SUBSCRIPTION', 'HALTED'));
      expect(b.isLive, isTrue);
      expect(b.statusLabel, contains('failed'));
    });
  });
}
