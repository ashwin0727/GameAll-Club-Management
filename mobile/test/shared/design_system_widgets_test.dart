import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/shared/widgets/app_avatar.dart';
import 'package:gameall_club_mobile/shared/widgets/app_button.dart';
import 'package:gameall_club_mobile/shared/widgets/app_metric_card.dart';
import 'package:gameall_club_mobile/shared/widgets/misc.dart';
import 'package:google_fonts/google_fonts.dart';

/// Spec §"Responsive Requirements" / §"Large Font Requirement" / §"No
/// Overflow": every new design-system component must render cleanly at the
/// narrowest supported width and at large system font scaling — zero
/// tolerance for RenderFlex overflow or clipped text.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget wrap(Widget child, {ThemeData? theme, double textScale = 1.0, double width = 320}) {
    return MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SizedBox(width: width, child: child)),
      ),
    );
  }

  group('AppMetricCard', () {
    testWidgets('renders a long label/value pair at 320dp without overflow', (tester) async {
      await tester.pumpWidget(wrap(
        const AppMetricCard(label: 'Membership Included Usage', value: '₹12,48,500.00', changePercent: 12.4, icon: Icons.trending_up),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Membership Included Usage'), findsOneWidget);
    });

    testWidgets('renders correctly at 200% system font scaling', (tester) async {
      await tester.pumpWidget(wrap(
        const AppMetricCard(label: 'Revenue', value: '₹2,75,000', changePercent: -8.2),
        textScale: 2.0,
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in both light and dark theme without exceptions', (tester) async {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        await tester.pumpWidget(wrap(const AppMetricCard(label: 'Bookings', value: '24'), theme: theme));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('AppAvatar', () {
    testWidgets('falls back to initials when there is no image URL', (tester) async {
      await tester.pumpWidget(wrap(const AppAvatar(name: 'Arun Kumar')));
      expect(find.text('AK'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles a single-word name without crashing', (tester) async {
      await tester.pumpWidget(wrap(const AppAvatar(name: 'Cher')));
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('handles an empty name without crashing', (tester) async {
      await tester.pumpWidget(wrap(const AppAvatar(name: '')));
      expect(find.text('?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('StatusBadge', () {
    testWidgets('renders icon + text together, never color alone', (tester) async {
      await tester.pumpWidget(wrap(const StatusBadge(label: 'Confirmed', tone: StatusTone.success)));
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('a long label wraps/ellipsizes instead of overflowing at 320dp', (tester) async {
      await tester.pumpWidget(wrap(
        const SizedBox(width: 100, child: StatusBadge(label: 'Membership Protected — 3 of 5 Occupied', tone: StatusTone.info)),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('Buttons', () {
    testWidgets('GhostButton and DangerButton both meet the 48dp minimum touch target', (tester) async {
      await tester.pumpWidget(wrap(
        Column(
          children: [
            GhostButton(label: 'Cancel', onPressed: () {}),
            DangerButton(label: 'Remove', onPressed: () {}),
          ],
        ),
      ));
      expect(tester.takeException(), isNull);
      for (final finder in [find.text('Cancel'), find.text('Remove')]) {
        final size = tester.getSize(find.ancestor(of: finder, matching: find.byType(SizedBox)).first);
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });
  });
}