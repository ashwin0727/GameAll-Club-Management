import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/analytics.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import '../finance/revenue_trend_chart.dart';
import 'analytics_filter.dart';
import 'report_section_header.dart';
import 'report_shell.dart';

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
      title: 'Overview',
      status: _status,
      filter: _filter,
      onFilterChanged: _onFilterChanged,
      onRetry: _load,
      emptyMessage: 'No activity for this period yet.',
      errorMessage: 'Unable to load analytics. Please try again.',
      loadingSkeleton: const _ReportsOverviewSkeleton(),
      body: o == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heroRevenueCard(o),
                const SizedBox(height: AppSpacing.md),
                _kpiGrid(o),
                const SizedBox(height: AppSpacing.xl),
                ReportSectionHeader(
                  title: 'Revenue Trend',
                  trailing: _viewAllLink(() => context.push(_reportHref(AppRoutes.reportsRevenue))),
                ),
                const SizedBox(height: AppSpacing.sm),
                _sectionCard(
                  child: _trend.isEmpty
                      ? Text('No revenue in this period yet.', style: AppTypography.secondary(context))
                      : RevenueTrendChart(points: _trend),
                ),
                const SizedBox(height: AppSpacing.xl),
                ReportSectionHeader(
                  title: 'Top Courts',
                  trailing: _viewAllLink(
                      () => context.push(_reportHref(AppRoutes.reportsCourtUtilization))),
                ),
                const SizedBox(height: AppSpacing.sm),
                _sectionCard(child: _topCourts()),
                const SizedBox(height: AppSpacing.xl),
                ReportSectionHeader(
                  title: 'Peak Hours',
                  trailing: _viewAllLink(
                      () => context.push(_reportHref(AppRoutes.reportsCourtUtilization))),
                ),
                const SizedBox(height: AppSpacing.sm),
                _sectionCard(child: _peakHours()),
                const SizedBox(height: AppSpacing.xl),
                const ReportSectionHeader(title: 'Quick Insights'),
                const SizedBox(height: AppSpacing.sm),
                _quickInsights(o),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  Widget _viewAllLink(VoidCallback onTap) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('View all',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: tokens.primary)),
          const SizedBox(width: 2),
          Icon(Icons.arrow_forward_rounded, size: 15, color: tokens.primary),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child, Widget? trailing}) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: trailing == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(alignment: Alignment.centerRight, child: trailing),
                child,
              ],
            ),
    );
  }

  // ── Hero "Total Revenue" card — the headline figure with its own inline
  // trend chart, tinted in the brand green rather than a plain bordered box.
  Widget _heroRevenueCard(AnalyticsOverview o) {
    final tokens = context.tokens;
    final pct = _pct((x) => x.grossRevenueMinor);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.accentFill(tokens.primary),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.accentEdge(tokens.primary)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Total Revenue',
                          style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
                    ),
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tokens.primary.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.bar_chart_rounded, size: 16, color: tokens.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(analyticsAmount(o.grossRevenueMinor),
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                ),
                const SizedBox(height: 6),
                _deltaChip(pct, invert: false),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (_trend.isNotEmpty)
            Expanded(
              flex: 5,
              child: SizedBox(height: 88, child: _MiniTrendChart(points: _trend, color: tokens.primary)),
            ),
        ],
      ),
    );
  }

  Widget _deltaChip(double? pct, {required bool invert}) {
    final tokens = context.tokens;
    if (pct == null) {
      return Text('vs last period', style: TextStyle(fontSize: 11.5, color: tokens.textSecondary));
    }
    final good = invert ? pct <= 0 : pct >= 0;
    final color = good ? tokens.success : tokens.destructive;
    final rounded = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(pct >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 15, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text('${pct > 0 ? '+' : ''}$rounded% vs last period',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }

  // ── The other nine metrics — three per row, each with its own accent icon
  // badge, matching the dashboard/hub tiles rather than plain grey labels.
  Widget _kpiGrid(AnalyticsOverview o) {
    final tokens = context.tokens;
    final tiles = <_MiniKpi>[
      _MiniKpi('Net Revenue', analyticsAmount(o.netRevenueMinor), Icons.account_balance_wallet_outlined,
          tokens.primary, _pct((x) => x.netRevenueMinor), false,
          () => context.push(_reportHref(AppRoutes.reportsRevenue))),
      _MiniKpi('Total Expenses', analyticsAmount(o.expensesMinor), Icons.trending_down_rounded,
          tokens.destructive, _pct((x) => x.expensesMinor), true,
          () => context.push(AppRoutes.financeExpenses)),
      _MiniKpi('Total Bookings', '${o.totalBookings}', Icons.event_note_outlined, tokens.electricBlue,
          _pct((x) => x.totalBookings), false,
          () => context.push(_reportHref(AppRoutes.reportsBookings))),
      _MiniKpi('Court Utilization', '${o.overallUtilizationPct.round()}%', Icons.donut_small_outlined,
          tokens.violet, _pct((x) => x.overallUtilizationPct), false,
          () => context.push(_reportHref(AppRoutes.reportsCourtUtilization))),
      _MiniKpi('Outstanding Payments', analyticsAmount(o.outstandingMinor), Icons.hourglass_empty_rounded,
          tokens.warning, _pct((x) => x.outstandingMinor), true,
          () => context.push(AppRoutes.financePendingPayments)),
      _MiniKpi('Booking Revenue', analyticsAmount(o.bookingRevenueMinor), Icons.credit_card_outlined,
          tokens.electricBlue, null, false, null),
      _MiniKpi('Membership Revenue', analyticsAmount(o.membershipRevenueMinor),
          Icons.workspace_premium_outlined, tokens.destructive, null, false, null),
      _MiniKpi('Completed Bookings', '${o.completedBookings}', Icons.check_circle_outline_rounded,
          tokens.success, null, false, null),
      _MiniKpi('Cancelled Bookings', '${o.cancelledBookings}', Icons.cancel_outlined, tokens.destructive,
          null, false, null),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.15,
      children: [for (final t in tiles) _miniKpiTile(t)],
    );
  }

  Widget _miniKpiTile(_MiniKpi t) {
    final tokens = context.tokens;
    final content = Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accentFill(t.accent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(t.icon, size: 15, color: t.accent),
          ),
          const SizedBox(height: 6),
          Text(t.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: tokens.textSecondary)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(t.value,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: tokens.textPrimary)),
          ),
          const SizedBox(height: 2),
          _deltaChip(t.pct, invert: t.invert),
        ],
      ),
    );
    if (t.onTap == null) return content;
    return InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg), onTap: t.onTap, child: content);
  }

  Widget _emptyRow(String message) => Text(message, style: AppTypography.secondary(context));

  Widget _topCourts() {
    if (_courts.isEmpty) return _emptyRow('No court activity yet.');
    final tokens = context.tokens;
    final top = [..._courts]..sort((a, b) => b.utilizationPct.compareTo(a.utilizationPct));
    final rows = top.take(5).toList();
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : AppSpacing.md),
            child: InkWell(
              onTap: () => context.push(
                '${AppRoutes.reportsCourtUtilization}?${Uri(queryParameters: analyticsFilterToQuery(_filter.copyWith(courtId: rows[i].courtId, facilitySportId: null))).query}',
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: tokens.accentFill(tokens.primary), shape: BoxShape.circle),
                    child: Text('${i + 1}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: tokens.primary)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('${rows[i].sportName} · ${rows[i].courtName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tokens.textPrimary)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 70,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (rows[i].utilizationPct.clamp(0, 100)) / 100,
                        minHeight: 6,
                        backgroundColor: tokens.surface2,
                        valueColor: AlwaysStoppedAnimation(tokens.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 42,
                    child: Text('${rows[i].utilizationPct.toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.textSecondary)),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: tokens.textSecondary),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _peakHours() {
    if (_peak.isEmpty) return _emptyRow('No booking activity in this period.');
    final sorted = [..._peak]..sort((a, b) => a.hour.compareTo(b.hour));
    final top = sorted.reduce((a, b) => a.demandPct >= b.demandPct ? a : b);
    // Every hour at ~0% demand isn't a chart worth drawing — a near-blank
    // box just reads as broken. Say plainly that there isn't enough
    // booking activity yet instead.
    if (top.demandPct < 1) {
      return _emptyRow('Not enough booking activity yet to show peak hours.');
    }
    final tokens = context.tokens;
    final peakEndHour = (top.hour + 3).clamp(0, 23);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < sorted.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: (sorted[i].demandPct.clamp(0, 100) / 100 * 80).clamp(3, 80).toDouble(),
                      decoration: BoxDecoration(
                        color: sorted[i].hour == top.hour
                            ? tokens.primary
                            : tokens.primary.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 128,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: tokens.accentFill(tokens.warning),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_fire_department_rounded, size: 14, color: tokens.warning),
                    const SizedBox(width: 4),
                    Text('Peak',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: tokens.warning)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${formatHourLabel(top.hour)} – ${formatHourLabel(peakEndHour)}',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                const SizedBox(height: 3),
                Text('Highest court demand during this period.',
                    style: TextStyle(fontSize: 10, color: tokens.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Quick Insights — three short takeaways, all derived from the same
  // fetched figures above; nothing here is a separate/fabricated number.
  Widget _quickInsights(AnalyticsOverview o) {
    final tokens = context.tokens;
    final revenuePct = _pct((x) => x.grossRevenueMinor);
    final _Insight revenue;
    if (revenuePct == null) {
      revenue = _Insight(Icons.show_chart_rounded, tokens.textSecondary, 'Not enough data yet',
          'No comparison period available.');
    } else if (revenuePct == 0) {
      revenue = _Insight(Icons.show_chart_rounded, tokens.primary, 'Revenue is stable', 'Same as last period.');
    } else if (revenuePct > 0) {
      revenue = _Insight(Icons.trending_up_rounded, tokens.success, 'Revenue is growing',
          '+${revenuePct.toStringAsFixed(0)}% vs last period.');
    } else {
      revenue = _Insight(Icons.trending_down_rounded, tokens.destructive, 'Revenue is declining',
          '${revenuePct.toStringAsFixed(0)}% vs last period.');
    }

    final util = o.overallUtilizationPct;
    final _Insight utilization = util == 0
        ? _Insight(Icons.grid_view_rounded, tokens.textSecondary, 'Courts are idle',
            'No bookings recorded yet.')
        : util < 40
            ? _Insight(Icons.grid_view_rounded, tokens.violet, 'Courts are underutilized',
                '${util.round()}% average utilization.')
            : _Insight(Icons.grid_view_rounded, tokens.success, 'Courts are performing well',
                '${util.round()}% average utilization.');

    final bookings = o.totalBookings == 0
        ? _Insight(Icons.lightbulb_outline_rounded, tokens.warning, 'No bookings yet',
            'Insights will appear once bookings start.')
        : _Insight(Icons.lightbulb_outline_rounded, tokens.warning, '${o.totalBookings} total bookings',
            '${o.completedBookings} completed, ${o.cancelledBookings} cancelled.');

    return Column(
      children: [
        for (final insight in [revenue, utilization, bookings])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: tokens.surface1,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: tokens.borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.accentFill(insight.color),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(insight.icon, size: 16, color: insight.color),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(insight.title,
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
                        Text(insight.subtitle,
                            style: TextStyle(fontSize: 11.5, color: tokens.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniKpi {
  const _MiniKpi(
      this.label, this.value, this.icon, this.accent, this.pct, this.invert, this.onTap);
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final double? pct;
  final bool invert;
  final VoidCallback? onTap;
}

class _Insight {
  const _Insight(this.icon, this.color, this.title, this.subtitle);
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
}

/// A compact, axis-free trend line for the hero card — the full
/// [RevenueTrendChart] (with its y/x-axis labels) is too tall to sit beside
/// the headline figure.
class _MiniTrendChart extends StatelessWidget {
  const _MiniTrendChart({required this.points, required this.color});

  final List<RevenueTrendPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    var peakMinor = 0;
    for (final p in points) {
      if (p.grossMinor > peakMinor) peakMinor = p.grossMinor;
    }
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return CustomPaint(size: size, painter: _MiniTrendPainter(points: points, peakMinor: peakMinor, color: color));
    });
  }
}

class _MiniTrendPainter extends CustomPainter {
  _MiniTrendPainter({required this.points, required this.peakMinor, required this.color});

  final List<RevenueTrendPoint> points;
  final int peakMinor;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final scaleMax = peakMinor <= 0 ? 1 : peakMinor;
    // Shared with the full chart — a lone day (this facility's first sale)
    // still draws as a rising line anchored at an implied ₹0 start, not an
    // easily-missed dot floating alone.
    final pts = plotPoints(points, scaleMax, size);
    if (pts.length < 2) {
      canvas.drawCircle(pts.first, 3, Paint()..color = color);
      return;
    }
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final cx = (p0.dx + p1.dx) / 2;
      line.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    final area = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(pts.last, 4, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(pts.last, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MiniTrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

/// Shaped placeholder for the loading branch — mirrors the real body's hero
/// revenue card, 6-tile KPI grid, chart card and two list cards.
class _ReportsOverviewSkeleton extends StatelessWidget {
  const _ReportsOverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSkeleton(height: 128, radius: AppRadius.lg),
        const SizedBox(height: AppSpacing.md),
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
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 120, height: 15),
        const SizedBox(height: AppSpacing.sm),
        const AppSkeleton(height: 150, radius: AppRadius.lg),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 100, height: 15),
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
