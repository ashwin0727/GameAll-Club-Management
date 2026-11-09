import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/pressable.dart';
import '../application/auth_providers.dart';
import '../data/player_auth_repository.dart';
import '../domain/player_profile.dart';

/// Opens the login: a centred dialog on a wide window, a full-screen page on a phone. Returns true once the player is signed in
/// (and has a profile).
Future<bool> showPlayerLogin(BuildContext context) async {
  final wide =
      MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;
  final result = wide
      ? await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.62),
          builder: (_) => Dialog(
            key: const ValueKey('login-dialog'),
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const LoginFlow(),
            ),
          ),
        )
      : await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const LoginPage(),
          ),
        );
  return result ?? false;
}

/// The login as a page (phone app, and the /login route).
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const LoginFlow(),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Step { phone, code, profile }

/// Three steps in one card, like the design: "Enter your phone number", then the six-digit code, then (first time only) name and
/// email. Closes itself with `true` when the player is signed in.
class LoginFlow extends ConsumerStatefulWidget {
  const LoginFlow({super.key});

  @override
  ConsumerState<LoginFlow> createState() => _LoginFlowState();
}

class _LoginFlowState extends ConsumerState<LoginFlow> {
  _Step _step = _Step.phone;
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;

  /// What the clubs already know about this number (open login only): a name for the form, and a line saying we found records.
  int _clubRecords = 0;

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');
  String get _e164 => '+91$_digits';

  @override
  void initState() {
    super.initState();
    // Already signed in but never gave a name (closed the app half way): go straight to that step.
    final status = ref.read(authControllerProvider).value;
    if (status is NeedsProfile) _step = _Step.profile;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = (_resendIn - 1).clamp(0, 999));
      if (_resendIn == 0) t.cancel();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Continue on the phone step. With codes switched off this signs in at once; otherwise a code is sent.
  Future<void> _sendCode() => _run(() async {
    final start = await ref
        .read(playerAuthRepositoryProvider)
        .beginLogin(_e164);
    if (!mounted) return;
    if (start.next == LoginNext.signedIn) {
      _clubRecords = start.clubRecords;
      if (_name.text.trim().isEmpty && start.knownName != null)
        _name.text = start.knownName!;
      await _finishSignIn();
      return;
    }
    setState(() {
      _step = _Step.code;
      _code.clear();
    });
    _startCountdown();
  });

  /// Resend from the code step (a code is always what is wanted there).
  Future<void> _resend() => _run(() async {
    await ref.read(playerAuthRepositoryProvider).sendCode(_e164);
    if (mounted) _startCountdown();
  });

