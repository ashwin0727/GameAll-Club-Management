import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/repositories/session_repository.dart';

void main() {
  const facility = {
    'id': 'f1',
    'name': 'Smash Arena',
    'owner_id': 'u1',
    'created_at': '2026-10-01T00:00:00Z',
    'timezone': 'Asia/Kolkata',
    'currency': 'INR',
    'onboarding_step': 'COMPLETED',
    'status': 'ACTIVE',
    'facility_type': 'BADMINTON',
  };

  test('parses a full bundle for an owner on a trial', () {
    final b = SessionBundle.fromJson({
      'profile': {'id': 'u1', 'full_name': 'Olivia', 'email': 'o@x.com', 'role': 'admin', 'onboarding_completed': true},
      'facility': facility,
      'baseRole': 'owner',
      'permissions': ['HOME_VIEW', 'FINANCE_VIEW'],
      'plan': {
        'planCode': 'advanced',
        'effectiveCode': 'advanced',
        'name': 'Advanced',
        'status': 'trialing',
        'interval': 'month',
        'priceMinor': 19900,
        'validTill': '2027-01-25',
        'onTrial': true,
        'lapsed': false,
        'daysLeft': 88,
        'features': ['AUTOPAY', 'PLAYER_MEMBERSHIPS'],
        'pageKeys': ['HOME', 'FINANCE_OVERVIEW'],
      },
      'isPlatformAdmin': false,
    });
    expect(b.profile?['full_name'], 'Olivia');
    expect(b.facility?.id, 'f1');
    expect(b.baseRole, 'owner');
    expect(b.permissions, {'HOME_VIEW', 'FINANCE_VIEW'});
    expect(b.plan?.onTrial, isTrue);
    expect(b.plan?.hasFeature('AUTOPAY'), isTrue);
    expect(b.plan?.includesPage('FINANCE_OVERVIEW'), isTrue);
    expect(b.isPlatformAdmin, isFalse);
  });

  test('a person with no facility and no plan', () {
    final b = SessionBundle.fromJson({
      'profile': {'id': 'u2', 'full_name': 'Lone'},
      'facility': null,
      'baseRole': null,
      'permissions': <String>[],
      'plan': null,
      'isPlatformAdmin': false,
    });
    expect(b.facility, isNull);
    expect(b.baseRole, isNull);
    expect(b.permissions, isEmpty);
    expect(b.plan, isNull);
  });

  test('a missing profile row comes through as null so the caller can look it up the long way', () {
    final b = SessionBundle.fromJson({'profile': null, 'facility': facility, 'baseRole': 'staff', 'permissions': ['HOME_VIEW'], 'plan': null, 'isPlatformAdmin': false});
    expect(b.profile, isNull);
    expect(b.baseRole, 'staff');
  });
}
