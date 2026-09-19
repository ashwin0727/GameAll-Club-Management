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
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../finance/revenue_trend_chart.dart';
import 'analytics_filter.dart';
import 'analytics_filter_controls.dart';
import 'report_section_header.dart';
import 'report_shell.dart';
import 'sport_visuals.dart';

/// Reports → Revenue — mirrors src/features/reports/components/revenue-report.tsx.
///
/// Trend / breakdown / method / totals are the existing Finance RPCs called
/// verbatim, so Reports revenue == Finance revenue (web spec §34). The only
/// new cuts are get_revenue_by_sport / _by_court. When a sport or court
/// filter is set the Finance figures are facility-wide, so the report shows
/// only the (scoped) by-sport / by-court cards plus a note.
///
/// This screen owns its own header/scaffold (title + subtitle + a solid
/// date pill), matching Court Utilization's premium layout, rather than
/// [ReportShell]'s generic AppBar.
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
  RevenueSummary? _previousSummary;
  List<RevenueTrendPoint> _trend = const [];
  ReportRevenueBreakdown? _breakdown;
  List<PaymentMethodSlice> _methods = const [];
  List<RevenueBySportRow> _bySport = const [];
  List<RevenueByCourtRow> _byCourt = const [];
  RevenueTrendGranularity? _granularityOverride;
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
          _previousSummary = null;
          _trend = const [];
          _breakdown = null;
          _methods = const [];
          _bySport = bySport;
          _byCourt = byCourt;
          _status = bySport.every((r) => r.revenueMinor == 0) ? ReportStatus.empty : ReportStatus.ready;
        });
        return;
      }

      final granularity = _granularityOverride ?? pickAnalyticsGranularity(_filter);
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

      final prevFilter = previousAnalyticsPeriod(_filter);
      if (prevFilter != null) {
        try {
          final prev = await repo.getRevenueSummary(facility.id, prevFilter);
          if (mounted && requestId == _requestId) setState(() => _previousSummary = prev);
        } catch (_) {
          if (mounted && requestId == _requestId) setState(() => _previousSummary = null);
        }
      } else if (mounted && requestId == _requestId) {
        setState(() => _previousSummary = null);
      }
    } on AppException {
      if (mounted && requestId == _requestId) setState(() => _status = ReportStatus.error);
    } catch (_) {
      if (mounted && requestId == _requestId) setState(() => _status = ReportStatus.error);
    }
  }

  void _onFilterChanged(AnalyticsFilter next) {
    setState(() {
      _filter = next;
      _granularityOverride = null;
    });
    _load();
  }

  Future<void> _setGranularity(RevenueTrendGranularity g) async {
    if (_granularityOverride == g) return;
    setState(() => _granularityOverride = g);
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    try {
      final trend = await ref.read(reportsRepositoryProvider).getRevenueTrend(facility.id, _filter, g);
      if (mounted) setState(() => _trend = trend);
    } catch (_) {
      // Keep the previous chart rather than clearing it on a transient error.
    }
  }

  void _drill(String path, {String? sportId, String? courtId}) {
    context.push(
      '$path?${Uri(queryParameters: analyticsFilterToQuery(_filter.copyWith(facilitySportId: sportId, courtId: courtId))).query}',
    );
  }

  double? _pct(num Function(RevenueSummary) pick) {
    final s = _summary, p = _previousSummary;
    if (s == null || p == null) return null;
    return analyticsChangePct(current: pick(s), previous: pick(p));
  }

  @override
  Widget build(BuildContext context) {
    final facility = ref.watch(sessionControllerProvider).facility;
    final tokens = context.tokens;

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
                        ReportStatus.loading => const Padding(
                            padding: EdgeInsets.only(top: AppSpacing.xl),
                            child: _RevenueReportSkeleton(),
                          ),
                        ReportStatus.error => Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xxl),
                            child: ErrorView(
                              message: 'Unable to load the revenue report. Please try again.',
                              onRetry: _load,
                            ),
                          ),
                        ReportStatus.empty => const Padding(
                            padding: EdgeInsets.only(top: AppSpacing.xxl),
                            child: EmptyStateView(message: 'No revenue data for this period.'),
                          ),
                        ReportStatus.ready => _body(context),
                      },
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _body(BuildContext context) {
    final b = _breakdown;
    final sportRows = <RevenueBySportRow>[
      ..._bySport,
      if (b != null)
        RevenueBySportRow(facilitySportId: '__membership__', sportName: 'Memberships', revenueMinor: b.membershipMinor),
    ]..sort((a, c) => c.revenueMinor.compareTo(a.revenueMinor));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_scoped)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Trend and breakdown show the whole facility.', style: AppTypography.caption(context)),
                TextButton(
                  onPressed: () => _onFilterChanged(_filter.copyWith(facilitySportId: null, courtId: null)),
                  child: const Text('Clear sport & court'),
                ),
              ],
            ),
          ),
        if (!_scoped && _summary != null) ...[
          _kpiGrid(context),
          const SizedBox(height: AppSpacing.xl),
          ReportSectionHeader(title: 'Revenue Trend', trailing: _granularityToggle(context)),
          const SizedBox(height: AppSpacing.sm),
          _card(
            context,
            child: _trend.isEmpty
                ? Text('No revenue in this period yet.', style: AppTypography.secondary(context))
                : RevenueTrendChart(points: _trend),
          ),
          const SizedBox(height: AppSpacing.xl),
          ReportSectionHeader(
            title: 'Revenue Breakdown',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total  ', style: AppTypography.caption(context)),
                Text(analyticsAmount(_summary!.grossMinor),
                    style: TextStyle(fontWeight: FontWeight.w800, color: context.tokens.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _card(context, child: _revenueBreakdown(context, b)),
          const SizedBox(height: AppSpacing.xl),
          ReportSectionHeader(
            title: 'Payment Methods',
            trailing: _viewAllLink(context, 'View details', () => context.push(AppRoutes.financeTransactions)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _paymentMethods(context),
          const SizedBox(height: AppSpacing.xl),
        ],
        ReportSectionHeader(
          title: 'Revenue by Sport',
          trailing: _viewAllLink(context, 'View all', () => context.push(AppRoutes.reportsCourtUtilization)),
        ),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _bySportBody(context, sportRows)),
        const SizedBox(height: AppSpacing.xl),
        ReportSectionHeader(
          title: 'Revenue by Court',
          trailing: _viewAllLink(context, 'View all', () => context.push(AppRoutes.reportsCourtUtilization)),
        ),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _byCourtBody(context)),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  // ── Shared shell pieces ────────────────────────────────────────────────

  Widget _card(BuildContext context, {required Widget child}) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: child,
    );
  }

  Widget _viewAllLink(BuildContext context, String label, VoidCallback onTap) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: tokens.primary)),
          const SizedBox(width: 2),
          Icon(Icons.arrow_forward_rounded, size: 15, color: tokens.primary),
        ],
      ),
    );
  }

  // ── KPI grid ───────────────────────────────────────────────────────────

  Widget _kpiGrid(BuildContext context) {
    final s = _summary!;
    final tokens = context.tokens;
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _kpiCard(
                  context,
                  icon: Icons.paid_rounded,
                  accent: tokens.primary,
                  label: 'Total Revenue',
                  value: analyticsAmount(s.grossMinor),
                  pct: _pct((x) => x.grossMinor),
                  showGlyph: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _kpiCard(
                  context,
                  icon: Icons.account_balance_wallet_rounded,
                  accent: tokens.electricBlue,
                  label: 'Net Revenue',
                  value: analyticsAmount(s.netMinor),
                  pct: _pct((x) => x.netMinor),
                  showGlyph: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _kpiCard(
                  context,
                  icon: Icons.replay_rounded,
                  accent: tokens.destructive,
                  label: 'Refunds',
                  value: analyticsAmount(s.refundsMinor),
                  pct: _pct((x) => x.refundsMinor),
                  invert: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _kpiCard(
                  context,
                  icon: Icons.description_rounded,
                  accent: tokens.warning,
                  label: 'Expenses',
                  value: analyticsAmount(s.expensesMinor),
                  pct: _pct((x) => x.expensesMinor),
                  invert: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String label,
    required String value,
    double? pct,
    bool invert = false,
    bool showGlyph = false,
  }) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.accentFill(accent),
        border: Border.all(color: tokens.accentEdge(accent)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Stack(
        children: [
          if (showGlyph)
            Positioned(
              right: -4,
              bottom: -4,
              child: Icon(Icons.show_chart_rounded, size: 46, color: accent.withValues(alpha: 0.14)),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: tokens.accentSolid(accent), shape: BoxShape.circle),
                    child: Icon(icon, size: 15, color: tokens.onAccent(accent)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: tokens.textSecondary)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
              ),
              const SizedBox(height: 6),
              _kpiDelta(context, pct, invert: invert),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiDelta(BuildContext context, double? pct, {required bool invert}) {
    final tokens = context.tokens;
    if (pct == null || pct == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.remove_rounded, size: 13, color: tokens.textSecondary),
          const SizedBox(width: 3),
          Flexible(
            child: Text('0% vs last period',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tokens.textSecondary)),
          ),
        ],
      );
    }
    final good = invert ? pct <= 0 : pct >= 0;
    final color = good ? tokens.success : tokens.destructive;
    final rounded = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(pct >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text('${pct > 0 ? '+' : ''}$rounded% vs last period',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }

  // ── Revenue Trend — granularity toggle ────────────────────────────────

  Widget _granularityToggle(BuildContext context) {
    final tokens = context.tokens;
    final current = _granularityOverride ?? pickAnalyticsGranularity(_filter);

    Widget seg(String label, RevenueTrendGranularity g) {
      final active = current == g;
      return GestureDetector(
        onTap: () => _setGranularity(g),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? tokens.accentSolid(tokens.primary) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: active ? tokens.onAccent(tokens.primary) : tokens.textSecondary)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: tokens.surface2, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Daily', RevenueTrendGranularity.daily),
          seg('Weekly', RevenueTrendGranularity.weekly),
          seg('Monthly', RevenueTrendGranularity.monthly),
        ],
      ),
    );
  }

  // ── Revenue Breakdown — donut + legend ────────────────────────────────

  Widget _revenueBreakdown(BuildContext context, ReportRevenueBreakdown? b) {
    final tokens = context.tokens;
    final slices = <({String label, int amountMinor, Color color})>[
      (label: 'Memberships', amountMinor: b?.membershipMinor ?? 0, color: tokens.primary),
      (label: 'Guest Bookings', amountMinor: b?.guestBookingMinor ?? 0, color: tokens.electricBlue),
      (label: 'Member Bookings', amountMinor: b?.memberBookingMinor ?? 0, color: tokens.violet),
      (label: 'Coaching', amountMinor: b?.coachingMinor ?? 0, color: tokens.warning),
      (label: 'Refunds', amountMinor: b?.refundsMinor ?? 0, color: tokens.destructive),
    ];
    final total = slices.fold<int>(0, (sum, s) => sum + s.amountMinor);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(132, 132),
                painter: _DonutPainter(
                  values: [for (final s in slices) s.amountMinor],
                  colors: [for (final s in slices) s.color],
                  trackColor: tokens.surface2,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(analyticsAmount(total),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                  Text('Total Revenue', style: AppTypography.caption(context)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: tokens.textPrimary)),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(analyticsAmount(s.amountMinor),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 34,
                        child: Text(
                          total == 0 ? '0%' : '${(s.amountMinor / total * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Payment Methods ────────────────────────────────────────────────────

  Widget _paymentMethods(BuildContext context) {
    final tokens = context.tokens;
    int upi = 0, cash = 0, other = 0;
    for (final m in _methods) {
      final u = m.method.toUpperCase();
      if (u == 'UPI') {
        upi += m.amountMinor;
      } else if (u == 'CASH') {
        cash += m.amountMinor;
      } else {
        other += m.amountMinor;
      }
    }
    final total = upi + cash + other;
    double pct(int v) => total == 0 ? 0 : v / total * 100;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _paymentCard(context,
                icon: Icons.bolt_rounded, accent: tokens.warning, label: 'UPI', amountMinor: upi, pct: pct(upi)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _paymentCard(context,
                icon: Icons.payments_rounded,
                accent: tokens.success,
                label: 'Cash',
                amountMinor: cash,
                pct: pct(cash)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _paymentCard(context,
                icon: Icons.credit_card_rounded,
                accent: tokens.violet,
                label: 'Card / Other',
                amountMinor: other,
                pct: pct(other)),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String label,
    required int amountMinor,
    required double pct,
  }) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border.all(color: tokens.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tokens.accentSolid(accent), shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: tokens.onAccent(accent)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(analyticsAmount(amountMinor),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
          ),
          const SizedBox(height: 2),
          Text('${pct.round()}%', style: TextStyle(fontSize: 11, color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1).toDouble(),
              minHeight: 5,
              backgroundColor: tokens.surface2,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ],
      ),
    );
  }

  // ── Revenue by Sport ───────────────────────────────────────────────────

  Widget _bySportBody(BuildContext context, List<RevenueBySportRow> sportRows) {
    final live = sportRows.where((r) => r.revenueMinor > 0).toList();
    if (live.isEmpty) {
      return _emptyState(context,
          icon: Icons.bar_chart_rounded,
          title: 'No sport revenue',
          subtitle: 'Sport-wise revenue will appear once there are bookings.');
    }
    final tokens = context.tokens;
    final total = _summary?.grossMinor ?? live.fold<int>(0, (sum, r) => sum + r.revenueMinor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in live)
          _entityRow(
            context,
            icon: r.facilitySportId == '__membership__' ? Icons.workspace_premium_rounded : sportVisual(tokens, r.sportName).icon,
            accent: r.facilitySportId == '__membership__' ? tokens.destructive : sportVisual(tokens, r.sportName).accent,
            label: r.sportName,
            amountMinor: r.revenueMinor,
            pct: total == 0 ? 0 : r.revenueMinor / total * 100,
            onTap: r.facilitySportId == '__membership__'
                ? null
                : () => _drill(AppRoutes.reportsRevenue, sportId: r.facilitySportId),
          ),
      ],
    );
  }

  // ── Revenue by Court ───────────────────────────────────────────────────

  Widget _byCourtBody(BuildContext context) {
    final live = _byCourt.where((r) => r.revenueMinor > 0).toList();
    if (live.isEmpty) {
      return _emptyState(context,
          icon: Icons.grid_view_rounded,
          title: 'No court revenue in this period.',
          subtitle: 'Court-wise revenue will appear once there are bookings.');
    }
    final tokens = context.tokens;
    final total = live.fold<int>(0, (sum, r) => sum + r.revenueMinor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in live)
          _entityRow(
            context,
            icon: sportVisual(tokens, r.sportName).icon,
            accent: sportVisual(tokens, r.sportName).accent,
            label: '${r.sportName} · ${r.courtName}',
            amountMinor: r.revenueMinor,
            pct: total == 0 ? 0 : r.revenueMinor / total * 100,
            onTap: () => _drill(AppRoutes.reportsRevenue, courtId: r.courtId),
          ),
      ],
    );
  }

  Widget _entityRow(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String label,
    required int amountMinor,
    required double pct,
    VoidCallback? onTap,
  }) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tokens.accentFill(accent), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: tokens.textPrimary)),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: tokens.surface2,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(analyticsAmount(amountMinor),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: tokens.textPrimary)),
                const SizedBox(height: 2),
                Text('${pct.round()}%', style: AppTypography.caption(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, {required IconData icon, required String title, required String subtitle}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tokens.surface2, shape: BoxShape.circle),
            child: Icon(icon, size: 26, color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: tokens.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: AppTypography.caption(context)),
        ],
      ),
    );
  }
}

