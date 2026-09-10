import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/services/supabase_provider.dart';
import '../../shared/widgets/app_button.dart';
import '../authentication/session_controller.dart';

/// Forced first-sign-in password reset for an administrator-created staff
/// account. Reached only when profiles.must_reset_password is true; the
/// router keeps the user here until it clears.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _password.text;
    if (pw.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseClientProvider);
      await client.auth.updateUser(UserAttributes(password: pw));
      await ref.read(staffRepositoryProvider).markPasswordResetComplete();
      await ref.read(sessionControllerProvider.notifier).refresh();
      // The router's redirect takes over once the session no longer flags
      // must_reset_password.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set your password'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'Your account was set up with a one-time password. Choose your own to finish activating it.',
              style: AppTypography.secondary(context),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm new password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Set password',
              loadingLabel: 'Saving…',
              isLoading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
