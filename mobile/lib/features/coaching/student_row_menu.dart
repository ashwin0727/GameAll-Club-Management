import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/top_notice.dart';
import '../authentication/session_controller.dart';

/// What a Delete Student attempt ended in.
enum DeleteStudentOutcome {
  /// Nothing happened (backed out, or it failed — a notice says why).
  none,

  /// The student was deleted.
  deleted,

  /// Coaching and AutoPay were cancelled; the student is still there.
  coachingCancelled,
}

Future<bool> _ask(BuildContext context, {required String title, required String body, required String confirm, String cancel = 'Cancel'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ctx.tokens.destructive, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Delete Student, in the order the owner expects (same as the web):
///   1. "Delete Student" — confirm;
///   2. if an online payment / AutoPay is live, or money was received and coaching is still on, a second dialog asks
///      to cancel coaching (and AutoPay) — confirming cancels but does NOT delete the student;
///   3. choosing Delete again deletes the student.
Future<DeleteStudentOutcome> runDeleteStudentFlow(
  BuildContext context,
  WidgetRef ref, {
  required String enrollmentId,
  required String studentName,
  required String programName,
  required EnrollmentStatus status,
  required int paidMinor,
}) async {
  final proceed = await _ask(
    context,
    title: 'Delete Student',
    body: 'Do you want to proceed with deleting $studentName from $programName? Their enrollment will be removed. '
        "Payments already received stay in Finance. This can't be undone.",
    confirm: 'Yes, Delete',
  );
  if (!proceed || !context.mounted) return DeleteStudentOutcome.none;

  final repo = ref.read(coachingRepositoryProvider);
  try {
    final billing = await repo.getEnrollmentBilling(enrollmentId).catchError((_) => null);
    final liveBilling = billing != null && billing.isLive;
    final cancelled = status == EnrollmentStatus.cancelled;
    if (!cancelled && (liveBilling || paidMinor > 0)) {
      if (!context.mounted) return DeleteStudentOutcome.none;
      final cancel = await _ask(
        context,
        title: 'Cancel Coaching & AutoPay?',
        body: "$studentName still has an active payment or coaching, so they can't be deleted yet. Cancelling stops any online "
            'payment or AutoPay and cancels their coaching — the student is not deleted. You can delete them afterwards.',
        confirm: 'Cancel Coaching',
        cancel: 'Keep Coaching',
      );
      if (!cancel) return DeleteStudentOutcome.none;
      await repo.setEnrollmentStatus(enrollmentId, 'CANCELLED', reason: 'Cancelled before deleting the student');
      if (context.mounted) {
        showTopNotice(context, 'Coaching and AutoPay cancelled. $studentName was not deleted — choose Delete Student again to remove them.');
      }
      return DeleteStudentOutcome.coachingCancelled;
    }
    // Already cancelled but a link / AutoPay is somehow still live: stop it, then delete.
    if (liveBilling) await repo.cancelEnrollmentBilling(enrollmentId);
    await repo.deleteEnrollment(enrollmentId);
    if (context.mounted) showTopNotice(context, 'Student deleted successfully');
    return DeleteStudentOutcome.deleted;
  } on AppException catch (e) {
    if (context.mounted) showTopNotice(context, e.message, success: false);
    return DeleteStudentOutcome.none;
  }
}

enum _StudentAction { student, program, delete }

/// The ⋮ menu on a student row — View Student, View Program and, for someone who may manage enrollments, a red
/// Delete that runs the two-step flow above — the same entries as the web's row menu.
class StudentRowMenu extends ConsumerWidget {
  const StudentRowMenu({
    super.key,
    required this.enrollmentId,
    required this.studentName,
    required this.programName,
    required this.programId,
    required this.paidMinor,
    required this.status,
    required this.onChanged,
    this.onOpen,
  });

  final String enrollmentId;
  final String studentName;
  final String programName;
  final String programId;
  final int paidMinor;
  final EnrollmentStatus status;

  /// Called after the student was deleted or their coaching cancelled, so the list can reload.
  final VoidCallback onChanged;

  /// Opens a route; defaults to `context.push`.
  final Future<void> Function(String route)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final canManage = ref.watch(sessionControllerProvider).can('COACHING_MANAGE_ENROLLMENTS');
    final showDelete = canManage;

    Future<void> open(String route) async => onOpen != null ? onOpen!(route) : context.push(route);

    return PopupMenuButton<_StudentAction>(
      tooltip: 'Student actions',
      icon: Icon(Icons.more_vert, color: t.textSecondary),
      padding: EdgeInsets.zero,
      onSelected: (a) async {
        switch (a) {
          case _StudentAction.student:
            await open('${AppRoutes.coachingEnrollments}/$enrollmentId');
          case _StudentAction.program:
            await open('${AppRoutes.coachingPrograms}/$programId');
          case _StudentAction.delete:
            final outcome = await runDeleteStudentFlow(context, ref,
                enrollmentId: enrollmentId, studentName: studentName, programName: programName, status: status, paidMinor: paidMinor);
            if (outcome != DeleteStudentOutcome.none) onChanged();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: _StudentAction.student, child: Text('View Student')),
        if (programId.isNotEmpty) const PopupMenuItem(value: _StudentAction.program, child: Text('View Program')),
        if (showDelete)
          PopupMenuItem(
            value: _StudentAction.delete,
            child: Row(children: [
              Icon(Icons.delete_outline, size: 20, color: t.destructive),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: t.destructive)),
            ]),
          ),
      ],
    );
  }
}
