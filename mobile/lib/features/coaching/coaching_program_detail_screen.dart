import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'coaching_common.dart';
import 'coaching_program_form_screen.dart';

/// Coaching → Program detail — mirrors
/// src/features/coaching/components/program-details-page.tsx.
class CoachingProgramDetailScreen extends ConsumerStatefulWidget {
  const CoachingProgramDetailScreen({super.key, required this.programId});

  final String programId;

  @override
  ConsumerState<CoachingProgramDetailScreen> createState() => _CoachingProgramDetailScreenState();
}

class _CoachingProgramDetailScreenState extends ConsumerState<CoachingProgramDetailScreen> {
  ProgramDetail? _program;
  String? _error;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await ref.read(coachingRepositoryProvider).getProgram(widget.programId);
      if (mounted) setState(() => _program = p);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggle() async {
    final p = _program!;
    setState(() => _busy = true);
    try {
      await ref.read(coachingRepositoryProvider).updateProgram(
            programId: p.id,
            status: p.status == ProgramStatus.active ? ProgramStatus.inactive : ProgramStatus.active,
          );
      _changed = true;
      await _load();
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CoachingProgramFormScreen(existing: _program)),
    );
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Program', message: "You don't have permission to view coaching.");
    }
    final canManage = session.can('COACHING_MANAGE_PROGRAMS');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_program?.name ?? 'Program'),
          actions: [
            if (_program != null && canManage) ...[
              TextButton(
                onPressed: _busy ? null : _toggle,
                child: Text(_program!.status == ProgramStatus.active ? 'Deactivate' : 'Reactivate'),
              ),
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _edit),
            ],
          ],
        ),
        body: SafeArea(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _program == null
                  ? const LoadingView(message: 'Loading program…')
                  : _content(_program!),
        ),
      ),
    );
  }

  Widget _content(ProgramDetail p) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusBadge(
                label: p.status.label,
                tone: p.status == ProgramStatus.active ? StatusTone.success : StatusTone.neutral,
              ),
              if (p.isMembershipIncluded) const StatusBadge(label: 'Membership-included', tone: StatusTone.info),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('${p.level} · ${p.ageGroup} · ${p.category}', style: AppTypography.secondary(context)),
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 2.4,
            children: [
              CoachingKpi(label: 'Active Students', value: '${p.activeStudents}'),
              CoachingKpi(label: 'Total Enrollments', value: '${p.totalEnrollments}'),
              CoachingKpi(label: 'Scheduled', value: '${p.scheduledSessions}'),
              CoachingKpi(label: 'Completed', value: '${p.completedSessions}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('Default duration', '${p.defaultDurationMinutes} min'),
                _kv('Default capacity', '${p.defaultCapacity}'),
                _kv('Sessions / package', p.sessionCount != null ? '${p.sessionCount}' : '—'),
                _kv(
                  'Default price',
                  p.isMembershipIncluded
                      ? 'Included'
                      : p.defaultPriceMinor != null
                          ? coachMoney(p.defaultPriceMinor)
                          : 'Per enrollment',
                ),
                _kv('Created', coachDate(p.createdAt)),
                if (p.description != null && p.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(p.description!, style: AppTypography.secondary(context)),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 140, child: Text(k, style: AppTypography.caption(context))),
            Expanded(child: Text(v, style: AppTypography.body(context))),
          ],
        ),
      );
}