/// A ring chart drawn as stacked arcs — no chart package in pubspec.yaml, so
/// this follows [RevenueTrendChart]'s own precedent of a hand-rolled
/// [CustomPainter] rather than adding a dependency for one widget.
class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors, required this.trackColor});

  final List<int> values;
  final List<Color> colors;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 16.0;
    final ringRect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final total = values.fold<int>(0, (sum, v) => sum + v);

    if (total <= 0) {
      canvas.drawArc(
        ringRect,
        0,
        6.2832,
        false,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      return;
    }

    var start = -1.5708; // -90deg, 12 o'clock
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = (values[i] / total) * 6.28319;
      canvas.drawArc(
        ringRect,
        start,
        sweep,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors || oldDelegate.trackColor != trackColor;
}

/// Shaped placeholder for the loading branch — mirrors the real ready
/// body's 2x2 KPI grid, trend-chart card, breakdown card, 3 payment-method
/// tiles and the by-sport/by-court card lists.
class _RevenueReportSkeleton extends StatelessWidget {
  const _RevenueReportSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Expanded(child: SkeletonStatTile()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonStatTile()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: const [
            Expanded(child: SkeletonStatTile()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonStatTile()),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 120, height: 15),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonCard(child: AppSkeleton(height: 160)),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 150, height: 15),
        const SizedBox(height: AppSpacing.sm),
        SkeletonCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const AppSkeleton(width: 110, height: 110, radius: 55),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  children: List.generate(
                    4,
                    (_) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: AppSkeleton(height: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 150, height: 15),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: const [
            Expanded(child: SkeletonStatTile(height: 110)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile(height: 110)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile(height: 110)),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 140, height: 15),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 140, height: 15),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(),
      ],
    );
  }
}

/// Back button + title/subtitle + a solid green date pill — matches Court
/// Utilization's own header exactly (same premium layout for every Reports
/// screen), reusing the same preset picker sheet as [AnalyticsFilterControls].
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
                  Text('Revenue Report', style: AppTypography.heading1(context)),
                  const SizedBox(height: 2),
                  Text('Track your earnings and payments', style: AppTypography.secondary(context)),
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
                            fontSize: 13, fontWeight: FontWeight.w700, color: tokens.onAccent(tokens.primary))),
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
