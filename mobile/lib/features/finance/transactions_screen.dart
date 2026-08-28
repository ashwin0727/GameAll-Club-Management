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
import '../../data/models/payment.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'finance_date_range_picker.dart';
import 'finance_presentation.dart';
import 'transaction_details_sheet.dart';

/// Finance → Transactions — mirrors
/// src/features/finance/components/transactions-list.tsx.
///
/// Filtering, searching, and paging all happen server-side
/// (`list_finance_transactions` + `count_finance_transactions`,
/// 0024_finance.sql). This screen never downloads a full transaction list and
/// slices it locally, and it never sums the rows it holds — the only total it
/// displays is the server's own `count(*)` (spec §"Transaction Pagination").
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  /// Matches the web's PAGE_SIZE — one page is one RPC call, both sides.
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  String? _facilityId;
  bool _isReady = false;
  String? _loadError;

  FinanceDateRange _range = const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth);
  PaymentSourceType? _sourceType;
  TransactionStatus? _status;
  String _search = '';
  int _page = 0;

  List<FinanceTransaction> _transactions = [];
  int _totalCount = 0;
  bool _listLoading = false;
  String? _listError;

  /// Guards against an earlier, slower page's response overwriting a newer
  /// one — the mobile equivalent of the web effect's `cancelled` flag.
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    // A half-picked CUSTOM range isn't askable yet — the server would reject
    // it with "valid start and end date".
    if (!_range.isComplete) return;

    final requestId = ++_requestId;
    setState(() {
      _listLoading = true;
      _listError = null;
    });
    try {
      final page = await ref.read(financeRepositoryProvider).listTransactions(
            ListTransactionsInput(
              facilityId: facilityId,
              dateRange: _range,
              sourceType: _sourceType,
              status: _status,
              search: _search.trim().isEmpty ? null : _search.trim(),
              limit: _pageSize,
              offset: _page * _pageSize,
            ),
          );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _transactions = page.transactions;
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

  /// Any filter change resets to page 1 — otherwise page 3 of the old filter
  /// would be requested against the new one and look empty.
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

  Future<void> _pickSourceType() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _sourceType?.toJson() ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Sources'),
        ...PaymentSourceType.values.map((s) => (value: s.toJson(), label: sourceTypeMenuLabel(s))),
      ],
    );
    if (picked == null) return;
    _applyFilterChange(() => _sourceType = picked == 'ALL' ? null : PaymentSourceType.fromJson(picked));
  }

  Future<void> _pickStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _status?.toJson() ?? 'ALL',
      options: const [
        (value: 'ALL', label: 'All Status'),
        (value: 'paid', label: 'Paid'),
        // The DB value is `created`; the web labels it "Pending" for owners.
        (value: 'created', label: 'Pending'),
        (value: 'failed', label: 'Failed'),
        (value: 'refunded', label: 'Refunded'),
      ],
    );
    if (picked == null) return;
    _applyFilterChange(() => _status = picked == 'ALL' ? null : TransactionStatus.fromJson(picked));
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // Ceiling division on the server's own count — page arithmetic, not
    // revenue arithmetic.
    final totalPages = _totalCount == 0 ? 1 : ((_totalCount + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
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
                          hintText: 'ID, name, booking, or Razorpay ID',
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
                            label: _sourceType == null ? 'All Sources' : sourceTypeMenuLabel(_sourceType!),
                            onSelect: _pickSourceType,
                          ),
                          PickerChip(
                            label: _status == null ? 'All Status' : transactionStatusLabel(_status!),
                            onSelect: _pickStatus,
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
                        Text('Choose a start and end date to see transactions.', style: AppTypography.secondary(context))
                      else if (_listLoading)
                        const LoadingView(message: 'Loading transactions…')
                      else if (_transactions.isEmpty)
                        Text('No transactions found for this period.', style: AppTypography.secondary(context))
                      else
                        ..._transactions.map(_buildTransactionCard),
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

  Widget _buildTransactionCard(FinanceTransaction txn) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => showTransactionDetailsSheet(context, transactionId: txn.id),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(txn.reference, style: AppTypography.rowTitle(context)),
                  Text(
                    '${Formatters.dateShort(txn.effectiveAt.toLocal())} · '
                    '${sourceTypeLabel(txn.sourceType)} · ${txn.customerName ?? '—'}',
                    style: AppTypography.caption(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(financeAmount(txn.amountMinor), style: const TextStyle(fontWeight: FontWeight.w600)),
                // Only shown when money actually went back — and it is the
                // view's own net_minor, never amount minus refunded computed
                // on this device.
                if (txn.refundedMinor > 0)
                  Text('Net ${financeAmount(txn.netMinor)}', style: AppTypography.caption(context)),
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

/// Previous/Next over server-side pages, with the server's own total count.
/// Wrapped so the label and the buttons stack rather than overflow at 320dp
/// or at large system font sizes.
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