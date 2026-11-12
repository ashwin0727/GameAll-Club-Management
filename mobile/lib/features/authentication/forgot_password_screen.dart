import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_text_field.dart';
import 'auth_widgets.dart';
import 'forgot_password_art.dart';
import 'welcome_screen.dart' show introBackground, introPurple;

/// Forgot Password: one email field, and a reset link is emailed. (The process is unchanged; only the look is new.)
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _isSubmitting = false;
  bool _sent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).resetPassword(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on AppException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _backToLogin() => context.canPop() ? context.pop() : context.go(AppRoutes.signIn);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // The picture gives way to the keyboard so the form always has room.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final artWidth = (MediaQuery.of(context).size.width * 0.78).clamp(220.0, 320.0);
    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: introBackground,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _BackSquare(onTap: _backToLogin),
                ),
              ),
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
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                            child: Theme(
                              data: authFieldsTheme(context),
                              child: _sent ? _sentState(tokens) : _formState(tokens),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!keyboardOpen) Padding(padding: const EdgeInsets.only(bottom: 12), child: ForgotPasswordArt(width: artWidth)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formState(AppColorTokens tokens) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Image.asset('assets/images/gameall_logo_light.png', height: 38)),
          const SizedBox(height: 28),
          const Text(
            'Forgot Password?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF171717)),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No worries! Enter your registered email address and we’ll send you a reset link.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, height: 1.45, color: tokens.textSecondary),
          ),
          const SizedBox(height: 28),
          if (_errorMessage != null) ...[
            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.destructive)),
            const SizedBox(height: AppSpacing.md),
          ],
          AppTextField(
            label: 'Email Address',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(Icons.mail_outline),
            validator: Validators.email,
          ),
          const SizedBox(height: 22),
          AuthGradientButton(
            label: 'Send Reset Link',
            loadingLabel: 'Sending…',
            isLoading: _isSubmitting,
            radius: 16,
            labelSize: 19,
            labelWeight: FontWeight.w600,
            trailing: const Icon(Icons.arrow_forward_rounded),
            onPressed: _submit,
          ),
          const SizedBox(height: 10),
          Center(child: _backToLoginLink()),
        ],
      ),
    );
  }

  Widget _sentState(AppColorTokens tokens) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: Image.asset('assets/images/gameall_logo_light.png', height: 38)),
        const SizedBox(height: 28),
        const Text(
          'Check Your Email',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF171717)),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'If an account exists for ${_email.text.trim()}, we\'ve sent a link to reset your password.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, height: 1.45, color: tokens.textSecondary),
        ),
        const SizedBox(height: 28),
        AuthGradientButton(
          label: 'Back to Sign In',
          radius: 16,
          labelSize: 19,
          labelWeight: FontWeight.w600,
          onPressed: _backToLogin,
        ),
      ],
    );
  }

  Widget _backToLoginLink() {
    return TextButton(
      key: const ValueKey('forgot-back-to-login'),
      onPressed: _backToLogin,
      style: TextButton.styleFrom(
        foregroundColor: introPurple,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: const Text('Back to Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    );
  }
}

/// The rounded-square back button of the design: a white square with a soft outline and a thin arrow.
class _BackSquare extends StatelessWidget {
  const _BackSquare({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE5E1EF))),
        child: InkWell(
          key: const ValueKey('forgot-back'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: const SizedBox(height: 48, width: 48, child: Icon(Icons.arrow_back_rounded, size: 24, color: Color(0xFF171717))),
        ),
      ),
    );
  }
}
