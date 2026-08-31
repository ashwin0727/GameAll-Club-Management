import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/memberships/membership_charges.dart';

/// Guards that the client-side charge preview matches the server-side
/// computation in `create_membership_full`
/// (supabase/migrations/0028_membership_creation_form.sql):
///   gst_amount := round(fee * gst / 100.0);
///   total      := fee + gst_amount + reg;
void main() {
  group('computeMembershipCharges', () {
    test('sums fee + GST + registration', () {
      final c = computeMembershipCharges(feeInr: 1000, gstPercent: 18, registrationInr: 500);
      expect(c.subTotal, 1000);
      expect(c.gstAmount, 180);
      expect(c.registration, 500);
      expect(c.total, 1680);
    });

    test('rounds GST to the nearest rupee', () {
      final c = computeMembershipCharges(feeInr: 999, gstPercent: 18, registrationInr: 0);
      // 999 * 18 / 100 = 179.82 -> 180
      expect(c.gstAmount, 180);
      expect(c.total, 1179);
    });

    test('zero GST leaves only fee + registration', () {
      final c = computeMembershipCharges(feeInr: 1200, gstPercent: 0, registrationInr: 300);
      expect(c.gstAmount, 0);
      expect(c.total, 1500);
    });

    test('null / negative / non-finite inputs clamp to zero', () {
      final c = computeMembershipCharges(feeInr: null, gstPercent: -5, registrationInr: double.nan);
      expect(c.subTotal, 0);
      expect(c.gstAmount, 0);
      expect(c.registration, 0);
      expect(c.total, 0);
    });
  });
}