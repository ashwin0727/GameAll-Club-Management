import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gameall_club_mobile/features/tournaments/tournament_app_config.dart';
import 'package:gameall_club_mobile/features/tournaments/tournament_app_launcher.dart';
import 'package:gameall_club_mobile/features/tournaments/tournament_app_preview.dart';
import 'package:gameall_club_mobile/features/tournaments/tournament_management_screen.dart';

void main() {
  group('TournamentAppConfig', () {
    test('nothing configured → no links, no CTAs', () {
      const c = TournamentAppConfig();
      expect(c.openUrl, isNull);
      expect(c.downloadUrl, isNull);
      expect(c.hasStores, isFalse);
      expect(c.availabilityLabel, isNull);
    });

    test('openUrl prefers deep link, then web, then stores', () {
      expect(
        const TournamentAppConfig(deepLink: 'app://x', webUrl: 'https://w', androidStoreUrl: 'https://p').openUrl,
        'app://x',
      );
      expect(const TournamentAppConfig(webUrl: 'https://w', iosStoreUrl: 'https://i').openUrl, 'https://w');
      expect(const TournamentAppConfig(iosStoreUrl: 'https://i').openUrl, 'https://i');
    });

    test('availabilityLabel reflects the store links present', () {
      expect(
        const TournamentAppConfig(androidStoreUrl: 'a', iosStoreUrl: 'i').availabilityLabel,
        'Available on Android and iOS',
      );
      expect(const TournamentAppConfig(androidStoreUrl: 'a').availabilityLabel, 'Available on Android');
      expect(const TournamentAppConfig(iosStoreUrl: 'i').availabilityLabel, 'Available on iOS');
    });
  });

  group('TournamentAppLauncher', () {
    test('returns notConfigured for a null/empty url without calling the launcher', () async {
      var called = false;
      final l = TournamentAppLauncher(launcher: (uri, {mode = LaunchMode.platformDefault}) async {
        called = true;
        return true;
      });
      expect(await l.open(null), TournamentLaunchResult.notConfigured);
      expect(await l.open('   '), TournamentLaunchResult.notConfigured);
      expect(called, isFalse);
    });

    test('opened when the launcher succeeds, failed when it returns false or throws', () async {
      final ok = TournamentAppLauncher(launcher: (uri, {mode = LaunchMode.platformDefault}) async => true);
      expect(await ok.open('https://x'), TournamentLaunchResult.opened);

      final no = TournamentAppLauncher(launcher: (uri, {mode = LaunchMode.platformDefault}) async => false);
      expect(await no.open('https://x'), TournamentLaunchResult.failed);

      final boom = TournamentAppLauncher(launcher: (uri, {mode = LaunchMode.platformDefault}) async => throw Exception('x'));
      expect(await boom.open('https://x'), TournamentLaunchResult.failed);
    });
  });

  group('TournamentManagementScreen', () {
    // disableAnimations also switches the preview's autoplay timer off, so the
    // screen tests don't leave a periodic Timer pending.
    Widget wrap(Widget child) => MaterialApp(
          home: child,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: c!,
          ),
        );

    // The screen is a long scroller; give the test surface room so every
    // section is laid out without needing to drive scroll for each assertion.
    setUp(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(1200, 6000);
      view.devicePixelRatio = 1.0;
    });
    tearDown(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('renders the handoff content: eyebrow, heading, feature + why sections', (tester) async {
      await tester.pumpWidget(wrap(const TournamentManagementScreen()));
      await tester.pump();

      expect(find.text('POWERED BY GAMEALL'), findsOneWidget);
      expect(find.textContaining('Bigger Tournaments.'), findsOneWidget);
      expect(find.text('Everything You Need for Tournament Success'), findsOneWidget);
      expect(find.text('Why a separate application?'), findsOneWidget);
      expect(find.text('Already have the app?'), findsOneWidget);
      expect(find.text('Create & Manage Tournaments'), findsOneWidget);
    });

    testWidgets('with no config → shows the not-configured note, no Open button', (tester) async {
      await tester.pumpWidget(wrap(const TournamentManagementScreen()));
      await tester.pump();

      expect(find.textContaining("aren't configured yet"), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Open Tournament App'), findsNothing);
    });

    testWidgets('with an open url → tapping Open Tournament App invokes the launcher', (tester) async {
      var openedWith = '';
      final launcher = TournamentAppLauncher(launcher: (uri, {mode = LaunchMode.platformDefault}) async {
        openedWith = uri.toString();
        return true;
      });
      await tester.pumpWidget(wrap(TournamentManagementScreen(
        config: const TournamentAppConfig(webUrl: 'https://tournament.example'),
        launcher: launcher,
      )));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Open Tournament App').first);
      await tester.pump();
      expect(openedWith, 'https://tournament.example');
    });

    testWidgets('shows the error card when the launch fails', (tester) async {
      final launcher = TournamentAppLauncher(launcher: (uri, {mode = LaunchMode.platformDefault}) async => false);
      await tester.pumpWidget(wrap(TournamentManagementScreen(
        config: const TournamentAppConfig(webUrl: 'https://x', androidStoreUrl: 'https://play'),
        launcher: launcher,
      )));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Open Tournament App').first);
      await tester.pump();
      expect(find.text("We couldn't open the Tournament App."), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });
  });

  group('TournamentAppPreview', () {
    testWidgets('empty previews → labelled placeholder, no Image', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TournamentAppPreview(previews: [], autoplay: false))),
      );
      await tester.pump();
      expect(find.text('App preview coming soon'), findsOneWidget);
    });

    testWidgets('multiple previews → one image at a time with dot controls', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TournamentAppPreview(autoplay: false, previews: [
            TournamentPreview('assets/images/a.png', 'Organizer home'),
            TournamentPreview('assets/images/b.png', 'Tournament hub'),
          ]),
        ),
      ));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.bySemanticsLabel('Show Tournament hub'), findsOneWidget);
    });
  });
}