  /// Signed in: a returning player goes straight in; a new one gives their name and email next.
  Future<void> _finishSignIn() async {
    await ref.read(authControllerProvider.notifier).refresh();
    if (!mounted) return;
    final status = ref.read(authControllerProvider).value;
    if (status is SignedIn) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _step = _Step.profile);
    }
  }

  Future<void> _verify() => _run(() async {
    await ref
        .read(playerAuthRepositoryProvider)
        .verifyCode(_e164, _code.text.trim());
    await _finishSignIn();
  });

  Future<void> _register() => _run(() async {
    await ref
        .read(authControllerProvider.notifier)
        .register(fullName: _name.text, email: _email.text);
    if (mounted) Navigator.of(context).pop(true);
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = switch (_step) {
      _Step.phone => 'Enter your phone number',
      _Step.code => 'Enter the code',
      _Step.profile => 'Tell us about you',
    };
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: close on the left, the title in the middle.
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    label: 'Close',
                    child: Pressable(
                      key: const ValueKey('login-close'),
                      onTap: () => Navigator.of(context).pop(false),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.close_rounded,
                          color: p.primaryText,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  'Login / Signup to continue',
                  style: AppTextStyles.cardHeading(p.primaryText)
                      .copyWith(fontSize: 16),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.sectionHeading(p.primaryText)
                      .copyWith(fontSize: 22),
                ),
                const SizedBox(height: 22),
                switch (_step) {
                  _Step.phone => _phoneStep(p),
                  _Step.code => _codeStep(p),
                  _Step.profile => _profileStep(p),
                },
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          key: const ValueKey('login-error'),
                          style: AppTextStyles.support(AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: phone ──────────────────────────────────────────────────────

  Widget _phoneStep(AppPalette p) {
    final valid = isValidIndianMobile(_digits);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          p,
          child: Row(
            children: [
              const _IndiaFlag(),
              const SizedBox(width: 8),
              Text(
                '+91',
                style: AppTextStyles.body(p.primaryText)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 22, color: p.border),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('login-phone'),
                  controller: _phone,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => valid && !_busy ? _sendCode() : null,
                  style: AppTextStyles.body(p.primaryText),
                  cursorColor: AppColors.cyan,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Phone number',
                    hintStyle: AppTextStyles.body(p.mutedText),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text.rich(
          TextSpan(
            style: AppTextStyles.support(p.secondaryText),
            children: [
              const TextSpan(
                text: "By entering your number, you're agreeing to our ",
              ),
              TextSpan(
                text: 'Terms of Service',
                style: TextStyle(
                  color: AppColors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
              const TextSpan(text: ' & '),
              TextSpan(
                text: 'Privacy Policy.',
                style: TextStyle(
                  color: AppColors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _continue(p, enabled: valid && !_busy, onPressed: _sendCode),
      ],
    );
  }

  // ── Step 2: code ───────────────────────────────────────────────────────

  Widget _codeStep(AppPalette p) {
    final valid = _code.text.trim().length == 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'We sent a 6-digit code to +91 $_digits.',
          style: AppTextStyles.body(p.secondaryText),
        ),
        const SizedBox(height: 18),
        _field(
          p,
          child: TextField(
            key: const ValueKey('login-code'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => valid && !_busy ? _verify() : null,
            style: AppTextStyles.sectionHeading(p.primaryText)
                .copyWith(letterSpacing: 8),
            cursorColor: AppColors.cyan,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: '······',
              hintStyle: AppTextStyles.sectionHeading(p.mutedText)
                  .copyWith(letterSpacing: 8),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Pressable(
              key: const ValueKey('login-change-number'),
              onTap: _busy
                  ? null
                  : () => setState(() {
                      _step = _Step.phone;
                      _error = null;
                    }),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Change number',
                  style: AppTextStyles.button(AppColors.blue),
                ),
              ),
            ),
            const Spacer(),
            if (_resendIn > 0)
              Text(
                'Resend in ${_resendIn}s',
                key: const ValueKey('login-resend-wait'),
                style: AppTextStyles.support(p.secondaryText),
              )
            else
              Pressable(
                key: const ValueKey('login-resend'),
                onTap: _busy ? null : _resend,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Resend code',
                    style: AppTextStyles.button(AppColors.blue),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _continue(p, enabled: valid && !_busy, onPressed: _verify),
      ],
    );
  }

  // ── Step 3: name and email (first time only) ───────────────────────────

  /// "+91 98765 43210": the number just verified (what was typed this time, else what the session was signed in with).
  String? get _verifiedNumber {
    var d = _digits;
    if (d.length < 10) d = (ref.read(signedInPhoneProvider) ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length < 10) return null;
    d = d.substring(d.length - 10);
    return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
  }

  Widget _profileStep(AppPalette p) {
    final valid = _name.text.trim().isNotEmpty && isValidEmail(_email.text);
    final number = _verifiedNumber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _clubRecords > 0
              ? 'We found your records at your clubs. Confirm your name and add your email to finish.'
              : 'Add your name and email to finish.',
          key: const ValueKey('login-profile-intro'),
          style: AppTextStyles.body(p.secondaryText),
        ),
        const SizedBox(height: 18),
        if (number != null) ...[
          _field(
            p,
            child: Row(
              key: const ValueKey('login-verified-phone'),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.call_outlined, size: 18, color: p.secondaryText),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mobile number', style: AppTextStyles.meta(p.mutedText)),
                      const SizedBox(height: 2),
                      Text(number, key: const ValueKey('login-verified-number'), style: AppTextStyles.body(p.primaryText)),
                    ],
                  ),
                ),
                const Icon(Icons.verified_rounded, size: 18, color: AppColors.success),
                const SizedBox(width: 4),
                Text('Verified', style: AppTextStyles.meta(AppColors.success).copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _field(
          p,
          child: TextField(
            key: const ValueKey('login-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _error = null),
            style: AppTextStyles.body(p.primaryText),
            cursorColor: AppColors.cyan,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'Full name',
              hintStyle: AppTextStyles.body(p.mutedText),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _field(
          p,
          child: TextField(
            key: const ValueKey('login-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => valid && !_busy ? _register() : null,
            style: AppTextStyles.body(p.primaryText),
            cursorColor: AppColors.cyan,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'Email address',
              hintStyle: AppTextStyles.body(p.mutedText),
            ),
          ),
        ),
        const SizedBox(height: 28),
        _continue(
          p,
          enabled: valid && !_busy,
          onPressed: _register,
          label: 'Continue',
        ),
      ],
    );
  }

  // ── Shared pieces ──────────────────────────────────────────────────────

  Widget _field(AppPalette p, {required Widget child}) => Container(
    height: 62,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: p.isDark ? p.background.withValues(alpha: 0.5) : p.elevated,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: p.border),
    ),
    child: child,
  );

  Widget _continue(
    AppPalette p, {
    required bool enabled,
    required VoidCallback onPressed,
    String label = 'Continue',
  }) => SizedBox(
    width: double.infinity,
    child: _busy
        ? SizedBox(
            height: 56,
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: p.highlight,
                ),
              ),
            ),
          )
        : GameAllButton.gradient(
            label: label,
            expand: true,
            height: 56,
            onPressed: enabled ? onPressed : null,
          ),
  );
}

/// The India flag, drawn (so it looks the same on every platform; flag emoji do not on Windows): saffron, white and green bands in
/// the 3:2 shape, with the navy Ashoka Chakra (24 spokes) in the middle of the white band.
class _IndiaFlag extends StatelessWidget {
  const _IndiaFlag();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      key: const ValueKey('india-flag'),
      width: 33,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x33FFFFFF), width: 0.6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2.4),
        child: Column(
          children: [
            Expanded(child: Container(color: const Color(0xFFFF9933))),
            Expanded(
              child: Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 6.4,
                  height: 6.4,
                  child: CustomPaint(painter: _ChakraPainter()),
                ),
              ),
            ),
            Expanded(child: Container(color: const Color(0xFF138808))),
          ],
        ),
      ),
    ),
  );
}

/// The Ashoka Chakra: a navy ring with 24 spokes and a hub.
class _ChakraPainter extends CustomPainter {
  const _ChakraPainter();

  static const _navy = Color(0xFF000080);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final ring = Paint()
      ..color = _navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final spoke = Paint()
      ..color = _navy
      ..strokeWidth = 0.32;
    canvas.drawCircle(c, r - 0.35, ring);
    for (var i = 0; i < 24; i++) {
      final a = i * 2 * 3.141592653589793 / 24;
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * (r - 0.35), spoke);
    }
    canvas.drawCircle(c, 0.7, Paint()..color = _navy);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
