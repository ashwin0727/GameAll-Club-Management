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
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'finance_date_range_picker.dart';
import 'finance_period.dart';
import 'finance_presentation.dart';
import 'revenue_trend_chart.dart';

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
  String _facilityName = '';

  FinanceDateRange _range = const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth);
  RevenueTrendGranularity _granularity = RevenueTrendGranularity.daily;

  FinanceSummary? _summary;
  FinanceSummary? _previous;
  RevenueBreakdown? _breakdown;
  List<PaymentMethodSlice>? _methods;
  List<RevenueTrendPoint>? _trend;
  List<FinanceTransaction> _recent = [];
  bool _rangeLoading = false;
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
    _facilityName = facility.name;
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

  void _onRangeChanged(FinanceDateRange next) {
    setState(() {
      _range = next;
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

  void _openTransaction(String transactionId) {
    context.push('${AppRoutes.financeTransactions}/$transactionId');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
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
                          if (_facilityName.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.place_outlined, size: 16, color: AppColors.muted),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(_facilityName,
                                      style: AppTypography.secondary(context),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          const _FinanceSectionsNav(),
                          const SizedBox(height: AppSpacing.md),
                          FinanceDateRangePicker(value: _range, onChanged: _onRangeChanged),
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
                                  ? const LoadingView(compact: true)
                                  : _trend!.isEmpty
                                      ? Text('No revenue in this period yet.',
                                          style: AppTypography.secondary(context))
                                      : RevenueTrendChart(points: _trend!),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            SectionHeader(title: 'Revenue Breakdown'),
                            const SizedBox(height: AppSpacing.sm),
                            AppCard(
                              child: _breakdown == null
                                  ? const LoadingView(compact: true)
                                  : _buildBreakdown(_breakdown!),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            SectionHeader(title: 'Payment Methods'),
                            const SizedBox(height: AppSpacing.sm),
                            AppCard(
                              child: _methods == null
                                  ? const LoadingView(compact: true)
                                  : _buildMethods(_methods!),
                            ),
                          ],
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
                            const LoadingView(compact: true)
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
                  ),
      ),
    );
  }

  Widget _statCards() {
    final s = _summary;
    final p = _previous;
    final cards = <Widget>[
      _StatCard(
        label: 'Total Revenue',
        value: s == null ? '—' : financeAmount(s.grossRevenueMinor),
        pct: (s == null) ? null : changePct(current: s.grossRevenueMinor, previous: p?.grossRevenueMinor ?? 0),
      ),
      _StatCard(
        label: 'Total Expenses',
        value: s == null ? '—' : financeAmount(s.expensesMinor),
        pct: (s == null) ? null : changePct(current: s.expensesMinor, previous: p?.expensesMinor ?? 0),
        // For spending, a rise is bad news.
        invert: true,
      ),
      _StatCard(
        label: 'Net Revenue',
        value: s == null ? '—' : financeAmount(s.netRevenueMinor),
        pct: (s == null) ? null : changePct(current: s.netRevenueMinor, previous: p?.netRevenueMinor ?? 0),
      ),
      _StatCard(
        label: 'Pending Payments',
        value: s == null ? '—' : financeAmount(s.outstandingMinor),
        pct: (s == null) ? null : changePct(current: s.outstandingMinor, previous: p?.outstandingMinor ?? 0),
        invert: true,
        onTap: () => context.push(AppRoutes.financePendingPayments),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(1, 2);
        final width = (constraints.maxWidth - (AppSpacing.md * (columns - 1))) / columns;
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
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.pct,
    this.invert = false,
    this.onTap,
  });

  final String label;
  final String value;
  final double? pct;

  /// For expenses and money owed, a rise is bad news — so the colour follows
  /// what the change means, not just its direction.
  final bool invert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppTypography.caption(context))),
              if (onTap != null) const Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          _Delta(pct: pct, invert: invert),
        ],
      ),
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta({required this.pct, required this.invert});

  final double? pct;
  final bool invert;

  @override
  Widget build(BuildContext context) {
    if (pct == null) {
      return Text('vs last period', style: AppTypography.caption(context));
    }
    final good = invert ? pct! <= 0 : pct! >= 0;
    final colour = good ? context.tokens.success : context.tokens.destructive;
    final rounded = pct! == pct!.roundToDouble() ? pct!.toStringAsFixed(0) : pct!.toStringAsFixed(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(pct! >= 0 ? Icons.trending_up : Icons.trending_down, size: 13, color: colour),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            '${pct! > 0 ? '+' : ''}$rounded% vs last period',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colour, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

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
