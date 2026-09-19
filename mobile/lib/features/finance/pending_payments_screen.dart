import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
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
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
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
    } catch (e, stack) {
      if (!mounted || requestId != _requestId) return;
      debugPrint('Pending payments load failed: $e\n$stack');
      // Deliberately NOT an empty list: telling someone nothing is owed when
      // the query failed is the worst way this page can be wrong. Any error
      // type surfaces here rather than leaving the screen stuck on skeletons.
      setState(() => _error = e is AppException ? e.message : 'Unable to load pending payments. Pull to retry.');
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

  bool get _hasActiveFilters =>
      _sourceType != null ||
      _status != PendingPaymentStatusFilter.allOutstanding ||
      _sort != ObligationSort.dueDate;

  /// One sheet for every filter on the page, opened from the icon beside
  /// the search field — the same pattern as Guest Bookings, so filtering
  /// is the same gesture everywhere in the app.
  ///
  /// Each group is single-select because that is what the backend can
  /// express: `list_pending_payments` takes one `status` and one
  /// `sourceType`, not arrays. Selecting two statuses has no server-side
  /// meaning, and faking it by over-fetching and filtering locally would
  /// silently corrupt the pager's counts.
  Future<void> _openFilterSheet() async {
    final tokens = context.tokens;
    var tmpStatus = _status;
    var tmpSource = _sourceType;
    var tmpSort = _sort;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: tokens.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          Widget heading(String text) => Text(text,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: tokens.textSecondary));

          Widget group<T>(
            String title,
            List<({T value, String label})> opts,
            T current,
            ValueChanged<T> onPick,
          ) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading(title),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final o in opts)
                        _ChoiceChip(
                          label: o.label,
                          selected: o.value == current,
                          onTap: () => setSheet(() => onPick(o.value)),
                        ),
                    ],
                  ),
                ],
              );

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Filter payments',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                        ),
                        if (tmpStatus !=
                                PendingPaymentStatusFilter.allOutstanding ||
                            tmpSource != null ||
                            tmpSort != ObligationSort.dueDate)
                          TextButton(
                            onPressed: () => setSheet(() {
                              tmpStatus =
                                  PendingPaymentStatusFilter.allOutstanding;
                              tmpSource = null;
                              tmpSort = ObligationSort.dueDate;
                            }),
                            child: const Text('Clear all'),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    group<PendingPaymentStatusFilter>(
                      'STATUS',
                      PendingPaymentStatusFilter.values
                          .map((s) => (value: s, label: s.label))
                          .toList(),
                      tmpStatus,
                      (v) => tmpStatus = v,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    group<ObligationSource?>(
                      'SOURCE',
                      [
                        (value: null, label: 'All sources'),
                        ...ObligationSource.values
                            .map((s) => (value: s, label: s.label)),
                      ],
                      tmpSource,
                      (v) => tmpSource = v,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    group<ObligationSort>(
                      'SORT BY',
                      ObligationSort.values
                          .map((s) => (value: s, label: s.label))
                          .toList(),
                      tmpSort,
                      (v) => tmpSort = v,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AuthGradientButton(
                      label: 'Show results',
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _applyFilterChange(() {
                          _status = tmpStatus;
                          _sourceType = tmpSource;
                          _sort = tmpSort;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final totalPages = _totalCount == 0 ? 1 : ((_totalCount + _pageSize - 1) ~/ _pageSize);
    final filtered = _search.trim().isNotEmpty ||
        _sourceType != null ||
        _status != PendingPaymentStatusFilter.allOutstanding;

    return Scaffold(
      backgroundColor: tokens.surface0,
      appBar: AppBar(
        title: const Text('Pending Payments',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: !_isReady
            ? ErrorView(message: _loadError ?? 'Unable to load pending payments.')
            : RefreshIndicator(
                onRefresh: _load,
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OutstandingHero(summary: _summary, count: _totalCount),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: _SearchField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              onSubmitted: (v) =>
                                  _applyFilterChange(() => _search = v),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _FilterButton(
                              active: _hasActiveFilters,
                              onTap: _openFilterSheet),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_error != null)
                        _ErrorPanel(message: _error!, onRetry: _load)
                      else if (_obligations == null)
                        const _ObligationsListSkeleton()
                      else if (_obligations!.isEmpty)
                        _AllCaughtUp(filtered: filtered)
                      else ...[
                        for (final o in _obligations!)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _ObligationCard(
                                obligation: o,
                                onRecord: () => _openRecord(o)),
                          ),
                        if (_totalCount > 0) ...[
                          const SizedBox(height: AppSpacing.md),
                          PaginationBar(
                            page: _page,
                            totalPages: totalPages,
                            totalLabel: '$_totalCount owed',
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

/// The money-owed hero. One solid marigold slab carrying the figure the
/// whole page exists for, with the three-way split banded underneath it —
/// so "how much" and "how urgent" read in one glance instead of four flat
/// tiles that all look equally important.
class _OutstandingHero extends StatelessWidget {
  const _OutstandingHero({required this.summary, required this.count});

  final PendingPaymentsSummary? summary;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fill = tokens.accentSolid(tokens.warning);
    final onC = tokens.onAccent(tokens.warning);
    final s = summary;

    Widget fig(String label, int? minor, {bool alert = false}) {
      final loading = s == null;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading)
              AppSkeleton(width: 48, height: 15, radius: AppRadius.sm)
            else if (alert && (minor ?? 0) > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(financeAmount(minor!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: tokens.destructive)),
              )
            else
              Text(financeAmount(minor ?? 0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: onC)),
            const SizedBox(height: 1),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: onC.withValues(alpha: 0.75))),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Outstanding total',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: onC.withValues(alpha: 0.8))),
              ),
              if (count > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: onC.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$count to collect',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: onC)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          s == null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: AppSkeleton(width: 140, height: 30, radius: AppRadius.sm),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    financeAmount(s.outstandingMinor),
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                        color: onC),
                  ),
                ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: onC.withValues(alpha: 0.22)),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fig('Pending', s?.pendingMinor),
              fig('Partly paid', s?.partiallyPaidMinor),
              fig('Overdue', s?.overdueMinor, alert: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: tokens.borderColor),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: TextStyle(fontSize: 14, color: tokens.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 14),
          prefixIcon:
              Icon(Icons.search_rounded, size: 20, color: tokens.textSecondary),
          hintText: 'Search name, phone or reference',
          hintStyle: TextStyle(fontSize: 14, color: tokens.textSecondary),
        ),
      ),
    );
  }
}

/// The single filter affordance, sitting beside the search field. Carries a
/// dot when anything is narrowing the list, so an unexpected empty page is
/// never a mystery.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fill = active ? tokens.accentSolid(tokens.primary) : tokens.surface1;
    final fg = active ? tokens.onAccent(tokens.primary) : tokens.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: active ? fill : tokens.borderColor),
        ),
        child: Icon(Icons.tune_rounded, size: 20, color: fg),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fill =
        selected ? tokens.accentSolid(tokens.primary) : tokens.surface1;
    final fg = selected ? tokens.onAccent(tokens.primary) : tokens.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 9),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? fill : tokens.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: fg)),
          ],
        ),
      ),
    );
  }
}

