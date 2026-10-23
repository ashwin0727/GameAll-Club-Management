import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/analytics.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/utils/csv_export.dart';
import '../../shared/widgets/metric_trend_chart.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import 'analytics_filter.dart';
import 'report_section_header.dart';
import 'report_shell.dart';
import '../../core/access/access.dart';

enum _Kind { money, count }

/// One of the twelve overview cards. Mirrors OVERVIEW_METRICS in
/// src/features/reports/overview-metrics.ts (same order, titles, colours).
class _Metric {
  const _Metric({
    required this.key,
    required this.title,
    required this.kind,
    required this.color,
    required this.icon,
    required this.heading,
    required this.read,
  });

  final String key;
  final String title;
  final _Kind kind;
  final Color color;
  final IconData icon;

  /// The chart heading when this card is selected.
  final String heading;
  final int Function(ReportsOverviewMetrics m) read;
}

const _financeGroup = ['REVENUE', 'EXPENSES', 'NET'];

final _metrics = <_Metric>[
  _Metric(key: 'REVENUE', title: 'Total Revenue', kind: _Kind.money, color: const Color(0xFF00D084), icon: Icons.payments_outlined, heading: 'Revenue Trend', read: (m) => m.totalRevenueMinor),
  _Metric(key: 'EXPENSES', title: 'Total Expenses', kind: _Kind.money, color: const Color(0xFFFF4D67), icon: Icons.receipt_long_outlined, heading: 'Expenses Trend', read: (m) => m.totalExpensesMinor),
  _Metric(key: 'NET', title: 'Net Revenue', kind: _Kind.money, color: const Color(0xFF6366F1), icon: Icons.account_balance_wallet_outlined, heading: 'Net Revenue Trend', read: (m) => m.netRevenueMinor),
  _Metric(key: 'GUEST_BOOKINGS', title: 'Total Guest Booking', kind: _Kind.count, color: const Color(0xFF0EA5E9), icon: Icons.event_available_outlined, heading: 'Guest Bookings', read: (m) => m.guestBookings),
  _Metric(key: 'MEMBERS', title: 'Total Members', kind: _Kind.count, color: const Color(0xFF8B5CF6), icon: Icons.workspace_premium_outlined, heading: 'New Memberships Started', read: (m) => m.members),
  _Metric(key: 'PROGRAMS', title: 'Total Program', kind: _Kind.count, color: const Color(0xFFF59E0B), icon: Icons.school_outlined, heading: 'Programs Started', read: (m) => m.programs),
  _Metric(key: 'COACHES', title: 'Total Coach', kind: _Kind.count, color: const Color(0xFF14B8A6), icon: Icons.sports_outlined, heading: 'Coaches Joined', read: (m) => m.coaches),
  _Metric(key: 'STUDENTS', title: 'Total Students', kind: _Kind.count, color: const Color(0xFFEC4899), icon: Icons.groups_outlined, heading: 'Students Enrolled', read: (m) => m.students),
  _Metric(key: 'GUEST_BOOKING_REVENUE', title: 'Guest Booking Revenue', kind: _Kind.money, color: const Color(0xFF00D084), icon: Icons.confirmation_number_outlined, heading: 'Guest Booking Revenue Trend', read: (m) => m.guestBookingRevenueMinor),
  _Metric(key: 'MEMBERSHIP_REVENUE', title: 'Membership Revenue', kind: _Kind.money, color: const Color(0xFF8B5CF6), icon: Icons.card_membership_outlined, heading: 'Membership Revenue Trend', read: (m) => m.membershipRevenueMinor),
  _Metric(key: 'COACHING_REVENUE', title: 'Coaching Revenue', kind: _Kind.money, color: const Color(0xFFF59E0B), icon: Icons.sports_score_outlined, heading: 'Coaching Revenue Trend', read: (m) => m.coachingRevenueMinor),
  _Metric(key: 'COACHING_EXPENSES', title: 'Coaching Expenses', kind: _Kind.money, color: const Color(0xFFFF4D67), icon: Icons.money_off_csred_outlined, heading: 'Coaching Expenses Trend', read: (m) => m.coachingExpensesMinor),
];

