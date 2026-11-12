import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../data/repositories/repository_providers.dart';
import 'intro_art.dart';
import 'otp_widgets.dart';
import 'session_controller.dart';
import 'signup_draft.dart';

const _resendSeconds = 30;

/// Verify Your Email: the second verification step. The 6-digit code was emailed when the account was created (right after the number
/// was verified). Once it checks out, the owner is signed in and the router moves on to setup.
///
/// Back returns to Create Your Account, still filled in, so the email or password can be changed.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.draft});

  final SignupDraft draft;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _message;
  bool _messageIsError = true;
  int _cooldown = _resendSeconds;
  Timer? _timer;

  SignupDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _startCooldown(); // the code went out a moment ago, so the server holds off another for 30 s
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = (_cooldown - 1).clamp(0, _resendSeconds));
      if (_cooldown == 0) t.cancel();
    });
  }

  void _error(String message) => setState(() {
        _message = message;
        _messageIsError = true;
      });

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.verifySignupCode(email: _draft.email, code: code);
      await repo.login(email: _draft.email, password: _draft.password);
      await ref.read(sessionControllerProvider.notifier).refresh();
      // Stays busy: the router replaces this page now that the owner is signed in (to setup, since the number is already verified).
    } on AppException catch (e) {
      if (!mounted) return;
      _error(e.message);
      setState(() => _busy = false);
    } catch (e, stack) {
      debugPrint('Email verification failed: $e\n$stack');
      if (!mounted) return;
      _error('Could not verify right now. Please try again.');
      setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).resendVerificationEmail(_draft.email);
      if (!mounted) return;
      _code.clear();
      _startCooldown();
      setState(() {
        _message = 'A new code has been sent to your email.';
        _messageIsError = false;
      });
    } on AppException catch (e) {
      if (mounted) _error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OtpPageFrame(
      onBack: () => context.canPop() ? context.pop() : context.go(AppRoutes.createAccount),
      art: IntroArtKind.otpEmail,
      title: 'Verify Your Email',
      lead: 'We’ve sent a 6-digit code to',
      strong: _draft.email,
      buttonLabel: 'Verify & Continue',
      busy: _busy,
      backEnabled: !_busy,
      onSubmit: _code.text.trim().length == 6 && !_busy ? _verify : null,
      message: _message,
      messageIsError: _messageIsError,
      body: Column(
        children: [
          OtpBoxes(
            controller: _code,
            focusNode: _focus,
            onChanged: () => setState(() {}),
            onSubmitted: _verify,
            hasError: _message != null && _messageIsError,
          ),
          const SizedBox(height: 26),
          OtpResendRow(label: 'Resend code', secondsLeft: _cooldown, busy: _busy, onResend: _resend),
        ],
      ),
    );
  }
}
