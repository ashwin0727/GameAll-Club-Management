import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/analytics.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../authentication/session_controller.dart';
import '../finance/revenue_trend_chart.dart';
import 'analytics_filter.dart';
import 'report_shell.dart';
import 'report_widgets.dart';

/// Reports → Overview — mirrors src/features/reports/components/reports-overview.tsx.
///
/// One `get_analytics_overview` round trip for the headline numbers (it
/// composes the other analytics RPCs server-side), plus the revenue trend,
/// top courts and peak hours reused from their own reports. Every figure is
/// an RPC response field — nothing is derived here except the comparison
/// percentage, computed from two fetched totals.
class ReportsOverviewScreen extends ConsumerStatefulWidget {
  const ReportsOverviewScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  ConsumerState<ReportsOverviewScreen> createState() => _ReportsOverviewScreenState();
}

class _ReportsOverviewScreenState extends ConsumerState<ReportsOverviewScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  ReportStatus _status = ReportStatus.loading;
  AnalyticsOverview? _overview;
  AnalyticsOverview? _previous;
  List<RevenueTrendPoint> _trend = const [];
  List<CourtUtilizationRow> _courts = const [];
  List<PeakHourRow> _peak = const [];
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null || !_filter.isComplete) return;
    final requestId = ++_requestId;
    setState(() => _status = ReportStatus.loading);

    final repo = ref.read(reportsRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.getAnalyticsOverview(facility.id, _filter),
        repo.getRevenueTrend(facility.id, _filter, pickAnalyticsGranularity(_filter)),
        repo.getCourtUtilization(facility.id, _filter),
        repo.getPeakHours(facility.id, _filter),
      ]);
      if (!mounted || requestId != _requestId) return;

      final overview = results[0] as AnalyticsOverview;
      setState(() {
        _overview = overview;
        _trend = results[1] as List<RevenueTrendPoint>;
        _courts = results[2] as List<CourtUtilizationRow>;
        _peak = results[3] as List<PeakHourRow>;
        _status = overview.grossRevenueMinor == 0 && overview.totalBookings == 0
            ? ReportStatus.empty
            : ReportStatus.ready;
      });

      final prevFilter = previousAnalyticsPeriod(_filter);
      if (prevFilter != null) {
        try {
          final prev = await repo.getAnalyticsOverview(facility.id, prevFilter);
          if (mounted && requestId == _requestId) setState(() => _previous = prev);
        } catch (_) {
          if (mounted && requestId == _requestId) setState(() => _previous = null);
        }
      } else if (mounted && requestId == _requestId) {
        setState(() => _previous = null);
      }
    } on AppException {
      if (mounted && requestId == _requestId) setState(() => _status = ReportStatus.error);
    } catch (_) {
      if (mounted && requestId == _requestId) setState(() => _status = ReportStatus.error);
    }
  }

  void _onFilterChanged(AnalyticsFilter next) {
    setState(() => _filter = next);
    _load();
  }

  String _reportHref(String path) => '$path?${Uri(queryParameters: analyticsFilterToQuery(_filter)).query}';

  double? _pct(num Function(AnalyticsOverview) pick) {
    final o = _overview, p = _previous;
    if (o == null || p == null) return null;
    return analyticsChangePct(current: pick(o), previous: pick(p));
  }

  @override
  Widget build(BuildContext context) {
    final o = _overview;
    return ReportShell(
      title: 'Reports & Analytics',
      status: _status,
      filter: _filter,
      onFilterChanged: _onFilterChanged,
      onRetry: _load,
      emptyMessage: 'No activity for this period yet.',
      errorMessage: 'Unable to load analytics. Please try again.',
      body: o == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReportKpiGrid(items: [
                  ReportKpi(
                    label: 'Total Revenue',
                    value: analyticsAmount(o.grossRevenueMinor),
                    pct: _pct((x) => x.grossRevenueMinor),
                    onTap: () => context.push(_reportHref(AppRoutes.reportsRevenue)),
                  ),
                  ReportKpi(
                    label: 'Net Revenue',
                    value: analyticsAmount(o.netRevenueMinor),
                    pct: _pct((x) => x.netRevenueMinor),
                    onTap: () => context.push(_reportHref(AppRoutes.reportsRevenue)),
                  ),
                  ReportKpi(
                    label: 'Total Expenses',
                    value: analyticsAmount(o.expensesMinor),
                    pct: _pct((x) => x.expensesMinor),
                    invert: true,
                    onTap: () => context.push(AppRoutes.financeExpenses),
                  ),
                  ReportKpi(
                    label: 'Total Bookings',
                    value: o.totalBookings.toString(),
                    pct: _pct((x) => x.totalBookings),
                    onTap: () => context.push(_reportHref(AppRoutes.reportsBookings)),
                  ),
                  ReportKpi(
                    label: 'Court Utilization',
                    value: '${o.overallUtilizationPct.round()}%',
                    pct: _pct((x) => x.overallUtilizationPct),
                    onTap: () => context.push(_reportHref(AppRoutes.reportsCourtUtilization)),
                  ),
                  ReportKpi(
                    label: 'Outstanding Payments',
                    value: analyticsAmount(o.outstandingMinor),
                    pct: _pct((x) => x.outstandingMinor),
                    invert: true,
                    onTap: () => context.push(AppRoutes.financePendingPayments),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                ReportKpiGrid(items: [
                  ReportKpi(label: 'Booking Revenue', value: analyticsAmount(o.bookingRevenueMinor)),
                  ReportKpi(label: 'Membership Revenue', value: analyticsAmount(o.membershipRevenueMinor)),
                  ReportKpi(label: 'Completed Bookings', value: o.completedBookings.toString()),
                  ReportKpi(label: 'Cancelled Bookings', value: o.cancelledBookings.toString()),
                ]),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Revenue Trend'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: _trend.isEmpty
                      ? Text('No revenue in this period yet.', style: AppTypography.secondary(context))
                      : RevenueTrendChart(points: _trend),
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(
                  title: 'Top Courts',
                  trailing: TextButton(
                    onPressed: () => context.push(_reportHref(AppRoutes.reportsCourtUtilization)),
                    child: const Text('View all'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _topCourts()),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(
                  title: 'Peak Hours',
                  trailing: TextButton(
                    onPressed: () => context.push(_reportHref(AppRoutes.reportsCourtUtilization)),
                    child: const Text('View all'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _peakHours()),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  Widget _topCourts() {
    if (_courts.isEmpty) {
      return Text('No court activity yet.', style: AppTypography.secondary(context));
    }
    final top = [..._courts]..sort((a, b) => b.utilizationPct.compareTo(a.utilizationPct));
    final rows = top.take(5).toList();
    return ReportDataTable(
      caption: 'Top courts by utilization',
      columns: const [ReportColumn(label: 'Court'), ReportColumn(label: 'Utilization', numeric: true)],
      rows: [
        for (final c in rows) [c.courtName, '${c.utilizationPct.toStringAsFixed(1)}%'],
      ],
      onTapRow: (i) => context.push(
        '${AppRoutes.reportsCourtUtilization}?${Uri(queryParameters: analyticsFilterToQuery(_filter.copyWith(courtId: rows[i].courtId, facilitySportId: null))).query}',
      ),
    );
  }

  Widget _peakHours() {
    if (_peak.isEmpty) {
      return Text('No booking activity in this period.', style: AppTypography.secondary(context));
    }
    final top = [..._peak]..sort((a, b) => b.demandPct.compareTo(a.demandPct));
    return ReportBarList(
      max: 100,
      items: [
        for (final h in top.take(6))
          ReportBar(
            label: formatHourLabel(h.hour),
            value: h.demandPct,
            caption: '${h.demandPct.toStringAsFixed(1)}%',
          ),
      ],
    );
  }
}
