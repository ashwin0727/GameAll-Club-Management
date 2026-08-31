import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';

void main() {
  group('MembershipPlan.fromJson', () {
    test('parses a full membership_plans row, matching the web app column names', () {
      final plan = MembershipPlan.fromJson({
        'id': 'plan-1',
        'facility_id': 'facility-1',
        'name': 'Monthly',
        'price_inr': 1500,
        'duration_days': 30,
        'features': ['Unlimited slots', 'Priority booking'],
        'is_active': true,
        'created_at': '2026-08-01T10:00:00Z',
      });

      expect(plan.name, 'Monthly');
      expect(plan.priceInr, 1500);
      expect(plan.durationDays, 30);
      expect(plan.features, ['Unlimited slots', 'Priority booking']);
      expect(plan.isActive, isTrue);
    });
  });

  group('Membership.fromJson', () {
    test('parses a memberships row using the plan_name column when present', () {
      final membership = Membership.fromJson({
        'id': 'membership-1',
        'facility_id': 'facility-1',
        'member_id': 'member-1',
        'plan_id': 'plan-1',
        'plan_name': 'Monthly',
        'status': 'active',
        'start_date': '2026-08-01',
        'end_date': '2026-08-31',
        'auto_renew': false,
        'created_at': '2026-08-01T10:00:00Z',
      });

      expect(membership.status, MembershipStatus.active);
      expect(membership.planName, 'Monthly');
      expect(membership.startDate, DateTime.parse('2026-08-01'));
      expect(membership.endDate, DateTime.parse('2026-08-31'));
    });

    test('uses the planName override when the row has no plan_name column (joined query)', () {
      final membership = Membership.fromJson({
        'id': 'membership-1',
        'facility_id': 'facility-1',
        'member_id': 'member-1',
        'plan_id': 'plan-1',
        'status': 'cancelled',
        'start_date': '2026-08-01',
        'end_date': '2026-08-31',
        'auto_renew': false,
        'created_at': '2026-08-01T10:00:00Z',
      }, planName: 'Quarterly');

      expect(membership.status, MembershipStatus.cancelled);
      expect(membership.planName, 'Quarterly');
    });
  });

  group('membershipStatusToDb', () {
    test('round-trips every status', () {
      expect(membershipStatusToDb(MembershipStatus.active), 'active');
      expect(membershipStatusToDb(MembershipStatus.expired), 'expired');
      expect(membershipStatusToDb(MembershipStatus.cancelled), 'cancelled');
      expect(membershipStatusToDb(MembershipStatus.pending), 'pending');
    });
  });

  group('FacilityMemberRow.fromJson', () {
    test('parses a search_facility_members row', () {
      final row = FacilityMemberRow.fromJson({
        'member_id': 'member-1',
        'full_name': 'Priya Shah',
        'phone': '9876543210',
        'email': 'priya@example.com',
        'membership_id': 'membership-1',
        'plan_id': 'plan-1',
        'plan_name': 'Monthly',
        'start_date': '2026-08-01',
        'end_date': '2026-08-31',
        'status': 'active',
      });

      expect(row.fullName, 'Priya Shah');
      expect(row.phone, '9876543210');
      expect(row.status, MembershipStatus.active);
      expect(row.planName, 'Monthly');
    });

    test('email can be null', () {
      final row = FacilityMemberRow.fromJson({
        'member_id': 'member-1',
        'full_name': 'Priya Shah',
        'phone': '9876543210',
        'email': null,
        'membership_id': 'membership-1',
        'plan_id': 'plan-1',
        'plan_name': 'Monthly',
        'start_date': '2026-08-01',
        'end_date': '2026-08-31',
        'status': 'expired',
      });

      expect(row.email, isNull);
      expect(row.status, MembershipStatus.expired);
    });

    test('a member with no membership yet has all membership fields null', () {
      final row = FacilityMemberRow.fromJson({
        'member_id': 'member-1',
        'full_name': 'Priya Shah',
        'phone': '9876543210',
        'email': null,
        'membership_id': null,
        'plan_id': null,
        'plan_name': null,
        'start_date': null,
        'end_date': null,
        'status': null,
      });

      expect(row.memberId, 'member-1');
      expect(row.fullName, 'Priya Shah');
      expect(row.phone, '9876543210');
      expect(row.membershipId, isNull);
      expect(row.planId, isNull);
      expect(row.planName, isNull);
      expect(row.startDate, isNull);
      expect(row.endDate, isNull);
      expect(row.status, isNull);
    });
  });

  group('Member.fromJson', () {
    test('parses a members row — a facility customer record, not an auth account', () {
      final member = Member.fromJson({
        'id': 'member-1',
        'facility_id': 'facility-1',
        'full_name': 'Priya Shah',
        'phone': '9876543210',
        'email': 'priya@example.com',
        'date_of_birth': '1995-05-01',
        'gender': 'Female',
        'notes': 'Prefers evening slots',
        'status': 'ACTIVE',
        'user_id': null,
        'created_at': '2026-08-01T10:00:00Z',
        'updated_at': '2026-08-01T10:00:00Z',
      });

      expect(member.fullName, 'Priya Shah');
      expect(member.phone, '9876543210');
      expect(member.status, 'ACTIVE');
      // A member normally has no linked Supabase Auth account.
      expect(member.userId, isNull);
    });

    test('email/dateOfBirth/gender/notes/userId are all optional', () {
      final member = Member.fromJson({
        'id': 'member-1',
        'facility_id': 'facility-1',
        'full_name': 'Priya Shah',
        'phone': '9876543210',
        'email': null,
        'date_of_birth': null,
        'gender': null,
        'notes': null,
        'status': 'ACTIVE',
        'user_id': null,
        'created_at': '2026-08-01T10:00:00Z',
        'updated_at': '2026-08-01T10:00:00Z',
      });

      expect(member.email, isNull);
      expect(member.dateOfBirth, isNull);
      expect(member.gender, isNull);
      expect(member.notes, isNull);
    });
  });

  group('MemberStats.fromJson', () {
    test('parses a full get_member_stats row', () {
      final stats = MemberStats.fromJson({
        'total_visits': 12,
        'total_bookings': 14,
        'last_visit': '2026-08-24T10:00:00Z',
        'total_amount_minor': 600000,
        'pending_amount_minor': 50000,
        'sports': [
          {'sportId': 'sport-1', 'sportName': 'Badminton'},
        ],
      });

      expect(stats.totalVisits, 12);
      expect(stats.totalBookings, 14);
      expect(stats.lastVisit, isNotNull);
      expect(stats.totalAmountMinor, 600000);
      expect(stats.pendingAmountMinor, 50000);
      expect(stats.sports.single.sportName, 'Badminton');
    });

    test('a member with no bookings has zeroed stats and no last visit', () {
      final stats = MemberStats.fromJson({
        'total_visits': 0,
        'total_bookings': 0,
        'last_visit': null,
        'total_amount_minor': 0,
        'pending_amount_minor': 0,
        'sports': <dynamic>[],
      });

      expect(stats.totalVisits, 0);
      expect(stats.lastVisit, isNull);
      expect(stats.sports, isEmpty);
    });
  });

  group('MembershipDetail.fromJson', () {
    test('parses the get_membership_detail jsonb document', () {
      final d = MembershipDetail.fromJson({
        'membershipId': 'ms-1',
        'facilityId': 'fac-1',
        'displayStatus': 'payment_not_initiated',
        'member': {
          'id': 'mem-1',
          'fullName': 'Rahul Sharma',
          'phone': '9876543210',
          'email': 'r@e.com',
          'dateOfBirth': '1992-04-12',
          'gender': 'Male',
          'address': 'Indiranagar',
          'status': 'ACTIVE',
          'memberSince': '2026-05-24T00:00:00Z',
        },
        'membership': {
          'name': 'Premium',
          'membershipType': 'FAMILY',
          'rawStatus': 'active',
          'startDate': '2026-05-24',
          'endDate': '2026-06-24',
          'durationDays': 31,
          'maxFamilyMembers': 2,
          'description': 'All courts',
          'membershipFeeInr': 2500,
          'registrationFeeInr': 500,
          'gstPercent': 18,
          'totalAmountInr': 3540,
          'monthlyPriceInr': 2500,
          'autoRenew': false,
          'createdAt': '2026-05-24T11:20:00Z',
        },
        'payment': {
          'amountInr': 3540,
          'status': 'paid',
          'method': 'upi',
          'paidAt': '2026-05-24T11:23:00Z',
          'createdAt': '2026-05-24T11:20:00Z',
          'transactionId': 'UPI/4123/5598/2026',
        },
        'referralName': 'Sneha Reddy',
        'createdByName': 'Arun Kumar',
        'discoverySource': 'Friends',
        'paymentReference': null,
        'notes': null,
        'slot': null,
        'timeline': [
          {'label': 'Membership created', 'actor': 'Arun Kumar', 'at': '2026-05-24T11:20:00Z'},
          {'label': 'Payment received', 'actor': 'upi', 'at': '2026-05-24T11:23:00Z'},
        ],
      });

      expect(d.displayStatus, MembershipListStatus.paymentNotInitiated);
      expect(d.member.fullName, 'Rahul Sharma');
      expect(d.membership.gstAmountInr, 540);
      expect(d.payment!.transactionId, 'UPI/4123/5598/2026');
      expect(d.referralName, 'Sneha Reddy');
      expect(d.timeline, hasLength(2));
      expect(d.timeline.first.label, 'Membership created');
    });
  });
}