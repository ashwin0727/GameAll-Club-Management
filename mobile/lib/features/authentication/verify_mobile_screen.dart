import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import 'session_controller.dart';

const _resendCooldownSeconds = 30;

/// Signup step 2 (after the email code): the new owner proves their mobile number with an OTP read out in a phone call. Once it checks out
/// the session refreshes and the router sends them on to onboarding.
class VerifyMobileScreen extends ConsumerStatefulWidget {
  const VerifyMobileScreen({super.key});

  @override
  ConsumerState<VerifyMobileScreen> createState() => _VerifyMobileScreenState();
}

class _VerifyMobileScreenState extends ConsumerState<VerifyMobileScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _message;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _phoneValid => RegExp(r'^[6-9]\d{9}$').hasMatch(_phone.text.trim());

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendCooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = (_cooldown - 1).clamp(0, _resendCooldownSeconds));
      if (_cooldown == 0) t.cancel();
    });
  }

  Future<void> _send() async {
    if (!_phoneValid || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendMobileOtp(_phone.text.trim());
      if (!mounted) return;
      _code.clear();
      setState(() => _sent = true);
      _startCooldown();
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyMobileOtp(phone: _phone.text.trim(), code: _code.text.trim());
      // Re-reads the session; the router then moves a verified owner on to onboarding.
      await ref.read(sessionControllerProvider.notifier).refresh();
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not verify right now. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ResponsivePage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Verify Your Mobile', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              const Text(
                "We'll call you with a 6-digit OTP to confirm your number. Please accept the incoming call, listen to the code and enter it below. It expires in 10 minutes.",
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: _phone,
                enabled: !_sent,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91  ', counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
              if (_sent) ...[
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 10),
                  decoration: const InputDecoration(labelText: 'Code from the call', counterText: ''),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _verify(),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(_message!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (!_sent)
                PrimaryButton(
                  label: 'Call Me With OTP',
                  loadingLabel: 'Calling…',
                  isLoading: _busy,
                  onPressed: _phoneValid ? _send : null,
                )
              else ...[
                PrimaryButton(
                  label: 'Verify & Continue',
                  loadingLabel: 'Verifying…',
                  isLoading: _busy,
                  onPressed: _code.text.trim().length == 6 ? _verify : null,
                ),
                const SizedBox(height: AppSpacing.md),
                SecondaryButton(
                  label: _cooldown > 0 ? 'Call again in ${_cooldown}s' : 'Call again',
                  onPressed: _busy || _cooldown > 0 ? null : _send,
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _sent = false;
                            _message = null;
                          }),
                  child: const Text('Change number'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
