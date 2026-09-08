import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_text_field.dart';
import 'auth_widgets.dart';
import 'session_controller.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _keepSignedIn = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).login(
        email: _email.text.trim(),
        password: _password.text,
      );
      await ref.read(sessionControllerProvider.notifier).refresh();
      // Deliberately stay in the submitting state on success. The redirect
      // that replaces this screen is driven by the session change and lands
      // a frame or more later; clearing the flag here put an idle-looking
      // button back under the user's finger while they were still staring
      // at the sign-in form, which reads as "nothing happened" and invites
      // a second tap. The spinner now runs until the screen goes away.
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isSubmitting = false;
      });
    } catch (e, stack) {
      debugPrint('Sign-in failed: $e\n$stack');
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
                const SizedBox(height: AppSpacing.sm),
                const AuthBrandMark(),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Log in',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Use the email your club account was created with.',
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
                  label: 'Email',
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
                  textInputAction: TextInputAction.done,
                  prefixIcon: const Icon(Icons.lock_outline),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Password is required.' : null,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _keepSignedIn,
                        onChanged: (v) => setState(() => _keepSignedIn = v ?? false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text('Keep me signed in', style: TextStyle(color: tokens.textSecondary)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.push(AppRoutes.forgotPassword),
                      child: Text(
                        'Forgot?',
                        style: TextStyle(color: tokens.primary, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
              bottom: [
                AuthGradientButton(
                  label: 'Log in',
                  loadingLabel: 'Signing in…',
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpacing.lg),
                const AuthOrDivider(),
                const SizedBox(height: AppSpacing.lg),
                AuthOutlineButton(
                  label: 'Log in with mobile OTP',
                  icon: Icons.smartphone_outlined,
                  onPressed: () => showComingSoon(context, 'Mobile OTP login'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: AuthFooterPrompt(
                    prompt: 'New here?',
                    action: 'Create an account',
                    onTap: () => context.push(AppRoutes.createAccount),
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
