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

/// Coaching → Enrollment detail — mirrors
/// src/features/coaching/components/enrollment-details-page.tsx.
class CoachingEnrollmentDetailScreen extends ConsumerStatefulWidget {
  const CoachingEnrollmentDetailScreen({super.key, required this.enrollmentId});

  final String enrollmentId;

  @override
  ConsumerState<CoachingEnrollmentDetailScreen> createState() => _CoachingEnrollmentDetailScreenState();
}

class _CoachingEnrollmentDetailScreenState extends ConsumerState<CoachingEnrollmentDetailScreen> {
  static const _tabs = ['Overview', 'Sessions', 'Payments', 'Progress'];

  EnrollmentDetail? _e;
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
      final e = await ref.read(coachingRepositoryProvider).getEnrollment(widget.enrollmentId);
      if (mounted) setState(() => _e = e);
    } on AppException catch (err) {
      if (mounted) setState(() => _error = err.message);
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
      return const StaffPermissionDenied(title: 'Enrollment', message: "You don't have permission to view coaching.");
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_e?.studentName ?? 'Enrollment')),
        body: SafeArea(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _e == null
                  ? const LoadingView(message: 'Loading enrollment…')
                  : _content(_e!, session),
        ),
      ),
    );
  }

  Widget _content(EnrollmentDetail e, session) {
    final canManage = session.can('COACHING_MANAGE_ENROLLMENTS');
    final canProgress = session.can('COACHING_MANAGE_PROGRESS');
    final canRecordPayment = session.can('FINANCE_RECORD_PAYMENT');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${e.programName} · ${e.programLevel}', style: AppTypography.rowTitle(context)),
              ),
              StatusBadge(label: e.status.label, tone: enrollmentTone(e.status)),
            ],
          ),
          if (e.status == EnrollmentStatus.cancelled && e.cancelReason != null)
            Text('Cancelled: ${e.cancelReason}', style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 2.4,
            children: [
              CoachingKpi(label: 'Fee', value: e.isMembershipIncluded ? 'Included' : coachMoney(e.priceMinor)),
              CoachingKpi(label: 'Paid', value: coachMoney(e.paidMinor)),
              CoachingKpi(label: 'Outstanding', value: coachMoney(e.outstandingMinor)),
              CoachingKpi(label: 'Sessions', value: e.sessionsTotal != null ? '${e.sessionsTotal}' : '—'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (canRecordPayment && !e.isMembershipIncluded && e.outstandingMinor > 0)
                OutlinedButton(
                  onPressed: () => context.push('/finance/pending-payments/${e.id}/record'),
                  child: const Text('Record Payment'),
                ),
              if (canManage && e.status == EnrollmentStatus.active)
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => ref.read(coachingRepositoryProvider).setEnrollmentStatus(e.id, 'PAUSED')),
                  child: const Text('Pause'),
                ),
              if (canManage && e.status == EnrollmentStatus.paused)
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => ref.read(coachingRepositoryProvider).setEnrollmentStatus(e.id, 'ACTIVE')),
                  child: const Text('Resume'),
                ),
              if (canManage && (e.status == EnrollmentStatus.active || e.status == EnrollmentStatus.paused))
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => ref.read(coachingRepositoryProvider).setEnrollmentStatus(e.id, 'COMPLETED')),
                  child: const Text('Complete'),
                ),
              if (canManage && e.status != EnrollmentStatus.cancelled && e.status != EnrollmentStatus.completed)
                OutlinedButton(onPressed: _busy ? null : () => _cancel(e), child: const Text('Cancel')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: AppSpacing.md),
          if (_tab == 0) _overview(e),
          if (_tab == 1) ..._sessions(e),
          if (_tab == 2) ..._payments(e),
          if (_tab == 3) ..._progress(e, canProgress),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _overview(EnrollmentDetail e) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Student', '${e.studentName}${e.studentPhone != null ? ' · ${e.studentPhone}' : ''}'),
            _kv('Program', e.programName),
            _kv('Coach', e.coachName ?? '—'),
            _kv('Start date', coachDate(e.startDate)),
            _kv('End date', coachDate(e.endDate)),
            _kv('Pricing', e.pricingType),
            _kv('Enrolled', coachDate(e.createdAt)),
            if (e.notes != null && e.notes!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(e.notes!, style: AppTypography.secondary(context)),
            ],
          ],
        ),
      );

  List<Widget> _sessions(EnrollmentDetail e) {
    if (e.sessions.isEmpty) {
      return [Text('Not on any session rosters yet.', style: AppTypography.secondary(context))];
    }
    return e.sessions
        .map((s) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              onTap: () => context.push('/coaching/sessions/${s.id}'),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.programName, style: AppTypography.rowTitle(context)),
                        Text('${coachDateTime(s.startAt)} · ${s.courtName}', style: AppTypography.caption(context)),
                      ],
                    ),
                  ),
                  StatusBadge(label: s.status.label, tone: sessionTone(s.status)),
                ],
              ),
            ))
        .toList();
  }

  List<Widget> _payments(EnrollmentDetail e) {
    if (e.payments.isEmpty) {
      return [Text('No payments recorded.', style: AppTypography.secondary(context))];
    }
    return e.payments
        .map((p) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(child: Text(coachMoney(p.amountMinor), style: AppTypography.rowTitle(context))),
                  Text('${coachDateTime(p.paidAt)}${p.method != null ? ' · ${p.method}' : ''}',
                      style: AppTypography.caption(context)),
                ],
              ),
            ))
        .toList();
  }

  List<Widget> _progress(EnrollmentDetail e, bool canProgress) {
    return [
      if (canProgress)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _addProgress(e.id),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add note'),
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
      if (!e.canViewProgress)
        Text("You don't have permission to view student progress.", style: AppTypography.secondary(context))
      else if (e.progressNotes.isEmpty)
        Text('No progress notes yet.', style: AppTypography.secondary(context))
      else
        ...e.progressNotes.map((n) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(n.skillOrGoal ?? 'Progress note', style: AppTypography.rowTitle(context))),
                      StatusBadge(label: n.progressStatus.label, tone: progressTone(n.progressStatus)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(n.note, style: AppTypography.body(context)),
                  Text('${n.coachName != null ? '${n.coachName} · ' : ''}${coachDateTime(n.createdAt)}',
                      style: AppTypography.caption(context)),
                ],
              ),
            )),
    ];
  }

  Future<void> _cancel(EnrollmentDetail e) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel enrollment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The record is kept. Any refund is handled separately through Finance.'),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Reason'), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel enrollment')),
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
    await _run(() => ref.read(coachingRepositoryProvider).setEnrollmentStatus(e.id, 'CANCELLED', reason: reason));
  }

  Future<void> _addProgress(String enrollmentId) async {
    final skill = TextEditingController();
    final note = TextEditingController();
    var status = 'ON_TRACK';
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
                Text('Add progress note', style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                TextField(controller: skill, decoration: const InputDecoration(labelText: 'Skill or goal (optional)')),
                const SizedBox(height: AppSpacing.sm),
                TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Note')),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: ProgressStatus.values
                      .map((s) => ChoiceChip(
                            label: Text(s.label),
                            selected: status == s.toJson(),
                            onSelected: (_) => setSheet(() => status = s.toJson()),
                          ))
                      .toList(),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(label: 'Save note', onPressed: () => Navigator.pop(ctx, true)),
              ],
            ),
          ),
        ),
      ),
    );
    final noteText = note.text.trim();
    final skillText = skill.text.trim();
    skill.dispose();
    note.dispose();
    if (ok != true) return;
    if (noteText.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a progress note.')));
      return;
    }
    await _run(() => ref.read(coachingRepositoryProvider).addProgressNote(
          enrollmentId: enrollmentId,
          note: noteText,
          skillOrGoal: skillText.isEmpty ? null : skillText,
          progressStatus: status,
        ));
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: AppTypography.caption(context))),
            Expanded(child: Text(v, style: AppTypography.body(context))),
          ],
        ),
      );
}
