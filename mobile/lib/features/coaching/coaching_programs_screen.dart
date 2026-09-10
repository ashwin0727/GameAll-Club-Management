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

/// Coaching → Programs — mirrors src/features/coaching/components/programs-page.tsx.
class CoachingProgramsScreen extends ConsumerStatefulWidget {
  const CoachingProgramsScreen({super.key});

  @override
  ConsumerState<CoachingProgramsScreen> createState() => _CoachingProgramsScreenState();
}

class _CoachingProgramsScreenState extends ConsumerState<CoachingProgramsScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  ProgramStatus? _status;
  int _page = 0;
  List<ProgramRow>? _rows;
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
      final page = await ref.read(coachingRepositoryProvider).listPrograms(
            facilityId: fid,
            search: _search,
            status: _status,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _rows = page.programs;
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
        (value: 'INACTIVE', label: 'Inactive'),
      ],
    );
    if (picked == null) return;
    setState(() {
      _status = picked == 'ALL' ? null : ProgramStatus.fromJson(picked);
      _page = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Programs', message: "You don't have permission to view coaching.");
    }
    final canCreate = session.can('COACHING_MANAGE_PROGRAMS');
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coaching Programs'),
        actions: [
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Create program',
              onPressed: () async {
                final created = await context.push<bool>(AppRoutes.coachingProgramNew);
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
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search programs'),
              ),
              const SizedBox(height: AppSpacing.sm),
              PickerChip(label: _status?.label ?? 'All Status', onSelect: _pickStatus),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_rows == null)
                const LoadingView(message: 'Loading programs…')
              else if (_rows!.isEmpty)
                Text('No coaching programs yet.', style: AppTypography.secondary(context))
              else ...[
                ..._rows!.map(_row),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total programs',
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

  Widget _row(ProgramRow p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            final changed = await context.push<bool>('/coaching/programs/${p.id}');
            if (changed == true) _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: AppTypography.rowTitle(context)),
                      Text(
                        '${p.level} · ${p.ageGroup} · ${p.studentCount} students'
                        '${p.isMembershipIncluded ? ' · Included' : p.defaultPriceMinor != null ? ' · ${coachMoney(p.defaultPriceMinor)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  label: p.status.label,
                  tone: p.status == ProgramStatus.active ? StatusTone.success : StatusTone.neutral,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
