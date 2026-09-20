import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/skeleton.dart';
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
      appBar: AppBar(
        title: const Text('Profit & Loss', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: _loading
            ? const _ProfitLossSkeleton()
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
    final tokens = context.tokens;
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

    final profitColor = p.netProfitMinor < 0 ? tokens.destructive : tokens.success;

    return [
      _kpiGrid(p),
      const SizedBox(height: AppSpacing.md),
      _card('Revenue vs expenses', Icons.stacked_line_chart_rounded, tokens.electricBlue,
          _TrendBars(points: _trend)),
      const SizedBox(height: AppSpacing.md),
      _card(
        'Revenue',
        Icons.payments_outlined,
        tokens.primary,
        Column(
          children: [
            for (final r in revenueRows) _line(r.label, r.value),
            if (p.refundsMinor > 0) _line('Less: refunds', -p.refundsMinor),
            Divider(color: tokens.borderColor),
            _line('Total revenue', p.totalRevenueMinor, bold: true),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      _card(
        'Expenses by category',
        Icons.receipt_long_outlined,
        tokens.destructive,
        Column(
          children: [
            if (p.expenseByCategory.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text('No expenses recorded in this period.',
                    style: AppTypography.secondary(context)),
              )
            else
              for (final c in p.expenseByCategory) _line(c.category, c.amountMinor),
            Divider(color: tokens.borderColor),
            _line('Total expenses', p.totalExpenseMinor, bold: true),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: tokens.accentFill(profitColor),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tokens.accentEdge(profitColor)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: profitColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                  p.netProfitMinor < 0
                      ? Icons.trending_down_rounded
                      : Icons.trending_up_rounded,
                  size: 18,
                  color: profitColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('Net operating profit / loss',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
            ),
            Text(
              financeAmount(p.netProfitMinor),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: profitColor),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _kpiGrid(ProfitAndLoss p) {
    final tokens = context.tokens;
    final profitColor = p.netProfitMinor < 0 ? tokens.destructive : tokens.success;
    final tiles = <({String label, String value, Color accent, IconData icon})>[
      (
        label: 'Total Revenue',
        value: financeAmount(p.totalRevenueMinor),
        accent: tokens.primary,
        icon: Icons.payments_outlined,
      ),
      (
        label: 'Total Expenses',
        value: financeAmount(p.totalExpenseMinor),
        accent: tokens.destructive,
        icon: Icons.receipt_long_outlined,
      ),
      (
        label: 'Net Profit',
        value: financeAmount(p.netProfitMinor),
        accent: profitColor,
        icon: p.netProfitMinor < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
      ),
      (
        label: 'Profit Margin',
        value: '${p.profitMarginPct.toStringAsFixed(1)}%',
        accent: tokens.electricBlue,
        icon: Icons.donut_small_outlined,
      ),
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
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
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
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tokens.accentFill(t.accent),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(t.icon, size: 14, color: t.accent),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(t.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption(context)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(t.value,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14, color: t.accent)),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _card(String title, IconData icon, Color accent, Widget child) {
    final tokens = context.tokens;
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
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.accentFill(accent),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
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
    final tokens = context.tokens;
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
                const SizedBox(height: 3),
                _bar(context, p.revenueMinor / max, tokens.success),
                const SizedBox(height: 3),
                _bar(context, p.expenseMinor / max, tokens.warning),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _legend(tokens.success, 'Revenue'),
            const SizedBox(width: AppSpacing.md),
            _legend(tokens.warning, 'Expenses'),
          ],
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, double fraction, Color color) {
    final tokens = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      return Stack(
        children: [
          Container(
            height: 8,
            width: double.infinity,
            decoration: BoxDecoration(color: tokens.surface2, borderRadius: BorderRadius.circular(4)),
          ),
          Container(
            height: 8,
            width: (c.maxWidth * fraction.clamp(0.0, 1.0)).clamp(2.0, c.maxWidth),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
        ],
      );
    });
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Structure-shaped placeholder shown while the P&L and its trend load —
/// date picker, the 4-tile KPI grid, a chart block, two line-item cards, and
/// the net-profit banner.
class _ProfitLossSkeleton extends StatelessWidget {
  const _ProfitLossSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [
        AppSkeleton(height: 48, radius: AppRadius.md),
        SizedBox(height: AppSpacing.lg),
        _KpiGridSkeleton(),
        SizedBox(height: AppSpacing.md),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 180, height: 16),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(height: 100, radius: AppRadius.sm),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 100, height: 16),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(width: 140, height: 13),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 180, height: 16),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(width: 140, height: 13),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        AppSkeleton(height: 68, radius: AppRadius.lg),
      ],
    );
  }
}

/// The 4-tile KPI-grid placeholder for `_kpiGrid`.
class _KpiGridSkeleton extends StatelessWidget {
  const _KpiGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - AppSpacing.sm) / 2;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (var i = 0; i < 4; i++)
            SizedBox(width: width, child: const SkeletonStatTile(height: 76)),
        ],
      );
    });
  }
}
