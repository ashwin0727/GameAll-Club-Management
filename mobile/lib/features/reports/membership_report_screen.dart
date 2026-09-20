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
import 'analytics_filter.dart';
import 'analytics_filter_controls.dart';
import 'report_section_header.dart';
import 'report_shell.dart';

enum _SessionView { total, utilized, remaining }

enum _GrowthTab { members, revenue, expiring }

/// Reports → Memberships — mirrors
/// src/features/reports/components/membership-report.tsx.
///
/// Membership revenue is Finance's (folded into get_membership_analytics via
/// get_revenue_breakdown). Session usage is never revenue — member
/// allocations are a capacity figure. Every number is an RPC field.
///
/// This screen owns its own header/scaffold (title + subtitle + a solid
/// date pill), matching Court Utilization and Revenue's premium layout,
/// rather than [ReportShell]'s generic AppBar.
///
/// The reference design's "Membership Growth" section is a day-by-day trend
/// line plus a cancellation count — neither figure exists yet (the
/// membership RPCs only return this-period snapshot totals, no daily
/// series, no cancelled count), so that section renders as a real-data
/// snapshot (the same three counts as the KPI grid, as coloured chips)
/// instead of a fabricated chart.
class MembershipReportScreen extends ConsumerStatefulWidget {
  const MembershipReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  ConsumerState<MembershipReportScreen> createState() => _MembershipReportScreenState();
}