/// One thing someone owes. Leads with who and how much, shows how far
/// along the payment is as a bar rather than two number rows, and puts the
/// action — the amount you'd actually take — on the button.
class _ObligationCard extends StatelessWidget {
  const _ObligationCard({required this.obligation, required this.onRecord});

  final PaymentObligation obligation;
  final VoidCallback onRecord;

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final o = obligation;
    final overdue = o.status == ObligationStatus.overdue;
    // How much of the bill is already in — the single most useful thing to
    // see before deciding what to chase.
    final progress = o.totalMinor <= 0
        ? 0.0
        : (o.paidMinor / o.totalMinor).clamp(0.0, 1.0).toDouble();
    final accent = overdue ? tokens.destructive : tokens.warning;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
            color: overdue
                ? tokens.destructive.withValues(alpha: 0.45)
                : tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.accentSolid(tokens.violet),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(_initials(o.customerName),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: tokens.onAccent(tokens.violet))),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.textPrimary)),
                    const SizedBox(height: 1),
                    Text('${o.sourceType.label} · ${o.reference}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: tokens.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(label: o.status.label, tone: _tone(o.status)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(o.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.md),

          // paid-of-total progress
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Positioned.fill(
                      child: ColoredBox(color: tokens.surface2)),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: ColoredBox(color: tokens.accentSolid(tokens.primary)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                    '${financeAmount(o.paidMinor)} of ${financeAmount(o.totalMinor)} paid',
                    style:
                        TextStyle(fontSize: 11, color: tokens.textSecondary)),
              ),
              Text('Due ${Formatters.dateShort(DateTime.parse(o.dueOn))}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: overdue ? FontWeight.w800 : FontWeight.w500,
                      color:
                          overdue ? tokens.destructive : tokens.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Outstanding',
                        style: TextStyle(
                            fontSize: 11, color: tokens.textSecondary)),
                    Text(financeAmount(o.outstandingMinor),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            color: accent)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: onRecord,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: 11),
                  decoration: BoxDecoration(
                    color: o.isSettled
                        ? tokens.surface2
                        : tokens.accentSolid(tokens.primary),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: o.isSettled
                        ? Border.all(color: tokens.borderColor)
                        : null,
                  ),
                  child: Text(
                    o.isSettled ? 'View' : 'Collect',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: o.isSettled
                            ? tokens.textPrimary
                            : tokens.onAccent(tokens.primary)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AllCaughtUp extends StatelessWidget {
  const _AllCaughtUp({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.accentSolid(tokens.primary),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded,
                  size: 32, color: tokens.onAccent(tokens.primary)),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(filtered ? 'Nothing matches' : "You're all caught up",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(
                filtered
                    ? 'No outstanding payments fit these filters. Try widening them.'
                    : 'Every booking and membership is fully paid.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder for the search+filter row and obligation
/// list while [_PendingPaymentsScreenState._obligations] is still loading.
class _ObligationsListSkeleton extends StatelessWidget {
  const _ObligationsListSkeleton();

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

