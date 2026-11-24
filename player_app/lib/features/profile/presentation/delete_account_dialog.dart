import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/application/auth_providers.dart';
import '../data/account_repository.dart';

const _confirmWord = 'DELETE';

/// "Delete my account": says exactly what goes, asks the player to type DELETE, deletes, then signs out. Google Play requires an
/// in-app way to do this for any app that lets people create an account.
Future<void> showDeleteAccountDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showDialog<AccountDeletion>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DeleteAccountDialog(),
  );
  if (result == null || !context.mounted) return;
  if (result is AccountClosedForNow) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('delete-closed'),
        title: const Text('Your account is closed'),
        content: const Text(
          'Your sign-in is closed and any Auto Pay has been cancelled. The rest of your data is deleted automatically once all pending payments are settled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  // deleted or closed: either way this phone is signed out
  await ref.read(authControllerProvider.notifier).signOut();
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
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
      final result = await ref
          .read(accountRepositoryProvider)
          .deleteMyAccount();
      if (mounted) Navigator.of(context).pop(result);
    } on AccountDeletionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We could not delete your account. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final matches = _controller.text.trim() == _confirmWord;
    return AlertDialog(
      key: const ValueKey('delete-dialog'),
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently removes your GameAll sign-in and your profile (name, email and phone), and cancels any Auto Pay you set up so nobody is charged again.',
              style: AppTextStyles.body(p.secondaryText),
            ),
            const SizedBox(height: 10),
            Text(
              'A venue keeps its own booking and payment records of you, as a business must. This cannot be undone.',
              style: AppTextStyles.support(p.mutedText),
            ),
            const SizedBox(height: 14),
            Text(
              'Type $_confirmWord to confirm',
              style: AppTextStyles.support(p.secondaryText),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('delete-confirm-field'),
              controller: _controller,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: _confirmWord),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('delete-error'),
                style: const TextStyle(color: Color(0xFFD64545), fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('delete-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('delete-confirm'),
          onPressed: (matches && !_busy) ? _confirm : null,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  'Delete my account',
                  style: TextStyle(color: Color(0xFFD64545)),
                ),
        ),
      ],
    );
  }
}