class _MembershipReportScreenState extends ConsumerState<MembershipReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  ReportStatus _status = ReportStatus.loading;
  MembershipAnalytics? _analytics;
  MembershipAnalytics? _previousAnalytics;
  List<MembershipTypeRow> _byType = const [];
  MembershipSessionAnalytics? _session;
  MembershipSessionAnalytics? _previousSession;
  GuestReleaseAnalytics? _guestReleaseAnalytics;
  _SessionView _sessionView = _SessionView.total;
  _GrowthTab _growthTab = _GrowthTab.members;
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
        repo.getMembershipAnalytics(facility.id, _filter),
        repo.getMembershipsByType(facility.id, _filter),
        repo.getMembershipSessionAnalytics(facility.id, _filter),
        repo.getGuestReleaseAnalytics(facility.id, _filter),
      ]);
      if (!mounted || requestId != _requestId) return;
      final analytics = results[0] as MembershipAnalytics;
      final session = results[2] as MembershipSessionAnalytics;
      setState(() {
        _analytics = analytics;
        _byType = results[1] as List<MembershipTypeRow>;
        _session = session;
        _guestReleaseAnalytics = results[3] as GuestReleaseAnalytics;
        _status = analytics.activeMembers == 0 && analytics.newMemberships == 0 && session.sessionCount == 0
            ? ReportStatus.empty
            : ReportStatus.ready;
      });

      final prevFilter = previousAnalyticsPeriod(_filter);
      if (prevFilter != null) {
        try {
          final prevResults = await Future.wait([
            repo.getMembershipAnalytics(facility.id, prevFilter),
            repo.getMembershipSessionAnalytics(facility.id, prevFilter),
          ]);
          if (mounted && requestId == _requestId) {
            setState(() {
              _previousAnalytics = prevResults[0] as MembershipAnalytics;
              _previousSession = prevResults[1] as MembershipSessionAnalytics;
            });
          }
        } catch (_) {
          if (mounted && requestId == _requestId) {
            setState(() {
              _previousAnalytics = null;
              _previousSession = null;
            });
          }
        }
      } else if (mounted && requestId == _requestId) {
        setState(() {
          _previousAnalytics = null;
          _previousSession = null;
        });
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

  String _titleCase(String s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

  int _sessionUtilPctOf(MembershipSessionAnalytics? s) {
    if (s == null || s.totalCapacity == 0) return 0;
    return ((s.memberAllocations + s.guestBooked) / s.totalCapacity * 100).round();
  }

  double? _pct(num current, num? previous) {
    if (previous == null) return null;
    return analyticsChangePct(current: current, previous: previous);
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
                            child: _MembershipReportSkeleton(),
                          ),
                        ReportStatus.error => Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xxl),
                            child: ErrorView(
                              message: 'Unable to load the membership report. Please try again.',
                              onRetry: _load,
                            ),
                          ),
                        ReportStatus.empty => const Padding(
                            padding: EdgeInsets.only(top: AppSpacing.xxl),
                            child: EmptyStateView(message: 'No membership activity for this period.'),
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
    final a = _analytics!;
    final s = _session!;
    final g = _guestReleaseAnalytics!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kpiGrid(context, a, s),
        const SizedBox(height: AppSpacing.xl),
        ReportSectionHeader(title: 'Membership Growth', trailing: _growthTabToggle(context)),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _growthChart(context, a)),
        const SizedBox(height: AppSpacing.xl),
        ReportSectionHeader(
          title: 'Membership Payments',
          trailing: _viewAllLink(context, 'Collect Payments', () => context.push(AppRoutes.financePendingPayments)),
        ),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _membershipPayments(context, a)),
        const SizedBox(height: AppSpacing.xl),
        const ReportSectionHeader(title: 'Membership Types'),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _byTypeBody(context)),
        const SizedBox(height: AppSpacing.xl),
        ReportSectionHeader(title: 'Membership Sessions', trailing: _sessionViewToggle(context)),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _sessionsGrid(context, s)),
        const SizedBox(height: AppSpacing.xl),
        ReportSectionHeader(
          title: 'Guest Release',
          trailing: _viewAllLink(
            context,
            'Guest details',
            () => context.push('${AppRoutes.reportsGuestBookings}?${Uri(queryParameters: analyticsFilterToQuery(_filter)).query}'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _guestRelease(context, g)),
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

  Widget _kpiGrid(BuildContext context, MembershipAnalytics a, MembershipSessionAnalytics s) {
    final tokens = context.tokens;
    final pa = _previousAnalytics;
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _kpiCard(
                  context,
                  icon: Icons.groups_rounded,
                  accent: tokens.primary,
                  label: 'Active Members',
                  value: a.activeMembers.toString(),
                  pct: _pct(a.activeMembers, pa?.activeMembers),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _kpiCard(
                  context,
                  icon: Icons.person_add_alt_1_rounded,
                  accent: tokens.electricBlue,
                  label: 'New Memberships',
                  value: a.newMemberships.toString(),
                  pct: _pct(a.newMemberships, pa?.newMemberships),
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
                  icon: Icons.schedule_rounded,
                  accent: tokens.warning,
                  label: 'Expiring Soon',
                  value: a.expiringSoon.toString(),
                  pct: _pct(a.expiringSoon, pa?.expiringSoon),
                  invert: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _kpiCard(
                  context,
                  icon: Icons.savings_rounded,
                  accent: tokens.success,
                  label: 'Membership Revenue',
                  value: analyticsAmount(a.membershipRevenueMinor),
                  pct: _pct(a.membershipRevenueMinor, pa?.membershipRevenueMinor),
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
                  icon: Icons.credit_card_rounded,
                  accent: tokens.destructive,
                  label: 'Membership Outstanding',
                  value: analyticsAmount(a.outstandingMinor),
                  pct: _pct(a.outstandingMinor, pa?.outstandingMinor),
                  invert: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _kpiCard(
                  context,
                  icon: Icons.pie_chart_rounded,
                  accent: tokens.violet,
                  label: 'Session Utilization',
                  value: '${_sessionUtilPctOf(s)}%',
                  pct: _pct(_sessionUtilPctOf(s), _previousSession == null ? null : _sessionUtilPctOf(_previousSession)),
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
          Positioned(
            right: -4,
            bottom: -4,
            child: Icon(Icons.show_chart_rounded, size: 42, color: accent.withValues(alpha: 0.14)),
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

  // ── Membership Growth ──────────────────────────────────────────────────
  //
  // The reference design's line traces a DAILY series; no RPC returns one
  // for memberships (get_membership_analytics is a single this-period
  // snapshot). What IS real: this period's totals and — already fetched,
  // for the KPI deltas — the prior period's. Plotting exactly those two
  // points (prior → current) gives a genuine, server-sourced line rather
  // than an invented daily shape; a facility with a mapped prior period
  // (rolling presets, or a custom range) gets a real two-point trend, and
  // one without (e.g. "This Year") still gets a real single point, drawn
  // the same anchored-from-zero way [RevenueTrendChart] draws a lone day.

  ({int? previous, int current, Color color}) _growthSeries(MembershipAnalytics a) {
    final pa = _previousAnalytics;
    switch (_growthTab) {
      case _GrowthTab.members:
        return (previous: pa?.activeMembers, current: a.activeMembers, color: context.tokens.primary);
      case _GrowthTab.revenue:
        return (
          previous: pa == null ? null : (pa.membershipRevenueMinor / 100).round(),
          current: (a.membershipRevenueMinor / 100).round(),
          color: context.tokens.success,
        );
      case _GrowthTab.expiring:
        return (previous: pa?.expiringSoon, current: a.expiringSoon, color: context.tokens.warning);
    }
  }

  String _growthValueLabel(int value) =>
      _growthTab == _GrowthTab.revenue ? analyticsAmount(value * 100) : value.toString();

  Widget _growthTabToggle(BuildContext context) {
    final tokens = context.tokens;
    Widget seg(String label, _GrowthTab tab) {
      final active = _growthTab == tab;
      return GestureDetector(
        onTap: () => setState(() => _growthTab = tab),
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
          seg('Members', _GrowthTab.members),
          seg('Revenue', _GrowthTab.revenue),
          seg('Expiring', _GrowthTab.expiring),
        ],
      ),
    );
  }

  Widget _growthChart(BuildContext context, MembershipAnalytics a) {
    final tokens = context.tokens;
    final series = _growthSeries(a);
    final prevFilter = previousAnalyticsPeriod(_filter);
    final leftLabel = prevFilter?.preset.label ?? 'Before';
    final rightLabel = _filter.preset.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GrowthLineChart(
          previous: series.previous,
          current: series.current,
          color: series.color,
          leftLabel: leftLabel,
          rightLabel: rightLabel,
          valueLabel: _growthValueLabel,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _growthLegendItem(context,
                  color: tokens.primary, value: a.activeMembers.toString(), label: 'Active Members'),
            ),
            Expanded(
              child: _growthLegendItem(context,
                  color: tokens.electricBlue, value: a.newMemberships.toString(), label: 'New Memberships'),
            ),
            Expanded(
              child: _growthLegendItem(context,
                  color: tokens.warning, value: a.expiringSoon.toString(), label: 'Expiring Soon'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _growthLegendItem(BuildContext context, {required Color color, required String value, required String label}) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: tokens.textPrimary)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.caption(context)),
      ],
    );
  }

  // ── Membership Payments — donut + legend ──────────────────────────────

  Widget _membershipPayments(BuildContext context, MembershipAnalytics a) {
    final tokens = context.tokens;
    final slices = <({String label, int count, Color color})>[
      (label: 'Paid', count: a.paidCount, color: tokens.primary),
      (label: 'Partially paid', count: a.partiallyPaidCount, color: tokens.electricBlue),
      (label: 'Pending', count: a.pendingCount, color: tokens.warning),
    ];
    final total = slices.fold<int>(0, (sum, s) => sum + s.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 116,
              height: 116,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(116, 116),
                    painter: _DonutPainter(
                      values: [for (final s in slices) s.count],
                      colors: [for (final s in slices) s.color],
                      trackColor: tokens.surface2,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(total.toString(),
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                      Text('Total', style: AppTypography.caption(context)),
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
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(s.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: tokens.textPrimary)),
                          ),
                          Text('${s.count} (${total == 0 ? 0 : (s.count / total * 100).round()}%)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Text('Outstanding  ', style: AppTypography.caption(context)),
            Text(analyticsAmount(a.outstandingMinor),
                style: TextStyle(fontWeight: FontWeight.w800, color: tokens.textPrimary)),
          ],
        ),
      ],
    );
  }

  // ── Membership Types ───────────────────────────────────────────────────

  Widget _byTypeBody(BuildContext context) {
    if (_byType.isEmpty) {
      return Text('No new memberships in this period.', style: AppTypography.secondary(context));
    }
    final tokens = context.tokens;
    final total = _byType.fold<int>(0, (sum, r) => sum + r.count);
    final sorted = [..._byType]..sort((a, b) => b.count.compareTo(a.count));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in sorted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: tokens.accentFill(tokens.primary), shape: BoxShape.circle),
                  child: Icon(_membershipTypeIcon(r.membershipType), size: 18, color: tokens.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                                r.planName == '—'
                                    ? _titleCase(r.membershipType)
                                    : '${_titleCase(r.membershipType)} · ${r.planName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: tokens.textPrimary)),
                          ),
                          Text(analyticsAmount(r.revenueMinor),
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: tokens.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${r.count} member${r.count == 1 ? '' : 's'}', style: AppTypography.caption(context)),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : (r.count / total).clamp(0, 1).toDouble(),
                          minHeight: 6,
                          backgroundColor: tokens.surface2,
                          valueColor: AlwaysStoppedAnimation(tokens.primary),
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

  IconData _membershipTypeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('family')) return Icons.diversity_1_rounded;
    if (t.contains('corporate') || t.contains('business')) return Icons.business_rounded;
    if (t.contains('couple') || t.contains('duo')) return Icons.people_alt_rounded;
    if (t.contains('student')) return Icons.school_rounded;
    return Icons.person_rounded;
  }

  // ── Membership Sessions ────────────────────────────────────────────────

  Widget _sessionViewToggle(BuildContext context) {
    final tokens = context.tokens;
    Widget seg(String label, _SessionView v) {
      final active = _sessionView == v;
      return GestureDetector(
        onTap: () => setState(() => _sessionView = v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: active ? tokens.accentSolid(tokens.primary) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
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
          seg('Total', _SessionView.total),
          seg('Utilized', _SessionView.utilized),
          seg('Remaining', _SessionView.remaining),
        ],
      ),
    );
  }

  Widget _sessionsGrid(BuildContext context, MembershipSessionAnalytics s) {
    final tokens = context.tokens;
    final tiles = <({String label, int value, IconData icon, Color accent, _SessionView group})>[
      (label: 'Total capacity', value: s.totalCapacity, icon: Icons.groups_rounded, accent: tokens.primary, group: _SessionView.total),
      (label: 'Member allocations', value: s.memberAllocations, icon: Icons.person_pin_rounded, accent: tokens.violet, group: _SessionView.utilized),
      (label: 'Guest released', value: s.guestReleased, icon: Icons.no_accounts_rounded, accent: tokens.primary, group: _SessionView.total),
      (label: 'Guest booked', value: s.guestBooked, icon: Icons.person_add_alt_1_rounded, accent: tokens.violet, group: _SessionView.utilized),
      (label: 'Remaining released', value: s.remainingReleased, icon: Icons.person_outline_rounded, accent: tokens.warning, group: _SessionView.remaining),
      (label: 'Unused capacity', value: s.unusedCapacity, icon: Icons.hexagon_outlined, accent: tokens.electricBlue, group: _SessionView.remaining),
    ];

    Widget tile(int i) {
      final t = tiles[i];
      final on = _sessionView == _SessionView.total || _sessionView == t.group;
      return Opacity(
        opacity: on ? 1 : 0.4,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(color: tokens.surface2, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tokens.accentFill(t.accent), shape: BoxShape.circle),
                child: Icon(t.icon, size: 15, color: t.accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context)),
                    Text(t.value.toString(),
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: tokens.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget row(int a, int b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tile(a)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: tile(b)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(0, 1),
        const SizedBox(height: AppSpacing.sm),
        row(2, 3),
        const SizedBox(height: AppSpacing.sm),
        row(4, 5),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 15, color: tokens.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Session usage is capacity, not revenue — member allocations are never counted as income.',
                style: AppTypography.caption(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Guest Release ───────────────────────────────────────────────────────

  Widget _guestRelease(BuildContext context, GuestReleaseAnalytics g) {
    final tokens = context.tokens;
    final tiles = <({String label, int value, IconData icon, Color accent})>[
      (label: 'Released', value: g.released, icon: Icons.person_rounded, accent: tokens.primary),
      (label: 'Booked', value: g.booked, icon: Icons.event_available_rounded, accent: tokens.electricBlue),
      (label: 'Remaining', value: g.remaining, icon: Icons.schedule_rounded, accent: tokens.warning),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: tokens.accentFill(tiles[i].accent), shape: BoxShape.circle),
                    child: Icon(tiles[i].icon, size: 15, color: tiles[i].accent),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(tiles[i].label, style: AppTypography.caption(context)),
                  Text(tiles[i].value.toString(),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: tokens.textPrimary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Membership Growth line — a real two-point trend (prior period →
/// this period) drawn with the same gridlines/gradient/dot/peak-bubble
/// language as [RevenueTrendChart], rather than a fabricated daily series.
/// When there's no mapped prior period, [previous] is null and the single
/// real point is anchored against an implied 0 on the left, the same
/// convention [RevenueTrendChart] uses for a facility's first day of data.
class _GrowthLineChart extends StatelessWidget {
  const _GrowthLineChart({
    required this.previous,
    required this.current,
    required this.color,
    required this.leftLabel,
    required this.rightLabel,
    required this.valueLabel,
  });

  final int? previous;
  final int current;
  final Color color;
  final String leftLabel;
  final String rightLabel;
  final String Function(int) valueLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final left = previous ?? 0;
    final scaleMax = [left, current, 1].reduce((a, b) => a > b ? a : b);
    final axisStyle = TextStyle(fontSize: 10, color: tokens.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                height: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(valueLabel(scaleMax), style: axisStyle),
                    Text(valueLabel((scaleMax / 2).round()), style: axisStyle),
                    Text('0', style: axisStyle),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 150,
                  child: LayoutBuilder(builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, constraints.maxHeight);
                    final leftY = size.height - (size.height * (left / scaleMax));
                    final rightY = size.height - (size.height * (current / scaleMax));
                    final plot = [Offset(0, leftY), Offset(size.width, rightY)];
                    const bubbleWidth = 62.0;
                    final bubbleLeft =
                        (plot.last.dx - bubbleWidth / 2).clamp(0.0, (size.width - bubbleWidth).clamp(0.0, double.infinity));

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CustomPaint(
                          size: size,
                          painter: _GrowthPainter(plot: plot, lineColor: color, gridColor: tokens.borderColor),
                        ),
                        Positioned(
                          left: bubbleLeft,
                          top: (plot.last.dy - 30).clamp(-8.0, size.height),
                          child: IgnorePointer(
                            child: Container(
                              width: bubbleWidth,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                              decoration: BoxDecoration(
                                color: tokens.surface1,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                border: Border.all(color: tokens.borderColor),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: Text(valueLabel(current),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(leftLabel, style: AppTypography.caption(context)),
              Text(rightLabel, style: AppTypography.caption(context)),
            ],
          ),
        ),
      ],
    );
  }
}

class _GrowthPainter extends CustomPainter {
  _GrowthPainter({required this.plot, required this.lineColor, required this.gridColor});

  final List<Offset> plot;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * (i / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final p0 = plot.first;
    final p1 = plot.last;
    final cx = (p0.dx + p1.dx) / 2;
    final linePath = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);

    final areaPath = Path.from(linePath)
      ..lineTo(p1.dx, size.height)
      ..lineTo(p0.dx, size.height)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withValues(alpha: 0.32), lineColor.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(p0, 4, Paint()..color = lineColor.withValues(alpha: 0.55));
    canvas.drawCircle(p1, 6, Paint()..color = lineColor.withValues(alpha: 0.22));
    canvas.drawCircle(p1, 3.5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(_GrowthPainter oldDelegate) => oldDelegate.plot != plot || oldDelegate.lineColor != lineColor;
}

/// A ring chart drawn as stacked arcs — no chart package in pubspec.yaml, so
/// this follows the Revenue report's own [CustomPainter] precedent.
class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors, required this.trackColor});

  final List<int> values;
  final List<Color> colors;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 14.0;
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

    var start = -1.5708;
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

/// Shaped placeholder for the loading branch — mirrors the ready body's
/// 6-tile KPI grid, growth-chart card, payments donut card, types list,
/// sessions grid and guest-release tiles.
class _MembershipReportSkeleton extends StatelessWidget {
  const _MembershipReportSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget statRow() => Row(
          children: const [
            Expanded(child: SkeletonStatTile()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonStatTile()),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        statRow(),
        const SizedBox(height: AppSpacing.md),
        statRow(),
        const SizedBox(height: AppSpacing.md),
        statRow(),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 160, height: 15),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonCard(child: AppSkeleton(height: 90)),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 170, height: 15),
        const SizedBox(height: AppSpacing.sm),
        SkeletonCard(
          child: Row(
            children: [
              const AppSkeleton(width: 90, height: 90, radius: 45),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  children: List.generate(
                    3,
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
        const SkeletonListRow(),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 170, height: 15),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: const [
            Expanded(child: SkeletonStatTile(height: 76)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile(height: 76)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: const [
            Expanded(child: SkeletonStatTile(height: 76)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile(height: 76)),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 130, height: 15),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: const [
            Expanded(child: SkeletonStatTile(height: 76)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile(height: 76)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonStatTile(height: 76)),
          ],
        ),
      ],
    );
  }
}

/// Back button + title/subtitle + a solid green date pill — matches Revenue
/// and Court Utilization's own header exactly, reusing the same preset
/// picker sheet as [AnalyticsFilterControls].
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
                  Text('Membership Report', style: AppTypography.heading1(context)),
                  const SizedBox(height: 2),
                  Text('Track, manage and grow your membership', style: AppTypography.secondary(context)),
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
