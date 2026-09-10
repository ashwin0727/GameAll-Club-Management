import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'finance_date_range_picker.dart';
import 'finance_presentation.dart';

/// Finance → Profit & Loss — mirrors
/// src/features/finance/components/profit-loss-page.tsx.
///
/// Every figure is `get_pnl` / `get_pnl_trend` (0071) — recognised revenue
/// less refunds less recorded expenses, composed in the database. Nothing is
/// summed on the device.
class ProfitLossScreen extends ConsumerStatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  ConsumerState<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends ConsumerState<ProfitLossScreen> {
  String? _facilityId;
  FinanceDateRange _range = const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth);

  ProfitAndLoss? _pnl;
  List<PnlTrendPoint> _trend = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _facilityId = ref.read(sessionControllerProvider).facility?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  RevenueTrendGranularity _granularity() {
    switch (_range.preset) {
      case FinanceDateRangePreset.today:
      case FinanceDateRangePreset.yesterday:
      case FinanceDateRangePreset.thisWeek:
      case FinanceDateRangePreset.lastWeek:
        return RevenueTrendGranularity.daily;
      case FinanceDateRangePreset.thisYear:
        return RevenueTrendGranularity.monthly;
      default:
        return RevenueTrendGranularity.daily;
    }
  }

  Future<void> _load() async {
    final facilityId = _facilityId;
    if (facilityId == null) {
      setState(() {
        _loading = false;
        _error = 'No facility found for this account yet.';
      });
      return;
    }
    if (!_range.isComplete) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      final results = await Future.wait([
        repo.getProfitAndLoss(facilityId, _range),
        repo.getPnlTrend(facilityId, _range, _granularity()),
      ]);
      if (!mounted) return;
      setState(() {
        _pnl = results[0] as ProfitAndLoss;
        _trend = results[1] as List<PnlTrendPoint>;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profit & Loss')),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Calculating…')
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        FinanceDateRangePicker(
                          value: _range,
                          onChanged: (next) {
                            setState(() => _range = next);
                            _load();
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (_pnl != null) ..._content(_pnl!),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
      ),
    );
  }

  List<Widget> _content(ProfitAndLoss p) {
    if (p.totalRevenueMinor == 0 && p.totalExpenseMinor == 0) {
      return const [
        EmptyStateView(
          title: 'Not enough financial data',
          message: 'There is no recognised revenue or recorded expense in this period.',
        ),
      ];
    }

    final revenueRows = <({String label, int value})>[
      (label: 'Court booking revenue', value: p.bookingRevenueMinor),
      (label: 'Membership revenue', value: p.membershipRevenueMinor),
      (label: 'Guest booking revenue', value: p.guestBookingRevenueMinor),
      (label: 'Other revenue', value: p.otherRevenueMinor),
    ].where((r) => r.value != 0).toList();

    return [
      _kpiGrid(p),
      const SizedBox(height: AppSpacing.md),
      _card('Revenue vs expenses', _TrendBars(points: _trend)),
      const SizedBox(height: AppSpacing.md),
      _card(
        'Revenue',
        Column(
          children: [
            for (final r in revenueRows) _line(r.label, r.value),
            if (p.refundsMinor > 0) _line('Less: refunds', -p.refundsMinor),
            const Divider(),
            _line('Total revenue', p.totalRevenueMinor, bold: true),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      _card(
        'Expenses by category',
        Column(
          children: [
            if (p.expenseByCategory.isEmpty)
              Text('No expenses recorded in this period.', style: AppTypography.secondary(context))
            else
              for (final c in p.expenseByCategory) _line(c.category, c.amountMinor),
            const Divider(),
            _line('Total expenses', p.totalExpenseMinor, bold: true),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(child: Text('Net operating profit / loss', style: AppTypography.rowTitle(context))),
            Text(
              financeAmount(p.netProfitMinor),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: p.netProfitMinor < 0 ? AppColors.destructive : AppColors.success,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _kpiGrid(ProfitAndLoss p) {
    final tiles = <({String label, String value, Color? tone})>[
      (label: 'Total Revenue', value: financeAmount(p.totalRevenueMinor), tone: null),
      (label: 'Total Expenses', value: financeAmount(p.totalExpenseMinor), tone: null),
      (
        label: 'Net Profit',
        value: financeAmount(p.netProfitMinor),
        tone: p.netProfitMinor < 0 ? AppColors.destructive : AppColors.success,
      ),
      (label: 'Profit Margin', value: '${p.profitMarginPct.toStringAsFixed(1)}%', tone: null),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - AppSpacing.sm) / 2;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final t in tiles)
            SizedBox(
              width: width,
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.label, style: AppTypography.caption(context)),
                    const SizedBox(height: 2),
                    Text(t.value, style: TextStyle(fontWeight: FontWeight.w800, color: t.tone)),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _card(String title, Widget child) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.rowTitle(context)),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _line(String label, int minor, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: bold
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : AppTypography.secondary(context)),
          ),
          Text(financeAmount(minor),
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}

/// A compact revenue-vs-expense bar per bucket — no chart package, and every
/// bar length is a fraction of a server-provided figure, never a derived total.
class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.points});

  final List<PnlTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Text('Not enough financial data to chart this period.',
          style: AppTypography.secondary(context));
    }
    final max = points
        .map((p) => p.revenueMinor > p.expenseMinor ? p.revenueMinor : p.expenseMinor)
        .fold<int>(1, (a, b) => b > a ? b : a);

    return Column(
      children: [
        for (final p in points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Formatters.dateShort(DateTime.parse(p.date)),
                    style: AppTypography.caption(context)),
                const SizedBox(height: 2),
                _bar(p.revenueMinor / max, AppColors.success),
                const SizedBox(height: 2),
                _bar(p.expenseMinor / max, AppColors.warning),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _legend(AppColors.success, 'Revenue'),
            const SizedBox(width: AppSpacing.md),
            _legend(AppColors.warning, 'Expenses'),
          ],
        ),
      ],
    );
  }

  Widget _bar(double fraction, Color color) {
    return LayoutBuilder(builder: (context, c) {
      return Container(
        height: 8,
        width: (c.maxWidth * fraction.clamp(0.0, 1.0)).clamp(2.0, c.maxWidth),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      );
    });
  }

  Widget _legend(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
