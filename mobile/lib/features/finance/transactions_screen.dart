import 'dart:async';

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
import 'transaction_details_sheet.dart';

/// Finance → Transactions — mirrors
/// src/features/finance/components/transactions-list.tsx.
///
/// One list over the whole ledger: payments, refunds and expenses. Filtering,
/// searching and paging all happen server-side (`list_finance_ledger`,
/// 0049_finance_ledger.sql). This screen never downloads more than the page it
/// shows and never sums the rows it holds — the only total it displays is the
/// server's own `total_count`.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  /// Matches the web's PAGE_SIZE for the ledger.
  static const int _pageSize = 10;

  /// Every category the ledger can produce — mirrors web's `CATEGORIES`.
  static const List<String> _categories = [
    'Guest Booking Revenue',
    'Membership Revenue',
    'Court Booking Revenue',
    'Other Revenue',
    'Booking Refund',
  ];

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  String? _facilityId;
  bool _isReady = false;
  String? _loadError;

  FinanceDateRange _range = const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth);
  LedgerTxnType? _txnType;
  String? _category;
  String? _paymentMethod;
  String _search = '';
  int _page = 0;

  List<String> _methods = [];
  List<LedgerEntry> _entries = [];
  int _totalCount = 0;
  bool _listLoading = false;
  String? _listError;

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

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    try {
      final methods = await ref.read(financeRepositoryProvider).listPaymentMethods(facilityId);
      if (mounted) setState(() => _methods = methods);
    } on AppException {
      // A missing method list only narrows the filter; the list still loads.
    }
    if (!mounted) return;
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
      final page = await ref.read(financeRepositoryProvider).listLedger(
            ListLedgerInput(
              facilityId: facilityId,
              dateRange: _range,
              filters: LedgerFilters(
                txnType: _txnType,
                category: _category,
                paymentMethod: _paymentMethod,
                search: _search.trim().isEmpty ? null : _search.trim(),
              ),
              limit: _pageSize,
              offset: _page * _pageSize,
            ),
          );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _entries = page.entries;
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

  /// Any filter change resets to page 1 — page 3 of the old filter would look
  /// empty against the new one.
  void _applyFilterChange(VoidCallback mutate) {
    setState(() {
      mutate();
      _page = 0;
    });
    _load();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _applyFilterChange(() => _search = value);
    });
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _load();
  }

  Future<void> _pickType() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _txnType?.toJson() ?? 'ALL',
      options: const [
        (value: 'ALL', label: 'All Types'),
        (value: 'INCOME', label: 'Income'),
        (value: 'EXPENSE', label: 'Expense'),
        (value: 'REFUND', label: 'Refund'),
      ],
    );
    if (picked == null) return;
    _applyFilterChange(() => _txnType = picked == 'ALL' ? null : LedgerTxnType.fromJson(picked));
  }

  Future<void> _pickCategory() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _category ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Categories'),
        ..._categories.map((c) => (value: c, label: c)),
      ],
    );
    if (picked == null) return;
    _applyFilterChange(() => _category = picked == 'ALL' ? null : picked);
  }

  Future<void> _pickMethod() async {
    if (_methods.isEmpty) return;
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _paymentMethod ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Payment Modes'),
        ..._methods.map((m) => (value: m, label: m)),
      ],
    );
    if (picked == null) return;
    _applyFilterChange(() => _paymentMethod = picked == 'ALL' ? null : picked);
  }

  Future<void> _addExpense() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    try {
      final categories = await ref.read(financeRepositoryProvider).listExpenseCategories(facilityId);
      if (!mounted || categories.isEmpty) return;
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => AddExpenseSheet(facilityId: facilityId, categories: categories),
      );
      if (saved == true) _applyFilterChange(() => _page = 0);
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _totalCount == 0 ? 1 : ((_totalCount + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
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
            ? ErrorView(message: _loadError ?? 'Unable to load transactions right now.')
            : RefreshIndicator(
                onRefresh: _load,
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Search',
                          hintText: 'Transaction ID, description…',
                        ),
                        onChanged: _onSearchChanged,
                        onSubmitted: (value) => _applyFilterChange(() => _search = value),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          PickerChip(
                            label: _txnType == null ? 'All Types' : _txnType!.label,
                            onSelect: _pickType,
                          ),
                          PickerChip(
                            label: _category ?? 'All Categories',
                            onSelect: _pickCategory,
                          ),
                          PickerChip(
                            label: _paymentMethod ?? 'All Payment Modes',
                            onSelect: _methods.isEmpty ? () {} : _pickMethod,
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
                        Text('Choose a start and end date to see transactions.',
                            style: AppTypography.secondary(context))
                      else if (_listLoading)
                        const LoadingView(message: 'Loading transactions…')
                      else if (_entries.isEmpty)
                        Text('No transactions match these filters.',
                            style: AppTypography.secondary(context))
                      else
                        ..._entries.map(_buildEntryCard),
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

  Widget _buildEntryCard(LedgerEntry entry) {
    // The sign follows what kind of money it is, from the server's txn_type —
    // never derived from the amount, which is always a positive magnitude.
    final signed = '${entry.isIncome ? '' : '−'}${financeAmount(entry.amountMinor)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: entry.isIncome
            ? () => showTransactionDetailsSheet(context, transactionId: entry.id)
            : null,
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
                      Text(entry.description, style: AppTypography.rowTitle(context)),
                      Text(
                        '${entry.reference} · ${Formatters.dateShort(entry.occurredAt.toLocal())}',
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(signed, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Tag(entry.category),
                if (entry.paymentMethod != null) _Tag(entry.paymentMethod!),
                StatusBadge(label: _statusLabel(entry.status), tone: _statusTone(entry.status)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) => status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

StatusTone _statusTone(String status) {
  switch (status) {
    case 'paid':
    case 'processed':
      return StatusTone.success;
    case 'failed':
      return StatusTone.danger;
    case 'refunded':
      return StatusTone.neutral;
    default:
      return StatusTone.warning;
  }
}

/// A small neutral pill for a ledger row's category / payment mode.
class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: context.tokens.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// Previous/Next over server-side pages, with the server's own total count.
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
          'Page ${page + 1} of $totalPages · $totalCount transaction${totalCount == 1 ? '' : 's'}',
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
