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
import 'session_controller.dart';
import 'welcome_screen.dart' show introBackground;

/// Welcome to GameAll: the login page. The wordmark, a short greeting, email and password, and at the bottom the facility picture.
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
    // The picture gives way to the keyboard so the form always has room.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: introBackground,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                // Centred in the space above the picture; scrolls when the screen is short or the keyboard is up.
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                            child: Theme(
                              data: authFieldsTheme(context),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Center(child: Image.asset('assets/images/gameall_logo_light.png', height: 44)),
                                    const SizedBox(height: 34),
                                    const Text(
                                      'Welcome to GameAll',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF171717)),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      'Login to manage your bookings, memberships, coaching, and more.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 16, height: 1.4, color: tokens.textSecondary),
                                    ),
                                    const SizedBox(height: 32),
                                    if (_errorMessage != null) ...[
                                      Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.destructive)),
                                      const SizedBox(height: AppSpacing.md),
                                    ],
                                    AppTextField(
                                      label: 'Email Address',
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      prefixIcon: const Icon(Icons.mail_outline),
                                      validator: Validators.email,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    AppTextField(
                                      label: 'Password',
                                      controller: _password,
                                      obscureText: _obscurePassword,
                                      textInputAction: TextInputAction.done,
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      validator: (v) => (v == null || v.isEmpty) ? 'Password is required.' : null,
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        key: const ValueKey('sign-in-forgot'),
                                        onPressed: () => context.push(AppRoutes.forgotPassword),
                                        style: TextButton.styleFrom(
                                          foregroundColor: tokens.primary,
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text('Forgot Password?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    AuthGradientButton(
                                      label: 'Login',
                                      loadingLabel: 'Signing In…',
                                      isLoading: _isSubmitting,
                                      radius: 16,
                                      labelSize: 19,
                                      labelWeight: FontWeight.w600,
                                      onPressed: _submit,
                                    ),
                                    const SizedBox(height: 26),
                                    Center(
                                      child: AuthFooterPrompt(
                                        prompt: 'Don’t have an account?',
                                        action: 'Create Account',
                                        onTap: () => context.push(AppRoutes.createAccount),
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
              if (!keyboardOpen) const _FacilityPicture(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sports-facility picture along the bottom of the login page, full width. Its top edge fades into the page so there is no hard
/// line between the form and the picture.
class _FacilityPicture extends StatelessWidget {
  const _FacilityPicture();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0xFF000000)],
        stops: [0.0, 0.2],
      ).createShader(rect),
      child: Image.asset(
        'assets/images/login_facility.png',
        width: double.infinity,
        fit: BoxFit.fitWidth,
        alignment: Alignment.bottomCenter,
      ),
    );
  }
}
