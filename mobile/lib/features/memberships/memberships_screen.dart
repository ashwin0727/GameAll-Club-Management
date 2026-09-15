import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/routing/page_transitions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_metric_card.dart';
import '../../shared/widgets/app_search_field.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import 'membership_detail_screen.dart';
import 'membership_access_days_sheet.dart';
import 'membership_list_presentation.dart';
import 'membership_plans_sheet.dart';
import 'slot_format.dart';
import '../authentication/session_controller.dart';

const _perPage = 10;

const _statusFilters = <MembershipListStatus?>[
  null,
  MembershipListStatus.active,
  MembershipListStatus.paymentIncomplete,
  MembershipListStatus.inactive,
];

/// Mirrors src/features/memberships/components/memberships-page.tsx — the
/// facility's full membership list (not one row per member), five KPI tiles,
/// server-side search / status filter / sort / pagination, and a shareable
/// self-registration link. Reuses the existing plans sheet.
class MembershipsScreen extends ConsumerStatefulWidget {
  const MembershipsScreen({super.key});

  @override
  ConsumerState<MembershipsScreen> createState() => _MembershipsScreenState();
}

class _MembershipsScreenState extends ConsumerState<MembershipsScreen> {
  String? _facilityId;
  bool _loading = true;
  String? _loadError;

  /// The facility's membership access days — seeded from the facility record,
  /// updated in place when the owner edits them. Pre-fills a new membership's
  /// time slot (parity gap G2).
  List<int> _accessDays = const [0, 1, 2, 3, 4, 5, 6];

  final _searchController = TextEditingController();
  String _search = '';
  MembershipListStatus? _status;
  MembershipListSort _sort = MembershipListSort.oldest;
  int _page = 1;
  Timer? _debounce;

  bool _listLoading = false;
  MembershipPageSummary? _summary;
  MembershipListResult _list = const MembershipListResult(rows: [], totalCount: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final facility = ref.read(sessionControllerProvider).facility ??
          await ref.read(facilityRepositoryProvider).getFacility();
      if (!mounted) return;
      if (facility == null) {
        setState(() {
          _loading = false;
          _loadError = 'Complete your facility setup to manage memberships.';
        });
        return;
      }
      setState(() {
        _facilityId = facility.id;
        _accessDays = facility.membershipAccessDays;
        _loading = false;
      });
      await _refresh();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _refresh() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    setState(() => _listLoading = true);
    final repo = ref.read(membershipRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.getMembershipPageSummary(facilityId),
        repo.listMemberships(
          facilityId,
          MembershipListParams(
            search: _search.trim().isEmpty ? null : _search.trim(),
            status: _status,
            sort: _sort,
            page: _page,
            perPage: _perPage,
          ),
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as MembershipPageSummary;
        _list = results[1] as MembershipListResult;
        _listLoading = false;
      });
    } on AppException catch (_) {
      if (mounted) setState(() => _listLoading = false);
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _search = value;
      _page = 1;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  void _setPage(int page) {
    setState(() => _page = page);
    _refresh();
  }

  static const _sortOptions = [
    (MembershipListSort.oldest, 'Oldest First'),
    (MembershipListSort.nextPayment, 'Next Payment: Soonest'),
    (MembershipListSort.name, 'Name (A–Z)'),
  ];

  /// One sheet for both filter controls — status and sort — reached from
  /// the single tune icon beside search, instead of two separate rows.
  static const _statusIcons = {
    null: Icons.apps_rounded,
    MembershipListStatus.active: Icons.check_circle_outline,
    MembershipListStatus.paymentIncomplete: Icons.error_outline,
    MembershipListStatus.inactive: Icons.pause_circle_outline,
  };

  static const _sortIcons = {
    MembershipListSort.oldest: Icons.history_rounded,
    MembershipListSort.nextPayment: Icons.event_available_outlined,
    MembershipListSort.name: Icons.sort_by_alpha_rounded,
  };

  Future<void> _openFilterSheet() async {
    var pendingStatus = _status;
    var pendingSort = _sort;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter & Sort', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: AppSpacing.lg),
                  Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: AppColors.muted)),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _statusFilters.map((s) {
                      final selected = pendingStatus == s;
                      return ChoiceChip(
                        avatar: Icon(_statusIcons[s], size: 16, color: selected ? AppColors.onPrimary : AppColors.muted),
                        label: Text(s == null ? 'All Status' : membershipListStatusLabel(s)),
                        selected: selected,
                        onSelected: (_) => setSheetState(() => pendingStatus = s),
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: selected ? AppColors.onPrimary : AppColors.foreground),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('SORT BY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: AppColors.muted)),
                  const SizedBox(height: AppSpacing.sm),
                  ...List.generate(_sortOptions.length, (i) {
                    final entry = _sortOptions[i];
                    final selected = pendingSort == entry.$1;
                    return Padding(
                      padding: EdgeInsets.only(bottom: i == _sortOptions.length - 1 ? 0 : AppSpacing.sm),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: () => setSheetState(() => pendingSort = entry.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.mutedBackground,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(_sortIcons[entry.$1], size: 18, color: selected ? AppColors.primary : AppColors.muted),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  entry.$2,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                    color: selected ? AppColors.primary : AppColors.foreground,
                                  ),
                                ),
                              ),
                              if (selected) const Icon(Icons.check_circle, size: 18, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: 'Apply',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (pendingStatus != _status || pendingSort != _sort) {
      setState(() {
        _status = pendingStatus;
        _sort = pendingSort;
        _page = 1;
      });
      _refresh();
    }
  }

  Future<void> _openCreate() async {
    final created = await context.push<bool>(AppRoutes.membershipsNew);
    if (created == true) _refresh();
  }

  Future<void> _openPlans() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MembershipPlansSheet(facilityId: facilityId),
    );
  }

  Future<void> _editAccessDays() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    final saved = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MembershipAccessDaysSheet(facilityId: facilityId, currentDays: _accessDays),
    );
    if (saved != null && mounted) setState(() => _accessDays = saved);
  }

