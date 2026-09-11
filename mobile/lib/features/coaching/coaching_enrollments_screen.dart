import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
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
import 'coaching_enrollment_form_sheet.dart';

/// Coaching → Enrollments — mirrors
/// src/features/coaching/components/enrollments-page.tsx.
class CoachingEnrollmentsScreen extends ConsumerStatefulWidget {
  const CoachingEnrollmentsScreen({super.key});

  @override
  ConsumerState<CoachingEnrollmentsScreen> createState() => _CoachingEnrollmentsScreenState();
}

class _CoachingEnrollmentsScreenState extends ConsumerState<CoachingEnrollmentsScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  EnrollmentStatus? _status;
  String? _programId;
  List<ProgramOption> _programs = const [];
  int _page = 0;
  List<EnrollmentRow>? _rows;
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
      final programs = await ref.read(coachingRepositoryProvider).listProgramOptions(fid);
      if (mounted) setState(() => _programs = programs);
    } on AppException {
      // filter still works
    }
    await _load();
  }

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    final reqId = ++_requestId;
    setState(() => _error = null);
    try {
      final page = await ref.read(coachingRepositoryProvider).listEnrollments(
            facilityId: fid,
            search: _search,
            status: _status,
            programId: _programId,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _rows = page.enrollments;
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
        (value: 'PAUSED', label: 'Paused'),
        (value: 'COMPLETED', label: 'Completed'),
        (value: 'CANCELLED', label: 'Cancelled'),
      ],
    );
    if (picked == null) return;
    setState(() {
      _status = picked == 'ALL' ? null : EnrollmentStatus.fromJson(picked);
      _page = 0;
    });
    _load();
  }

  Future<void> _pickProgram() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _programId ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Programs'),
        ..._programs.map((p) => (value: p.id, label: p.name)),
      ],
    );
    if (picked == null) return;
    setState(() {
      _programId = picked == 'ALL' ? null : picked;
      _page = 0;
    });
    _load();
  }

  Future<void> _add() async {
    final fid = _facilityId;
    if (fid == null) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CoachingEnrollmentFormSheet(facilityId: fid),
    );
    if (id != null && mounted) {
      context.push('/coaching/enrollments/$id');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Enrollments', message: "You don't have permission to view coaching.");
    }
    final canManage = session.can('COACHING_MANAGE_ENROLLMENTS');
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);
    final programLabel = _programId == null
        ? 'All Programs'
        : _programs.where((p) => p.id == _programId).map((p) => p.name).firstOrNull ?? 'Program';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Enrollments'),
        actions: [
          if (canManage) IconButton(icon: const Icon(Icons.add), tooltip: 'Add enrollment', onPressed: _add),
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
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search students'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  PickerChip(label: programLabel, onSelect: _pickProgram),
                  PickerChip(label: _status?.label ?? 'All Status', onSelect: _pickStatus),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_rows == null)
                const LoadingView(message: 'Loading enrollments…')
              else if (_rows!.isEmpty)
                Text('No enrollments match these filters.', style: AppTypography.secondary(context))
              else ...[
                ..._rows!.map(_row),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total enrollments',
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

  Widget _row(EnrollmentRow e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            final changed = await context.push<bool>('/coaching/enrollments/${e.id}');
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
                      Text(e.studentName, style: AppTypography.rowTitle(context)),
                      Text(
                        '${e.programName} · ${coachDate(e.startDate)}'
                        '${e.priceMinor == 0 ? ' · Included' : ' · ${coachMoney(e.priceMinor)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusBadge(label: e.status.label, tone: enrollmentTone(e.status)),
                    const SizedBox(height: 2),
                    StatusBadge(label: e.paymentStatus.label, tone: paymentTone(e.paymentStatus)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
