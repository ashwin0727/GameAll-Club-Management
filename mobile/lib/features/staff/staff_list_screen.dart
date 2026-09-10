import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'staff_common.dart';

/// Users & Roles → Staff — mirrors src/features/staff/components/staff-page.tsx.
class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  StaffStatus? _status;
  String? _roleId;
  int _page = 0;

  List<RoleRow> _roles = const [];
  List<StaffRow>? _staff;
  int _total = 0;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _init() async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final roles = await ref.read(staffRepositoryProvider).listRoles(fid);
      if (mounted) setState(() => _roles = roles);
    } on AppException {
      // Filter still works without the role list.
    }
    await _load();
  }

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    final reqId = ++_requestId;
    setState(() => _error = null);
    try {
      final page = await ref.read(staffRepositoryProvider).listStaff(
            facilityId: fid,
            search: _search,
            status: _status,
            roleId: _roleId,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _staff = page.staff;
        _total = page.totalCount;
      });
    } on AppException catch (e) {
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _error = e.message;
        _staff = const [];
      });
    }
  }

  void _apply(VoidCallback mutate) {
    setState(() {
      mutate();
      _page = 0;
    });
    _load();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _apply(() => _search = v));
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _load();
  }

  Future<void> _pickStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _status?.toJson() ?? 'ALL',
      options: const [
        (value: 'ALL', label: 'All Status'),
        (value: 'ACTIVE', label: 'Active'),
        (value: 'INACTIVE', label: 'Inactive'),
        (value: 'INVITED', label: 'Pending'),
      ],
    );
    if (picked == null) return;
    _apply(() => _status = picked == 'ALL' ? null : StaffStatus.fromJson(picked));
  }

  Future<void> _pickRole() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _roleId ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Roles'),
        ..._roles.map((r) => (value: r.id, label: r.name)),
      ],
    );
    if (picked == null) return;
    _apply(() => _roleId = picked == 'ALL' ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('USERS_VIEW')) {
      return const StaffPermissionDenied(message: "You don't have permission to view staff.");
    }
    final canAdd = session.can('USERS_CREATE');
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        actions: [
          if (canAdd)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add staff',
              onPressed: () => context.push(AppRoutes.staffAdd),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('Manage your facility staff, roles and access.', style: AppTypography.secondary(context)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name, email or phone',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  PickerChip(label: _status?.label ?? 'All Status', onSelect: _pickStatus),
                  PickerChip(
                    label: _roleId == null
                        ? 'All Roles'
                        : _roles.firstWhere((r) => r.id == _roleId, orElse: () => const RoleRow(id: '', key: null, name: 'Role', description: null, isSystem: false, isCustom: false, isActive: true, version: 1, staffCount: 0, permissionCount: 0)).name,
                    onSelect: _pickRole,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_staff == null)
                const LoadingView(message: 'Loading staff…')
              else if (_staff!.isEmpty)
                Text('No staff match these filters.', style: AppTypography.secondary(context))
              else ...[
                ..._staff!.map(_row),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total staff',
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
    );
  }

  Widget _row(StaffRow s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => context.push('/users-roles/staff/${s.userId}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                StaffAvatar(name: s.fullName, photoUrl: s.avatarUrl),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.fullName, style: AppTypography.rowTitle(context)),
                      Text('${s.roleName} · ${s.email}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusBadge(label: s.status.label, tone: staffStatusTone(s.status)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
