import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/utils/legal_links.dart';
import '../../shared/widgets/app_text_field.dart';
import 'auth_widgets.dart';
import 'signup_draft.dart';
import 'welcome_screen.dart' show introBackground;

/// Create Your Account: full name, mobile number, email, password and the password again. The email and the mobile number are both confirmed on the next
/// pages after it: first the number ([VerifyPhoneScreen]), then the email ([VerifyEmailScreen]).
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  /// What the verification pages work from. It lives here, so Back from them returns to this form still filled in, and a number
  /// that was already verified is remembered if the person changes only their email or password.
  final _draft = SignupDraft();
  String? _errorMessage;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _draft
      ..name = _name.text.trim()
      ..phone = _phone.text.trim()
      ..email = _email.text.trim()
      ..password = _password.text;

    // Step 1 is the mobile number. Nothing is created yet, so Back from there changes nothing on the server.
    if (!_draft.phoneVerified) {
      setState(() => _errorMessage = null);
      await context.push<void>(AppRoutes.verifyPhone, extra: _draft);
      return;
    }

    // The number was already verified (they came back to change something else): create the account now and go to step 2.
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).register(
        name: _draft.name,
        email: _draft.email,
        password: _draft.password,
        phone: _draft.phone,
        mobileProof: _draft.mobileProof,
      );
      if (!mounted) return;
      await context.push<void>(AppRoutes.verifyEmail, extra: _draft);
      if (mounted) setState(() => _isSubmitting = false);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isSubmitting = false;
      });
    } catch (e, stack) {
      debugPrint('Create account failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  /// To the login page. When it is already underneath (the person came from it), go back to that same page with the normal back
  /// motion; otherwise (they arrived from the intro) open it.
  void _goToLogin() {
    final router = GoRouter.of(context);
    final stack = router.routerDelegate.currentConfiguration.matches.map((m) => m.matchedLocation);
    if (router.canPop() && stack.contains(AppRoutes.signIn)) {
      router.pop();
    } else {
      router.go(AppRoutes.signIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final linkStyle = TextStyle(color: tokens.primary, fontWeight: FontWeight.w700);
    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: introBackground,
        child: SafeArea(
          child: Column(
            children: [
              // Back stays pinned at the top left; everything else is centred in the space below it.
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: IconButton(
                    key: const ValueKey('create-account-back'),
                    onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.welcome),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: const Color(0xFF171717),
                    tooltip: 'Back',
                  ),
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
                            padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                            child: Theme(
                              data: authFieldsTheme(context),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Center(child: Image.asset('assets/images/gameall_logo_light.png', height: 40)),
                                    const SizedBox(height: AppSpacing.xl),
                                    const Text(
                                      'Create Your Account',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF171717)),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      'Set up your facility in a few minutes and get started.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 16, height: 1.4, color: tokens.textSecondary),
                                    ),
                                    const SizedBox(height: AppSpacing.xl),
                                    if (_errorMessage != null) ...[
                                      Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.destructive)),
                                      const SizedBox(height: AppSpacing.md),
                                    ],
                                    AppTextField(
                                      label: 'Full Name',
                                      controller: _name,
                                      textInputAction: TextInputAction.next,
                                      prefixIcon: const Icon(Icons.person_outline),
                                      validator: (v) => Validators.name(v),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    TextFormField(
                                      controller: _phone,
                                      keyboardType: TextInputType.phone,
                                      textInputAction: TextInputAction.next,
                                      maxLength: 10,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      autovalidateMode: AutovalidateMode.onUserInteraction,
                                      validator: Validators.mobile,
                                      decoration: const InputDecoration(
                                        labelText: 'Mobile Number',
                                        prefixIcon: Icon(Icons.smartphone_outlined),
                                        prefixText: '+91  ',
                                        counterText: '',
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    AppTextField(
                                      label: 'Email Address',
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      prefixIcon: const Icon(Icons.mail_outline),
                                      validator: Validators.email,
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    AppTextField(
                                      label: 'Password',
                                      controller: _password,
                                      obscureText: _obscurePassword,
                                      textInputAction: TextInputAction.next,
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      validator: Validators.password,
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    AppTextField(
                                      label: 'Confirm Password',
                                      controller: _confirmPassword,
                                      obscureText: _obscureConfirm,
                                      textInputAction: TextInputAction.done,
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      validator: (v) => Validators.confirmPassword(v, _password.text),
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xl),
                                    AuthGradientButton(
                                      label: 'Create Account',
                                      loadingLabel: 'Creating Account…',
                                      isLoading: _isSubmitting,
                                      radius: 16,
                                      labelSize: 19,
                                      labelWeight: FontWeight.w600,
                                      onPressed: _submit,
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    Text.rich(
                                      TextSpan(
                                        style: TextStyle(fontSize: 13.5, height: 1.45, color: tokens.textSecondary),
                                        children: [
                                          const TextSpan(text: 'By creating an account you agree to the '),
                                          TextSpan(
                                            text: 'Terms of Service',
                                            style: linkStyle,
                                            recognizer: TapGestureRecognizer()..onTap = () => openLegalPage(LegalPage.terms),
                                          ),
                                          const TextSpan(text: ' and '),
                                          TextSpan(
                                            text: 'Privacy Policy',
                                            style: linkStyle,
                                            recognizer: TapGestureRecognizer()..onTap = () => openLegalPage(LegalPage.privacy),
                                          ),
                                          const TextSpan(text: '.'),
                                        ],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    Center(
                                      child: AuthFooterPrompt(
                                        prompt: 'Already have an account?',
                                        action: 'Log in',
                                        onTap: _goToLogin,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
