import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
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
import 'finance_presentation.dart';

/// Finance → Pending Payments — mirrors
/// src/features/finance/components/pending-payments-page.tsx.
///
/// Everything still owed, from every source, in one place — so collecting a
/// membership balance and a guest booking balance are the same job. Nothing
/// here computes what is owed: `list_pending_payments` /
/// `get_pending_payments_summary` (0052 + 0053) derive it from cost and
/// collections. An error is shown as an error, never as "all caught up".
class PendingPaymentsScreen extends ConsumerStatefulWidget {
  const PendingPaymentsScreen({super.key});

  @override
  ConsumerState<PendingPaymentsScreen> createState() => _PendingPaymentsScreenState();
}

class _PendingPaymentsScreenState extends ConsumerState<PendingPaymentsScreen> {
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  String? _facilityId;
  bool _isReady = false;
  String? _loadError;

  String _search = '';
  ObligationSource? _sourceType;
  PendingPaymentStatusFilter _status = PendingPaymentStatusFilter.allOutstanding;
  ObligationSort _sort = ObligationSort.dueDate;
  int _page = 0;

  PendingPaymentsSummary? _summary;
  List<PaymentObligation>? _obligations;
  int _totalCount = 0;
  String? _error;

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

    final requestId = ++_requestId;
    setState(() {
      _error = null;
      _obligations = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      final results = await Future.wait([
        repo.listPendingPayments(
          ListPendingPaymentsInput(
            facilityId: facilityId,
            filters: PendingPaymentFilters(
              search: _search.trim().isEmpty ? null : _search.trim(),
              sourceType: _sourceType,
              status: _status,
              sort: _sort,
            ),
            limit: _pageSize,
            offset: _page * _pageSize,
          ),
        ),
        repo.getPendingPaymentsSummary(facilityId),
      ]);
      if (!mounted || requestId != _requestId) return;
      final page = results[0] as PendingPaymentsPage;
      setState(() {
        _obligations = page.obligations;
        _totalCount = page.totalCount;
        _summary = results[1] as PendingPaymentsSummary;
      });
    } on AppException catch (e) {
      if (!mounted || requestId != _requestId) return;
      // Deliberately NOT an empty list: telling someone nothing is owed when
      // the query failed is the worst way this page can be wrong.
      setState(() => _error = e.message);
    }
  }