  Future<void> _openDetail(MembershipListRow row) async {
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => MembershipDetailScreen(membershipId: row.membershipId)),
    );
    if (mounted) _refresh();
  }

  Future<void> _recordPayment(MembershipListRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record payment'),
        content: Text(
          "Mark this billing cycle as paid for ${row.memberName}. Use this when you've collected the payment outside the app.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Record payment')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(membershipRepositoryProvider).recordMembershipPayment(row.membershipId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment recorded')));
      _refresh();
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmDelete(MembershipListRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete member'),
        content: Text(
          'Permanently remove ${row.memberName}. This only works for members with no bookings and no settled payments.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: context.tokens.destructive)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(membershipRepositoryProvider).deleteMember(row.memberId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${row.memberName} deleted')));
      _refresh();
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _shareLink() {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    final base = AppConfig.webAppUrl.trim();
    if (base.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Self-registration link is not configured for this build.')),
      );
      return;
    }
    final url = '${base.replaceAll(RegExp(r'/+$'), '')}/join/$facilityId';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Membership sign-up link copied')));
  }

  int get _totalPages => (_list.totalCount / _perPage).ceil().clamp(1, 1 << 30);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memberships'),
        actions: [
          if (_facilityId != null) ...[
            IconButton(icon: const Icon(Icons.link), tooltip: 'Share sign-up link', onPressed: _shareLink),
            IconButton(icon: const Icon(Icons.event_available_outlined), tooltip: 'Access Days', onPressed: _editAccessDays),
            IconButton(icon: const Icon(Icons.card_membership), tooltip: 'Manage Plans', onPressed: _openPlans),
          ],
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading memberships…')
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ResponsivePage(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_summary != null) _SummaryGrid(summary: _summary!),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: AppSearchField(
                                  controller: _searchController,
                                  hintText: 'Search by name, phone or email',
                                  onChanged: _onSearchChanged,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              InkWell(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                onTap: _openFilterSheet,
                                child: Container(
                                  width: AppSpacing.minTouchTarget,
                                  height: AppSpacing.minTouchTarget,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _status == null ? AppColors.card : AppColors.primary.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                    border: Border.all(color: _status == null ? AppColors.border : AppColors.primary),
                                  ),
                                  child: Icon(Icons.tune_rounded, size: 20, color: _status == null ? AppColors.muted : AppColors.primary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          if (_listLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_list.rows.isEmpty)
                            EmptyStateView(
                              message: _search.isNotEmpty || _status != null
                                  ? 'No memberships match these filters.'
                                  : 'No memberships yet — create your first one.',
                              actionLabel: _search.isEmpty && _status == null ? 'Create Membership' : null,
                              onAction: _search.isEmpty && _status == null ? _openCreate : null,
                            )
                          else ...[
                            ..._list.rows.map((row) => Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                  child: _MembershipRowCard(row: row, onView: () => _openDetail(row), onRecordPayment: row.status == MembershipListStatus.paymentIncomplete ? () => _recordPayment(row) : null, onDelete: () => _confirmDelete(row)),
                                )),
                            const SizedBox(height: AppSpacing.sm),
                            _Pagination(
                              page: _page,
                              totalPages: _totalPages,
                              totalCount: _list.totalCount,
                              onPrev: _page > 1 ? () => _setPage(_page - 1) : null,
                              onNext: _page < _totalPages ? () => _setPage(_page + 1) : null,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                        ],
                      ),
                    ),
                  ),
      ),
      floatingActionButton: _facilityId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Membership'),
            ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.members),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final MembershipPageSummary summary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cards = [
      AppMetricCard(
        label: 'Total Members',
        value: '${summary.totalMembers}',
        countTo: summary.totalMembers,
        formatValue: (v) => v.round().toString(),
        changePercent: summary.totalMembersChangePct,
        icon: Icons.groups_outlined,
        accentColor: tokens.violet,
      ),
      AppMetricCard(
        label: 'Active Members',
        value: '${summary.activeMembers}',
        countTo: summary.activeMembers,
        formatValue: (v) => v.round().toString(),
        icon: Icons.verified_user_outlined,
        accentColor: tokens.success,
      ),
      AppMetricCard(
        label: 'Payment Incomplete',
        value: '${summary.paymentIncompleteMembers}',
        countTo: summary.paymentIncompleteMembers,
        formatValue: (v) => v.round().toString(),
        icon: Icons.money_off_rounded,
        accentColor: tokens.destructive,
      ),
      AppMetricCard(
        label: 'Revenue (this month)',
        value: Formatters.currencyInr(summary.revenueInr),
        countTo: summary.revenueInr,
        formatValue: (v) => Formatters.currencyInr(v.round()),
        changePercent: summary.revenueChangePct,
        icon: Icons.currency_rupee_rounded,
        accentColor: tokens.electricBlue,
      ),
    ];
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: cards[1]),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: cards[2]),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: cards[3]),
          ],
        ),
      ],
    );
  }
}

