import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/core/access/access.dart';

void main() {
  AccessPage page(String k) => accessPageFor(k)!;

  test('owners are Edit everywhere; a role with no keys is None everywhere', () {
    for (final p in accessPages) {
      expect(accessLevelFor(p, {}, isOwner: true), AccessLevel.edit);
      expect(accessLevelFor(p, {}, isOwner: false), AccessLevel.none);
    }
  });

  test('View keys give View, any Edit key gives Edit, no View key hides the page', () {
    final g = page(accessPageGuestBookings);
    expect(accessLevelFor(g, {'GUEST_BOOKINGS_VIEW'}, isOwner: false), AccessLevel.view);
    expect(accessLevelFor(g, {'GUEST_BOOKINGS_VIEW', 'GUEST_BOOKINGS_CREATE'}, isOwner: false), AccessLevel.edit);
    expect(accessLevelFor(g, {'GUEST_BOOKINGS_CREATE'}, isOwner: false), AccessLevel.none);
    expect(accessLevelFor(page(accessPageHome), {'DASHBOARD_VIEW'}, isOwner: false), AccessLevel.view);
  });

  test('a half-edit role reads as custom in the editor', () {
    final c = page(accessPageCalendar);
    final base = {'BOOKINGS_VIEW', 'COURTS_VIEW'};
    expect(editorLevelFor(c, base), EditorLevel.view);
    expect(editorLevelFor(c, {...base, 'BOOKINGS_CREATE'}), EditorLevel.custom);
    expect(editorLevelFor(c, {...base, ...c.editKeys}), EditorLevel.edit);
  });

  test('withPageLevel rewrites only that page and keeps unmanaged keys', () {
    final start = {'INVENTORY_VIEW', 'DASHBOARD_VIEW'};
    final next = withPageLevel(start, page(accessPageCalendar), AccessLevel.edit);
    expect(next, containsAll(['INVENTORY_VIEW', 'DASHBOARD_VIEW', 'BOOKINGS_VIEW', 'BOOKINGS_CANCEL']));
    final cleared = withPageLevel(next, page(accessPageCalendar), AccessLevel.none);
    expect(cleared, {'INVENTORY_VIEW', 'DASHBOARD_VIEW'});
  });

  test('each screen maps to its own page; create / edit screens need Edit; profile screens stay open', () {
    expect(accessPageForPath('/dashboard'), (page: accessPageHome, needsEdit: false));
    expect(accessPageForPath('/memberships/schedule')?.page, accessPageMembershipSchedule);
    expect(accessPageForPath('/memberships/plans/new'), (page: accessPageMembershipPlans, needsEdit: true));
    expect(accessPageForPath('/memberships')?.page, accessPageMembershipDashboard);
    expect(accessPageForPath('/coaching/sessions/new'), (page: accessPageCoachingSessions, needsEdit: true));
    expect(accessPageForPath('/users-roles/roles/abc/edit'), (page: accessPageRoles, needsEdit: true));
    expect(accessPageForPath('/profile'), isNull);
    expect(accessPageForPath('/profile/hub/personal'), isNull);
    expect(accessPageForPath('/profile/hub/payments')?.page, accessPageFacilitySettings);
  });
}
