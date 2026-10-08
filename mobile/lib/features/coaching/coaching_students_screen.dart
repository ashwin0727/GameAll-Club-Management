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
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'coaching_common.dart';

/// Coaching → Manage Students — mirrors src/features/coaching/components/students-page.tsx.
///
/// The roster of every enrolled student, one row per program enrollment (the existing
/// `coaching_enrollments` relationship — there is no separate Student entity). Each card carries
/// exactly the web table's columns: Student (name + age), Program / Batch, Phone, Enrollment
/// Date, Payment Status, Status, and an Actions menu.
class CoachingStudentsScreen extends ConsumerStatefulWidget {
  const CoachingStudentsScreen({super.key});

  @override
  ConsumerState<CoachingStudentsScreen> createState() => _CoachingStudentsScreenState();
}

class _CoachingStudentsScreenState extends ConsumerState<CoachingStudentsScreen> {
  static const _pageSize = 10;
  static const _tabs = ['All Students', 'Active', 'Inactive'];
  static const _levels = ['Beginner', 'Intermediate', 'Advanced', 'All Levels'];

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  int _tab = 0;
  String? _programId;
  String? _coachId;
  String? _level;
  List<ProgramOption> _programs = const [];
  List<CoachOption> _coaches = const [];
  int _page = 0;
  List<EnrollmentRow>? _rows;
  int _total = 0;
  String? _error;
  int _requestId = 0;

