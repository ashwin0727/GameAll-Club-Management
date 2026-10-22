import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import 'session_controller.dart';

const _resendCooldownSeconds = 30;

/// Verify Email: enter the 6-digit code emailed at signup. Only once it checks out is the account signed in and sent on
/// to onboarding.
///
/// [password] is the one just chosen at signup, handed over in memory by the router (never in the URL) so the verified
/// owner can be signed in without typing it again. If it's missing (app restarted), they're sent to Sign In instead.
class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key, required this.email, this.password});

  final String email;
  final String? password;

  @override
  ConsumerState<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends ConsumerState<EmailVerificationScreen> {
  final _code = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;
  String? _message;
  bool _messageIsError = false;
  int _cooldown = _resendCooldownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendCooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = (_cooldown - 1).clamp(0, _resendCooldownSeconds));
      if (_cooldown == 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6 || _isVerifying) return;
    setState(() {
      _isVerifying = true;
      _message = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.verifySignupCode(email: widget.email, code: code);
      final password = widget.password;
      if (password == null || password.isEmpty) {
        if (mounted) context.go(AppRoutes.signIn);
        return;
      }
      await repo.login(email: widget.email, password: password);
      await ref.read(sessionControllerProvider.notifier).refresh();
      // Keep the spinner running into the navigation rather than flicking back to idle first.
      if (mounted) context.go(AppRoutes.onboardingWelcome);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _messageIsError = true;
        _isVerifying = false;
      });
    } catch (e, stack) {
      debugPrint('Verification failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _message = 'Could not verify right now. Please try again.';
        _messageIsError = true;
        _isVerifying = false;
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).resendVerificationEmail(widget.email);
      if (!mounted) return;
      _startCooldown();
      setState(() {
        _message = 'A new code has been sent.';
        _messageIsError = false;
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _message = e.message;
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ResponsivePage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Verify Your Email', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              Text(
                'We sent a 6-digit code to ${widget.email}. Enter it below to finish creating your account. '
                'It expires in 10 minutes — check your spam folder if you can\'t find it.',
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 10),
                decoration: const InputDecoration(labelText: 'Verification code', counterText: ''),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _verify(),
              ),
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(_message!, style: TextStyle(color: _messageIsError ? scheme.error : null)),
              ],
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Verify & Continue',
                loadingLabel: 'Verifying…',
                isLoading: _isVerifying,
                onPressed: _code.text.trim().length == 6 ? _verify : null,
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: _isResending
                    ? 'Resending…'
                    : _cooldown > 0
                        ? 'Resend code in ${_cooldown}s'
                        : 'Resend code',
                onPressed: _isResending || _cooldown > 0 ? null : _resend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