  void _applyFilterChange(VoidCallback mutate) {
    setState(() {
      mutate();
      _page = 0;
    });
    _load();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _applyFilterChange(() => _search = value);
    });
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _load();
  }

  Future<void> _openRecord(PaymentObligation o) async {
    await context.push('${AppRoutes.financePendingPayments}/${o.sourceId}/record');
    if (mounted) _load();
  }

  Future<void> _pickStatus() async {
    final picked = await showPickerSheet<PendingPaymentStatusFilter>(
      context: context,
      selected: _status,
      options: PendingPaymentStatusFilter.values
          .map((s) => (value: s, label: s.label))
          .toList(),
    );
    if (picked != null) _applyFilterChange(() => _status = picked);
  }

  Future<void> _pickSource() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _sourceType?.toJson() ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Sources'),
        ...ObligationSource.values.map((s) => (value: s.toJson(), label: s.label)),
      ],
    );
    if (picked == null) return;
    _applyFilterChange(() => _sourceType = picked == 'ALL' ? null : ObligationSource.fromJson(picked));
  }

  Future<void> _pickSort() async {
    final picked = await showPickerSheet<ObligationSort>(
      context: context,
      selected: _sort,
      options: ObligationSort.values.map((s) => (value: s, label: s.label)).toList(),
    );
    if (picked != null) _applyFilterChange(() => _sort = picked);
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _totalCount == 0 ? 1 : ((_totalCount + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(title: const Text('Pending Payments')),
      body: SafeArea(
        child: !_isReady
            ? ErrorView(message: _loadError ?? 'Unable to load pending payments.')
            : RefreshIndicator(
                onRefresh: _load,
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Track and collect outstanding payments.',
                        style: AppTypography.secondary(context),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _KpiRow(summary: _summary),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Search',
                          hintText: 'Customer, phone, booking or membership ID',
                        ),
                        onChanged: _onSearchChanged,
                        onSubmitted: (v) => _applyFilterChange(() => _search = v),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          PickerChip(label: _status.label, onSelect: _pickStatus),
                          PickerChip(
                            label: _sourceType?.label ?? 'All Sources',
                            onSelect: _pickSource,
                          ),
                          PickerChip(label: 'Sort: ${_sort.label}', onSelect: _pickSort),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_error != null)
                        _ErrorPanel(message: _error!, onRetry: _load)
                      else if (_obligations == null)
                        const LoadingView(message: 'Loading pending payments…')
                      else if (_obligations!.isEmpty)
                        _AllCaughtUp()
                      else ...[
                        ..._obligations!.map(_buildObligationCard),
                        if (_totalCount > 0) ...[
                          const SizedBox(height: AppSpacing.md),
                          _Pagination(
                            page: _page,
                            totalPages: totalPages,
                            totalCount: _totalCount,
                            onPrevious: _page == 0 ? null : () => _goToPage(_page - 1),
                            onNext: _page + 1 >= totalPages ? null : () => _goToPage(_page + 1),
                          ),
                        ],
                      ],
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildObligationCard(PaymentObligation o) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                      Text(o.customerName, style: AppTypography.rowTitle(context)),
                      Text('${o.sourceType.label} · ${o.reference}',
                          style: AppTypography.caption(context)),
                      const SizedBox(height: 2),
                      Text(o.description, style: AppTypography.caption(context)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusBadge(label: o.status.label, tone: _tone(o.status)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _AmountRow(label: 'Total', minor: o.totalMinor),
            _AmountRow(label: 'Paid', minor: o.paidMinor, muted: true),
            const Divider(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text('Outstanding', style: AppTypography.rowTitle(context)),
                ),
                Text(financeAmount(o.outstandingMinor),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Due ${Formatters.dateShort(DateTime.parse(o.dueOn))}',
                style: AppTypography.caption(context)),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: o.isSettled ? 'View' : 'Record ${financeAmount(o.outstandingMinor)}',
              onPressed: () => _openRecord(o),
            ),
          ],
        ),
      ),
    );
  }
}

StatusTone _tone(ObligationStatus status) {
  switch (status) {
    case ObligationStatus.overdue:
      return StatusTone.danger;
    case ObligationStatus.partiallyPaid:
      return StatusTone.warning;
    case ObligationStatus.paid:
      return StatusTone.success;
    case ObligationStatus.pending:
      return StatusTone.neutral;
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.summary});

  final PendingPaymentsSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final tiles = <({String label, String value, Color? accent})>[
      (label: 'Outstanding Total', value: s == null ? '—' : financeAmount(s.outstandingMinor), accent: AppColors.primary),
      (label: 'Pending', value: s == null ? '—' : financeAmount(s.pendingMinor), accent: null),
      (label: 'Partially Paid', value: s == null ? '—' : financeAmount(s.partiallyPaidMinor), accent: null),
      (label: 'Overdue', value: s == null ? '—' : financeAmount(s.overdueMinor), accent: AppColors.destructive),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 160).floor().clamp(1, tiles.length);
        final width = (constraints.maxWidth - (AppSpacing.sm * (columns - 1))) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: tiles
              .map((t) => SizedBox(
                    width: width,
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.label, style: AppTypography.caption(context)),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            t.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: t.accent, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.minor, this.muted = false});

  final String label;
  final int minor;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final style = muted ? AppTypography.secondary(context) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.secondary(context))),
          Text(financeAmount(minor), style: style),
        ],
      ),
    );
  }
}

class _AllCaughtUp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline, size: 40, color: AppColors.primary),
            const SizedBox(height: AppSpacing.sm),
            Text("You're all caught up", style: AppTypography.rowTitle(context)),
            const SizedBox(height: AppSpacing.xs),
            Text('There are no pending payments for the selected filters.',
                textAlign: TextAlign.center, style: AppTypography.secondary(context)),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          children: [
            Text('Unable to load pending payments',
                style: AppTypography.rowTitle(context).copyWith(color: AppColors.destructive)),
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center, style: AppTypography.secondary(context)),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

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
        Text('Page ${page + 1} of $totalPages · $totalCount owed',
            style: AppTypography.secondary(context)),
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
