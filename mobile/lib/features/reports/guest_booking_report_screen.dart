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
import 'report_shell.dart';
import 'report_widgets.dart';

/// Reports → Guest Bookings — mirrors
/// src/features/reports/components/guest-booking-report.tsx.
///
/// Ad-hoc guest bookings only (bookings.customer_type = 'GUEST'). Revenue is
/// collected (paid payments), cash basis. Average booking value and
/// collection rate come straight from get_guest_booking_analytics — the
/// ₹800 pending booking of the spec §50 fixture is in outstanding, never in
/// collected.
class GuestBookingReportScreen extends ConsumerStatefulWidget {
  const GuestBookingReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  ConsumerState<GuestBookingReportScreen> createState() => _GuestBookingReportScreenState();
}

class _GuestBookingReportScreenState extends ConsumerState<GuestBookingReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  ReportStatus _status = ReportStatus.loading;
  GuestBookingAnalytics? _analytics;
  List<GuestBookingsBySportRow> _bySport = const [];
  List<GuestBookingsByCourtRow> _byCourt = const [];
  List<GuestPeakHourRow> _peak = const [];
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
        repo.getGuestBookingAnalytics(facility.id, _filter),
        repo.getGuestBookingsBySport(facility.id, _filter),
        repo.getGuestBookingsByCourt(facility.id, _filter),
        repo.getGuestPeakHours(facility.id, _filter),
      ]);
      if (!mounted || requestId != _requestId) return;
      final analytics = results[0] as GuestBookingAnalytics;
      setState(() {
        _analytics = analytics;
        _bySport = results[1] as List<GuestBookingsBySportRow>;
        _byCourt = results[2] as List<GuestBookingsByCourtRow>;
        _peak = results[3] as List<GuestPeakHourRow>;
        _status = analytics.total == 0 ? ReportStatus.empty : ReportStatus.ready;
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
      '${AppRoutes.reportsGuestBookings}?${Uri(queryParameters: analyticsFilterToQuery(_filter.copyWith(facilitySportId: sportId, courtId: courtId))).query}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _analytics;
    return ReportShell(
      title: 'Guest Booking Report',
      status: _status,
      filter: _filter,
      onFilterChanged: _onFilterChanged,
      onRetry: _load,
      emptyMessage: 'No guest bookings for this period.',
      errorMessage: 'Unable to load the guest booking report. Please try again.',
      body: a == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReportKpiGrid(items: [
                  ReportKpi(label: 'Total Guest Bookings', value: a.total.toString()),
                  ReportKpi(label: 'Completed', value: a.completed.toString()),
                  ReportKpi(label: 'Cancelled', value: a.cancelled.toString()),
                  ReportKpi(label: 'Guest Revenue', value: analyticsAmount(a.revenueMinor)),
                  ReportKpi(label: 'Avg Booking Value', value: analyticsAmount(a.avgBookingValueMinor)),
                  ReportKpi(label: 'Collection Rate', value: '${a.collectionRatePct.toStringAsFixed(1)}%'),
                ]),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Guest Bookings by Sport'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _bySportBody()),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Guest Bookings by Court'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _byCourtBody()),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Peak Guest Hours'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _peakBody()),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Payment Collection'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReportDataTable(
                        caption: 'Guest payment collection',
                        columns: const [ReportColumn(label: 'Metric'), ReportColumn(label: 'Value', numeric: true)],
                        rows: [
                          ['Collected', analyticsAmount(a.collectedMinor)],
                          ['Outstanding', analyticsAmount(a.outstandingMinor)],
                          ['Collection rate', '${a.collectionRatePct.toStringAsFixed(1)}%'],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => context.push(AppRoutes.financePendingPayments),
                          child: const Text('Collect outstanding'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  Widget _bySportBody() {
    final rows = _bySport.where((r) => r.bookingCount > 0).toList();
    if (rows.isEmpty) {
      return Text('No guest bookings by sport.', style: AppTypography.secondary(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(
          items: [
            for (final r in rows)
              ReportBar(label: r.sportName, value: r.bookingCount, caption: '${r.bookingCount} · ${analyticsAmount(r.revenueMinor)}'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Guest bookings by sport',
          columns: const [
            ReportColumn(label: 'Sport'),
            ReportColumn(label: 'Bookings', numeric: true),
            ReportColumn(label: 'Revenue', numeric: true),
          ],
          rows: [for (final r in rows) [r.sportName, r.bookingCount.toString(), analyticsAmount(r.revenueMinor)]],
          onTapRow: (i) => _drill(sportId: rows[i].facilitySportId),
        ),
      ],
    );
  }

  Widget _byCourtBody() {
    final rows = _byCourt.where((r) => r.bookingCount > 0).toList();
    if (rows.isEmpty) {
      return Text('No guest bookings by court.', style: AppTypography.secondary(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(
          items: [
            for (final r in rows)
              ReportBar(label: r.courtName, value: r.bookingCount, caption: '${r.bookingCount} · ${analyticsAmount(r.revenueMinor)}'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Guest bookings by court',
          columns: const [
            ReportColumn(label: 'Court'),
            ReportColumn(label: 'Bookings', numeric: true),
            ReportColumn(label: 'Revenue', numeric: true),
          ],
          rows: [for (final r in rows) [r.courtName, r.bookingCount.toString(), analyticsAmount(r.revenueMinor)]],
          onTapRow: (i) => _drill(courtId: rows[i].courtId),
        ),
      ],
    );
  }

  Widget _peakBody() {
    if (_peak.isEmpty) {
      return Text('No guest booking activity.', style: AppTypography.secondary(context));
    }
    final byHour = [..._peak]..sort((a, b) => a.hour.compareTo(b.hour));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(
          items: [for (final h in byHour) ReportBar(label: formatHourLabel(h.hour), value: h.bookingCount)],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Peak guest hours',
          columns: const [ReportColumn(label: 'Hour'), ReportColumn(label: 'Bookings', numeric: true)],
          rows: [for (final h in byHour) [formatHourLabel(h.hour), h.bookingCount.toString()]],
        ),
      ],
    );
  }
}