  ({int total, int active, int inactive, int pendingPayment})? _kpis;

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
    final repo = ref.read(coachingRepositoryProvider);
    try {
      final results = await Future.wait([repo.listProgramOptions(fid), repo.listCoachOptions(fid)]);
      if (mounted) {
        setState(() {
          _programs = results[0] as List<ProgramOption>;
          _coaches = results[1] as List<CoachOption>;
        });
      }
    } on AppException {
      // the filters just stay empty
    }
    await Future.wait([_load(), _loadKpis()]);
  }

  Future<void> _loadKpis() async {
    final fid = _facilityId;
    if (fid == null) return;
    final repo = ref.read(coachingRepositoryProvider);
    try {
      final all = await repo.listEnrollments(facilityId: fid, limit: 1);
      final active = await repo.listEnrollments(facilityId: fid, status: EnrollmentStatus.active, limit: 1);
      // Payment Pending needs a real per-row status, not just a count — page through active
      // enrollments (bounded) rather than adding an aggregate RPC.
      final activeRows = await repo.listEnrollments(facilityId: fid, status: EnrollmentStatus.active, limit: 200);
      final pending = activeRows.enrollments
          .where((e) => e.paymentStatus == EnrollmentPaymentStatus.pending || e.paymentStatus == EnrollmentPaymentStatus.partial)
          .length;
      if (mounted) {
        setState(() => _kpis = (
              total: all.totalCount,
              active: active.totalCount,
              inactive: all.totalCount - active.totalCount,
              pendingPayment: pending,
            ));
      }
    } on AppException {
      if (mounted) setState(() => _kpis = null);
    }
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
            statusKey: _tab == 1 ? 'ACTIVE' : (_tab == 2 ? 'NOT_ACTIVE' : null),
            programId: _programId,
            coachId: _coachId,
            level: _level,
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

  void _resetAndLoad() {
    setState(() => _page = 0);
    _load();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _search = v);
      _resetAndLoad();
    });
  }

  Future<void> _pickProgram() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _programId ?? 'ALL',
      options: [(value: 'ALL', label: 'All Programs'), ..._programs.map((p) => (value: p.id, label: p.name))],
    );
    if (picked == null) return;
    setState(() => _programId = picked == 'ALL' ? null : picked);
    _resetAndLoad();
  }

  Future<void> _pickCoach() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _coachId ?? 'ALL',
      options: [(value: 'ALL', label: 'All Coaches'), ..._coaches.map((c) => (value: c.id, label: c.name))],
    );
    if (picked == null) return;
    setState(() => _coachId = picked == 'ALL' ? null : picked);
    _resetAndLoad();
  }

  Future<void> _pickLevel() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _level ?? 'ALL',
      options: [(value: 'ALL', label: 'All Levels'), ..._levels.map((l) => (value: l, label: l))],
    );
    if (picked == null) return;
    setState(() => _level = picked == 'ALL' ? null : picked);
    _resetAndLoad();
  }

  Future<void> _addStudent() async {
    await context.push(AppRoutes.coachingStudentNew);
    if (!mounted) return;
    _load();
    _loadKpis();
  }

  Future<void> _refresh() async {
    await Future.wait([_load(), _loadKpis()]);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Manage Students', message: "You don't have permission to view coaching.");
    }
    final canManage = session.can('COACHING_MANAGE_ENROLLMENTS');
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);
    final programLabel = _programId == null
        ? 'All Programs'
        : _programs.where((p) => p.id == _programId).map((p) => p.name).firstOrNull ?? 'Program';
    final coachLabel = _coachId == null
        ? 'All Coaches'
        : _coaches.where((c) => c.id == _coachId).map((c) => c.name).firstOrNull ?? 'Coach';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Students'),
        actions: [
          if (canManage) IconButton(icon: const Icon(Icons.person_add_alt_1_outlined), tooltip: 'Add Student', onPressed: _addStudent),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('View and manage all students enrolled in your coaching programs.', style: AppTypography.secondary(context)),
              const SizedBox(height: AppSpacing.md),
              _kpiGrid(),
              const SizedBox(height: AppSpacing.md),
              SegmentedTabs(
                tabs: _tabs,
                index: _tab,
                onChanged: (i) {
                  setState(() => _tab = i);
                  _resetAndLoad();
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search student by name, phone or email'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  PickerChip(label: programLabel, onSelect: _pickProgram),
                  PickerChip(label: coachLabel, onSelect: _pickCoach),
                  PickerChip(label: _level ?? 'All Levels', onSelect: _pickLevel),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_rows == null)
                const _StudentsSkeleton()
              else if (_rows!.isEmpty)
                Text('Start by adding your first student.', style: AppTypography.secondary(context))
              else ...[
                ..._rows!.map(_card),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total students',
                    onPrevious: _page == 0
                        ? null
                        : () {
                            setState(() => _page--);
                            _load();
                          },
                    onNext: _page + 1 >= totalPages
                        ? null
                        : () {
                            setState(() => _page++);
                            _load();
                          },
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

  Widget _kpiGrid() {
    final k = _kpis;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.4,
      children: k == null
          ? const [SkeletonStatTile(), SkeletonStatTile(), SkeletonStatTile(), SkeletonStatTile()]
          : [
              CoachingKpi(label: 'Total Students', value: '${k.total}'),
              CoachingKpi(label: 'Active Students', value: '${k.active}'),
              CoachingKpi(label: 'Inactive Students', value: '${k.inactive}'),
              CoachingKpi(label: 'Pending Payment', value: '${k.pendingPayment}'),
            ],
    );
  }

  /// "Pending" / "Partial" — the roster's own wording for what the student still owes.
  String _paymentLabel(EnrollmentPaymentStatus s) => switch (s) {
        EnrollmentPaymentStatus.included => 'Included',
        EnrollmentPaymentStatus.paid => 'Paid',
        EnrollmentPaymentStatus.partial => 'Partial',
        EnrollmentPaymentStatus.pending => 'Pending',
      };

  Widget _card(EnrollmentRow e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            final changed = await context.push<bool>('${AppRoutes.coachingEnrollments}/${e.id}');
            if (changed == true) _refresh();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.xs, AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppAvatar(name: e.studentName),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.studentName, style: AppTypography.rowTitle(context)),
                      if (e.studentAge != null) Text('age ${e.studentAge}', style: AppTypography.caption(context)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        e.batchName != null ? '${e.programName} · ${e.batchName}' : e.programName,
                        style: AppTypography.body(context),
                      ),
                      Text(
                        '${e.studentPhone ?? '—'} · ${coachDate(e.startDate)}',
                        style: AppTypography.caption(context),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          StatusBadge(label: _paymentLabel(e.paymentStatus), tone: paymentTone(e.paymentStatus)),
                          StatusBadge(label: e.status.label, tone: enrollmentTone(e.status)),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Student actions',
                  onSelected: (v) {
                    if (v == 'student') context.push('${AppRoutes.coachingEnrollments}/${e.id}');
                    if (v == 'program') context.push('${AppRoutes.coachingPrograms}/${e.programId}');
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'student', child: Text('View Student')),
                    if (e.programId.isNotEmpty) const PopupMenuItem(value: 'program', child: Text('View Program')),
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

/// Structure-shaped placeholder for the paginated student cards.
class _StudentsSkeleton extends StatelessWidget {
  const _StudentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
