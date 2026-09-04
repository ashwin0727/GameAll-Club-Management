import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/data/models/analytics.dart';
import 'package:gameall_club_mobile/features/reports/count_trend_chart.dart';
import 'package:gameall_club_mobile/features/reports/heatmap.dart';
import 'package:gameall_club_mobile/features/reports/report_widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Reports & Analytics — Phase 9.1/9.2 shared widgets. Same bar as the rest
/// of the design system: clean at 320dp and at 200% font scaling, and — for
/// the KPI delta — colour is never the only signal (spec §54).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget wrap(Widget child, {double textScale = 1.0, double width = 320}) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: width, child: child))),
      ),
    );
  }

  group('ReportBarList', () {
    testWidgets('renders a labelled row per item, no overflow at 320dp', (tester) async {
      await tester.pumpWidget(wrap(const ReportBarList(items: [
        ReportBar(label: 'Badminton', value: 120),
        ReportBar(label: 'Football', value: 60, caption: '60 · ₹30,000'),
      ])));
      expect(tester.takeException(), isNull);
      expect(find.text('Badminton'), findsOneWidget);
      expect(find.text('60 · ₹30,000'), findsOneWidget);
    });

    testWidgets('sizes bars relative to the largest value', (tester) async {
      await tester.pumpWidget(wrap(const ReportBarList(items: [
        ReportBar(label: 'A', value: 100),
        ReportBar(label: 'B', value: 25),
      ])));
      final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
      expect(bars[0].value, 1.0);
      expect(bars[1].value, 0.25);
    });

    testWidgets('survives 200% font scaling', (tester) async {
      await tester.pumpWidget(wrap(
        const ReportBarList(items: [ReportBar(label: 'Membership · Corporate Annual', value: 8)]),
        textScale: 2.0,
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('ReportKpiGrid', () {
    testWidgets('renders each KPI with its value and a delta', (tester) async {
      await tester.pumpWidget(wrap(const ReportKpiGrid(items: [
        ReportKpi(label: 'Total Revenue', value: '₹1,20,000', pct: 12.4),
        ReportKpi(label: 'Expenses', value: '₹35,000', pct: 8.0, invert: true),
        ReportKpi(label: 'Bookings', value: '205'),
      ])));
      expect(tester.takeException(), isNull);
      expect(find.text('Total Revenue'), findsOneWidget);
      expect(find.text('205'), findsOneWidget);
      // delta shows a % figure as text, not colour alone
      expect(find.textContaining('12'), findsWidgets);
      expect(find.text('vs last period'), findsOneWidget); // the KPI with no pct
    });
  });

  group('CountTrendChart', () {
    testWidgets('renders the empty message with no points', (tester) async {
      await tester.pumpWidget(wrap(const CountTrendChart(points: [], emptyMessage: 'No bookings in this period.')));
      expect(tester.takeException(), isNull);
      expect(find.text('No bookings in this period.'), findsOneWidget);
    });

    testWidgets('paints a chart + axis labels for real points, no overflow', (tester) async {
      await tester.pumpWidget(wrap(const CountTrendChart(points: [
        CountTrendPoint(date: '2026-09-01', value: 8),
        CountTrendPoint(date: '2026-09-02', value: 5),
        CountTrendPoint(date: '2026-09-03', value: 12),
      ])));
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('1 Sep'), findsOneWidget);
      expect(find.text('12'), findsOneWidget); // peak label
    });
  });

  group('ReportAmountRows', () {
    testWidgets('renders each label + value pair', (tester) async {
      await tester.pumpWidget(wrap(const ReportAmountRows(rows: [
        (label: 'Guest Bookings', value: '₹45,000'),
        (label: 'Memberships', value: '₹60,000'),
      ])));
      expect(tester.takeException(), isNull);
      expect(find.text('Guest Bookings'), findsOneWidget);
      expect(find.text('₹60,000'), findsOneWidget);
    });
  });

  group('Heatmap', () {
    testWidgets('shows the empty message with no cells', (tester) async {
      await tester.pumpWidget(wrap(const Heatmap(cells: [])));
      expect(tester.takeException(), isNull);
      expect(find.text('No demand data for this period.'), findsOneWidget);
    });

    testWidgets('prints the demand percentage as a number, not colour alone', (tester) async {
      await tester.pumpWidget(wrap(const Heatmap(cells: [
        HeatmapCell(dow: 1, hour: 18, openMinutes: 60, bookedMinutes: 54, demandPct: 90),
        HeatmapCell(dow: 2, hour: 18, openMinutes: 60, bookedMinutes: 30, demandPct: 50),
      ])));
      expect(tester.takeException(), isNull);
      expect(find.text('90'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('6p'), findsOneWidget); // hour column header
    });
  });

  group('ReportDataTable', () {
    testWidgets('renders headers + rows and scrolls horizontally', (tester) async {
      await tester.pumpWidget(wrap(const ReportDataTable(
        caption: 'Bookings by sport',
        columns: [ReportColumn(label: 'Sport'), ReportColumn(label: 'Bookings', numeric: true)],
        rows: [
          ['Badminton', '120'],
          ['Football', '60'],
        ],
      )));
      expect(tester.takeException(), isNull);
      expect(find.text('Sport'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
    });
  });
}
