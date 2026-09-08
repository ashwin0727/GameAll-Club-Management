import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_text_field.dart';
import 'auth_widgets.dart';

class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms = false;
  bool _showTermsError = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Drives the live password-strength meter.
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!_agreedToTerms) setState(() => _showTermsError = true);
    if (!formValid || !_agreedToTerms) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).register(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      // Stays in the submitting state on success — see sign_in_screen: the
      // button must not return to idle while this screen is still on top.
      context.go(
        '${AppRoutes.emailVerification}?email=${Uri.encodeQueryComponent(_email.text.trim())}',
      );
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      body: AuthGradientBackground(
        child: SafeArea(
        child: ResponsivePage(
          scrollable: false,
          child: Form(
            key: _formKey,
            child: AuthLayout(
              top: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton.filledTonal(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go(AppRoutes.signIn),
                    icon: const Icon(Icons.chevron_left),
                    style: IconButton.styleFrom(
                      backgroundColor: tokens.surface2,
                      foregroundColor: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Create your\nclub account',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'One owner account per facility. You can invite staff '
                  'after setup.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: const TextStyle(color: AppColors.destructive)),
                  const SizedBox(height: AppSpacing.md),
                ],
                AppTextField(
                  label: 'Your name',
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  prefixIcon: const Icon(Icons.person_outline),
                  validator: (v) => Validators.name(v),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Work email',
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
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                PasswordStrengthMeter(password: _password.text),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Confirm password',
                  controller: _confirmPassword,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  prefixIcon: const Icon(Icons.lock_outline),
                  validator: (v) => Validators.confirmPassword(v, _password.text),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _TermsCheckbox(
                  value: _agreedToTerms,
                  showError: _showTermsError,
                  onChanged: (v) => setState(() {
                    _agreedToTerms = v;
                    if (v) _showTermsError = false;
                  }),
                ),
              ],
              bottom: [
                AuthGradientButton(
                  label: 'Create account',
                  loadingLabel: 'Creating account…',
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpacing.lg),
                const AuthOrDivider(),
                const SizedBox(height: AppSpacing.lg),
                AuthOutlineButton(
                  label: 'Sign up with mobile number',
                  icon: Icons.smartphone_outlined,
                  onPressed: () => showComingSoon(context, 'Mobile sign-up'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: AuthFooterPrompt(
                    prompt: 'Already have an account?',
                    action: 'Log in',
                    onTap: () => context.go(AppRoutes.signIn),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({
    required this.value,
    required this.showError,
    required this.onChanged,
  });

  final bool value;
  final bool showError;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final linkStyle = TextStyle(color: tokens.primary, fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(color: tokens.textSecondary),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(text: 'terms of service', style: linkStyle),
                      const TextSpan(text: ' and '),
                      TextSpan(text: 'privacy policy', style: linkStyle),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (showError) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Please accept the terms of service to continue.',
            style: TextStyle(color: tokens.destructive, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
