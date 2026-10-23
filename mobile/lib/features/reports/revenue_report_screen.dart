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
import '../../shared/utils/csv_export.dart';
import '../../shared/widgets/app_metric_card.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../finance/revenue_trend_chart.dart';
import 'analytics_filter.dart';
import 'analytics_filter_controls.dart';
import 'report_section_header.dart';
import 'report_shell.dart';
import 'sport_visuals.dart';
import '../../shared/widgets/smooth_switcher.dart';
import '../../core/access/access.dart';

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
  List<RevenueTrendPoint> _trend = const [];
  ReportRevenueBreakdown? _breakdown;
  List<PaymentMethodSlice> _methods = const [];
  List<RevenueBySportRow> _bySport = const [];
  List<RevenueByCourtRow> _byCourt = const [];
  RevenueTrendGranularity? _granularityOverride;
  bool _exporting = false;
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

  Future<void> _export() async {
    final x = _summary;
    if (x == null) return;
    setState(() => _exporting = true);
    try {
      String inr(int minor) => (minor / 100).toStringAsFixed(2);
      final b = _breakdown;
      final rows = <List<Object?>>[
        ['Section', 'Label', 'Value'],
        ['Period', 'From', _filter.startDate],
        ['Period', 'To', _filter.endDate],
        ['Summary', 'Total Revenue (INR)', inr(x.grossMinor)],
        ['Summary', 'Refunds (INR)', inr(x.refundsMinor)],
        ['Summary', 'Net Revenue (INR)', inr(x.netMinor)],
        ['Summary', 'Expenses (INR)', inr(x.expensesMinor)],
        if (b != null) ['Breakdown', 'Memberships (INR)', inr(b.membershipMinor)],
        for (final m in _methods) ['Payment methods', '${m.method} (${m.count})', inr(m.amountMinor)],
        for (final r in _bySport) ['Revenue by sport', r.sportName, inr(r.revenueMinor)],
        for (final r in _byCourt) ['Revenue by court', '${r.courtName} · ${r.sportName}', inr(r.revenueMinor)],
        for (final t in _trend) ['Revenue trend', t.date, inr(t.netMinor)],
      ];
      await saveCsv(context, fileName: 'revenue_${_filter.startDate}_to_${_filter.endDate}.csv', rows: rows);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not export the report.')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _drill(String path, {String? sportId, String? courtId}) {
    context.push(
      '$path?${Uri(queryParameters: analyticsFilterToQuery(_filter.copyWith(facilitySportId: sportId, courtId: courtId))).query}',
    );
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
                      const _Header(),
                      const SizedBox(height: AppSpacing.lg),
                      AnalyticsFilterControls(
                        filter: _filter,
                        onChanged: _onFilterChanged,
                        trailing: !ref.watch(sessionControllerProvider).canEditPage(accessPageReportRevenue) ? null : OutlinedButton.icon(
                          onPressed: _summary == null || _exporting ? null : _export,
                          icon: _exporting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('Export'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SmoothSwitcher(child: KeyedSubtree(key: ValueKey(_status), child: switch (_status) {
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
                      })),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _body(BuildContext context) {
    final b = _breakdown;
    final sportRows = [..._bySport]..sort((a, c) => c.revenueMinor.compareTo(a.revenueMinor));

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
                  child: const Text('Clear Sport & Court'),
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
    final x = _summary!;
    final tokens = context.tokens;
    String money(num v) => analyticsAmount(v.round());
    final cards = <Widget>[
      AppMetricCard(
        label: 'Total Revenue',
        value: money(x.grossMinor),
        icon: Icons.paid_rounded,
        accentColor: tokens.primary,
        countTo: x.grossMinor,
        formatValue: money,
      ),
      AppMetricCard(
        label: 'Net Revenue',
        value: money(x.netMinor),
        icon: Icons.account_balance_wallet_rounded,
        accentColor: tokens.electricBlue,
        countTo: x.netMinor,
        formatValue: money,
        entranceDelay: const Duration(milliseconds: 60),
      ),
      AppMetricCard(
        label: 'Refunds',
        value: money(x.refundsMinor),
        icon: Icons.replay_rounded,
        accentColor: tokens.destructive,
        countTo: x.refundsMinor,
        formatValue: money,
        entranceDelay: const Duration(milliseconds: 120),
      ),
      AppMetricCard(
        label: 'Expenses',
        value: money(x.expensesMinor),
        icon: Icons.description_rounded,
        accentColor: tokens.warning,
        countTo: x.expensesMinor,
        formatValue: money,
        entranceDelay: const Duration(milliseconds: 180),
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - AppSpacing.md) / 2;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [for (final c in cards) SizedBox(width: width, child: c)],
      );
    });
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
          title: 'No Sport Revenue',
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
            icon: r.facilitySportId == null ? Icons.link_off_rounded : sportVisual(tokens, r.sportName).icon,
            accent: r.facilitySportId == null ? tokens.textSecondary : sportVisual(tokens, r.sportName).accent,
            label: r.sportName,
            amountMinor: r.revenueMinor,
            pct: total == 0 ? 0 : r.revenueMinor / total * 100,
            onTap: null,
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
  const _Header();

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
                  Text('Track Your Earnings and Payments', style: AppTypography.secondary(context)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

