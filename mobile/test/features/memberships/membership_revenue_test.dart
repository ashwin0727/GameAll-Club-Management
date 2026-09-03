import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';

/// Parity gap G1 — the membership revenue trend chart.
///
/// `get_membership_revenue_timeseries` (migration 0026) → `(bucket date,
/// amount_inr bigint, payment_count bigint)`, granularity day/month/year.
/// Mirrors src/features/memberships/components/membership-revenue-trend.tsx.
/// `amount_inr` is whole rupees here, not minor units.
void main() {
  group('MembershipRevenueGranularity', () {
    test('serialises to the exact strings the RPC accepts', () {
      expect(MembershipRevenueGranularity.day.toJson(), 'day');
      expect(MembershipRevenueGranularity.month.toJson(), 'month');
      expect(MembershipRevenueGranularity.year.toJson(), 'year');
    });
  });

  group('MembershipRevenuePoint.fromJson', () {
    test('maps the bucket, whole-rupee amount and payment count', () {
      final p = MembershipRevenuePoint.fromJson({
        'bucket': '2026-08-01',
        'amount_inr': 124500,
        'payment_count': 9,
      });
      expect(p.bucket, '2026-08-01');
      expect(p.amountInr, 124500);
      expect(p.paymentCount, 9);
    });
  });

  group('MembershipRepository.getMembershipRevenueTimeseries', () {
    late String source;
    setUpAll(() {
      source = File('lib/data/repositories/membership_repository.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
    });

    test('calls get_membership_revenue_timeseries with the facility id and granularity', () {
      expect(source, contains("'get_membership_revenue_timeseries'"));
      expect(source, contains("'p_facility_id':"));
      expect(source, contains("'p_granularity':"));
    });

    test('maps rows straight from the server — the widget never sums a headline itself in the repo', () {
      expect(source, contains('MembershipRevenuePoint.fromJson('));
    });
  });
}
