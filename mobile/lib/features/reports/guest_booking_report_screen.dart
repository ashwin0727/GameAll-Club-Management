import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/analytics.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/utils/csv_export.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/skeleton.dart';
import 'report_section_header.dart';
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

  Future<void> _export() async {
    final a = _analytics;
    if (a == null) return;
    await saveCsv(context, fileName: 'guest_bookings_${_filter.startDate ?? _filter.preset.name}_to_${_filter.endDate ?? 'today'}.csv', rows: [
      ['Section', 'Label', 'Value'],
      ['Summary', 'Total', a.total],
      ['Summary', 'Completed', a.completed],
      ['Summary', 'Cancelled', a.cancelled],
      ['Summary', 'Guest Revenue', a.revenueMinor / 100],
      ['Summary', 'Avg Booking Value', a.avgBookingValueMinor / 100],
      ['Summary', 'Collected', a.collectedMinor / 100],
      ['Summary', 'Outstanding', a.outstandingMinor / 100],
      ['Summary', 'Collection Rate %', a.collectionRatePct],
      for (final r in _bySport) ['By sport', r.sportName, r.bookingCount],
      for (final r in _byCourt) ['By court', r.courtName, r.bookingCount],
      for (final h in _peak) ['Peak hour', formatHourLabel(h.hour), h.bookingCount],
    ]);
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
      filterTrailing: OutlinedButton.icon(
        onPressed: a == null ? null : _export,
        icon: const Icon(Icons.download_rounded, size: 18),
        label: const Text('Export'),
      ),
      onRetry: _load,
      emptyMessage: 'No guest bookings for this period.',
      errorMessage: 'Unable to load the guest booking report. Please try again.',
      loadingSkeleton: const _GuestBookingReportSkeleton(),
      body: a == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReportKpiGrid(showDelta: false, items: [
                  ReportKpi(label: 'Total Guest Bookings', value: a.total.toString()),
                  ReportKpi(label: 'Completed', value: a.completed.toString()),
                  ReportKpi(label: 'Cancelled', value: a.cancelled.toString()),
                  ReportKpi(label: 'Guest Revenue', value: analyticsAmount(a.revenueMinor)),
                  ReportKpi(label: 'Avg Booking Value', value: analyticsAmount(a.avgBookingValueMinor)),
                  ReportKpi(label: 'Collection Rate', value: '${a.collectionRatePct.toStringAsFixed(1)}%'),
                ]),
                const SizedBox(height: AppSpacing.xl),
                ReportSectionHeader(title: 'Guest Bookings by Sport'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _bySportBody()),
                const SizedBox(height: AppSpacing.xl),
                ReportSectionHeader(title: 'Guest Bookings by Court'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _byCourtBody()),
                const SizedBox(height: AppSpacing.xl),
                ReportSectionHeader(title: 'Peak Guest Hours'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _peakBody()),
                const SizedBox(height: AppSpacing.xl),
                ReportSectionHeader(title: 'Payment Collection'),
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
                          child: const Text('Collect Outstanding'),
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

/// Shaped placeholder for the loading branch — 6-tile KPI grid plus the
/// four by-sport/by-court/peak-hours/payment-collection cards.
class _GuestBookingReportSkeleton extends StatelessWidget {
  const _GuestBookingReportSkeleton();

  Widget _sectionCard() => const SkeletonCard(
        child: Column(
          children: [
            AppSkeleton(height: 14),
            SizedBox(height: AppSpacing.sm),
            AppSkeleton(height: 14),
            SizedBox(height: AppSpacing.sm),
            AppSkeleton(height: 14),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Expanded(child: SkeletonStatTile()),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile()),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile()),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: const [
            Expanded(child: SkeletonStatTile()),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile()),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile()),
          ],
        ),
        for (var i = 0; i < 4; i++) ...[
          const SizedBox(height: AppSpacing.xl),
          const AppSkeleton(width: 160, height: 15),
          const SizedBox(height: AppSpacing.sm),
          _sectionCard(),
        ],
      ],
    );
  }
}
