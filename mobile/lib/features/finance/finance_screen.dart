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
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/utils/csv_export.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_metric_card.dart';
import '../../shared/widgets/metric_trend_chart.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'finance_date_range_picker.dart';
import 'finance_period.dart';
import 'finance_presentation.dart';
import '../../shared/widgets/smooth_switcher.dart';

/// The Finance Dashboard — mirrors
/// src/features/finance/components/finance-dashboard.tsx.
///
/// Every figure comes from a backend RPC response field — this widget never
/// sums, subtracts or derives a monetary total. The only arithmetic here is
/// the period-over-period percentage, computed from two authoritative totals
/// (both fetched, never one derived from the other).
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  bool _isLoading = true;
  String? _loadError;
  String? _facilityId;

  FinanceDateRange _range = currentMonthRange();
  RevenueTrendGranularity _granularity = _granularityFor(currentMonthRange());

  FinanceSummary? _summary;
  FinanceSummary? _previous;
  RevenueBreakdown? _breakdown;
  List<PaymentMethodSlice>? _methods;
  List<RevenueTrendPoint>? _trend;
  List<FinanceTransaction> _recent = [];
  bool _rangeLoading = false;
  bool _exporting = false;
  String? _rangeError;

  /// Guards against a slow response for an earlier range landing after a
  /// faster one for the range the owner has since picked.
  int _rangeRequestId = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'No facility found for this account yet.';
      });
      return;
    }
    _facilityId = facility.id;
    setState(() => _isLoading = false);
    await _loadRange();
  }

  Future<void> _loadRange() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    // A half-picked CUSTOM range is not askable yet — the server would reject it.
    if (!_range.isComplete) return;

    final requestId = ++_rangeRequestId;
    setState(() {
      _rangeLoading = true;
      _rangeError = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      final results = await Future.wait([
        repo.getSummary(facilityId, _range),
        repo.getRevenueBreakdown(facilityId, _range),
        repo.getPaymentMethodBreakdown(facilityId, _range),
        repo.getRevenueTrend(facilityId, _range, _granularity),
        repo.listTransactions(
          ListTransactionsInput(facilityId: facilityId, dateRange: _range, limit: 5, offset: 0),
        ),
      ]);
      if (!mounted || requestId != _rangeRequestId) return;
      setState(() {
        _summary = results[0] as FinanceSummary;
        _breakdown = results[1] as RevenueBreakdown;
        _methods = results[2] as List<PaymentMethodSlice>;
        _trend = results[3] as List<RevenueTrendPoint>;
        _recent = (results[4] as TransactionPage).transactions;
        _rangeLoading = false;
      });

      // The comparison window: the same span immediately before this one.
      // Fetched rather than derived, so it is the server's total either way.
      // A missing comparison is not worth failing the page over.
      try {
        final previous = await repo.getSummary(facilityId, previousFinanceRange(_range));
        if (mounted && requestId == _rangeRequestId) setState(() => _previous = previous);
      } on AppException {
        if (mounted && requestId == _rangeRequestId) setState(() => _previous = null);
      }
    } on AppException catch (e) {
      if (!mounted || requestId != _rangeRequestId) return;
      setState(() {
        _rangeLoading = false;
        _rangeError = e.message;
      });
    }
  }

  Future<void> _refresh() => _loadRange();

  /// Readable buckets for the span: daily up to a month, weekly up to six, monthly beyond.
  static RevenueTrendGranularity _granularityFor(FinanceDateRange r) {
    final s = r.startDate, e = r.endDate;
    if (s == null || e == null) return RevenueTrendGranularity.daily;
    final days = DateTime.parse(e).difference(DateTime.parse(s)).inDays + 1;
    if (days <= 31) return RevenueTrendGranularity.daily;
    if (days <= 183) return RevenueTrendGranularity.weekly;
    return RevenueTrendGranularity.monthly;
  }

  Future<void> _export() async {
    final s = _summary;
    if (s == null) return;
    setState(() => _exporting = true);
    try {
      final b = _breakdown;
      final rows = <List<Object?>>[
        ['Finance report', '${_range.startDate} to ${_range.endDate}'],
        [],
        ['Section', 'Item', 'Amount (INR)'],
        ['Summary', 'Total revenue', s.grossRevenueMinor / 100],
        ['Summary', 'Refunds', s.refundsMinor / 100],
        ['Summary', 'Total expenses', s.expensesMinor / 100],
        ['Summary', 'Net revenue', s.netRevenueMinor / 100],
        ['Summary', 'Pending payments', s.outstandingMinor / 100],
        if (b != null) ...[
          ['Revenue breakdown', 'Guest bookings', b.guestBookingRevenueMinor / 100],
          ['Revenue breakdown', 'Memberships', b.membershipRevenueMinor / 100],
          ['Revenue breakdown', 'Member bookings', b.memberBookingRevenueMinor / 100],
          ['Revenue breakdown', 'Coaching', b.coachingRevenueMinor / 100],
          ['Revenue breakdown', 'Refunds', b.refundsMinor / 100],
        ],
        for (final m in _methods ?? const <PaymentMethodSlice>[])
          ['Payment methods', '${m.paymentMethod} (${m.paymentCount})', m.amountMinor / 100],
        for (final t in _trend ?? const <RevenueTrendPoint>[]) ['Revenue trend', t.date, t.netMinor / 100],
      ];
      await saveCsv(context, fileName: 'finance_${_range.startDate}_to_${_range.endDate}.csv', rows: rows);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not export the report.')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _onRangeChanged(FinanceDateRange next) {
    setState(() {
      _range = next;
      _granularity = _granularityFor(next);
      _previous = null;
    });
    _loadRange();
  }

  Future<void> _pickGranularity() async {
    final picked = await showPickerSheet<RevenueTrendGranularity>(
      context: context,
      selected: _granularity,
      options: const [
        (value: RevenueTrendGranularity.daily, label: 'By Day'),
        (value: RevenueTrendGranularity.weekly, label: 'By Week'),
        (value: RevenueTrendGranularity.monthly, label: 'By Month'),
      ],
    );
    if (picked == null || picked == _granularity) return;
    setState(() => _granularity = picked);
    _loadRange();
  }

  Future<void> _openTransaction(String transactionId) async {
    await context.push('${AppRoutes.financeTransactions}/$transactionId');
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      body: SafeArea(
        child: SmoothSwitcher(child: _isLoading
            ? const _FinanceSkeleton()
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _refresh)
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ResponsivePage(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FinanceSectionsNav(),
                          const SizedBox(height: AppSpacing.md),
                          FinanceDateRangePicker(
                            value: _range,
                            onChanged: _onRangeChanged,
                            trailing: OutlinedButton.icon(
                              onPressed: _summary == null || _exporting ? null : _export,
                              icon: _exporting
                                  ? const SizedBox(
                                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.ios_share_rounded, size: 18),
                              label: const Text('Export'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          if (_rangeError != null) ...[
                            Text(_rangeError!, style: const TextStyle(color: AppColors.destructive)),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          if (_range.preset == FinanceDateRangePreset.custom && !_range.isComplete)
                            Text('Choose a start and end date to see this range.',
                                style: AppTypography.secondary(context))
                          else ...[
                            _statCards(),
                            const SizedBox(height: AppSpacing.xl),
                            SectionHeader(
                              title: 'Revenue Trend',
                              trailing: PickerChip(
                                label: _granularityLabel(_granularity),
                                onSelect: _pickGranularity,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            AppCard(
                              child: _trend == null
                                  ? const _ChartSkeleton()
                                  : _trend!.isEmpty
                                      ? Text('No revenue in this period yet.',
                                          style: AppTypography.secondary(context))
                                      : MetricTrendChart(
                                          points: [
                                            for (final t in _trend!) TrendPoint(t.date, t.grossMinor / 100),
                                          ],
                                          color: context.tokens.primary,
                                          formatValue: (v) => financeAmount((v * 100).round()),
                                        ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            SectionHeader(title: 'Revenue Breakdown'),
                            const SizedBox(height: AppSpacing.sm),
                            AppCard(
                              child: _breakdown == null
                                  ? const _LinesSkeleton()
                                  : _buildBreakdown(_breakdown!),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            SectionHeader(title: 'Payment Methods'),
                            const SizedBox(height: AppSpacing.sm),
                            AppCard(
                              child: _methods == null
                                  ? const _LinesSkeleton()
                                  : _buildMethods(_methods!),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          SectionHeader(
                            title: 'Recent Transactions',
                            trailing: TextButton(
                              onPressed: () => context.push(AppRoutes.financeTransactions),
                              child: const Text('View All'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (_rangeLoading && _recent.isEmpty)
                            const _RecentTransactionsSkeleton()
                          else if (_recent.isEmpty)
                            Text('No transactions found for this period.',
                                style: AppTypography.secondary(context))
                          else
                            ..._recent.map(_buildRecentRow),
                          if (_summary != null && _summary!.settlementExceptionCount > 0) ...[
                            const SizedBox(height: AppSpacing.xl),
                            _SettlementExceptionsCallout(count: _summary!.settlementExceptionCount),
                          ],
                          if (_summary != null && _summary!.pendingRefundCount > 0) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '${_summary!.pendingRefundCount} refund${_summary!.pendingRefundCount == 1 ? '' : 's'} still in progress.',
                              style: AppTypography.secondary(context),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                        ],
                      ),
                    ),
                  )),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.money),
    );
  }

  Widget _statCards() {
    final s = _summary;
    final p = _previous;
    final tokens = context.tokens;
    String money(num v) => financeAmount(v.round());
    // A rise in spend or money owed is bad news, so those two carry no
    // green/red arrow rather than a misleading one.
    final cards = <Widget>[
      AppMetricCard(
        label: 'Total Revenue',
        value: s == null ? '—' : money(s.grossRevenueMinor),
        icon: Icons.payments_outlined,
        accentColor: tokens.primary,
        changePercent: s == null ? null : changePct(current: s.grossRevenueMinor, previous: p?.grossRevenueMinor ?? 0),
        countTo: s?.grossRevenueMinor,
        formatValue: money,
      ),
      AppMetricCard(
        label: 'Total Expenses',
        value: s == null ? '—' : money(s.expensesMinor),
        icon: Icons.receipt_long_outlined,
        accentColor: tokens.destructive,
        countTo: s?.expensesMinor,
        formatValue: money,
        entranceDelay: const Duration(milliseconds: 60),
      ),
      AppMetricCard(
        label: 'Net Revenue',
        value: s == null ? '—' : money(s.netRevenueMinor),
        icon: Icons.account_balance_wallet_outlined,
        accentColor: tokens.electricBlue,
        changePercent: s == null ? null : changePct(current: s.netRevenueMinor, previous: p?.netRevenueMinor ?? 0),
        countTo: s?.netRevenueMinor,
        formatValue: money,
        entranceDelay: const Duration(milliseconds: 120),
      ),
      InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () async {
          await context.push(AppRoutes.financePendingPayments);
          if (mounted) _refresh();
        },
        child: AppMetricCard(
          label: 'Pending Payments',
          value: s == null ? '—' : money(s.outstandingMinor),
          icon: Icons.hourglass_empty_rounded,
          accentColor: tokens.warning,
          countTo: s?.outstandingMinor,
          formatValue: money,
          entranceDelay: const Duration(milliseconds: 180),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildBreakdown(RevenueBreakdown breakdown) {
    final rows = <({String label, int amountMinor})>[
      (label: 'Guest Bookings', amountMinor: breakdown.guestBookingRevenueMinor),
      (label: 'Memberships', amountMinor: breakdown.membershipRevenueMinor),
      (label: 'Member Bookings', amountMinor: breakdown.memberBookingRevenueMinor),
      (label: 'Coaching', amountMinor: breakdown.coachingRevenueMinor),
      (label: 'Refunds', amountMinor: breakdown.refundsMinor),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(child: Text(row.label, style: AppTypography.secondary(context))),
                const SizedBox(width: AppSpacing.sm),
                Text(financeAmount(row.amountMinor),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        if (breakdown.membershipIncludedUsageCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Plus ${breakdown.membershipIncludedUsageCount} included membership '
            'session${breakdown.membershipIncludedUsageCount == 1 ? '' : 's'} — usage, not revenue.',
            style: AppTypography.caption(context),
          ),
        ],
      ],
    );
  }

  Widget _buildMethods(List<PaymentMethodSlice> methods) {
    if (methods.isEmpty) {
      return Text('No payments taken in this period.', style: AppTypography.secondary(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in methods)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${m.paymentMethod} · ${m.paymentCount} payment${m.paymentCount == 1 ? '' : 's'}',
                    style: AppTypography.secondary(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(financeAmount(m.amountMinor),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRecentRow(FinanceTransaction txn) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: () => _openTransaction(txn.id),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${txn.reference} · ${sourceTypeLabel(txn.sourceType)}',
                      style: AppTypography.rowTitle(context)),
                  Text(txn.customerName ?? '—', style: AppTypography.caption(context)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(financeAmount(txn.amountMinor),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.xs),
                StatusBadge(
                  label: transactionStatusLabel(txn.status),
                  tone: transactionStatusTone(txn.status),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The Finance section switcher — the mobile stand-in for the web's expandable
/// "Finance" nav group (Dashboard / Transactions / Expenses / Pending
/// Payments). This screen is the Dashboard, so it links to the other three.
class _FinanceSectionsNav extends StatelessWidget {
  const _FinanceSectionsNav();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: const [
        _SectionPill(
          icon: Icons.receipt_long,
          label: 'Transactions',
          route: AppRoutes.financeTransactions,
        ),
        _SectionPill(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Expenses',
          route: AppRoutes.financeExpenses,
        ),
        _SectionPill(
          icon: Icons.pending_actions_outlined,
          label: 'Pending Payments',
          route: AppRoutes.financePendingPayments,
        ),
        _SectionPill(
          icon: Icons.point_of_sale_outlined,
          label: 'Daily Closing',
          route: AppRoutes.financeDailyClosing,
        ),
        _SectionPill(
          icon: Icons.trending_up,
          label: 'P&L',
          route: AppRoutes.financeProfitLoss,
        ),
      ],
    );
  }
}

class _SectionPill extends StatelessWidget {
  const _SectionPill({required this.icon, required this.label, required this.route});

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(route),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: context.tokens.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: context.tokens.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

String _granularityLabel(RevenueTrendGranularity g) {
  switch (g) {
    case RevenueTrendGranularity.daily:
      return 'By Day';
    case RevenueTrendGranularity.weekly:
      return 'By Week';
    case RevenueTrendGranularity.monthly:
      return 'By Month';
  }
}

/// A headline figure for the selected range, with its change against the
/// preceding window of equal length.
/// The actionable queue callout — a current count (not date-filtered by the
/// backend), linking to the Refunds screen where the owner resolves them.
class _SettlementExceptionsCallout extends StatelessWidget {
  const _SettlementExceptionsCallout({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => context.push(AppRoutes.refunds),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settlement Exceptions', style: AppTypography.rowTitle(context)),
                Text(
                  '$count payment${count == 1 ? '' : 's'} require attention.',
                  style: AppTypography.secondary(context),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// Structure-shaped placeholder for the whole Finance Dashboard page load —
/// facility row, nav strip, date picker, 4 stat cards, chart card, two
/// breakdown cards, and a few recent-transaction rows.
class _FinanceSkeleton extends StatelessWidget {
  const _FinanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeleton(width: 160, height: 13),
          SizedBox(height: AppSpacing.md),
          SkeletonChipRow(count: 5),
          SizedBox(height: AppSpacing.md),
          AppSkeleton(height: 48, radius: AppRadius.md),
          SizedBox(height: AppSpacing.lg),
          _StatCardsSkeleton(),
          SizedBox(height: AppSpacing.xl),
          AppSkeleton(width: 140, height: 16),
          SizedBox(height: AppSpacing.sm),
          _ChartSkeleton(),
          SizedBox(height: AppSpacing.xl),
          AppSkeleton(width: 160, height: 16),
          SizedBox(height: AppSpacing.sm),
          _LinesSkeleton(),
          SizedBox(height: AppSpacing.xl),
          AppSkeleton(width: 160, height: 16),
          SizedBox(height: AppSpacing.sm),
          _LinesSkeleton(),
          SizedBox(height: AppSpacing.xl),
          AppSkeleton(width: 180, height: 16),
          SizedBox(height: AppSpacing.sm),
          _RecentTransactionsSkeleton(),
        ],
      ),
    );
  }
}

/// The 4-tile stat-card row placeholder, matching `_statCards`' responsive
/// wrap.
class _StatCardsSkeleton extends StatelessWidget {
  const _StatCardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(1, 2);
        final width = (constraints.maxWidth - (AppSpacing.md * (columns - 1))) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (var i = 0; i < 4; i++) SizedBox(width: width, child: const SkeletonStatTile()),
          ],
        );
      },
    );
  }
}

/// A tall block placeholder for the Revenue Trend chart card.
class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppSkeleton(height: 140, radius: AppRadius.md);
  }
}

/// A few text-line placeholders, for the breakdown / payment-methods cards.
class _LinesSkeleton extends StatelessWidget {
  const _LinesSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSkeleton(height: 13),
        SizedBox(height: AppSpacing.sm),
        AppSkeleton(height: 13),
        SizedBox(height: AppSpacing.sm),
        AppSkeleton(width: 160, height: 13),
      ],
    );
  }
}

/// A few row placeholders for the Recent Transactions list.
class _RecentTransactionsSkeleton extends StatelessWidget {
  const _RecentTransactionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
      ],
    );
  }
}
