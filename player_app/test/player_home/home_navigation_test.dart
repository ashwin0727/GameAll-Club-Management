import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/shell/player_pages.dart';
import 'package:gameall_player/features/shell/player_shell.dart';

class _Repo implements PlayerHomeRepository {
  _Repo(this.data);
  final PlayerHomeData data;
  @override
  Future<PlayerHomeData> load() async => data;
}

/// The phone app for real: the Home screen, and a Navigator that builds a page for every address, as main.dart does. Tapping a card must
/// open the right page, not just report a route.
Future<void> openHome(WidgetTester tester, {required bool has}) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [
      playerHomeRepositoryProvider.overrideWithValue(
        _Repo(
          PlayerHomeData(
            fullName: 'Alex',
            signedIn: true,
            unreadNotifications: 0,
            hasActiveMembership: has,
            hasActiveCoaching: has,
            hasBookingHistory: has,
            upcomingBookings: const [],
          ),
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const PlayerShell(),
        onGenerateRoute: (s) => MaterialPageRoute<void>(
          settings: s,
          builder: (_) => playerPageForRoute(s.name ?? ''),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
}

Future<void> tapCard(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  group('Home cards open real pages on a phone', () {
    testWidgets(
      'no membership, coaching or booking: each card opens its search',
      (tester) async {
        await openHome(tester, has: false);
        await tapCard(tester, 'summary-membership');
        expect(find.text('Explore Memberships'), findsWidgets);
        expect(find.byKey(const ValueKey('mm-title')), findsNothing);
        Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
        await tester.pumpAndSettle();

        await tapCard(tester, 'summary-coaching');
        expect(find.text('Find a Coach'), findsOneWidget);
        Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
        await tester.pumpAndSettle();

        await tapCard(tester, 'summary-guest');
        expect(find.text('Book a Court'), findsWidgets);
        expect(find.byKey(const ValueKey('gb-title')), findsNothing);
      },
    );

    testWidgets('enrolled and booked: each card opens the player\'s own page', (
      tester,
    ) async {
      await openHome(tester, has: true);
      await tapCard(tester, 'summary-membership');
      expect(find.byKey(const ValueKey('mm-title')), findsOneWidget);
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await tester.pumpAndSettle();

      await tapCard(tester, 'summary-coaching');
      expect(find.byKey(const ValueKey('mc-title')), findsOneWidget);
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await tester.pumpAndSettle();

      await tapCard(tester, 'summary-guest');
      expect(find.byKey(const ValueKey('gb-title')), findsOneWidget);
    });
  });
}
