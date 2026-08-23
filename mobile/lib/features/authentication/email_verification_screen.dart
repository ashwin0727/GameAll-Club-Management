import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import 'session_controller.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends ConsumerState<EmailVerificationScreen> {
  bool _isChecking = false;
  bool _isResending = false;
  String? _message;

  Future<void> _checkVerification() async {
    setState(() => _isChecking = true);
    try {
      await ref.read(sessionControllerProvider.notifier).refresh();
      final repo = ref.read(authRepositoryProvider);
      if (!repo.isEmailVerified) {
        setState(() => _message = 'Not verified yet — check your inbox and tap the link.');
      } else if (mounted) {
        context.go(AppRoutes.onboardingFacility);
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).resendVerificationEmail(widget.email);
      if (mounted) setState(() => _message = 'Verification email resent.');
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ResponsivePage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Verify your email', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              Text(
                'We sent a verification link to ${widget.email}. '
                'Tap the link, then come back and check your status.',
              ),
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(_message!),
              ],
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: "I've verified — Check status",
                loadingLabel: 'Checking…',
                isLoading: _isChecking,
                onPressed: _checkVerification,
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: _isResending ? 'Resending…' : 'Resend verification email',
                onPressed: _isResending ? null : _resend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}