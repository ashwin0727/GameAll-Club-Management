import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'coaching_common.dart';

/// Coaching → Session detail — mirrors
/// src/features/coaching/components/session-details-page.tsx.
class CoachingSessionDetailScreen extends ConsumerStatefulWidget {
  const CoachingSessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<CoachingSessionDetailScreen> createState() => _CoachingSessionDetailScreenState();
}

class _CoachingSessionDetailScreenState extends ConsumerState<CoachingSessionDetailScreen> {
  static const _tabs = ['Students', 'Notes', 'Progress', 'Activity'];

  SessionDetail? _s;
  String? _error;
  int _tab = 0;
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
      final s = await ref.read(coachingRepositoryProvider).getSession(widget.sessionId);
      if (mounted) setState(() => _s = s);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      _changed = true;
      await _load();
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Session', message: "You don't have permission to view coaching.");
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_s?.programName ?? 'Session')),
        body: SafeArea(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _s == null
                  ? const LoadingView(message: 'Loading session…')
                  : _content(_s!, session),
        ),
      ),
    );
  }

  Widget _content(SessionDetail s, session) {
    final canEdit = session.can('COACHING_EDIT_SESSION');
    final canCancel = session.can('COACHING_CANCEL_SESSION');
    final canProgress = session.can('COACHING_MANAGE_PROGRESS');
    final live = s.status.isLive;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${s.coachName} · ${s.courtName}', style: AppTypography.rowTitle(context)),
              ),
              StatusBadge(label: s.status.label, tone: sessionTone(s.status)),
            ],
          ),
          Text(coachDateTime(s.startAt), style: AppTypography.caption(context)),
          if (s.status == SessionStatus.cancelled && s.cancelReason != null)
            Text('Cancelled: ${s.cancelReason}', style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('Program', '${s.programName} (${s.programLevel})'),
                _kv('Capacity', '${s.enrolledCount} / ${s.capacity}'),
                if (s.objective != null && s.objective!.isNotEmpty) _kv('Objective', s.objective!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (canEdit || canCancel)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (canEdit && s.status == SessionStatus.scheduled)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run(() => ref.read(coachingRepositoryProvider).setSessionStatus(s.id, 'CONFIRMED')),
                    child: const Text('Confirm'),
                  ),
                if (canEdit && live)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run(() => ref.read(coachingRepositoryProvider).setSessionStatus(s.id, 'IN_PROGRESS')),
                    child: const Text('Start'),
                  ),
                if (canEdit && (live || s.status == SessionStatus.inProgress))
                  ElevatedButton(onPressed: _busy ? null : () => _complete(s), child: const Text('Complete')),
                if (canEdit && live)
                  OutlinedButton(onPressed: _busy ? null : () => _reschedule(s), child: const Text('Edit')),
                if (canCancel && s.status != SessionStatus.completed && s.status != SessionStatus.cancelled)
                  OutlinedButton(onPressed: _busy ? null : () => _cancel(s), child: const Text('Cancel')),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          SegmentedTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: AppSpacing.md),
          if (_tab == 0) ..._students(s, canEdit, canProgress, live),
          if (_tab == 1) _notes(s),
          if (_tab == 2) ..._progress(s),
          if (_tab == 3) ..._activity(s),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  List<Widget> _students(SessionDetail s, bool canEdit, bool canProgress, bool live) {
    return [
      Row(
        children: [
          Expanded(
            child: Text('Students (${s.enrolledCount}/${s.capacity})', style: Theme.of(context).textTheme.titleSmall),
          ),
          if (canEdit && live && s.enrolledCount < s.capacity)
            TextButton(onPressed: () => _addStudent(s), child: const Text('Add')),
        ],
      ),
      if (s.students.isEmpty)
        Text('No students on the roster.', style: AppTypography.secondary(context))
      else
        ...s.students.map(
          (st) => AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => context.push('/coaching/enrollments/${st.enrollmentId}'),
                    child: Text(st.name, style: AppTypography.rowTitle(context)),
                  ),
                ),
                if (canProgress)
                  IconButton(
                    icon: const Icon(Icons.note_add_outlined, size: 20),
                    tooltip: 'Add progress note',
                    onPressed: () => _addProgress(s.id, st.enrollmentId, st.name),
                  ),
                if (canEdit && live)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    tooltip: 'Remove',
                    onPressed: _busy
                        ? null
                        : () => _run(() => ref.read(coachingRepositoryProvider).removeSessionStudent(s.id, st.enrollmentId)),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _notes(SessionDetail s) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.notes ?? 'No session notes yet.', style: AppTypography.body(context)),
            if (s.objectiveResult != null && s.objectiveResult!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Objective result', style: AppTypography.caption(context)),
              Text(s.objectiveResult!, style: AppTypography.body(context)),
            ],
          ],
        ),
      );

  List<Widget> _progress(SessionDetail s) {
    if (!s.canViewProgress) {
      return [Text("You don't have permission to view student progress.", style: AppTypography.secondary(context))];
    }
    if (s.progressNotes.isEmpty) {
      return [Text('No progress notes for this session.', style: AppTypography.secondary(context))];
    }
    return s.progressNotes
        .map((n) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(n.memberName, style: AppTypography.rowTitle(context))),
                      StatusBadge(label: n.progressStatus.label, tone: progressTone(n.progressStatus)),
                    ],
                  ),
                  if (n.skillOrGoal != null) Text(n.skillOrGoal!, style: AppTypography.caption(context)),
                  const SizedBox(height: 2),
                  Text(n.note, style: AppTypography.body(context)),
                ],
              ),
            ))
        .toList();
  }

  List<Widget> _activity(SessionDetail s) {
    if (s.events.isEmpty) {
      return [Text('Nothing recorded yet.', style: AppTypography.secondary(context))];
    }
    return s.events
        .map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(e.summary, style: AppTypography.body(context))),
                  Text(coachDateTime(e.createdAt), style: AppTypography.caption(context)),
                ],
              ),
            ))
        .toList();
  }

  // ── actions ────────────────────────────────────────────────────────────
  Future<void> _addStudent(SessionDetail s) async {
    final onRoster = s.students.map((x) => x.enrollmentId).toSet();
    EnrollmentPage page;
    try {
      page = await ref.read(coachingRepositoryProvider).listEnrollments(
            facilityId: s.facilityId,
            programId: s.programId,
            status: EnrollmentStatus.active,
            limit: 200,
          );
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    final candidates = page.enrollments.where((e) => !onRoster.contains(e.id)).toList();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: candidates.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('No eligible students.'))
            : ListView(
                shrinkWrap: true,
                children: candidates
                    .map((e) => ListTile(title: Text(e.studentName), onTap: () => Navigator.pop(ctx, e.id)))
                    .toList(),
              ),
      ),
    );
    if (picked != null) {
      await _run(() => ref.read(coachingRepositoryProvider).addSessionStudent(s.id, picked));
    }
  }

  Future<void> _addProgress(String sessionId, String enrollmentId, String name) async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProgressNoteSheet(studentName: name),
    );
    if (result == null) return;
    await _run(() => ref.read(coachingRepositoryProvider).addProgressNote(
          enrollmentId: enrollmentId,
          note: result['note']!,
          skillOrGoal: (result['skill'] ?? '').isEmpty ? null : result['skill'],
          progressStatus: result['status'] ?? 'ON_TRACK',
          sessionId: sessionId,
        ));
  }

  Future<void> _complete(SessionDetail s) async {
    final controllers = [TextEditingController(), TextEditingController()];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Records completion and coach notes. Student attendance is not tracked.'),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: controllers[0], decoration: const InputDecoration(labelText: 'Session notes (optional)'), maxLines: 2),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: controllers[1], decoration: const InputDecoration(labelText: 'Objective result (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ],
      ),
    );
    final notes = controllers[0].text.trim();
    final result = controllers[1].text.trim();
    for (final c in controllers) {
      c.dispose();
    }
    if (ok != true) return;
    await _run(() => ref.read(coachingRepositoryProvider).completeSession(
          s.id,
          notes: notes.isEmpty ? null : notes,
          objectiveResult: result.isEmpty ? null : result,
        ));
  }

  Future<void> _cancel(SessionDetail s) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The session record is kept — its status becomes Cancelled.'),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Reason'), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep session')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel session')),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (ok != true) return;
    if (reason.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required.')));
      return;
    }
    await _run(() => ref.read(coachingRepositoryProvider).cancelSession(s.id, reason));
  }

  Future<void> _reschedule(SessionDetail s) async {
    var date = DateTime(s.startAt.year, s.startAt.month, s.startAt.day);
    var start = TimeOfDay.fromDateTime(s.startAt);
    var end = TimeOfDay.fromDateTime(s.endAt);
    final capacity = TextEditingController(text: '${s.capacity}');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reschedule', style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text('Re-checked against courts, coaches and maintenance.', style: AppTypography.caption(ctx)),
                const SizedBox(height: AppSpacing.md),
                InkWell(
                  onTap: () async {
                    final p = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime(date.year + 2),
                    );
                    if (p != null) setSheet(() => date = p);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date'),
                    child: Text('${date.day}/${date.month}/${date.year}'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final p = await showTimePicker(context: ctx, initialTime: start);
                          if (p != null) setSheet(() => start = p);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Start'),
                          child: Text(start.format(ctx)),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final p = await showTimePicker(context: ctx, initialTime: end);
                          if (p != null) setSheet(() => end = p);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'End'),
                          child: Text(end.format(ctx)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: capacity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(label: 'Save', onPressed: () => Navigator.pop(ctx, true)),
              ],
            ),
          ),
        ),
      ),
    );
    final cap = int.tryParse(capacity.text.trim());
    capacity.dispose();
    if (ok != true) return;
    await _run(() => ref.read(coachingRepositoryProvider).rescheduleSession(
          sessionId: s.id,
          startAt: DateTime(date.year, date.month, date.day, start.hour, start.minute),
          endAt: DateTime(date.year, date.month, date.day, end.hour, end.minute),
          capacity: cap,
        ));
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(k, style: AppTypography.caption(context))),
            Expanded(child: Text(v, style: AppTypography.body(context))),
          ],
        ),
      );
}

class _ProgressNoteSheet extends StatefulWidget {
  const _ProgressNoteSheet({required this.studentName});
  final String studentName;

  @override
  State<_ProgressNoteSheet> createState() => _ProgressNoteSheetState();
}

class _ProgressNoteSheetState extends State<_ProgressNoteSheet> {
  final _skill = TextEditingController();
  final _note = TextEditingController();
  String _status = 'ON_TRACK';
  String? _error;

  @override
  void dispose() {
    _skill.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress note — ${widget.studentName}', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _skill, decoration: const InputDecoration(labelText: 'Skill or goal (optional)')),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'Note')),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: ProgressStatus.values
                  .map((s) => ChoiceChip(
                        label: Text(s.label),
                        selected: _status == s.toJson(),
                        onSelected: (_) => setState(() => _status = s.toJson()),
                      ))
                  .toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Save note',
              onPressed: () {
                if (_note.text.trim().isEmpty) {
                  setState(() => _error = 'Enter a progress note.');
                  return;
                }
                Navigator.pop(context, {
                  'note': _note.text.trim(),
                  'skill': _skill.text.trim(),
                  'status': _status,
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
