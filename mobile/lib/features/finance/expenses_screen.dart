import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'add_expense_sheet.dart';
import 'finance_date_range_picker.dart';
import 'mark_expense_paid_sheet.dart';
import 'finance_presentation.dart';

/// Finance → Expenses — mirrors src/features/finance/components/expenses-page.tsx.
///
/// Filtering and paging happen server-side (`list_expenses`, 0069). The KPI
/// row is `get_expense_summary` — never summed on the device. An expense
/// counts against Net Revenue the moment it is RECORDED; its payment status
/// only tracks what has actually been settled.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  static const int _pageSize = 20;

  String? _facilityId;
  bool _isReady = false;
  String? _loadError;

  List<ExpenseCategory> _categories = [];
  FinanceDateRange _range = const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth);
  String? _categoryId;
  ExpensePaymentStatus? _paymentStatus;
  int _page = 0;

  ExpenseSummary? _summary;
  List<ExpenseRow> _expenses = [];
  int _totalCount = 0;
  bool _listLoading = false;
  String? _listError;

  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) {
      _loadError = 'No facility found for this account yet.';
      return;
    }
    _facilityId = facility.id;
    _isReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    try {
      final categories = await ref.read(financeRepositoryProvider).listExpenseCategories(facilityId);
      if (!mounted) return;
      setState(() => _categories = categories);
    } on AppException {
      // A category-load failure only disables the filter and the Add form.
    }
    await _load();
  }

  Future<void> _load() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    if (!_range.isComplete) return;

    final requestId = ++_requestId;
    setState(() {
      _listLoading = true;
      _listError = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      final results = await Future.wait([
        repo.listExpenses(ListExpensesInput(
          facilityId: facilityId,
          dateRange: _range,
          categoryId: _categoryId,
          paymentStatus: _paymentStatus,
          limit: _pageSize,
          offset: _page * _pageSize,
        )),
        repo.getExpenseSummary(facilityId, _range),
      ]);
      if (!mounted || requestId != _requestId) return;
      final page = results[0] as ExpensePage;
      setState(() {
        _expenses = page.expenses;
        _totalCount = page.totalCount;
        _summary = results[1] as ExpenseSummary;
        _listLoading = false;
      });
    } on AppException catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _listLoading = false;
        _listError = e.message;
      });
    }
  }

  void _applyFilterChange(VoidCallback mutate) {
    setState(() {
      mutate();
      _page = 0;
    });
    _load();
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _load();
  }

  Future<void> _pickCategory() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _categoryId ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Categories'),
        ..._categories.map((c) => (value: c.id, label: c.name)),
      ],
    );
    if (picked == null) return;
    _applyFilterChange(() => _categoryId = picked == 'ALL' ? null : picked);
  }

  Future<void> _pickPaymentStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _paymentStatus?.toJson() ?? 'ALL',
      options: const [
        (value: 'ALL', label: 'Any payment status'),
        (value: 'PAID', label: 'Paid'),
        (value: 'PARTIAL', label: 'Partial'),
        (value: 'PENDING', label: 'Unpaid'),
      ],
    );
    if (picked == null) return;
    _applyFilterChange(
      () => _paymentStatus = picked == 'ALL' ? null : ExpensePaymentStatus.fromJson(picked),
    );
  }

  Future<void> _addExpense() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense categories are unavailable right now.')),
      );
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddExpenseSheet(facilityId: facilityId, categories: _categories),
    );
    if (saved == true) _applyFilterChange(() => _page = 0);
  }

  Future<void> _markPaid(ExpenseRow expense) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MarkExpensePaidSheet(expense: expense),
    );
    if (done == true) _load();
  }

  StatusTone _tone(ExpensePaymentStatus s) => switch (s) {
        ExpensePaymentStatus.paid => StatusTone.success,
        ExpensePaymentStatus.partial => StatusTone.warning,
        ExpensePaymentStatus.pending => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final totalPages = _totalCount == 0 ? 1 : ((_totalCount + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded, color: tokens.primary),
            tooltip: 'Add expense',
            onPressed: _isReady ? _addExpense : null,
          ),
        ],
      ),
      body: SafeArea(
        child: !_isReady
            ? ErrorView(message: _loadError ?? 'Unable to load expenses right now.')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text('Track facility expenses and operating costs.',
                        style: AppTypography.secondary(context)),
                    const SizedBox(height: AppSpacing.md),
                    if (_summary != null)
                      _SummaryGrid(summary: _summary!)
                    else
                      const _SummaryGridSkeleton(),
                    const SizedBox(height: AppSpacing.md),
                    // One horizontally-scrolling filter strip — same pattern
                    // as Transactions/Refunds/Reports — instead of a chip
                    // Wrap plus a separate date-range row underneath.
                    SizedBox(
                      height: AppSpacing.minTouchTarget,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          PickerChip(
                            label: _categoryId == null
                                ? 'All Categories'
                                : _categories
                                    .firstWhere((c) => c.id == _categoryId,
                                        orElse: () => const ExpenseCategory(id: '', name: 'Category'))
                                    .name,
                            onSelect: _categories.isEmpty ? () {} : _pickCategory,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          PickerChip(
                            label: _paymentStatus?.label ?? 'Any status',
                            onSelect: _pickPaymentStatus,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IntrinsicWidth(
                            child: FinanceDateRangePicker(
                              value: _range,
                              onChanged: (next) => _applyFilterChange(() => _range = next),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_listError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: tokens.destructive.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Text(_listError!,
                            style: TextStyle(color: tokens.destructive, fontSize: 13)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    if (_range.preset == FinanceDateRangePreset.custom && !_range.isComplete)
                      _EmptyRow(
                        icon: Icons.date_range_outlined,
                        color: tokens.textSecondary,
                        message: 'Choose a start and end date to see expenses.',
                      )
                    else if (_listLoading)
                      const _ExpensesListSkeleton()
                    else if (_expenses.isEmpty)
                      _EmptyRow(
                        icon: Icons.receipt_long_outlined,
                        color: tokens.textSecondary,
                        message: 'No expenses recorded for this period.',
                      )
                    else
                      ..._expenses.map(_buildExpenseRow),
                    if (_totalCount > 0 && !_listLoading) ...[
                      const SizedBox(height: AppSpacing.md),
                      PaginationBar(
                        page: _page,
                        totalPages: totalPages,
                        totalLabel: '$_totalCount expense${_totalCount == 1 ? '' : 's'}',
                        onPrevious: _page == 0 ? null : () => _goToPage(_page - 1),
                        onNext: _page + 1 >= totalPages ? null : () => _goToPage(_page + 1),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
      ),
    );
  }

  Color _toneColor(BuildContext context, StatusTone tone) {
    final tokens = context.tokens;
    return switch (tone) {
      StatusTone.success => tokens.success,
      StatusTone.warning => tokens.warning,
      StatusTone.danger => tokens.destructive,
      StatusTone.info => tokens.info,
      StatusTone.neutral => tokens.textSecondary,
    };
  }

  Widget _buildExpenseRow(ExpenseRow expense) {
    final tokens = context.tokens;
    final tone = expense.isVoid ? StatusTone.neutral : _tone(expense.paymentStatus);
    final color = _toneColor(context, tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Opacity(
        opacity: expense.isVoid ? 0.5 : 1,
        child: Material(
          color: tokens.surface1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              await context.push('${AppRoutes.financeExpenses}/${expense.id}');
              if (mounted) _load();
            },
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: tokens.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.accentFill(color),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Icon(Icons.receipt_long_rounded, size: 17, color: color),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(expense.vendor ?? expense.categoryName,
                                style: AppTypography.rowTitle(context)),
                            Text(
                              '${expense.categoryName} · ${Formatters.dateShort(DateTime.parse(expense.spentOn))}'
                              '${expense.paymentMethod != null ? ' · ${expense.paymentMethod}' : ''}',
                              style: AppTypography.caption(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(financeAmount(expense.amountMinor),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (expense.paymentStatus == ExpensePaymentStatus.partial)
                            Text('${financeAmount(expense.outstandingMinor)} due',
                                style: AppTypography.caption(context)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      expense.isVoid
                          ? const StatusBadge(label: 'Void', tone: StatusTone.neutral)
                          : StatusBadge(label: expense.paymentStatus.label, tone: tone),
                      const Spacer(),
                      if (!expense.isVoid && expense.paymentStatus != ExpensePaymentStatus.paid)
                        _MarkPaidButton(onPressed: () => _markPaid(expense)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small solid-green pill CTA — matches Refunds' "Initiate Refund" button,
/// rather than a flat outlined button that reads as a secondary action.
class _MarkPaidButton extends StatelessWidget {
  const _MarkPaidButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.primary,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
          child: Text('Mark paid',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: tokens.onAccent(tokens.primary))),
        ),
      ),
    );
  }
}

/// A quiet "nothing here" row — an icon + message instead of a bare line of
/// grey text, matching the rest of the app's list screens.
class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.icon, required this.color, required this.message});

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Each tile gets its own accent, same as the dashboard's quick actions
    // and the Reports hub — six tiles, six of the app's distinct colours, so
    // the grid scans at a glance instead of reading as one grey block.
    final tiles = <({String label, String value, IconData icon, Color accent})>[
      (
        label: 'Total (period)',
        value: financeAmount(summary.totalMinor),
        icon: Icons.account_balance_wallet_outlined,
        accent: tokens.primary,
      ),
      (
        label: 'This Month',
        value: financeAmount(summary.thisMonthMinor),
        icon: Icons.calendar_month_outlined,
        accent: tokens.electricBlue,
      ),
      (
        label: 'This Week',
        value: financeAmount(summary.thisWeekMinor),
        icon: Icons.date_range_outlined,
        accent: tokens.violet,
      ),
      (
        label: summary.pendingCount > 0 ? 'Unpaid (${summary.pendingCount})' : 'Unpaid',
        value: financeAmount(summary.pendingMinor),
        icon: Icons.hourglass_empty_rounded,
        accent: tokens.warning,
      ),
      (
        label: 'Maintenance',
        value: financeAmount(summary.maintenanceMinor),
        icon: Icons.build_outlined,
        accent: tokens.destructive,
      ),
      (
        label: 'Other Operating',
        value: financeAmount(summary.otherMinor),
        icon: Icons.category_outlined,
        accent: tokens.success,
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 520 ? 3 : 2;
      final width = (constraints.maxWidth - (cols - 1) * AppSpacing.sm) / cols;
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
                    Text(t.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Placeholder for [_SummaryGrid] while `_summary` is still loading — same
/// six-tile responsive layout, so the KPI row never renders as a blank gap.
class _SummaryGridSkeleton extends StatelessWidget {
  const _SummaryGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 520 ? 3 : 2;
      final width = (constraints.maxWidth - (cols - 1) * AppSpacing.sm) / cols;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (var i = 0; i < 6; i++)
            SizedBox(width: width, child: const SkeletonStatTile(height: 76)),
        ],
      );
    });
  }
}

/// Structure-shaped placeholder for the filter strip + expense list while
/// [_ExpensesScreenState._listLoading] is true.
class _ExpensesListSkeleton extends StatelessWidget {
  const _ExpensesListSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonChipRow(count: 3),
        SizedBox(height: AppSpacing.md),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
      ],
    );
  }
}

