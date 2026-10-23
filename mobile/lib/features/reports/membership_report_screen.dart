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
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'analytics_filter.dart';
import 'analytics_filter_controls.dart';
import 'membership_timing.dart';
import 'report_section_header.dart';
import 'report_shell.dart';
import 'report_widgets.dart';
import '../../shared/widgets/smooth_switcher.dart';
import '../../core/access/access.dart';

const _allCourts = '__all__';

/// Reports → Memberships — mirrors
/// src/features/reports/components/membership-report.tsx.
///
/// Five member/money cards, the payment split, membership types, members by
/// sport and by court / turf, the timing list (filterable by court) and the
/// guest-release summary. Membership revenue is Finance's; every number is an
/// RPC field.
class MembershipReportScreen extends ConsumerStatefulWidget {
  const MembershipReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  ConsumerState<MembershipReportScreen> createState() => _MembershipReportScreenState();
}

class _MembershipReportScreenState extends ConsumerState<MembershipReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  ReportStatus _status = ReportStatus.loading;
  MembershipMemberCounts? _counts;
  MembershipAnalytics? _analytics;
  List<MembershipTypeRow> _byType = const [];
  GuestReleaseAnalytics? _guestRelease;
  List<MembershipBatchRow> _batches = const [];

  /// Narrows the timing list only — the rest of the report ignores it.
  String _timingCourt = _allCourts;
  bool _exporting = false;
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
        repo.getMembershipMemberCounts(facility.id, _filter),
        repo.getMembershipAnalytics(facility.id, _filter),
        repo.getMembershipsByType(facility.id, _filter),
        repo.getGuestReleaseAnalytics(facility.id, _filter),
        repo.getMembershipBatchBreakdown(facility.id, _filter),
      ]);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _counts = results[0] as MembershipMemberCounts;
        _analytics = results[1] as MembershipAnalytics;
        _byType = results[2] as List<MembershipTypeRow>;
        _guestRelease = results[3] as GuestReleaseAnalytics;
        _batches = results[4] as List<MembershipBatchRow>;
        _status = ReportStatus.ready;
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

  String _typeLabel(MembershipTypeRow r) =>
      r.planName == '—' ? _titleCase(r.membershipType) : '${_titleCase(r.membershipType)} · ${r.planName}';

  String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  Future<void> _export() async {
    final c = _counts, a = _analytics, g = _guestRelease;
    if (c == null || a == null || g == null) return;
    setState(() => _exporting = true);
    try {
      final rows = <List<Object?>>[
        ['Section', 'Label', 'Value'],
        ['Period', 'From', _filter.startDate],
        ['Period', 'To', _filter.endDate],
        ['Members', 'Total Members (registered or running in the dates)', c.total],
        ['Members', 'Active Members (not ended or cancelled by ${c.asOf})', c.active],
        ['Members', 'Inactive Members (ended or cancelled by then)', c.inactive],
        ['Payments', 'Membership Revenue (INR)', (a.membershipRevenueMinor / 100).toStringAsFixed(2)],
        ['Payments', 'Membership Outstanding (INR)', (a.outstandingMinor / 100).toStringAsFixed(2)],
        ['Payments', 'Paid', a.paidCount],
        ['Payments', 'Partially Paid', a.partiallyPaidCount],
        ['Payments', 'Pending', a.pendingCount],
        for (final r in _byType) ...[
          ['Membership Types', '${_typeLabel(r)} — members', r.count],
          ['Membership Types', '${_typeLabel(r)} — revenue (INR)', (r.revenueMinor / 100).toStringAsFixed(2)],
        ],
        for (final b in _batches)
          [
            'Members by sport, court and timing',
            b.batchId == null
                ? b.sportName
                : '${b.sportName} · ${b.courtName} · ${formatTiming(b.startTime, b.endTime)} (${formatDays(b.daysOfWeek)})',
            '${b.members} members, ${b.activeMembers} active',
          ],
        ['Guest release', 'Revenue (INR)', (g.revenueMinor / 100).toStringAsFixed(2)],
      ];
      await saveCsv(context, fileName: 'memberships_${_filter.startDate}_to_${_filter.endDate}.csv', rows: rows);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not export the report.')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
                        trailing: !ref.watch(sessionControllerProvider).canEditPage(accessPageReportMemberships) ? null : OutlinedButton.icon(
                          onPressed: _status != ReportStatus.ready || _exporting ? null : _export,
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
                            child: _MembershipReportSkeleton(),
                          ),
                        ReportStatus.error => Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xxl),
                            child: ErrorView(
                              message: 'Unable to load the membership report. Please try again.',
                              onRetry: _load,
                            ),
                          ),
                        _ => _body(context),
                      })),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _body(BuildContext context) {
    final c = _counts, a = _analytics, g = _guestRelease;
    if (c == null || a == null || g == null) return const SizedBox.shrink();
    final groups = groupByCourt(_batches);
    final courts = [
      for (final grp in groups)
        for (final court in grp.courts) (sport: grp.sportName, court: court),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cards(context, c, a),
        const SizedBox(height: AppSpacing.xl),
        ReportSectionHeader(
          title: 'Membership Payments',
          trailing: _link(context, 'Collect', () => context.push(AppRoutes.financePendingPayments)),
        ),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _payments(context, a)),
        const SizedBox(height: AppSpacing.xl),
        const ReportSectionHeader(title: 'Membership Types'),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _types(context)),
        const SizedBox(height: AppSpacing.xl),
        const ReportSectionHeader(title: 'Memberships by Sport'),
        const SizedBox(height: AppSpacing.sm),
        _card(
          context,
          child: groups.isEmpty
              ? _none(context)
              : ReportBarList(items: [
                  for (final grp in groups)
                    ReportBar(
                      label: grp.sportName,
                      value: grp.members,
                      color: _membersColor,
                      caption:
                          '${_plural(grp.members, 'member', 'members')} · ${_plural(grp.courts.length, 'court', 'courts')}',
                    ),
                ]),
        ),
        const SizedBox(height: AppSpacing.xl),
        const ReportSectionHeader(title: 'Memberships by Court / Turf'),
        const SizedBox(height: AppSpacing.sm),
        _card(
          context,
          child: courts.isEmpty
              ? _none(context)
              : ReportBarList(items: [
                  for (final e in courts)
                    ReportBar(
                      label: '${e.court.courtName} · ${e.sport}',
                      value: e.court.members,
                      color: _membersColor,
                      caption: _plural(e.court.members, 'member', 'members'),
                    ),
                ]),
        ),
        const SizedBox(height: AppSpacing.xl),
        ReportSectionHeader(title: 'Memberships by Timing', trailing: _courtFilter(courts)),
        const SizedBox(height: AppSpacing.sm),
        _timings(context, courts),
        const SizedBox(height: AppSpacing.xl),
        ReportSectionHeader(
          title: 'Guest Release',
          trailing: _link(
            context,
            'Guest details',
            () => context.push('${AppRoutes.reportsGuestBookings}?${Uri(queryParameters: analyticsFilterToQuery(_filter)).query}'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _card(context, child: _guest(context, g)),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  static const _membersColor = Color(0xFF8B5CF6);

  // ── Cards ──────────────────────────────────────────────────────────────

  Widget _cards(BuildContext context, MembershipMemberCounts c, MembershipAnalytics a) {
    final tokens = context.tokens;
    String count(num v) => '${v.round()}';
    final items = <Widget>[
      AppMetricCard(
        label: 'Total Members',
        value: '${c.total}',
        icon: Icons.groups_rounded,
        accentColor: tokens.electricBlue,
        countTo: c.total,
        formatValue: count,
      ),
      AppMetricCard(
        label: 'Active Members',
        value: '${c.active}',
        icon: Icons.how_to_reg_rounded,
        accentColor: tokens.success,
        countTo: c.active,
        formatValue: count,
        entranceDelay: const Duration(milliseconds: 60),
      ),
      AppMetricCard(
        label: 'Inactive Members',
        value: '${c.inactive}',
        icon: Icons.person_off_rounded,
        accentColor: tokens.violet,
        countTo: c.inactive,
        formatValue: count,
        entranceDelay: const Duration(milliseconds: 120),
      ),
      AppMetricCard(
        label: 'Membership Revenue',
        value: analyticsAmount(a.membershipRevenueMinor),
        icon: Icons.savings_rounded,
        accentColor: tokens.primary,
        countTo: a.membershipRevenueMinor,
        formatValue: (v) => analyticsAmount(v.round()),
        entranceDelay: const Duration(milliseconds: 180),
      ),
      AppMetricCard(
        label: 'Membership Outstanding',
        value: analyticsAmount(a.outstandingMinor),
        icon: Icons.credit_card_rounded,
        accentColor: tokens.destructive,
        countTo: a.outstandingMinor,
        formatValue: (v) => analyticsAmount(v.round()),
        entranceDelay: const Duration(milliseconds: 240),
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - AppSpacing.md) / 2;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [for (final w in items) SizedBox(width: width, child: w)],
      );
    });
  }

  // ── Shared pieces ──────────────────────────────────────────────────────

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

  Widget _none(BuildContext context) =>
      Text('No membership timings in these dates.', style: AppTypography.secondary(context));

  Widget _link(BuildContext context, String label, VoidCallback onTap) {
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

  // ── Payments ───────────────────────────────────────────────────────────

  Widget _payments(BuildContext context, MembershipAnalytics a) {
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
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(s.label, style: TextStyle(fontSize: 13.5, color: tokens.textPrimary))),
                Text('${s.count} (${total == 0 ? 0 : (s.count / total * 100).round()}%)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (total == 0)
                  Expanded(child: ColoredBox(color: tokens.surface2))
                else
                  for (final s in slices)
                    if (s.count > 0) Expanded(flex: s.count, child: ColoredBox(color: s.color)),
              ],
            ),
          ),
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

  // ── Types ──────────────────────────────────────────────────────────────

  Widget _types(BuildContext context) {
    if (_byType.isEmpty) {
      return Text('No new memberships in this period.', style: AppTypography.secondary(context));
    }
    final tokens = context.tokens;
    final sorted = [..._byType]..sort((a, b) => b.count.compareTo(a.count));
    return Column(
      children: [
        for (var i = 0; i < sorted.length; i++) ...[
          if (i > 0) Divider(height: AppSpacing.lg, color: tokens.borderColor),
          Row(
            children: [
              Expanded(
                child: Text(_typeLabel(sorted[i]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: tokens.textPrimary)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(analyticsAmount(sorted[i].revenueMinor),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: tokens.textPrimary)),
                  Text(_plural(sorted[i].count, 'membership', 'memberships'),
                      style: AppTypography.caption(context)),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Timings ────────────────────────────────────────────────────────────

  String _courtKey(String sport, String court) => '$sport|$court';

  Widget? _courtFilter(List<({String sport, TimingCourt court})> courts) {
    if (courts.length < 2) return null;
    final duplicate = {
      for (final e in courts) e.court.courtName: courts.where((x) => x.court.courtName == e.court.courtName).length > 1,
    };
    String label(({String sport, TimingCourt court}) e) =>
        duplicate[e.court.courtName]! ? '${e.court.courtName} · ${e.sport}' : e.court.courtName;
    final active = courts.any((e) => _courtKey(e.sport, e.court.courtName) == _timingCourt) ? _timingCourt : _allCourts;
    final current = active == _allCourts
        ? 'All courts / turfs'
        : label(courts.firstWhere((e) => _courtKey(e.sport, e.court.courtName) == active));
    return PickerChip(
      label: current,
      onSelect: () async {
        final picked = await showPickerSheet<String>(
          context: context,
          selected: active,
          options: [
            (value: _allCourts, label: 'All courts / turfs'),
            for (final e in courts) (value: _courtKey(e.sport, e.court.courtName), label: label(e)),
          ],
        );
        if (picked != null && mounted) setState(() => _timingCourt = picked);
      },
    );
  }

  Widget _timings(BuildContext context, List<({String sport, TimingCourt court})> courts) {
    final tokens = context.tokens;
    final active = courts.any((e) => _courtKey(e.sport, e.court.courtName) == _timingCourt) ? _timingCourt : _allCourts;
    final rows = [
      for (final e in courts)
        if (active == _allCourts || _courtKey(e.sport, e.court.courtName) == active)
          for (final t in e.court.timings) (sport: e.sport, court: e.court.courtName, t: t),
    ];
    final unassigned = _batches.where((b) => b.batchId == null && b.members > 0).firstOrNull;

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Members by the timing they are booked into (members counted for the selected dates)',
              style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.md),
          if (rows.isEmpty)
            _none(context)
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: AppSpacing.lg, color: tokens.borderColor),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _membersColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.schedule_rounded, size: 18, color: _membersColor),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatTiming(rows[i].t.startTime, rows[i].t.endTime),
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: tokens.textPrimary)),
                        const SizedBox(height: 2),
                        Text(formatDays(rows[i].t.daysOfWeek), style: AppTypography.caption(context)),
                        Text('${rows[i].court} · ${rows[i].sport}', style: AppTypography.caption(context)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_plural(rows[i].t.members, 'member', 'members'),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: tokens.textPrimary)),
                      Text('${rows[i].t.activeMembers} active',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.success)),
                    ],
                  ),
                ],
              ),
            ],
          if (unassigned != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              '${unassigned.members} ${unassigned.members == 1 ? 'member is' : 'members are'} not assigned to any session timing.',
              style: AppTypography.caption(context),
            ),
          ],
        ],
      ),
    );
  }

  // ── Guest release ──────────────────────────────────────────────────────

  Widget _guest(BuildContext context, GuestReleaseAnalytics g) {
    final tokens = context.tokens;
    final tiles = <({String label, int value, IconData icon, Color accent})>[
      (label: 'Released', value: g.released, icon: Icons.person_rounded, accent: tokens.primary),
      (label: 'Booked', value: g.booked, icon: Icons.event_available_rounded, accent: tokens.electricBlue),
      (label: 'Remaining', value: g.remaining, icon: Icons.schedule_rounded, accent: tokens.warning),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      Text('${tiles[i].value}',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: tokens.textPrimary)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Text('Guest revenue  ', style: AppTypography.caption(context)),
            Text(analyticsAmount(g.revenueMinor),
                style: TextStyle(fontWeight: FontWeight.w800, color: tokens.textPrimary)),
          ],
        ),
      ],
    );
  }
}

class _MembershipReportSkeleton extends StatelessWidget {
  const _MembershipReportSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget statRow() => const Row(
          children: [
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
        const Row(children: [Expanded(child: SkeletonStatTile()), Spacer()]),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 160, height: 15),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonCard(child: AppSkeleton(height: 90)),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 150, height: 15),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(),
      ],
    );
  }
}

/// Back button + title/subtitle.
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
        Text('Membership Report', style: AppTypography.heading1(context)),
        const SizedBox(height: 2),
        Text('Members, revenue and what is still owed', style: AppTypography.secondary(context)),
      ],
    );
  }
}
