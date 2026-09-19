import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/analytics.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import 'report_section_header.dart';
import '../../shared/widgets/picker_chip.dart';
import '../authentication/session_controller.dart';
import 'analytics_filter.dart';
import 'analytics_filter_controls.dart';
import 'heatmap.dart';
import 'peak_hours_chart.dart';
import 'sport_visuals.dart';

enum _CourtSort { high, low, name }

enum _LoadStatus { loading, error, ready }

/// Reports → Court Utilization — mirrors
/// src/features/reports/components/court-utilization-report.tsx.
///
/// booked ÷ open, from the availability RPCs (0057/0059). "Open" is the
/// facility's operating hours (no maintenance model); utilisation is capped
/// at 100% server-side. Every figure is an RPC field.
///
/// This screen uses its own header/scaffold (title + subtitle + a date
/// pill) rather than the shared [ReportShell] AppBar, and always renders the
/// full card layout — even at 0% utilisation — with small inline "No X yet"
/// hints per section, matching the target design exactly.
class CourtUtilizationReportScreen extends ConsumerStatefulWidget {
  const CourtUtilizationReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  ConsumerState<CourtUtilizationReportScreen> createState() => _CourtUtilizationReportScreenState();
}

class _CourtUtilizationReportScreenState extends ConsumerState<CourtUtilizationReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  _LoadStatus _status = _LoadStatus.loading;
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
    setState(() => _status = _LoadStatus.loading);

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
      setState(() {
        _overall = results[0] as OverallUtilization;
        _courts = results[1] as List<CourtUtilizationRow>;
        _sports = results[2] as List<SportUtilizationRow>;
        _peak = results[3] as List<PeakHourRow>;
        _heatmap = results[4] as List<HeatmapCell>;
        _status = _LoadStatus.ready;
      });
    } on AppException {
      if (mounted && requestId == _requestId) setState(() => _status = _LoadStatus.error);
    } catch (_) {
      if (mounted && requestId == _requestId) setState(() => _status = _LoadStatus.error);
    }
  }

  void _onFilterChanged(AnalyticsFilter next) {
    setState(() => _filter = next);
    _load();
  }

  String _courtLabel(CourtUtilizationRow row) => '${row.sportName} · ${row.courtName}';

  List<CourtUtilizationRow> get _sortedCourts {
    final rows = [..._courts];
    rows.sort((a, b) => _courtLabel(a).compareTo(_courtLabel(b)));
    switch (_sort) {
      case _CourtSort.high:
        rows.sort((a, b) => b.utilizationPct.compareTo(a.utilizationPct));
      case _CourtSort.low:
        rows.sort((a, b) => a.utilizationPct.compareTo(b.utilizationPct));
      case _CourtSort.name:
        break;
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
        _CourtSort.high => 'Highest utilization',
        _CourtSort.low => 'Lowest utilization',
        _CourtSort.name => 'By name',
      };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final facility = ref.watch(sessionControllerProvider).facility;

    return Scaffold(
      backgroundColor: tokens.surface0,
      body: facility == null
          ? const EmptyStateView(message: 'No facility found for this account yet.')
          : SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: () async => _load(),
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(filter: _filter, onFilterChanged: _onFilterChanged),
                      const SizedBox(height: AppSpacing.lg),
                      AnalyticsFilterControls(
                        facilityId: facility.id,
                        filter: _filter,
                        onChanged: _onFilterChanged,
                        showDate: false,
                        leadingIcons: true,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      switch (_status) {
                        _LoadStatus.loading => const Padding(
                            padding: EdgeInsets.only(top: AppSpacing.xl),
                            child: _CourtUtilizationSkeleton(),
                          ),
                        _LoadStatus.error => Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xxl),
                            child: ErrorView(
                              message: 'Unable to calculate utilization. Please try again.',
                              onRetry: _load,
                            ),
                          ),
                        _LoadStatus.ready => _overall == null ? const SizedBox.shrink() : _body(tokens),
                      },
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _body(AppColorTokens tokens) {
    final o = _overall!;
    final rows = _sortedCourts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OverallCard(overall: o),
        const SizedBox(height: AppSpacing.xl),
        const ReportSectionHeader(title: 'By Sport'),
        const SizedBox(height: AppSpacing.sm),
        _sports.isEmpty
            ? Text('No sport activity for this period.', style: AppTypography.secondary(context))
            : Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final s in _sports)
                    SizedBox(width: (_cardWidth(context) - AppSpacing.sm * 2) / 3, child: _SportCard(row: s)),
                ],
              ),
        const SizedBox(height: AppSpacing.xl),
        ReportSectionHeader(
          title: 'Court Performance',
          trailing: PickerChip(label: _sortLabel(), onSelect: _pickSort),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: EdgeInsets.zero,
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text('No courts configured.', style: AppTypography.secondary(context)),
                )
              : Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: tokens.borderColor),
                      _CourtRow(
                        row: rows[i],
                        onTap: () => _drill(AppRoutes.reportsCourtUtilization, courtId: rows[i].courtId),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const ReportSectionHeader(title: 'Peak Hours'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(child: PeakHoursChart(rows: _peak)),
        const SizedBox(height: AppSpacing.xl),
        const ReportSectionHeader(title: 'Demand Heatmap'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(child: Heatmap(cells: _heatmap)),
        const SizedBox(height: AppSpacing.xl),
        const ReportSectionHeader(title: 'Insights'),
        const SizedBox(height: AppSpacing.sm),
        const AppCard(child: _InsightsPlaceholder()),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  double _cardWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - AppSpacing.lg * 2;
    return width.clamp(280, 700);
  }
}

/// Shaped placeholder for the loading branch — mirrors the ready body's
/// overall-utilization hero card, 3-column by-sport grid and the
/// court-performance list.
class _CourtUtilizationSkeleton extends StatelessWidget {
  const _CourtUtilizationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 140, height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(width: 90, height: 30),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 8, radius: AppRadius.pill),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 90, height: 15),
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
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 150, height: 15),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(),
      ],
    );
  }
}

