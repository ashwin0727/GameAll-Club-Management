import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/picker_chip.dart';
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
    final totalPages = _totalCount == 0 ? 1 : ((_totalCount + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
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
                    if (_summary != null) _SummaryGrid(summary: _summary!),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
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
                        PickerChip(
                          label: _paymentStatus?.label ?? 'Any status',
                          onSelect: _pickPaymentStatus,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FinanceDateRangePicker(
                      value: _range,
                      onChanged: (next) => _applyFilterChange(() => _range = next),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_listError != null) ...[
                      Text(_listError!, style: const TextStyle(color: AppColors.destructive)),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    if (_range.preset == FinanceDateRangePreset.custom && !_range.isComplete)
                      Text('Choose a start and end date to see expenses.',
                          style: AppTypography.secondary(context))
                    else if (_listLoading)
                      const LoadingView(message: 'Loading expenses…')
                    else if (_expenses.isEmpty)
                      Text('No expenses recorded for this period.',
                          style: AppTypography.secondary(context))
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

  Widget _buildExpenseRow(ExpenseRow expense) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Opacity(
        opacity: expense.isVoid ? 0.5 : 1,
        child: AppCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: () => context.push('${AppRoutes.financeExpenses}/${expense.id}'),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                          : StatusBadge(label: expense.paymentStatus.label, tone: _tone(expense.paymentStatus)),
                      const Spacer(),
                      if (!expense.isVoid && expense.paymentStatus != ExpensePaymentStatus.paid)
                        OutlinedButton(
                          onPressed: () => _markPaid(expense),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, AppSpacing.minTouchTarget),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Mark paid'),
                        ),
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

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    final tiles = <({String label, String value})>[
      (label: 'Total (period)', value: financeAmount(summary.totalMinor)),
      (label: 'This Month', value: financeAmount(summary.thisMonthMinor)),
      (label: 'This Week', value: financeAmount(summary.thisWeekMinor)),
      (
        label: summary.pendingCount > 0 ? 'Unpaid (${summary.pendingCount})' : 'Unpaid',
        value: financeAmount(summary.pendingMinor),
      ),
      (label: 'Maintenance', value: financeAmount(summary.maintenanceMinor)),
      (label: 'Other Operating', value: financeAmount(summary.otherMinor)),
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
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.label, style: AppTypography.caption(context)),
                    const SizedBox(height: 2),
                    Text(t.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

