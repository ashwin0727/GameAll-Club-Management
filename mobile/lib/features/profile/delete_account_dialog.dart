import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../authentication/session_controller.dart';

const _confirmWord = 'DELETE';

/// "Delete account": says exactly what goes, asks the person to type DELETE, deletes, then signs out. Required by Google Play
/// for any app that lets people create an account.
Future<void> showDeleteAccountDialog(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<AccountDeletionResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DeleteAccountDialog(),
  );
  if (result == null || !context.mounted) return;

  if (result is AccountClosedPendingSettlement) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Your account is closed'),
        content: Text(
          '${result.unsettledCount} online payment${result.unsettledCount == 1 ? '' : 's'} (₹${result.unsettledInr}) still need to be settled to you. '
          'We keep those payment records until that is done, then everything else is deleted automatically. '
          'Auto Pay has been cancelled and no one can book with your facility.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }
  // Deleted or closed: either way this device is signed out; the router sends them to sign-in.
  await ref.read(sessionControllerProvider.notifier).signOut();
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(accountRepositoryProvider).deleteMyAccount();
      if (mounted) Navigator.pop(context, result);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'We could not delete your account. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final matches = _controller.text.trim() == _confirmWord;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: t.destructive),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: Text('Delete your account?')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This cannot be undone. Deleting your account removes:'),
            const SizedBox(height: AppSpacing.sm),
            for (final line in const [
              'Your sign-in and profile.',
              'Your facility and everything in it: courts, bookings, members, memberships, coaching and finance records.',
              'Staff accounts that only worked at your facility.',
              'Your plan and Auto Pay. Members paying through Auto Pay are no longer charged.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(line, style: TextStyle(color: t.textSecondary, height: 1.3))),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'If any online payment is still waiting to be settled to you, we keep those payment records and close your account right away; '
              'everything is deleted once they are settled.',
              style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              enabled: !_busy,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: t.destructive, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy || !matches ? null : _confirm,
          style: FilledButton.styleFrom(backgroundColor: t.destructive),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Delete my account'),
        ),
      ],
    );
  }
}
