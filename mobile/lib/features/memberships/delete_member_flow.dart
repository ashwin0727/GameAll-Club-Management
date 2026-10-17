import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/top_notice.dart';
import 'add_member_wizard.dart' show isAutoPayLive;

/// What a Delete Member attempt ended in.
enum DeleteMemberOutcome {
  /// Nothing happened (the owner backed out, or it failed — a notice says why).
  none,

  /// The member was deleted.
  deleted,

  /// AutoPay and the membership were cancelled; the member is still there.
  autoPayCancelled,
}

Future<bool> _ask(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  String cancel = 'Cancel',
}) async {
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

/// Delete Member, in the order the owner expects (same as the web):
///   1. "Delete Member" — confirm;
///   2. if AutoPay is still running, a second dialog asks to cancel it — confirming cancels AutoPay AND the
///      membership but does NOT delete the member;
///   3. choosing Delete again (AutoPay now stopped) deletes the member.
Future<DeleteMemberOutcome> runDeleteMemberFlow(
  BuildContext context,
  WidgetRef ref, {
  required String memberId,
  required String name,
  required String? membershipId,
}) async {
  final proceed = await _ask(
    context,
    title: 'Delete Member',
    body: 'Do you want to proceed with deleting $name? Their memberships and bookings will be removed. '
        "Payments already received stay in Finance. This can't be undone.",
    confirm: 'Yes, Delete',
  );
  if (!proceed || !context.mounted) return DeleteMemberOutcome.none;

  final repo = ref.read(membershipRepositoryProvider);
  try {
    final autoPay = membershipId == null ? null : await repo.getMembershipAutoPay(membershipId).catchError((_) => null);
    if (autoPay != null && isAutoPayLive(autoPay.status, autoPay.chargeCount)) {
      if (!context.mounted) return DeleteMemberOutcome.none;
      final cancel = await _ask(
        context,
        title: 'Cancel AutoPay?',
        body: "$name has AutoPay running, so they can't be deleted yet. Cancelling stops all future charges and cancels "
            'their membership — the member is not deleted. You can delete them afterwards.',
        confirm: 'Cancel AutoPay',
        cancel: 'Keep AutoPay',
      );
      if (!cancel) return DeleteMemberOutcome.none;
      await repo.cancelMembershipSubscription(membershipId!);
      await repo.cancelMembership(membershipId);
      if (context.mounted) {
        showTopNotice(context, 'AutoPay and membership cancelled. $name was not deleted — choose Delete Member again to remove them.');
      }
      return DeleteMemberOutcome.autoPayCancelled;
    }
    await repo.deleteMember(memberId);
    if (context.mounted) showTopNotice(context, 'Member deleted successfully');
    return DeleteMemberOutcome.deleted;
  } on AppException catch (e) {
    if (context.mounted) showTopNotice(context, e.message, success: false);
    return DeleteMemberOutcome.none;
  }
}
