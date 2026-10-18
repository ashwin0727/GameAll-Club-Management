import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/sports/sport_selection.dart';

void main() {
  lockedTests();
  const all = ['bad', 'cri', 'foo'];

  test('is All Sports by default and keeps a subset in the facility order', () {
    expect(resolveSportSelection(null, all).isAll, isTrue);
    final sub = resolveSportSelection(['cri', 'bad'], all);
    expect(sub.ids, ['bad', 'cri']);
    expect(sub.isAll, isFalse);
  });

  test('drops unknown ids, and every sport ticked is All Sports', () {
    expect(resolveSportSelection(['bad', 'gone'], all).ids, ['bad']);
    expect(resolveSportSelection(['gone'], all).isAll, isTrue);
    expect(resolveSportSelection(['foo', 'bad', 'cri'], all).isAll, isTrue);
  });

  test('toggling: untick from All, tick back to All, never leave nothing', () {
    expect(toggleSportSelection(null, all, 'foo'), ['bad', 'cri']);
    expect(toggleSportSelection(['bad', 'cri'], all, 'foo'), isNull);
    expect(toggleSportSelection(['bad'], all, 'bad'), ['bad']);
  });

  test('labels', () {
    final names = {'bad': 'Badminton', 'cri': 'Cricket', 'foo': 'Football'};
    expect(sportSelectionLabel(resolveSportSelection(null, all), names), 'All Sports');
    expect(sportSelectionLabel(resolveSportSelection(['bad'], all), names), 'Badminton');
    expect(sportSelectionLabel(resolveSportSelection(['bad', 'cri'], all), names), 'Badminton, Cricket');
    expect(sportSelectionLabel(resolveSportSelection(['bad', 'cri', 'foo'], [...all, 'ten']), names), 'Badminton +2');
  });
}

void lockedTests() {
  group('pages fixed at All Sports', () {
    test('locks Maintenance, Staff and Inventory (every page under them)', () {
      for (final p in ['/maintenance', '/maintenance/tickets', '/users-roles/staff', '/users-roles/access-history', '/inventory', '/inventory/items']) {
        expect(sportSelectionLocked(p), isTrue, reason: p);
      }
    });
    test('leaves everything else selectable', () {
      for (final p in ['/dashboard', '/coaching', '/memberships', '/maintenancex']) {
        expect(sportSelectionLocked(p), isFalse, reason: p);
      }
    });
  });
}
