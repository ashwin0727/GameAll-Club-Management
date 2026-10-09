import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/features/memberships/members_insights.dart';

/// "View More Insights" on the Memberships → Members tab: tapping it must actually reveal the four
/// figures. (It once expanded to nothing — the tiles threw a layout error inside the expanded area.)
void main() {
  List<InsightData> tiles() => [
        InsightData(icon: Icons.groups_outlined, color: Colors.blue, title: 'Total Members', value: '186', onTap: () {}),
        InsightData(icon: Icons.schedule_rounded, color: Colors.orange, title: 'Expiring Soon', value: '18', sub: 'Next 30 days', onTap: () {}),
        InsightData(
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.purple,
            title: 'Total Revenue',
            value: '₹4,32,000',
            sub: '↑ +18%',
            onTap: () {}),
        InsightData(icon: Icons.bar_chart_rounded, color: Colors.green, title: 'Utilization', value: '76%', sub: 'Avg. slot usage', onTap: () {}),
      ];

  Widget host({required bool open, VoidCallback? onToggle, double width = 360, List<InsightData>? data}) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: InsightsPanel(open: open, onToggle: onToggle ?? () {}, tiles: data ?? tiles()),
              ),
            ),
          ),
        ),
      );

  testWidgets('collapsed: shows the title and none of the figures', (tester) async {
    await tester.pumpWidget(host(open: false));
    expect(find.text('View More Insights'), findsOneWidget);
    expect(find.text('Total Revenue'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded: shows all four figures without a layout error', (tester) async {
    await tester.pumpWidget(host(open: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final text in ['Total Members', 'Expiring Soon', 'Total Revenue', 'Utilization', '186', '18', '₹4,32,000', '76%', 'Next 30 days', 'Avg. slot usage']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('tapping the header toggles it', (tester) async {
    var open = false;
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          set = setState;
          return SingleChildScrollView(
            child: InsightsPanel(open: open, onToggle: () => set(() => open = !open), tiles: tiles()),
          );
        }),
      ),
    ));
    expect(find.text('Utilization'), findsNothing);

    await tester.tap(find.text('View More Insights'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Utilization'), findsOneWidget);
    expect(find.text('₹4,32,000'), findsOneWidget);

    await tester.tap(find.text('View More Insights'));
    await tester.pumpAndSettle();
    expect(find.text('Utilization'), findsNothing);
  });

  testWidgets('a narrow phone still lays the tiles out', (tester) async {
    await tester.pumpWidget(host(open: true, width: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Total Revenue'), findsOneWidget);
  });

  testWidgets('an odd number of tiles leaves the last row half empty rather than failing', (tester) async {
    await tester.pumpWidget(host(open: true, data: tiles().take(3).toList()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Total Revenue'), findsOneWidget);
    expect(find.text('Utilization'), findsNothing);
  });

  testWidgets('tapping a tile runs its action', (tester) async {
    var tapped = '';
    final data = [
      InsightData(icon: Icons.schedule_rounded, color: Colors.orange, title: 'Expiring Soon', value: '18', onTap: () => tapped = 'expiring'),
    ];
    await tester.pumpWidget(host(open: true, data: data));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expiring Soon'));
    expect(tapped, 'expiring');
  });
}
