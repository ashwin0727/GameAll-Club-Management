import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/analytics.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/picker_chip.dart';
import '../authentication/session_controller.dart';
import 'analytics_filter.dart';
import 'heatmap.dart';
import 'report_shell.dart';
import 'report_widgets.dart';

enum _CourtSort { high, low, name }

/// Reports → Court Utilization — mirrors
/// src/features/reports/components/court-utilization-report.tsx.
///
/// booked ÷ open, from the availability RPCs (0057/0059). "Open" is the
/// facility's operating hours (no maintenance model); utilisation is capped
/// at 100% server-side. Every figure is an RPC field.
class CourtUtilizationReportScreen extends ConsumerStatefulWidget {
  const CourtUtilizationReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  ConsumerState<CourtUtilizationReportScreen> createState() => _CourtUtilizationReportScreenState();
}

class _CourtUtilizationReportScreenState extends ConsumerState<CourtUtilizationReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  ReportStatus _status = ReportStatus.loading;
  OverallUtilization? _overall;
  List<CourtUtilizationRow> _courts = const [];
  List<SportUtilizationRow> _sports = const [];
  List<PeakHourRow> _peak = const [];
  List<HeatmapCell> _heatmap = const [];
  _CourtSort _sort = _CourtSort.high;
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
        repo.getOverallUtilization(facility.id, _filter),
        repo.getCourtUtilization(facility.id, _filter),
        repo.getSportUtilization(facility.id, _filter),
        repo.getPeakHours(facility.id, _filter),
        repo.getDemandHeatmap(facility.id, _filter),
      ]);
      if (!mounted || requestId != _requestId) return;
      final overall = results[0] as OverallUtilization;
      setState(() {
        _overall = overall;
        _courts = results[1] as List<CourtUtilizationRow>;
        _sports = results[2] as List<SportUtilizationRow>;
        _peak = results[3] as List<PeakHourRow>;
        _heatmap = results[4] as List<HeatmapCell>;
        _status = overall.openMinutes == 0 ? ReportStatus.empty : ReportStatus.ready;
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

  List<CourtUtilizationRow> get _sortedCourts {
    final rows = [..._courts];
    switch (_sort) {
      case _CourtSort.high:
        rows.sort((a, b) => b.utilizationPct.compareTo(a.utilizationPct));
      case _CourtSort.low:
        rows.sort((a, b) => a.utilizationPct.compareTo(b.utilizationPct));
      case _CourtSort.name:
        rows.sort((a, b) => a.courtName.compareTo(b.courtName));
    }
    return rows;
  }

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<_CourtSort>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('Highest first'), onTap: () => Navigator.pop(ctx, _CourtSort.high)),
            ListTile(title: const Text('Lowest first'), onTap: () => Navigator.pop(ctx, _CourtSort.low)),
            ListTile(title: const Text('By name'), onTap: () => Navigator.pop(ctx, _CourtSort.name)),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  void _drill(String path, {String? courtId, String? sportId}) {
    context.push(
      '$path?${Uri(queryParameters: analyticsFilterToQuery(_filter.copyWith(courtId: courtId, facilitySportId: sportId))).query}',
    );
  }

  String _sortLabel() => switch (_sort) {
        _CourtSort.high => 'Highest first',
        _CourtSort.low => 'Lowest first',
        _CourtSort.name => 'By name',
      };

  @override
  Widget build(BuildContext context) {
    final o = _overall;
    return ReportShell(
      title: 'Court Utilization',
      status: _status,
      filter: _filter,
      onFilterChanged: _onFilterChanged,
      onRetry: _load,
      emptyMessage: 'No court activity for this period.',
      errorMessage: 'Unable to calculate utilization. Please try again.',
      body: o == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Overall Utilization', style: AppTypography.rowTitle(context)),
                      const SizedBox(height: AppSpacing.xs),
                      Text('${o.utilizationPct.round()}%', style: Theme.of(context).textTheme.displaySmall),
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (o.utilizationPct / 100).clamp(0, 1).toDouble(),
                          minHeight: 8,
                          backgroundColor: AppColors.border,
                          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${formatHours(o.bookedMinutes)} booked of ${formatHours(o.openMinutes)} bookable',
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(
                  title: 'By Court',
                  trailing: PickerChip(label: _sortLabel(), onSelect: _pickSort),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _byCourtBody()),
                const SizedBox(height: AppSpacing.xl),
                if (_sports.isNotEmpty) ...[
                  SectionHeader(title: 'By Sport'),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(child: _bySportBody()),
                  const SizedBox(height: AppSpacing.xl),
                ],
                SectionHeader(title: 'Peak Hours'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _peakBody()),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Demand Heatmap'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: Heatmap(cells: _heatmap)),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  Widget _byCourtBody() {
    final rows = _sortedCourts;
    if (rows.isEmpty) {
      return Text('No courts configured.', style: AppTypography.secondary(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(
          max: 100,
          items: [
            for (final c in rows)
              ReportBar(
                label: c.courtName,
                value: c.utilizationPct,
                caption:
                    '${c.utilizationPct.toStringAsFixed(1)}% · ${formatHours(c.bookedMinutes)}/${formatHours(c.openMinutes)}',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Court utilization',
          columns: const [
            ReportColumn(label: 'Court'),
            ReportColumn(label: 'Available (h)', numeric: true),
            ReportColumn(label: 'Booked (h)', numeric: true),
            ReportColumn(label: 'Utilization', numeric: true),
          ],
          rows: [
            for (final c in rows)
              [
                c.courtName,
                (c.openMinutes / 60).toStringAsFixed(1),
                (c.bookedMinutes / 60).toStringAsFixed(1),
                '${c.utilizationPct.toStringAsFixed(1)}%',
              ],
          ],
          onTapRow: (i) => _drill(AppRoutes.reportsCourtUtilization, courtId: rows[i].courtId),
        ),
      ],
    );
  }

  Widget _bySportBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(
          max: 100,
          items: [
            for (final s in _sports)
              ReportBar(label: s.sportName, value: s.utilizationPct, caption: '${s.utilizationPct.toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Sport utilization',
          columns: const [
            ReportColumn(label: 'Sport'),
            ReportColumn(label: 'Booked (h)', numeric: true),
            ReportColumn(label: 'Utilization', numeric: true),
          ],
          rows: [
            for (final s in _sports)
              [s.sportName, (s.bookedMinutes / 60).toStringAsFixed(1), '${s.utilizationPct.toStringAsFixed(1)}%'],
          ],
          onTapRow: (i) => _drill(AppRoutes.reportsCourtUtilization, sportId: _sports[i].facilitySportId),
        ),
      ],
    );
  }

  Widget _peakBody() {
    if (_peak.isEmpty) {
      return Text('No booking activity in this period.', style: AppTypography.secondary(context));
    }
    final byHour = [..._peak]..sort((a, b) => a.hour.compareTo(b.hour));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(
          max: 100,
          items: [
            for (final h in byHour)
              ReportBar(label: formatHourLabel(h.hour), value: h.demandPct, caption: '${h.demandPct.toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Peak hours',
          columns: const [
            ReportColumn(label: 'Hour'),
            ReportColumn(label: 'Demand', numeric: true),
            ReportColumn(label: 'Booked (min)', numeric: true),
            ReportColumn(label: 'Open (min)', numeric: true),
          ],
          rows: [
            for (final h in byHour)
              [
                formatHourLabel(h.hour),
                '${h.demandPct.toStringAsFixed(1)}%',
                h.bookedMinutes.toString(),
                h.openMinutes.toString(),
              ],
          ],
        ),
      ],
    );
  }
}
