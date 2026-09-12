import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'coaching_common.dart';

/// Coaching → Coaches — mirrors src/features/coaching/components/coaches-page.tsx.
class CoachesScreen extends ConsumerStatefulWidget {
  const CoachesScreen({super.key});

  @override
  ConsumerState<CoachesScreen> createState() => _CoachesScreenState();
}

class _CoachesScreenState extends ConsumerState<CoachesScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  CoachStatus? _status;
  int _page = 0;
  List<CoachRow>? _rows;
  int _total = 0;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    final reqId = ++_requestId;
    setState(() => _error = null);
    try {
      final page = await ref.read(coachingRepositoryProvider).listCoaches(
            facilityId: fid,
            search: _search,
            status: _status,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _rows = page.coaches;
        _total = page.totalCount;
      });
    } on AppException catch (e) {
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _error = e.message;
        _rows = const [];
      });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _search = v;
        _page = 0;
      });
      _load();
    });
  }

  Future<void> _pickStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _status?.toJson() ?? 'ALL',
      options: const [
        (value: 'ALL', label: 'All Status'),
        (value: 'ACTIVE', label: 'Active'),
        (value: 'ON_LEAVE', label: 'On Leave'),
        (value: 'INACTIVE', label: 'Inactive'),
      ],
    );
    if (picked == null) return;
    setState(() {
      _status = picked == 'ALL' ? null : CoachStatus.fromJson(picked);
      _page = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Coaches', message: "You don't have permission to view coaching.");
    }
    final canAdd = session.can('COACHING_MANAGE_COACHES');
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coaches'),
        actions: [
          if (canAdd)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add coach',
              onPressed: () async {
                final created = await context.push<bool>(AppRoutes.coachingCoachAdd);
                if (created == true) _load();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search coaches'),
              ),
              const SizedBox(height: AppSpacing.sm),
              PickerChip(label: _status?.label ?? 'All Status', onSelect: _pickStatus),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_rows == null)
                const LoadingView(message: 'Loading coaches…')
              else if (_rows!.isEmpty)
                Text('No coaches match these filters.', style: AppTypography.secondary(context))
              else ...[
                ..._rows!.map(_row),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total coaches',
                    onPrevious: _page == 0 ? null : () { setState(() => _page--); _load(); },
                    onNext: _page + 1 >= totalPages ? null : () { setState(() => _page++); _load(); },
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

  Widget _row(CoachRow c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            final changed = await context.push<bool>('/coaching/coaches/${c.id}');
            if (changed == true) _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                StaffAvatar(name: c.fullName, photoUrl: c.avatarUrl),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.fullName, style: AppTypography.rowTitle(context)),
                      Text(
                        '${c.specialization ?? '—'}'
                        '${c.experienceYears != null ? ' · ${c.experienceYears} yrs' : ''}'
                        ' · ${c.sessionCount} sessions · ${c.studentCount} students',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusBadge(label: c.status.label, tone: coachTone(c.status)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
