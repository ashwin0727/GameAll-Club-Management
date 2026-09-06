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

/// Reports → Revenue — mirrors src/features/reports/components/revenue-report.tsx.
///
/// Trend / breakdown / method / totals are the existing Finance RPCs called
/// verbatim, so Reports revenue == Finance revenue (web spec §34). The only
/// new cuts are get_revenue_by_sport / _by_court. When a sport or court
/// filter is set the Finance figures are facility-wide, so the report shows
/// only the (scoped) by-sport / by-court cards plus a note.
class RevenueReportScreen extends ConsumerStatefulWidget {
  const RevenueReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  ConsumerState<RevenueReportScreen> createState() => _RevenueReportScreenState();
}

class _RevenueReportScreenState extends ConsumerState<RevenueReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  ReportStatus _status = ReportStatus.loading;
  RevenueSummary? _summary;
  List<RevenueTrendPoint> _trend = const [];
  ReportRevenueBreakdown? _breakdown;
  List<PaymentMethodSlice> _methods = const [];
  List<RevenueBySportRow> _bySport = const [];
  List<RevenueByCourtRow> _byCourt = const [];
  int _requestId = 0;

  bool get _scoped => _filter.isScoped;

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
      final bySport = await repo.getRevenueBySport(facility.id, _filter);
      final byCourt = await repo.getRevenueByCourt(facility.id, _filter);
      if (!mounted || requestId != _requestId) return;

      if (_scoped) {
        setState(() {
          _summary = null;
          _trend = const [];
          _breakdown = null;
          _methods = const [];
          _bySport = bySport;
          _byCourt = byCourt;
          _status = bySport.every((r) => r.revenueMinor == 0) ? ReportStatus.empty : ReportStatus.ready;
        });
        return;
      }

      final granularity = pickAnalyticsGranularity(_filter);
      final results = await Future.wait([
        repo.getRevenueSummary(facility.id, _filter),
        repo.getRevenueTrend(facility.id, _filter, granularity),
        repo.getRevenueBreakdown(facility.id, _filter),
        repo.getPaymentMethodBreakdown(facility.id, _filter),
      ]);
      if (!mounted || requestId != _requestId) return;
      final summary = results[0] as RevenueSummary;
      setState(() {
        _summary = summary;
        _trend = results[1] as List<RevenueTrendPoint>;
        _breakdown = results[2] as ReportRevenueBreakdown;
        _methods = results[3] as List<PaymentMethodSlice>;
        _bySport = bySport;
        _byCourt = byCourt;
        _status = summary.grossMinor == 0 ? ReportStatus.empty : ReportStatus.ready;
      });
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

  void _drill({String? sportId, String? courtId}) {
    context.push(
      '${AppRoutes.reportsRevenue}?${Uri(queryParameters: analyticsFilterToQuery(_filter.copyWith(facilitySportId: sportId, courtId: courtId))).query}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _breakdown;
    final sportRows = <RevenueBySportRow>[
      ..._bySport,
      if (b != null) RevenueBySportRow(facilitySportId: '__membership__', sportName: 'Memberships', revenueMinor: b.membershipMinor),
    ];

    return ReportShell(
      title: 'Revenue Report',
      status: _status,
      filter: _filter,
      onFilterChanged: _onFilterChanged,
      onRetry: _load,
      emptyMessage: 'No revenue data for this period.',
      errorMessage: 'Unable to load the revenue report. Please try again.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_scoped)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Trend and breakdown show the whole facility.',
                      style: AppTypography.caption(context)),
                  TextButton(
                    onPressed: () => _onFilterChanged(
                      _filter.copyWith(facilitySportId: null, courtId: null),
                    ),
                    child: const Text('Clear sport & court'),
                  ),
                ],
              ),
            ),
          if (!_scoped && _summary != null) ...[
            ReportKpiGrid(items: [
              ReportKpi(label: 'Total Revenue', value: analyticsAmount(_summary!.grossMinor)),
              ReportKpi(label: 'Net Revenue', value: analyticsAmount(_summary!.netMinor)),
              ReportKpi(label: 'Refunds', value: analyticsAmount(_summary!.refundsMinor)),
              ReportKpi(label: 'Expenses', value: analyticsAmount(_summary!.expensesMinor)),
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
            SectionHeader(title: 'Revenue Breakdown'),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: ReportAmountRows(rows: [
                (label: 'Guest Bookings', value: analyticsAmount(b?.guestBookingMinor ?? 0)),
                (label: 'Memberships', value: analyticsAmount(b?.membershipMinor ?? 0)),
                (label: 'Member Bookings', value: analyticsAmount(b?.memberBookingMinor ?? 0)),
                (label: 'Refunds', value: analyticsAmount(b?.refundsMinor ?? 0)),
              ]),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(title: 'Payment Methods'),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: _methods.isEmpty
                  ? Text('No payments taken in this period.', style: AppTypography.secondary(context))
                  : ReportAmountRows(rows: [
                      for (final m in _methods) (label: m.method, value: analyticsAmount(m.amountMinor)),
                    ]),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          SectionHeader(title: 'Revenue by Sport'),
          const SizedBox(height: AppSpacing.sm),
          AppCard(child: _bySportBody(sportRows)),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: 'Revenue by Court'),
          const SizedBox(height: AppSpacing.sm),
          AppCard(child: _byCourtBody()),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _bySportBody(List<RevenueBySportRow> sportRows) {
    final live = sportRows.where((r) => r.revenueMinor > 0).toList();
    if (live.isEmpty) {
      return Text('No sport revenue in this period.', style: AppTypography.secondary(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(
          items: [
            for (final r in live)
              ReportBar(label: r.sportName, value: r.revenueMinor, caption: analyticsAmount(r.revenueMinor)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Revenue by sport',
          columns: const [ReportColumn(label: 'Sport'), ReportColumn(label: 'Revenue', numeric: true)],
          rows: [for (final r in sportRows) [r.sportName, analyticsAmount(r.revenueMinor)]],
          onTapRow: (i) {
            final row = sportRows[i];
            if (row.facilitySportId == '__membership__') return;
            _drill(sportId: row.facilitySportId);
          },
        ),
      ],
    );
  }

  Widget _byCourtBody() {
    final live = _byCourt.where((r) => r.revenueMinor > 0).toList();
    if (live.isEmpty) {
      return Text('No court revenue in this period.', style: AppTypography.secondary(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(
          items: [
            for (final r in live)
              ReportBar(label: r.courtName, value: r.revenueMinor, caption: analyticsAmount(r.revenueMinor)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Revenue by court',
          columns: const [ReportColumn(label: 'Court'), ReportColumn(label: 'Revenue', numeric: true)],
          rows: [for (final r in _byCourt) [r.courtName, analyticsAmount(r.revenueMinor)]],
          onTapRow: (i) => _drill(courtId: _byCourt[i].courtId),
        ),
      ],
    );
  }
}
