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

/// Reports → Memberships — mirrors
/// src/features/reports/components/membership-report.tsx.
///
/// Membership revenue is Finance's (folded into get_membership_analytics via
/// get_revenue_breakdown). Session usage is never revenue — member
/// allocations are a capacity figure. Every number is an RPC field.
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
  List<MembershipTypeRow> _byType = const [];
  MembershipSessionAnalytics? _session;
  GuestReleaseAnalytics? _guestRelease;
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
        _guestRelease = results[3] as GuestReleaseAnalytics;
        _status = analytics.activeMembers == 0 && analytics.newMemberships == 0 && session.sessionCount == 0
            ? ReportStatus.empty
            : ReportStatus.ready;
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

  String _titleCase(String s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

  int get _sessionUtilPct {
    final s = _session;
    if (s == null || s.totalCapacity == 0) return 0;
    return ((s.memberAllocations + s.guestBooked) / s.totalCapacity * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final a = _analytics;
    final s = _session;
    final g = _guestRelease;
    return ReportShell(
      title: 'Membership Report',
      status: _status,
      filter: _filter,
      onFilterChanged: _onFilterChanged,
      onRetry: _load,
      emptyMessage: 'No membership activity for this period.',
      errorMessage: 'Unable to load the membership report. Please try again.',
      body: a == null || s == null || g == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReportKpiGrid(items: [
                  ReportKpi(label: 'Active Members', value: a.activeMembers.toString()),
                  ReportKpi(label: 'New Memberships', value: a.newMemberships.toString()),
                  ReportKpi(label: 'Expiring Soon', value: a.expiringSoon.toString()),
                  ReportKpi(label: 'Membership Revenue', value: analyticsAmount(a.membershipRevenueMinor)),
                  ReportKpi(label: 'Membership Outstanding', value: analyticsAmount(a.outstandingMinor)),
                  ReportKpi(label: 'Session Utilization', value: '$_sessionUtilPct%'),
                ]),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Membership Payments'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReportDataTable(
                        caption: 'Membership payment completion',
                        columns: const [ReportColumn(label: 'Status'), ReportColumn(label: 'Count', numeric: true)],
                        rows: [
                          ['Paid', a.paidCount.toString()],
                          ['Partially paid', a.partiallyPaidCount.toString()],
                          ['Pending', a.pendingCount.toString()],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Text('Outstanding: ${analyticsAmount(a.outstandingMinor)}',
                              style: AppTypography.caption(context)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => context.push(AppRoutes.financePendingPayments),
                            child: const Text('Collect'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Membership Types'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _byTypeBody()),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Membership Sessions'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReportDataTable(
                        caption: 'Membership session capacity',
                        columns: const [ReportColumn(label: 'Metric'), ReportColumn(label: 'Slots', numeric: true)],
                        rows: [
                          ['Total capacity', s.totalCapacity.toString()],
                          ['Member allocations', s.memberAllocations.toString()],
                          ['Guest released', s.guestReleased.toString()],
                          ['Guest booked', s.guestBooked.toString()],
                          ['Remaining released', s.remainingReleased.toString()],
                          ['Unused capacity', s.unusedCapacity.toString()],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Session usage is capacity, not revenue — member allocations are never counted as income.',
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(
                  title: 'Guest Release',
                  trailing: TextButton(
                    onPressed: () => context.push(
                      '${AppRoutes.reportsGuestBookings}?${Uri(queryParameters: analyticsFilterToQuery(_filter)).query}',
                    ),
                    child: const Text('Guest detail'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: ReportDataTable(
                    caption: 'Guest release capacity',
                    columns: const [ReportColumn(label: 'Metric'), ReportColumn(label: 'Value', numeric: true)],
                    rows: [
                      ['Released', g.released.toString()],
                      ['Booked', g.booked.toString()],
                      ['Remaining', g.remaining.toString()],
                      ['Revenue', analyticsAmount(g.revenueMinor)],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  Widget _byTypeBody() {
    if (_byType.isEmpty) {
      return Text('No new memberships in this period.', style: AppTypography.secondary(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportBarList(
          items: [
            for (final r in _byType)
              ReportBar(
                label: r.planName == '—' ? _titleCase(r.membershipType) : '${_titleCase(r.membershipType)} · ${r.planName}',
                value: r.count,
                caption: '${r.count} · ${analyticsAmount(r.revenueMinor)}',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportDataTable(
          caption: 'Memberships by type',
          columns: const [
            ReportColumn(label: 'Type'),
            ReportColumn(label: 'Plan'),
            ReportColumn(label: 'Count', numeric: true),
            ReportColumn(label: 'Revenue', numeric: true),
          ],
          rows: [
            for (final r in _byType)
              [_titleCase(r.membershipType), r.planName, r.count.toString(), analyticsAmount(r.revenueMinor)],
          ],
        ),
      ],
    );
  }
}
