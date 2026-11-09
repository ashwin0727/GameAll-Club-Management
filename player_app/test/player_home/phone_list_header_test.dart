import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/features/venues/application/venues_providers.dart';
import 'package:gameall_player/features/venues/presentation/phone_list_header.dart';

void main() {
  group('nearest first', () {
    final km = {'a': 12.0, 'b': 0.8, 'c': 3.5};

    test('orders by distance; venues with no position come last, in order', () {
      final ids = ['x', 'a', 'y', 'b', 'c'];
      expect(sortNearestFirst(ids, (s) => s, km), ['b', 'c', 'a', 'x', 'y']);
    });

    test('with no distances the list is left as it is', () {
      final ids = ['x', 'a', 'b'];
      expect(sortNearestFirst(ids, (s) => s, const {}), ids);
    });

    test('equal distances keep their order', () {
      expect(
        sortNearestFirst(['p', 'q'], (s) => s, {'p': 2.0, 'q': 2.0}),
        ['p', 'q'],
      );
    });

    test('distance reads as a person would say it', () {
      expect(distanceLabel(0.84), '850 m');
      expect(distanceLabel(2.43), '2.4 km');
      expect(distanceLabel(37.4), '37 km');
    });
  });

  group('phone header pieces', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.4),
            ),
            child: Scaffold(
              body: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          )),
        ),
      );
    }

    testWidgets('tapping a sport selects it at once; again clears it', (
      tester,
    ) async {
      String? picked = 'unset';
      await pump(
        tester,
        SportChipsRow(
          sports: const ['Badminton', 'Cricket', 'Football', 'Tennis'],
          selected: null,
          onSelect: (s) => picked = s,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('sport-chip-Cricket')));
      expect(picked, 'Cricket');
      await tester.tap(find.byKey(const ValueKey('sport-chip-all')));
      expect(picked, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chosen sport taps back to All', (tester) async {
      String? picked = 'unset';
      await pump(
        tester,
        SportChipsRow(
          sports: const ['Badminton', 'Cricket'],
          selected: 'cricket',
          onSelect: (s) => picked = s,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('sport-chip-Cricket')));
      expect(picked, isNull);
    });

    testWidgets('the title line keeps the location icon at its right end', (
      tester,
    ) async {
      await pump(tester, const PhoneTitleRow(title: 'Explore Memberships'));
      final title = tester.getRect(find.byKey(const ValueKey('phone-title')));
      final icon = tester.getRect(find.byKey(const ValueKey('discover-city')));
      expect(icon.right, greaterThan(title.right));
      expect(icon.overlaps(title), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the search box is small', (tester) async {
      await pump(
        tester,
        CompactSearchField(
          controller: TextEditingController(),
          hint: 'Search',
          onChanged: (_) {},
          onSearch: () {},
        ),
      );
      final box = tester.getSize(find.byType(CompactSearchField));
      expect(box.height, lessThanOrEqualTo(44));
    });
  });
}