_Metric _def(String key) => _metrics.firstWhere((m) => m.key == key);

/// Reports → Overview — mirrors src/features/reports/components/reports-overview.tsx.
///
/// Twelve figures from one `get_reports_overview` call, split into three
/// groups; tapping a card draws its trend (`get_reports_overview_trend`) in
/// the card's own colour. Every number is an RPC field.
class ReportsOverviewScreen extends ConsumerStatefulWidget {
  const ReportsOverviewScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  ConsumerState<ReportsOverviewScreen> createState() => _ReportsOverviewScreenState();
}

class _ReportsOverviewScreenState extends ConsumerState<ReportsOverviewScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  ReportStatus _status = ReportStatus.loading;
  ReportsOverviewMetrics? _data;
  String _selected = 'REVENUE';
  List<OverviewTrendPoint>? _trend;
  bool _exporting = false;
  int _requestId = 0;
  final GlobalKey _chartKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Day-by-day for a short span, weekly for a few months, monthly beyond.
  String get _granularity {
    final s = _filter.startDate, e = _filter.endDate;
    if (s == null || e == null) return 'daily';
    final days = DateTime.parse(e).difference(DateTime.parse(s)).inDays + 1;
    if (days > 120) return 'monthly';
    if (days > 45) return 'weekly';
    return 'daily';
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null || !_filter.isComplete) return;
    final requestId = ++_requestId;
    setState(() {
      _status = ReportStatus.loading;
      _trend = null;
    });
    final repo = ref.read(reportsRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.getReportsOverview(facility.id, _filter),
        repo.getReportsOverviewTrend(facility.id, _filter, _selected, _granularity),
      ]);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _data = results[0] as ReportsOverviewMetrics;
        _trend = results[1] as List<OverviewTrendPoint>;
        _status = ReportStatus.ready;
      });
    } on AppException {
      if (mounted && requestId == _requestId) setState(() => _status = ReportStatus.error);
    } catch (_) {
      if (mounted && requestId == _requestId) setState(() => _status = ReportStatus.error);
    }
  }

  Future<void> _select(String key) async {
    if (key == _selected && _trend != null) return;
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    final requestId = ++_requestId;
    setState(() {
      _selected = key;
      _trend = null;
    });
    final ctx = _chartKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.1);
    }
    try {
      final points = await ref.read(reportsRepositoryProvider).getReportsOverviewTrend(facility.id, _filter, key, _granularity);
      if (!mounted || requestId != _requestId) return;
      setState(() => _trend = points);
    } catch (_) {
      if (mounted && requestId == _requestId) setState(() => _trend = const []);
    }
  }

  void _onFilterChanged(AnalyticsFilter next) {
    setState(() => _filter = next);
    _load();
  }

  Future<void> _export() async {
    final m = _data;
    if (m == null) return;
    setState(() => _exporting = true);
    try {
      String value(_Metric d) => d.kind == _Kind.money ? (d.read(m) / 100).toStringAsFixed(2) : '${d.read(m)}';
      List<Object?> line(String key) {
        final d = _def(key);
        return [d.title, d.kind == _Kind.money ? 'INR' : 'count', value(d)];
      }

      final sel = _def(_selected);
      final rows = <List<Object?>>[
        ['GameAll Reports & Analytics — Overview'],
        ['Period', '${_filter.startDate} to ${_filter.endDate}'],
        [],
        ['Metric', 'Unit', 'Value'],
        ['Finance'],
        for (final k in _financeGroup) line(k),
        ['Activity'],
        for (final k in ['GUEST_BOOKINGS', 'MEMBERS', 'PROGRAMS', 'COACHES', 'STUDENTS']) line(k),
        ['Revenue and coaching cost'],
        for (final k in ['GUEST_BOOKING_REVENUE', 'MEMBERSHIP_REVENUE', 'COACHING_REVENUE', 'COACHING_EXPENSES']) line(k),
        [],
        [sel.heading],
        ['Date', sel.kind == _Kind.money ? 'Amount (INR)' : 'Count'],
        for (final p in _trend ?? const <OverviewTrendPoint>[])
          [p.date, sel.kind == _Kind.money ? (p.value / 100).toStringAsFixed(2) : p.value],
      ];
      await saveCsv(context, fileName: 'overview_${_filter.startDate}_to_${_filter.endDate}.csv', rows: rows);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not export the report.')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _format(_Metric d, num v) => d.kind == _Kind.money ? analyticsAmount(v.round()) : '${v.round()}';

  @override
  Widget build(BuildContext context) {
    final m = _data;
    return ReportShell(
      title: 'Overview',
      status: _status,
      filter: _filter,
      onFilterChanged: _onFilterChanged,
      filterTrailing: !ref.watch(sessionControllerProvider).canEditPage(accessPageReportOverview) ? null : OutlinedButton.icon(
        onPressed: m == null || _exporting ? null : _export,
        icon: _exporting
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.ios_share_rounded, size: 18),
        label: const Text('Export'),
      ),
      onRetry: _load,
      emptyMessage: 'No activity for this period yet.',
      errorMessage: 'Unable to load analytics. Please try again.',
      loadingSkeleton: const _OverviewSkeleton(),
      body: m == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _group('Finance', _financeGroup, m),
                const SizedBox(height: AppSpacing.xl),
                _group('Activity', const ['GUEST_BOOKINGS', 'MEMBERS', 'PROGRAMS', 'COACHES', 'STUDENTS'], m),
                const SizedBox(height: AppSpacing.xl),
                _group('Revenue and coaching cost',
                    const ['GUEST_BOOKING_REVENUE', 'MEMBERSHIP_REVENUE', 'COACHING_REVENUE', 'COACHING_EXPENSES'], m),
                const SizedBox(height: AppSpacing.xl),
                KeyedSubtree(key: _chartKey, child: _chartCard()),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  Widget _group(String title, List<String> keys, ReportsOverviewMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeader(title: title),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(builder: (context, c) {
          final width = (c.maxWidth - AppSpacing.sm) / 2;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final k in keys) SizedBox(width: width, child: _card(_def(k), m)),
            ],
          );
        }),
      ],
    );
  }

  Widget _card(_Metric d, ReportsOverviewMetrics m) {
    final tokens = context.tokens;
    final selected = d.key == _selected;
    return Semantics(
      button: true,
      selected: selected,
      label: '${d.title}, ${_format(d, d.read(m))}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => _select(d.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? d.color.withValues(alpha: 0.10) : tokens.surface1,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: selected ? d.color : tokens.borderColor, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(d.icon, size: 17, color: d.color),
                  ),
                  const Spacer(),
                  if (selected) Icon(Icons.show_chart_rounded, size: 16, color: d.color),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(d.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_format(d, d.read(m)),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chartCard() {
    final tokens = context.tokens;
    final d = _def(_selected);
    final points = _trend;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: d.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(d.heading,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('Tap a card above to change the chart · drag across it to read a day',
              style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.md),
          if (points == null)
            const AppSkeleton(height: 190, radius: AppRadius.md)
          else
            MetricTrendChart(
              points: [
                for (final p in points)
                  TrendPoint(p.date, d.kind == _Kind.money ? p.value / 100 : p.value),
              ],
              color: d.color,
              formatValue: (v) => d.kind == _Kind.money ? analyticsAmount((v * 100).round()) : '${v.round()}',
            ),
        ],
      ),
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row() => const Row(
          children: [
            Expanded(child: AppSkeleton(height: 92, radius: AppRadius.lg)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: AppSkeleton(height: 92, radius: AppRadius.lg)),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSkeleton(width: 90, height: 15),
        const SizedBox(height: AppSpacing.sm),
        row(),
        const SizedBox(height: AppSpacing.sm),
        row(),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 90, height: 15),
        const SizedBox(height: AppSpacing.sm),
        row(),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(height: 220, radius: AppRadius.lg),
      ],
    );
  }
}
