import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/tab_pop_scope.dart';
import '../../shared/widgets/states.dart';
import 'finance_presentation.dart';

/// The period choices the Payment filter sheet offers — a superset of
/// [FinanceDateRangePreset] (adds trailing multi-month windows and an
/// explicit single month), each resolved to a [FinanceDateRange] by
/// [_MoneyScreenState._range].
enum _MoneyRangeChoice {
  thisMonth,
  lastMonth,
  last3Months,
  last6Months,
  thisYear,
  specificMonth,
}

/// The redesigned "Finance" tab — a single glanceable view of the month: net
/// with its trend, where the revenue came from, what's pending vs settled,
/// and the latest ledger activity.
class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  _MoneyRangeChoice _choice = _MoneyRangeChoice.thisMonth;
  DateTime? _specificMonth;
  bool _loading = true;
  String? _error;

  FinanceSummary? _summary;
  FinanceSummary? _prevSummary;
  RevenueBreakdown? _breakdown;
  List<LedgerEntry> _ledger = const [];
  int _ledgerTotal = 0;
  List<PaymentMethodSlice> _methods = const [];

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  static DateTime _lastOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);
  static DateTime _monthsAgo(DateTime from, int n) =>
      DateTime(from.year, from.month - n, 1);

  FinanceDateRange get _range {
    final now = DateTime.now();
    switch (_choice) {
      case _MoneyRangeChoice.thisMonth:
        return const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth);
      case _MoneyRangeChoice.lastMonth:
        return const FinanceDateRange(preset: FinanceDateRangePreset.lastMonth);
      case _MoneyRangeChoice.last3Months:
        return FinanceDateRange(
          preset: FinanceDateRangePreset.custom,
          startDate: _iso(_monthsAgo(now, 2)),
          endDate: _iso(now),
        );
      case _MoneyRangeChoice.last6Months:
        return FinanceDateRange(
          preset: FinanceDateRangePreset.custom,
          startDate: _iso(_monthsAgo(now, 5)),
          endDate: _iso(now),
        );
      case _MoneyRangeChoice.thisYear:
        return const FinanceDateRange(preset: FinanceDateRangePreset.thisYear);
      case _MoneyRangeChoice.specificMonth:
        final m = _specificMonth ?? now;
        return FinanceDateRange(
          preset: FinanceDateRangePreset.custom,
          startDate: _iso(_firstOfMonth(m)),
          endDate: _iso(_lastOfMonth(m)),
        );
    }
  }

  /// Short label for the filter chip itself.
  String get _periodLabel {
    switch (_choice) {
      case _MoneyRangeChoice.thisMonth:
        return 'This month';
      case _MoneyRangeChoice.lastMonth:
        return 'Last month';
      case _MoneyRangeChoice.last3Months:
        return 'Last 3 months';
      case _MoneyRangeChoice.last6Months:
        return 'Last 6 months';
      case _MoneyRangeChoice.thisYear:
        return 'This year';
      case _MoneyRangeChoice.specificMonth:
        return DateFormat('MMM yyyy').format(_specificMonth ?? DateTime.now());
    }
  }

  /// "Net ___" for the headline card — lowercase for the worded presets,
  /// title-case for an explicit month ("Net Aug 2026").
  String get _netCardLabel => _choice == _MoneyRangeChoice.specificMonth
      ? 'Net $_periodLabel'
      : 'Net ${_periodLabel[0].toLowerCase()}${_periodLabel.substring(1)}';

  Future<void> _openMoneyFilterSheet() async {
    var staged = _choice;
    var stagedMonth = _specificMonth;
    final now = DateTime.now();
    final months = [for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i, 1)];

    final result = await showModalBottomSheet<({_MoneyRangeChoice choice, DateTime? month})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final tokens = sheetContext.tokens;
          Widget optionTile(String label, _MoneyRangeChoice value) {
            final selected = staged == value;
            return ListTile(
              dense: true,
              title: Text(label,
                  style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
              trailing: selected
                  ? Icon(Icons.check_circle_rounded, color: tokens.primary)
                  : null,
              onTap: () => setSheetState(() {
                staged = value;
                stagedMonth = null;
              }),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filter by period',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary)),
                  const SizedBox(height: AppSpacing.xs),
                  optionTile('This month', _MoneyRangeChoice.thisMonth),
                  optionTile('Last month', _MoneyRangeChoice.lastMonth),
                  optionTile('Last 3 months', _MoneyRangeChoice.last3Months),
                  optionTile('Last 6 months', _MoneyRangeChoice.last6Months),
                  optionTile('This year', _MoneyRangeChoice.thisYear),
                  const SizedBox(height: AppSpacing.md),
                  Text('Or pick a month',
                      style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: months.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (_, i) {
                        final m = months[i];
                        final selected = staged == _MoneyRangeChoice.specificMonth &&
                            stagedMonth?.year == m.year &&
                            stagedMonth?.month == m.month;
                        return GestureDetector(
                          onTap: () => setSheetState(() {
                            staged = _MoneyRangeChoice.specificMonth;
                            stagedMonth = m;
                          }),
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? tokens.primary : tokens.surface2,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color:
                                      selected ? tokens.primary : tokens.borderColor),
                            ),
                            child: Text(DateFormat('MMM yyyy').format(m),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? tokens.onPrimary
                                        : tokens.textPrimary)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                          sheetContext, (choice: staged, month: stagedMonth)),
                      child: const Text('Show results'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null) return;
    setState(() {
      _choice = result.choice;
      _specificMonth = result.month;
    });
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        setState(() {
          _loading = false;
          _error = 'Complete your facility setup to see your money.';
        });
        return;
      }
      final repo = ref.read(financeRepositoryProvider);
      final results = await Future.wait([
        repo.getSummary(facility.id, _range),
        repo.getRevenueBreakdown(facility.id, _range),
        repo.listLedger(ListLedgerInput(
          facilityId: facility.id,
          dateRange: _range,
          limit: 12,
        )),
        repo.getPaymentMethodBreakdown(facility.id, _range),
        if (_choice == _MoneyRangeChoice.thisMonth)
          repo.getSummary(
              facility.id,
              const FinanceDateRange(preset: FinanceDateRangePreset.lastMonth)),
      ]);

      final ledgerPage = results[2] as LedgerPage;
      setState(() {
        _summary = results[0] as FinanceSummary;
        _breakdown = results[1] as RevenueBreakdown;
        _ledger = ledgerPage.entries;
        _ledgerTotal = ledgerPage.totalCount;
        _methods = results[3] as List<PaymentMethodSlice>;
        _prevSummary =
            results.length > 4 ? results[4] as FinanceSummary : null;
        _loading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e, stack) {
      debugPrint('Money load failed: $e\n$stack');
      setState(() {
        _loading = false;
        _error = 'We couldn’t load your money. Pull to retry.';
      });
    }
  }

  ({String text, bool up})? get _trend {
    final cur = _summary?.netRevenueMinor;
    final prev = _prevSummary?.netRevenueMinor;
    if (cur == null || prev == null) return null;
    if (prev == 0) {
      if (cur == 0) return null;
      return (text: 'new', up: cur > 0);
    }
    final pct = (((cur - prev) / prev.abs()) * 100).round();
    return (text: '${pct.abs()}%', up: pct >= 0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TabPopScope(
      tab: AppTab.money,
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: const Text('Finance',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: GestureDetector(
              onTap: _openMoneyFilterSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 7),
                decoration: BoxDecoration(
                  color: tokens.surface1,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: tokens.borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, size: 14, color: tokens.primary),
                    const SizedBox(width: 6),
                    Text(_periodLabel,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more_rounded,
                        size: 15, color: tokens.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const _MoneySkeleton()
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                      children: [
                        _NetCard(
                          summary: _summary!,
                          breakdown: _breakdown!,
                          trend: _trend,
                          periodLabel: _netCardLabel,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: _MiniStat(
                                label: 'Pending',
                                amount: financeAmount(_summary!.outstandingMinor),
                                sub:
                                    '${_summary!.pendingPaymentCount} to collect',
                                accent: tokens.warning,
                                onTap: () async {
                                  await context
                                      .push(AppRoutes.financePendingPayments);
                                  if (mounted) _load();
                                },
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _MiniStat(
                                label: 'Settled',
                                amount: financeAmount(
                                    _summary!.grossRevenueMinor -
                                        _summary!.refundsMinor),
                                sub: 'to bank',
                                accent: null,
                                onTap: null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _FinanceLinkRow(),
                        const SizedBox(height: AppSpacing.xl),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Transactions',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16)),
                            ),
                            GestureDetector(
                              onTap: () async {
                                await context
                                    .push(AppRoutes.financeTransactions);
                                if (mounted) _load();
                              },
                              child: Text('Export',
                                  style: TextStyle(
                                      color: tokens.primary,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (_ledger.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.lg),
                            child: Text('No activity in this period.',
                                style:
                                    TextStyle(color: tokens.textSecondary)),
                          )
                        else ...[
                          for (final e in _ledger)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: _TxnRow(entry: e),
                            ),
                          if (_ledgerTotal > _ledger.length)
                            Center(
                              child: TextButton(
                                onPressed: () => context
                                    .push(AppRoutes.financeTransactions),
                                child: Text(
                                    'See all $_ledgerTotal transactions'),
                              ),
                            ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        if (_methods.isNotEmpty)
                          _MethodsCard(methods: _methods),
                        if (_summary!.pendingRefundCount > 0 ||
                            _summary!.settlementExceptionCount > 0) ...[
                          const SizedBox(height: AppSpacing.md),
                          _AttentionStrip(
                            refunds: _summary!.pendingRefundCount,
                            exceptions: _summary!.settlementExceptionCount,
                            onTap: () => context.push(AppRoutes.refunds),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.money),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

class _NetCard extends StatelessWidget {
  const _NetCard({
    required this.summary,
    required this.breakdown,
    required this.trend,
    required this.periodLabel,
  });

  final FinanceSummary summary;
  final RevenueBreakdown breakdown;
  final ({String text, bool up})? trend;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final courts = breakdown.memberBookingRevenueMinor +
        breakdown.guestBookingRevenueMinor;
    final memberships = breakdown.membershipRevenueMinor;
    final sessions = (summary.grossRevenueMinor - courts - memberships)
        .clamp(0, summary.grossRevenueMinor);
    final expensesAndRefunds = summary.expensesMinor + summary.refundsMinor;

    final grey = tokens.textSecondary;

    Widget seg(int value, Color c, bool last) => Expanded(
          flex: value <= 0 ? 0 : value,
          child: Padding(
            padding: EdgeInsets.only(right: last ? 0 : 3),
            child: Container(
              height: 9,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(periodLabel,
                    style:
                        TextStyle(fontSize: 13, color: tokens.textSecondary)),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (trend!.up ? tokens.primary : tokens.destructive)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${trend!.up ? '↑' : '↓'} ${trend!.text}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: trend!.up ? tokens.primary : tokens.destructive,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            financeAmount(summary.netRevenueMinor),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
            ),
          ),
          if (trend != null) ...[
            const SizedBox(height: 2),
            Text(
              trend!.text == 'new'
                  ? 'First month with revenue'
                  : '${trend!.up ? 'Up' : 'Down'} ${trend!.text} vs last month',
              style: TextStyle(
                fontSize: 12,
                color: trend!.up ? tokens.primary : tokens.destructive,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              seg(courts, tokens.primary, false),
              seg(memberships, tokens.violet, false),
              seg(sessions.toInt(), grey.withValues(alpha: 0.4), true),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _LegendRow(
              color: tokens.primary,
              label: 'Court bookings',
              amount: financeAmount(courts)),
          _LegendRow(
              color: tokens.violet,
              label: 'Memberships',
              amount: financeAmount(memberships)),
          _LegendRow(
              color: grey.withValues(alpha: 0.5),
              label: 'Session seats',
              amount: financeAmount(sessions.toInt())),
          const SizedBox(height: 2),
          _LegendRow(
            color: tokens.destructive,
            label: 'Expenses & refunds',
            amount: '−${financeAmount(expensesAndRefunds)}',
            amountColor: tokens.destructive,
            muted: true,
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.amount,
    this.amountColor,
    this.muted = false,
  });

  final Color color;
  final String label;
  final String amount;
  final Color? amountColor;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: muted ? tokens.textSecondary : tokens.textPrimary,
                )),
          ),
          Text(amount,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: amountColor ?? tokens.textPrimary,
              )),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.amount,
    required this.sub,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String amount;
  final String sub;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final solid = accent != null;
    final fill = solid ? tokens.accentSolid(accent!) : tokens.surface1;
    final onFill = solid ? tokens.onAccent(accent!) : null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: solid ? null : Border.all(color: tokens.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: onFill?.withValues(alpha: 0.8) ??
                      tokens.textSecondary,
                )),
            const SizedBox(height: 6),
            Text(amount,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: onFill ?? tokens.textPrimary,
                )),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(
                    fontSize: 12,
                    color: onFill?.withValues(alpha: 0.75) ??
                        tokens.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow({required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isIncome = entry.txnType == LedgerTxnType.income;
    final isMembership = isIncome && entry.sourceType.contains('MEMBERSHIP');

    final Color tint;
    final IconData icon;
    if (isMembership) {
      tint = tokens.violet;
      icon = Icons.card_membership;
    } else if (isIncome) {
      tint = tokens.primary;
      icon = Icons.arrow_upward_rounded;
    } else {
      tint = tokens.destructive;
      icon = Icons.arrow_downward_rounded;
    }

    final t = entry.occurredAt;
    final period = t.hour < 12 ? 'AM' : 'PM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final subParts = <String>[
      '$h12:${t.minute.toString().padLeft(2, '0')} $period',
      if ((entry.paymentMethod ?? '').isNotEmpty) entry.paymentMethod!.toLowerCase(),
      entry.status.toLowerCase(),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 20, color: tint),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: tokens.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${isIncome ? '+' : '−'}${financeAmount(entry.amountMinor)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isIncome ? tokens.primary : tokens.destructive,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodsCard extends StatelessWidget {
  const _MethodsCard({required this.methods});

  final List<PaymentMethodSlice> methods;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sorted = [...methods]
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    final total =
        sorted.fold<int>(0, (s, m) => s + m.amountMinor).clamp(1, 1 << 62);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How you got paid',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary)),
          const SizedBox(height: AppSpacing.md),
          for (final m in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(_label(m.paymentMethod),
                            style: TextStyle(
                                fontSize: 13, color: tokens.textPrimary)),
                      ),
                      Text(financeAmount(m.amountMinor),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: m.amountMinor / total,
                      minHeight: 6,
                      backgroundColor: tokens.surface2,
                      color: tokens.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _label(String raw) {
    if (raw.toUpperCase() == 'UPI') return 'UPI';
    final lower = raw.toLowerCase().replaceAll('_', ' ');
    return lower.isEmpty
        ? 'Unknown'
        : lower[0].toUpperCase() + lower.substring(1);
  }
}

class _AttentionStrip extends StatelessWidget {
  const _AttentionStrip({
    required this.refunds,
    required this.exceptions,
    required this.onTap,
  });

  final int refunds;
  final int exceptions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final parts = <String>[
      if (refunds > 0) '$refunds refund${refunds == 1 ? '' : 's'} in progress',
      if (exceptions > 0)
        '$exceptions settlement issue${exceptions == 1 ? '' : 's'}',
    ];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tokens.accentSolid(tokens.warning),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: tokens.onAccent(tokens.warning)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(parts.join(' · '),
                  style: TextStyle(
                      fontSize: 12.5,
                      color: tokens.onAccent(tokens.warning))),
            ),
            Icon(Icons.chevron_right,
                size: 18,
                color: tokens.onAccent(tokens.warning).withValues(alpha: 0.75)),
          ],
        ),
      ),
    );
  }
}

/// Expenses / Daily Closing / P&L — three equal-width cards, same shape as
/// the dashboard's quick-actions row, instead of a `Wrap` of pill chips that
/// clipped its last item at narrow widths.
class _FinanceLinkRow extends StatelessWidget {
  const _FinanceLinkRow();

  @override
  Widget build(BuildContext context) {
    final links = <(IconData, String, String)>[
      (Icons.account_balance_wallet_outlined, 'Expenses', AppRoutes.financeExpenses),
      (Icons.point_of_sale_outlined, 'Daily Closing', AppRoutes.financeDailyClosing),
      (Icons.trending_up_rounded, 'P&L', AppRoutes.financeProfitLoss),
    ];
    return Row(
      children: [
        for (var i = 0; i < links.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: _FinanceLink(icon: links[i].$1, label: links[i].$2, route: links[i].$3)),
        ],
      ],
    );
  }
}

class _FinanceLink extends StatelessWidget {
  const _FinanceLink({required this.icon, required this.label, required this.route});

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(route),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.borderColor),
          ),
          child: Column(
            children: [
              Icon(icon, size: 19, color: tokens.primary),
              const SizedBox(height: 5),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder while the Finance/Money page loads — the
/// net hero card, the pending/settled mini-stats, and a few ledger rows plus
/// a methods card.
class _MoneySkeleton extends StatelessWidget {
  const _MoneySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: const [
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 100, height: 12),
              SizedBox(height: 8),
              AppSkeleton(width: 160, height: 30),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(height: 9, radius: AppRadius.pill),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: SkeletonStatTile()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonStatTile()),
          ],
        ),
        SizedBox(height: AppSpacing.xl),
        AppSkeleton(width: 130, height: 16),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.xl),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 140, height: 15),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(height: 13),
              SizedBox(height: 5),
              AppSkeleton(height: 6, radius: AppRadius.pill),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
              SizedBox(height: 5),
              AppSkeleton(height: 6, radius: AppRadius.pill),
            ],
          ),
        ),
      ],
    );
  }
}
