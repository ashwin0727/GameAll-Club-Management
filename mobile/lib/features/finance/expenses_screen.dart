import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'add_expense_sheet.dart';
import 'finance_date_range_picker.dart';
import 'finance_presentation.dart';

/// Finance → Expenses — mirrors
/// src/features/finance/components/expenses-page.tsx.
///
/// The counterpart to Transactions: mostly money going out. Filtering and
/// paging happen server-side (`list_expenses`, 0046_finance_expenses.sql).
/// The one figure this screen adds is "total on this page" — a display sum of
/// values the server already computed for the rows in view, never a headline
/// total and never anything the repository does.
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
  int _page = 0;

  List<ExpenseRow> _expenses = [];
  int _totalCount = 0;
  bool _listLoading = false;
  String? _listError;
  String? _voidingId;

  /// Guards against an earlier, slower page's response overwriting a newer one.
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
      // A category-load failure only disables the filter and the Add form;
      // the list itself can still render.
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
      final page = await ref.read(financeRepositoryProvider).listExpenses(
            ListExpensesInput(
              facilityId: facilityId,
              dateRange: _range,
              categoryId: _categoryId,
              limit: _pageSize,
              offset: _page * _pageSize,
            ),
          );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _expenses = page.expenses;
        _totalCount = page.totalCount;
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
    if (saved == true) {
      _applyFilterChange(() => _page = 0);
    }
  }

  Future<void> _voidExpense(ExpenseRow expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void this expense?'),
        content: Text(
          'The ${financeAmount(expense.amountMinor)} ${expense.categoryName} expense stays on the books, marked void.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Void')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _voidingId = expense.id);
    try {
      await ref.read(financeRepositoryProvider).voidExpense(expense.id);
      if (!mounted) return;
      setState(() => _voidingId = null);
      await _load();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _voidingId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _totalCount == 0 ? 1 : ((_totalCount + _pageSize - 1) ~/ _pageSize);
    // Display sum of the server's own per-row figures for the rows in view —
    // not a headline total, and never computed in the repository.
    final pageTotalMinor = _expenses
        .where((e) => !e.isVoid)
        .fold<int>(0, (sum, e) => sum + e.amountMinor);

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
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          PickerChip(
                            label: _categoryId == null
                                ? 'All Categories'
                                : _categories
                                    .firstWhere(
                                      (c) => c.id == _categoryId,
                                      orElse: () => const ExpenseCategory(id: '', name: 'Category'),
                                    )
                                    .name,
                            onSelect: _categories.isEmpty ? () {} : _pickCategory,
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
                      else ...[
                        AppCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('Total on this page', style: AppTypography.caption(context)),
                              ),
                              Text(
                                financeAmount(pageTotalMinor),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ..._expenses.map(_buildExpenseRow),
                      ],
                      if (_totalCount > 0 && !_listLoading) ...[
                        const SizedBox(height: AppSpacing.md),
                        _Pagination(
                          page: _page,
                          totalPages: totalPages,
                          totalCount: _totalCount,
                          onPrevious: _page == 0 ? null : () => _goToPage(_page - 1),
                          onNext: _page + 1 >= totalPages ? null : () => _goToPage(_page + 1),
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

  Widget _buildExpenseRow(ExpenseRow expense) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Opacity(
        opacity: expense.isVoid ? 0.5 : 1,
        child: AppCard(
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
                  Text(financeAmount(expense.amountMinor),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: expense.isVoid
                    ? const StatusBadge(label: 'Void', tone: StatusTone.neutral)
                    : OutlinedButton.icon(
                        onPressed: _voidingId == expense.id ? null : () => _voidExpense(expense),
                        icon: const Icon(Icons.undo, size: 16),
                        label: Text(_voidingId == expense.id ? 'Voiding…' : 'Void'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Previous/Next over server-side pages, with the server's own total count.
/// Wrapped so the label and buttons stack rather than overflow at 320dp.
class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.totalCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final int totalCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        Text(
          'Page ${page + 1} of $totalPages · $totalCount expense${totalCount == 1 ? '' : 's'}',
          style: AppTypography.secondary(context),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SecondaryButton(label: 'Previous', onPressed: onPrevious),
            const SizedBox(width: AppSpacing.sm),
            SecondaryButton(label: 'Next', onPressed: onNext),
          ],
        ),
      ],
    );
  }
}
