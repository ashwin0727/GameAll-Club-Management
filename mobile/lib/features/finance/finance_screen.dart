import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'finance_date_range_picker.dart';
import 'finance_presentation.dart';
import 'revenue_trend_chart.dart';
import 'transaction_details_sheet.dart';

/// The Finance Dashboard — mirrors
/// src/features/finance/components/finance-dashboard.tsx.
///
/// Every number on this screen comes from a backend RPC response field
/// (0024_finance.sql). This widget never sums, subtracts, or derives a
/// monetary total: the "Net Revenue" card is `net_revenue_minor` as the
/// server computed it, not gross minus refunds computed here, and the
/// "Recent Transactions" list is never added up into a headline figure
/// (spec §"Core Finance Principle" / §"Critical Final Rule").
///
/// Layout is a single scrolling column of content-driven cards inside
/// [ResponsivePage], with every card grid reflowing on available width, so it
/// works from a 320dp phone through to a tablet and cannot overflow when the
/// system font size is enlarged.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  bool _isLoading = true;
  String? _loadError;
  String? _facilityId;

  /// The three at-a-glance cards. Each is its own `get_finance_summary` call
  /// for its own preset — the server resolves TODAY/THIS_WEEK/THIS_MONTH in
  /// the facility's timezone, so these are never sliced out of one another.
  FinanceSummary? _todaySummary;
  FinanceSummary? _weekSummary;
  FinanceSummary? _monthSummary;

  FinanceDateRange _range = const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth);
  FinanceSummary? _summary;
  RevenueBreakdown? _breakdown;
  List<RevenueTrendPoint>? _trend;
  List<FinanceTransaction> _recent = [];
  bool _rangeLoading = false;
  String? _rangeError;

  /// Guards against a slow response for an earlier range landing after a
  /// faster one for the range the owner has since picked — the mobile
  /// equivalent of the web effect's `cancelled` flag.
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
    await _loadPresetSummaries();
    if (!mounted) return;
    await _loadRange();
  }

  Future<void> _loadPresetSummaries() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      final summaries = await Future.wait([
        repo.getSummary(facilityId, const FinanceDateRange(preset: FinanceDateRangePreset.today)),
        repo.getSummary(facilityId, const FinanceDateRange(preset: FinanceDateRangePreset.thisWeek)),
        repo.getSummary(facilityId, const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth)),
      ]);
      if (!mounted) return;
      setState(() {
        _todaySummary = summaries[0];
        _weekSummary = summaries[1];
        _monthSummary = summaries[2];
        _isLoading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _loadRange() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    // A half-picked CUSTOM range is not askable yet — the server would
    // reject it. Wait for the owner to choose both ends.
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
        repo.getRevenueTrend(facilityId, _range, RevenueTrendGranularity.daily),
        repo.listTransactions(ListTransactionsInput(facilityId: facilityId, dateRange: _range, limit: 5, offset: 0)),
      ]);
      if (!mounted || requestId != _rangeRequestId) return;
      setState(() {
        _summary = results[0] as FinanceSummary;
        _breakdown = results[1] as RevenueBreakdown;
        _trend = results[2] as List<RevenueTrendPoint>;
        _recent = (results[3] as TransactionPage).transactions;
        _rangeLoading = false;
      });
    } on AppException catch (e) {
      if (!mounted || requestId != _rangeRequestId) return;
      setState(() {
        _rangeLoading = false;
        _rangeError = e.message;
      });
    }
  }

  Future<void> _refresh() async {
    await _loadPresetSummaries();
    if (!mounted) return;
    await _loadRange();
  }

  void _onRangeChanged(FinanceDateRange next) {
    setState(() => _range = next);
    _loadRange();
  }

  Future<void> _openTransaction(String transactionId) {
    return showTransactionDetailsSheet(context, transactionId: transactionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Expenses',
            onPressed: () => context.push(AppRoutes.financeExpenses),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Transactions',
            onPressed: () => context.push(AppRoutes.financeTransactions),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading finance…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _refresh)
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetricGrid(
                        minTileWidth: 150,
                        tiles: [
                          _Metric('Today', _todaySummary == null ? '—' : financeAmount(_todaySummary!.netRevenueMinor)),
                          _Metric('This Week', _weekSummary == null ? '—' : financeAmount(_weekSummary!.netRevenueMinor)),
                          _Metric('This Month', _monthSummary == null ? '—' : financeAmount(_monthSummary!.netRevenueMinor)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Revenue Summary'),
                      const SizedBox(height: AppSpacing.sm),
                      FinanceDateRangePicker(value: _range, onChanged: _onRangeChanged),
                      const SizedBox(height: AppSpacing.lg),
                      if (_rangeError != null) ...[
                        Text(_rangeError!, style: const TextStyle(color: AppColors.destructive)),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      if (_range.preset == FinanceDateRangePreset.custom && !_range.isComplete)
                        Text('Choose a start and end date to see this range.', style: AppTypography.secondary(context))
                      else if (_summary == null)
                        const LoadingView()
                      else ...[
                        _MetricGrid(
                          minTileWidth: 150,
                          tiles: [
                            _Metric('Gross Revenue', financeAmount(_summary!.grossRevenueMinor)),
                            _Metric('Refunds', financeAmount(_summary!.refundsMinor)),
                            _Metric('Net Revenue', financeAmount(_summary!.netRevenueMinor)),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _MetricGrid(
                          minTileWidth: 120,
                          tiles: [
                            _Metric('Transactions', '${_summary!.transactionCount}'),
                            _Metric('Successful', '${_summary!.successfulPaymentCount}'),
                            _Metric('Failed', '${_summary!.failedPaymentCount}'),
                            _Metric('Pending', '${_summary!.pendingPaymentCount}'),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Revenue Trend'),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: _trend == null
                            ? const LoadingView()
                            : RevenueTrendChart(points: _trend!),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Revenue Breakdown'),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: _breakdown == null ? const LoadingView() : _buildBreakdown(_breakdown!),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(
                        title: 'Recent Transactions',
                        trailing: TextButton(
                          onPressed: () => context.push(AppRoutes.financeTransactions),
                          child: const Text('View all'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_rangeLoading && _recent.isEmpty)
                        const LoadingView()
                      else if (_recent.isEmpty)
                        Text('No transactions found for this period.', style: AppTypography.secondary(context))
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
              ),
      ),
    );
  }

  Widget _buildBreakdown(RevenueBreakdown breakdown) {
    final rows = <({String label, int amountMinor})>[
      (label: 'Membership', amountMinor: breakdown.membershipRevenueMinor),
      (label: 'Member Booking', amountMinor: breakdown.memberBookingRevenueMinor),
      (label: 'Guest Booking', amountMinor: breakdown.guestBookingRevenueMinor),
      (label: 'Refunds', amountMinor: breakdown.refundsMinor),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(row.label, style: AppTypography.secondary(context))),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  financeAmount(row.amountMinor),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        // Volume, never revenue — an included member session has no payment
        // at all, so it is reported alongside the money rather than in them
        // (spec §"Membership Included Usage").
        if (breakdown.membershipIncludedUsageCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Plus ${breakdown.membershipIncludedUsageCount} included membership '
            'session${breakdown.membershipIncludedUsageCount == 1 ? '' : 's'} (not counted as revenue).',
            style: AppTypography.caption(context),
          ),
        ],
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
                  Text(
                    '${txn.reference} · ${sourceTypeLabel(txn.sourceType)}',
                    style: AppTypography.rowTitle(context),
                  ),
                  Text(txn.customerName ?? '—', style: AppTypography.caption(context)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(financeAmount(txn.amountMinor), style: const TextStyle(fontWeight: FontWeight.w600)),
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

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final String value;
}

/// Reflows metric cards into as many columns as the width allows (one column
/// at 320dp, more on a tablet) rather than assuming a fixed grid.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.tiles, required this.minTileWidth});

  final List<_Metric> tiles;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(1, tiles.length);
        final tileWidth = (constraints.maxWidth - (AppSpacing.md * (columns - 1))) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: tiles
              .map((tile) => SizedBox(width: tileWidth, child: _MetricCard(metric: tile)))
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(metric.label, style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            metric.value,
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The actionable queue callout — a current count (not date-filtered by the
/// backend), linking to the existing Refunds screen where the owner resolves
/// them.
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