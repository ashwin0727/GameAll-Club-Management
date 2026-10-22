import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/profile_hub.dart';
import 'package:gameall_club_mobile/features/profile/hub/hub_widgets.dart';

void main() {
  group('FacilityPlan', () {
    FacilityPlan plan({String status = 'active', String validTill = '2026-12-31'}) => FacilityPlan(
          planName: 'Pro Plan',
          priceMinor: 299900,
          currency: 'INR',
          interval: 'month',
          status: status,
          validTill: validTill,
        );

    test('is active until its last covered day has passed', () {
      expect(plan().isActive(DateTime(2026, 12, 31)), isTrue);
      expect(plan().isActive(DateTime(2027, 1, 1)), isFalse);
    });

    test('is inactive once cancelled', () {
      expect(plan(status: 'cancelled').isActive(DateTime(2026, 1, 1)), isFalse);
    });

    test('counts whole days left', () {
      expect(plan().daysLeft(DateTime(2026, 12, 30)), 1);
      expect(plan().daysLeft(DateTime(2026, 12, 31)), 0);
    });

    test('the sample plan is active until the end of the year', () {
      final sample = FacilityPlan.sample(DateTime(2026, 6, 1));
      expect(sample.isSample, isTrue);
      expect(sample.validTill, '2026-12-31');
      expect(sample.isActive(DateTime(2026, 6, 1)), isTrue);
    });
  });

  test('formats rupees with Indian grouping and dates', () {
    expect(hubMoney(299900), '₹2,999');
    expect(hubMoney(12450000), '₹1,24,500');
    expect(hubMoney(150), '₹1.50');
    expect(hubDate(DateTime(2026, 12, 31)), '31 Dec 2026');
  });

  test('notification preferences round-trip, defaulting the weekly summary off', () {
    final prefs = NotificationPrefs.fromJson(null);
    expect(prefs.bookings, isTrue);
    expect(prefs.reports, isFalse);
    expect(NotificationPrefs.fromJson(prefs.copyWith(reports: true).toJson()).reports, isTrue);
  });
}
