import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../data/repositories/repository_providers.dart';
import 'intro_art.dart';
import 'otp_widgets.dart';
import 'signup_draft.dart';

const _resendSeconds = 30;

/// Verify Your Number: the first of the two verification steps after Create Your Account. A 6-digit OTP is sent to the mobile number
/// typed there. Once it checks out, the account is created (which emails the code for the next step, [VerifyEmailScreen]) and this page
/// is replaced by it.
///
/// Back returns to Create Your Account with everything still filled in, so the number (or anything else) can be changed.
class VerifyPhoneScreen extends ConsumerStatefulWidget {
  const VerifyPhoneScreen({super.key, required this.draft});

  final SignupDraft draft;

  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen> {
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
    _startCooldown();
    // The code goes out as soon as the page opens, like the design's "We've sent a 6-digit OTP to ...".
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode(initial: true));
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

  Future<void> _sendCode({bool initial = false}) async {
    if (!mounted || _draft.phoneVerified) return;
    setState(() {
      _busy = !initial; // the first send happens behind the page, without a spinner on the button
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendSignupPhoneCode(_draft.phone);
      if (!mounted) return;
      if (!initial) {
        _code.clear();
        _startCooldown();
        setState(() {
          _message = 'A new OTP has been sent.';
          _messageIsError = false;
        });
      }
    } on AppException catch (e) {
      if (!mounted) return;
      _timer?.cancel();
      setState(() => _cooldown = 0); // let them try again straight away
      _error(e.message);
    } catch (_) {
      if (!mounted) return;
      _timer?.cancel();
      setState(() => _cooldown = 0);
      _error('Could not send the OTP right now. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Checks the OTP, then creates the account (the server emails the next code) and moves on to the email step.
  Future<void> _verify() async {
    final needsCode = !_draft.phoneVerified;
    if (_busy || (needsCode && _code.text.trim().length != 6)) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      if (needsCode) {
        final proof = await repo.verifySignupPhoneCode(phone: _draft.phone, code: _code.text.trim());
        _draft.markPhoneVerified(proof);
      }
      await repo.register(name: _draft.name, email: _draft.email, password: _draft.password, phone: _draft.phone, mobileProof: _draft.mobileProof);
      if (!mounted) return;
      // Replaces this page, so Back from the email step goes to Create Your Account.
      context.pushReplacement(AppRoutes.verifyEmail, extra: _draft);
    } on AppException catch (e) {
      if (mounted) _error(e.message);
    } catch (e, stack) {
      debugPrint('Phone verification failed: $e\n$stack');
      if (mounted) _error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _draft.phoneVerified || _code.text.trim().length == 6;
    return OtpPageFrame(
      onBack: () => context.canPop() ? context.pop() : context.go(AppRoutes.createAccount),
      art: IntroArtKind.otpPhone,
      title: 'Verify Your Number',
      lead: 'We’ve sent a 6-digit OTP to',
      strong: _draft.phoneDisplay,
      buttonLabel: 'Verify & Continue',
      busy: _busy,
      onSubmit: ready && !_busy ? _verify : null,
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
          OtpResendRow(secondsLeft: _cooldown, busy: _busy, onResend: _sendCode),
        ],
      ),
    );
  }
}
