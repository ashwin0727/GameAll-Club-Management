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
import 'analytics_filter.dart';
import 'count_trend_chart.dart';
import 'report_shell.dart';
import 'report_widgets.dart';

/// Reports → Bookings — mirrors src/features/reports/components/booking-report.tsx.
///
/// Status counts + guest/member split from `get_booking_analytics`, volume
/// over time from `get_booking_trend` (zero-filled, granularity-aware), and
/// demand by sport from `get_bookings_by_sport`. Every figure is an RPC
/// field; the only client arithmetic is the vs-previous-period percentage.
class BookingReportScreen extends ConsumerStatefulWidget {
  const BookingReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  ConsumerState<BookingReportScreen> createState() => _BookingReportScreenState();
}

class _BookingReportScreenState extends ConsumerState<BookingReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  ReportStatus _status = ReportStatus.loading;
  BookingAnalytics? _analytics;
  BookingAnalytics? _previous;
  List<BookingTrendPoint> _trend = const [];
  List<BookingsBySportRow> _bySport = const [];
  List<BookingSourceRow> _sourceSplit = const [];
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
        repo.getBookingAnalytics(facility.id, _filter),
        repo.getBookingTrend(facility.id, _filter, pickAnalyticsGranularity(_filter)),
        repo.getBookingsBySport(facility.id, _filter),
        repo.getBookingSourceSplit(facility.id, _filter),
      ]);
      if (!mounted || requestId != _requestId) return;

      final analytics = results[0] as BookingAnalytics;
      setState(() {
        _analytics = analytics;
        _trend = results[1] as List<BookingTrendPoint>;
        _bySport = results[2] as List<BookingsBySportRow>;
        _sourceSplit = results[3] as List<BookingSourceRow>;
        _status = analytics.total == 0 ? ReportStatus.empty : ReportStatus.ready;
      });

      final prevFilter = previousAnalyticsPeriod(_filter);
      if (prevFilter != null) {
        try {
          final prev = await repo.getBookingAnalytics(facility.id, prevFilter);
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

  double? _pct(num Function(BookingAnalytics) pick) {
    final a = _analytics, p = _previous;
    if (a == null || p == null) return null;
    return analyticsChangePct(current: pick(a), previous: pick(p));
  }

  void _drillToSport(String facilitySportId) {
    context.push(
      '${AppRoutes.reportsBookings}?${Uri(queryParameters: analyticsFilterToQuery(_filter.copyWith(facilitySportId: facilitySportId, courtId: null))).query}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _analytics;
    return ReportShell(
      title: 'Booking Report',
      status: _status,
      filter: _filter,
      onFilterChanged: _onFilterChanged,
      onRetry: _load,
      emptyMessage: 'No booking data for this period.',
      errorMessage: 'Unable to load the booking report. Please try again.',
      body: a == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReportKpiGrid(items: [
                  ReportKpi(
                    label: 'Total Bookings',
                    value: a.total.toString(),
                    pct: _pct((x) => x.total),
                  ),
                  ReportKpi(
                    label: 'Completed',
                    value: a.completed.toString(),
                    pct: _pct((x) => x.completed),
                  ),
                  ReportKpi(label: 'Confirmed', value: a.confirmed.toString()),
                  ReportKpi(label: 'Pending', value: a.pending.toString()),
                  ReportKpi(
                    label: 'Cancelled',
                    value: a.cancelled.toString(),
                    pct: _pct((x) => x.cancelled),
                    invert: true,
                  ),
                  ReportKpi(label: 'Avg Guest Booking', value: analyticsAmount(a.avgGuestBookingValueMinor)),
                ]),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Bookings Over Time'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CountTrendChart(
                        points: [for (final p in _trend) CountTrendPoint(date: p.date, value: p.total)],
                        emptyMessage: 'No bookings in this period.',
                      ),
                      if (_trend.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        ReportDataTable(
                          caption: 'Bookings over time',
                          columns: const [
                            ReportColumn(label: 'Date'),
                            ReportColumn(label: 'Total', numeric: true),
                            ReportColumn(label: 'Completed', numeric: true),
                            ReportColumn(label: 'Cancelled', numeric: true),
                          ],
                          rows: [
                            for (final p in _trend)
                              [
                                reportDateShort(p.date),
                                p.total.toString(),
                                p.completed.toString(),
                                p.cancelled.toString(),
                              ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Bookings by Sport'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _bySportBody()),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Booking Source'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _sourceBody()),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  Widget _bySportBody() {
    final rows = _bySport.where((r) => r.bookingCount > 0).toList();
    if (rows.isEmpty) {
      return Text('No sports configured.', style: AppTypography.secondary(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(items: [for (final r in rows) ReportBar(label: r.sportName, value: r.bookingCount)]),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Bookings by sport',
          columns: const [ReportColumn(label: 'Sport'), ReportColumn(label: 'Bookings', numeric: true)],
          rows: [for (final r in rows) [r.sportName, r.bookingCount.toString()]],
          onTapRow: (i) => _drillToSport(rows[i].facilitySportId),
        ),
      ],
    );
  }

  Widget _sourceBody() {
    if (_sourceSplit.every((r) => r.bookingCount == 0)) {
      return Text('No bookings to split.', style: AppTypography.secondary(context));
    }
    return ReportBarList(
      items: [
        for (final r in _sourceSplit)
          ReportBar(label: r.source == 'GUEST' ? 'Guest' : 'Member', value: r.bookingCount),
      ],
    );
  }
}
