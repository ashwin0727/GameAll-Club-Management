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

/// Coaching → Sessions — mirrors src/features/coaching/components/sessions-page.tsx.
class CoachingSessionsScreen extends ConsumerStatefulWidget {
  const CoachingSessionsScreen({super.key});

  @override
  ConsumerState<CoachingSessionsScreen> createState() => _CoachingSessionsScreenState();
}

class _CoachingSessionsScreenState extends ConsumerState<CoachingSessionsScreen> {
  static const _pageSize = 20;

  SessionStatus? _status;
  String? _coachId;
  List<CoachOption> _coaches = const [];
  int _page = 0;
  List<SessionRow>? _rows;
  int _total = 0;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _init() async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final coaches = await ref.read(coachingRepositoryProvider).listCoachOptions(fid);
      if (mounted) setState(() => _coaches = coaches);
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
      final page = await ref.read(coachingRepositoryProvider).listSessions(
            facilityId: fid,
            status: _status,
            coachId: _coachId,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _rows = page.sessions;
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

  Future<void> _pickStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _status?.toJson() ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Status'),
        ...SessionStatus.values.map((s) => (value: s.toJson(), label: s.label)),
      ],
    );
    if (picked == null) return;
    setState(() {
      _status = picked == 'ALL' ? null : SessionStatus.fromJson(picked);
      _page = 0;
    });
    _load();
  }

  Future<void> _pickCoach() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _coachId ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Coaches'),
        ..._coaches.map((c) => (value: c.id, label: c.name)),
      ],
    );
    if (picked == null) return;
    setState(() {
      _coachId = picked == 'ALL' ? null : picked;
      _page = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Sessions', message: "You don't have permission to view coaching.");
    }
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);
    final coachLabel = _coachId == null
        ? 'All Coaches'
        : _coaches.where((c) => c.id == _coachId).map((c) => c.name).firstOrNull ?? 'Coach';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coaching Sessions'),
        actions: [
          if (session.can('COACHING_CREATE_SESSION'))
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New session',
              onPressed: () async {
                final ok = await context.push<bool>(AppRoutes.coachingSessionNew);
                if (ok == true) _load();
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
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  PickerChip(label: _status?.label ?? 'All Status', onSelect: _pickStatus),
                  PickerChip(label: coachLabel, onSelect: _pickCoach),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_rows == null)
                const LoadingView(message: 'Loading sessions…')
              else if (_rows!.isEmpty)
                Text('No sessions match these filters.', style: AppTypography.secondary(context))
              else ...[
                ..._rows!.map(_row),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total sessions',
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

  Widget _row(SessionRow s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            final changed = await context.push<bool>('/coaching/sessions/${s.id}');
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
                      Text(s.programName, style: AppTypography.rowTitle(context)),
                      Text(
                        '${coachDateTime(s.startAt)} · ${s.coachName} · ${s.courtName} · ${s.enrolledCount}/${s.capacity}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
                StatusBadge(label: s.status.label, tone: sessionTone(s.status)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