/// Back button + title/subtitle + a solid green date pill — the one part of
/// this screen that intentionally departs from [ReportSectionHeader]'s
/// AppBar to match the reference design exactly.
class _Header extends StatelessWidget {
  const _Header({required this.filter, required this.onFilterChanged});

  final AnalyticsFilter filter;
  final ValueChanged<AnalyticsFilter> onFilterChanged;

  Future<void> _pickPreset(BuildContext context) async {
    final picked = await showModalBottomSheet<AnalyticsPreset>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in kAnalyticsPresets)
              ListTile(
                title: Text(p.label),
                trailing: p == filter.preset ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    if (picked == AnalyticsPreset.custom) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (range == null) return;
      onFilterChanged(filter.copyWith(
        preset: AnalyticsPreset.custom,
        startDate: _iso(range.start),
        endDate: _iso(range.end),
      ));
      return;
    }
    onFilterChanged(filter.copyWith(preset: picked));
  }

  String get _dateLabel {
    if (filter.preset == AnalyticsPreset.custom && filter.startDate != null && filter.endDate != null) {
      return '${filter.startDate} – ${filter.endDate}';
    }
    return filter.preset.label;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => context.canPop() ? context.pop() : null,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Icon(Icons.arrow_back, color: tokens.textPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Court Utilization', style: AppTypography.heading1(context)),
                  const SizedBox(height: 2),
                  Text('Track how your courts are being used', style: AppTypography.secondary(context)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            InkWell(
              onTap: () => _pickPreset(context),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: tokens.accentSolid(tokens.primary),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 14, color: tokens.onAccent(tokens.primary)),
                    const SizedBox(width: 6),
                    Text(_dateLabel,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: tokens.onAccent(tokens.primary))),
                    const SizedBox(width: 2),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: tokens.onAccent(tokens.primary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The hero "Overall Utilization" card — a solid mint fill, the big
/// percentage, a progress bar, and (when nothing's booked yet) an inline
/// "No bookings yet" hint instead of swapping the whole page for an empty
/// state.
class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.overall});

  final OverallUtilization overall;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final pct = overall.utilizationPct.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.accentFill(tokens.primary),
        border: Border.all(color: tokens.accentEdge(tokens.primary)),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -6,
            right: -6,
            child: _CornerGlyph(tokens: tokens),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Overall Utilization',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
                  const SizedBox(width: 6),
                  Icon(Icons.info_outline, size: 15, color: tokens.textSecondary),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('${pct.round()}%', style: AppTypography.display2(context)),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: (pct / 100).toDouble(),
                  minHeight: 8,
                  backgroundColor: tokens.surface1,
                  valueColor: AlwaysStoppedAnimation(tokens.primary),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatHours(overall.bookedMinutes)} booked • ${formatHours(overall.openMinutes)} available',
                style: AppTypography.caption(context),
              ),
              if (overall.bookedMinutes == 0) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.surface1,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bar_chart_rounded, size: 20, color: tokens.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('No bookings yet',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
                            const SizedBox(height: 2),
                            Text('Once members start booking, your utilization insights will appear here.',
                                style: AppTypography.caption(context)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CornerGlyph extends StatelessWidget {
  const _CornerGlyph({required this.tokens});

  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 56,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 6,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tokens.surface1, shape: BoxShape.circle),
              child: Icon(Icons.calendar_month_rounded, size: 20, color: tokens.textSecondary),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: tokens.accentSolid(tokens.primary), shape: BoxShape.circle),
              child: Icon(Icons.trending_up_rounded, size: 16, color: tokens.onAccent(tokens.primary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SportCard extends StatelessWidget {
  const _SportCard({required this.row});

  final SportUtilizationRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final visual = sportVisual(tokens, row.sportName);
    final pct = row.utilizationPct.clamp(0, 100);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tokens.accentFill(visual.accent), shape: BoxShape.circle),
            child: Icon(visual.icon, size: 18, color: visual.accent),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(row.sportName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
          const SizedBox(height: 2),
          Text('${pct.round()}%',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: visual.accent)),
          const SizedBox(height: 2),
          Text('${formatHours(row.bookedMinutes)} booked', style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: (pct / 100).toDouble(),
              minHeight: 5,
              backgroundColor: tokens.surface2,
              valueColor: AlwaysStoppedAnimation(visual.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourtRow extends StatelessWidget {
  const _CourtRow({required this.row, required this.onTap});

  final CourtUtilizationRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final visual = sportVisual(tokens, row.sportName);
    final pct = row.utilizationPct.clamp(0, 100);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tokens.accentFill(visual.accent), borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Icon(visual.icon, size: 20, color: visual.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${row.sportName} · ${row.courtName}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: tokens.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    '${formatHours(row.bookedMinutes)} booked • ${formatHours(row.openMinutes)} available',
                    style: AppTypography.caption(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${pct.round()}%',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: SizedBox(
                    width: 64,
                    child: LinearProgressIndicator(
                      value: (pct / 100).toDouble(),
                      minHeight: 5,
                      backgroundColor: tokens.surface2,
                      valueColor: AlwaysStoppedAnimation(visual.accent),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 20, color: tokens.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// No RPC computes narrative insights yet, so this stays a fixed "coming
/// soon" placeholder — matching the target design's empty state — rather
/// than fabricating a client-derived headline.
class _InsightsPlaceholder extends StatelessWidget {
  const _InsightsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tokens.accentFill(tokens.primary), shape: BoxShape.circle),
          child: Icon(Icons.lightbulb_outline_rounded, size: 20, color: tokens.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No insights yet',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
              const SizedBox(height: 2),
              Text('As bookings come in, we\'ll highlight trends, popular hours and underutilized courts here.',
                  style: AppTypography.caption(context)),
            ],
          ),
        ),
      ],
    );
  }
}
