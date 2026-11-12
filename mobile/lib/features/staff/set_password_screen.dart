import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/services/supabase_provider.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import '../authentication/welcome_screen.dart' show introBackground, introPurple;

/// Reset Password: forced first-sign-in password reset for an administrator-created staff account. Reached only when
/// profiles.must_reset_password is true; the router keeps the user here until it clears. There is deliberately no back button:
/// the only ways out are setting a password or "Back to Login", which signs out.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Drives the live ticks in the requirements card.
    _password.addListener(() => setState(() {}));
  }

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

  /// Signs out and returns to the login page.
  Future<void> _backToLogin() async {
    await ref.read(sessionControllerProvider.notifier).signOut();
    if (mounted) context.go(AppRoutes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    // The picture needs room: it gives way to the keyboard, to short screens and to enlarged text.
    final showArt = !keyboardOpen && size.height >= 700 && MediaQuery.textScalerOf(context).scale(16) <= 18.4;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: DecoratedBox(
          decoration: introBackground,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                              child: Theme(data: authFieldsTheme(context), child: _form(context)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showArt) Padding(padding: const EdgeInsets.only(bottom: 6), child: _ResetArt(width: (size.width * 0.86).clamp(240.0, 360.0))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: Image.asset('assets/images/gameall_logo_light.png', height: 38)),
        const SizedBox(height: 26),
        const Text(
          'Reset Password',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF171717)),
        ),
        const SizedBox(height: 10),
        Text(
          'Create a new password for your account.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, height: 1.4, color: tokens.textSecondary),
        ),
        const SizedBox(height: 24),
        TextField(
          key: const ValueKey('reset-new-password'),
          controller: _password,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'New Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(_showPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('reset-confirm-password'),
          controller: _confirm,
          obscureText: !_showConfirm,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submit(),
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _showConfirm ? 'Hide password' : 'Show password',
              icon: Icon(_showConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _showConfirm = !_showConfirm),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _RequirementsCard(password: _password.text),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.destructive, fontSize: 15)),
        ],
        const SizedBox(height: 20),
        AuthGradientButton(
          label: 'Reset Password',
          loadingLabel: 'Saving…',
          isLoading: _busy,
          radius: 16,
          labelSize: 19,
          labelWeight: FontWeight.w600,
          trailing: const Icon(Icons.arrow_forward_rounded),
          onPressed: _submit,
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            key: const ValueKey('reset-back-to-login'),
            onPressed: _busy ? null : _backToLogin,
            style: TextButton.styleFrom(
              foregroundColor: introPurple,
              minimumSize: const Size(64, 52),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Back to Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

/// The "Password Requirements" card. Each rule ticks (purple) once the password meets it. Only the first rule is enforced on submit
/// (the app-wide minimum); the rest are guidance toward a stronger password.
class _RequirementsCard extends StatelessWidget {
  const _RequirementsCard({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final rules = <(String, bool)>[
      ('At least 8 characters', password.length >= 8),
      ('One uppercase letter (A–Z)', password.contains(RegExp(r'[A-Z]'))),
      ('One number (0–9)', password.contains(RegExp(r'[0-9]'))),
      ('One special character (!@#\$%^)', password.contains(RegExp(r'[^A-Za-z0-9]'))),
    ];
    return Container(
      key: const ValueKey('reset-requirements'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EBFF).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E1EF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.verified_user_outlined, size: 30, color: Color(0xFF2A1070)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Password Requirements', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF171717))),
                const SizedBox(height: 6),
                for (final (text, met) in rules)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.check_rounded, key: ValueKey(met ? 'rule-met' : 'rule-open'), size: 20, color: met ? introPurple : const Color(0xFFC9C5D6)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(text, style: TextStyle(fontSize: 15.5, color: met ? const Color(0xFF171717) : const Color(0xFF6B6880)))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Your padlock-and-refresh picture, with its edges faded into the page so there is no box around it.
class _ResetArt extends StatelessWidget {
  const _ResetArt({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    Shader fade(Rect r, Axis axis) => LinearGradient(
          begin: axis == Axis.vertical ? Alignment.topCenter : Alignment.centerLeft,
          end: axis == Axis.vertical ? Alignment.bottomCenter : Alignment.centerRight,
          colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: const [0.0, 0.22, 0.78, 1.0],
        ).createShader(r);
    return Semantics(
      image: true,
      label: 'A padlock with a refresh badge',
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => fade(r, Axis.vertical),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => fade(r, Axis.horizontal),
          child: Image.asset('assets/images/reset_password_art.png', width: width, fit: BoxFit.fitWidth),
        ),
      ),
    );
  }
}