class _MembershipRowCard extends StatelessWidget {
  const _MembershipRowCard({required this.row, required this.onView, this.onRecordPayment, required this.onDelete});

  final MembershipListRow row;
  final VoidCallback onView;
  final VoidCallback? onRecordPayment;
  final VoidCallback onDelete;

  String get _initials {
    final parts = row.memberName.split(' ').where((p) => p.isNotEmpty).take(2);
    return parts.map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final overdue = isPastDate(row.endDate);
    return AppCard(
      onTap: onView,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 18, child: Text(_initials, style: const TextStyle(fontSize: 11))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.memberName, style: AppTypography.rowTitle(context)),
                    Text(
                      row.memberEmail == null ? row.memberPhone : '${row.memberPhone} · ${row.memberEmail}',
                      style: AppTypography.caption(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusBadge(label: membershipListStatusLabel(row.status), tone: membershipListStatusTone(row.status)),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: 'More actions',
                onSelected: (v) {
                  if (v == 'view') onView();
                  if (v == 'record') onRecordPayment?.call();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(Icons.visibility_outlined, size: 18),
                        SizedBox(width: AppSpacing.sm),
                        Text('View details'),
                      ],
                    ),
                  ),
                  if (onRecordPayment != null)
                    const PopupMenuItem(
                      value: 'record',
                      child: Row(
                        children: [
                          Icon(Icons.payments_outlined, size: 18),
                          SizedBox(width: AppSpacing.sm),
                          Text('Record payment'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: tokens.destructive),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Delete member', style: TextStyle(color: tokens.destructive)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('${row.planName} · ${Formatters.currencyInr(row.monthlyPriceInr)} / month', style: AppTypography.secondary(context)),
          if (row.slot != null)
            Text(
              row.slot!.courtName == null
                  ? formatSlot(row.slot!.daysOfWeek, row.slot!.startTime, row.slot!.endTime)
                  : '${row.slot!.courtName} · ${formatSlot(row.slot!.daysOfWeek, row.slot!.startTime, row.slot!.endTime)}',
              style: AppTypography.caption(context),
            ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text('Started ${Formatters.dateShort(row.startDate)}', style: AppTypography.caption(context)),
              ),
              Text(
                'Next payment ${Formatters.dateShort(row.endDate)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: overdue ? tokens.destructive : tokens.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.totalCount,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final int totalCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            totalCount == 0 ? 'No members' : 'Page $page / $totalPages · $totalCount total',
            style: AppTypography.caption(context),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Row(
          children: [
            IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ],
    );
  }
}