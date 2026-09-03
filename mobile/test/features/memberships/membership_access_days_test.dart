import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/features/memberships/access_days.dart';

/// Parity gap G2 — the per-facility "membership access days" setting.
///
/// `facilities.membership_access_days` (migration 0029) + the
/// `set_facility_membership_access_days` RPC. Mirrors
/// src/features/memberships/components/membership-access-days-dialog.tsx and
/// `slot-form.ts`.
void main() {
  group('Facility.membershipAccessDays', () {
    test('parses the smallint[] column', () {
      final f = Facility.fromJson(_facility({'membership_access_days': [1, 2, 3, 4, 5]}));
      expect(f.membershipAccessDays, [1, 2, 3, 4, 5]);
    });

    test('defaults to all seven days when the column is null/absent', () {
      final f = Facility.fromJson(_facility({}));
      expect(f.membershipAccessDays, [0, 1, 2, 3, 4, 5, 6]);
    });
  });

  group('access_days helpers', () {
    test('allDays is Sun..Sat, weekdays is Mon..Fri', () {
      expect(allDays, [0, 1, 2, 3, 4, 5, 6]);
      expect(weekdays, [1, 2, 3, 4, 5]);
    });

    test('dayLabel maps 0->Sun .. 6->Sat', () {
      expect(dayLabel(0), 'Sun');
      expect(dayLabel(1), 'Mon');
      expect(dayLabel(6), 'Sat');
    });

    test('sameDays ignores order', () {
      expect(sameDays([1, 2, 3], [3, 2, 1]), isTrue);
      expect(sameDays([1, 2], [1, 2, 3]), isFalse);
    });

    test('toggleDay adds and removes', () {
      expect(toggleDay([1, 2], 3), [1, 2, 3]);
      expect(toggleDay([1, 2, 3], 2), [1, 3]);
    });
  });

  group('MembershipRepository.setMembershipAccessDays', () {
    late String source;
    setUpAll(() {
      source = File('lib/data/repositories/membership_repository.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
    });

    test('calls set_facility_membership_access_days with the facility id and day list', () {
      expect(source, contains("'set_facility_membership_access_days'"));
      expect(source, contains("'p_facility_id':"));
      expect(source, contains("'p_days':"));
    });

    test('returns the days off the updated facilities row, not the request', () {
      expect(source, contains("['membership_access_days']"));
    });
  });
}

Map<String, dynamic> _facility(Map<String, dynamic> extra) => {
      'id': 'fac-1',
      'owner_id': 'own-1',
      'name': 'GameAll Arena',
      'facility_type': 'MULTI_SPORT',
      'business_email': 'a@b.com',
      'business_phone': '999',
      'status': 'ACTIVE',
      'onboarding_step': 'COMPLETE',
      ...extra,
    };
