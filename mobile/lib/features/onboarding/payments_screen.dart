import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import 'onboarding_scaffold.dart';

/// Screen 5 of the redesigned onboarding — "Get paid online". The full
/// Razorpay Route linked-account flow is a separate future project; this
/// step presents the offer, opens the Razorpay dashboard, and can be
/// deferred without blocking completion.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  bool _loading = true;
  String? _loadError;
  String? _facilityId;
  bool _connected = false;
  bool _finishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        if (mounted) context.go(AppRoutes.onboardingFacility);
        return;
      }
      setState(() {
        _facilityId = facility.id;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      debugPrint('Payments step load failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'We couldn’t load this step. Please try again.';
      });
    }
  }

  Future<void> _connectRazorpay() async {
    final uri = Uri.parse('https://dashboard.razorpay.com/signin');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Opening the browser is best-effort — still let them mark it done.
    }
    setState(() => _connected = true);
  }

  Future<void> _finish() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      if (_connected) {
        await ref
            .read(facilityRepositoryProvider)
            .setPaymentsConnected(facilityId, true);
      }
      await ref.read(onboardingRepositoryProvider).completeSetup(facilityId);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.onboardingComplete);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e, stack) {
      debugPrint('Payments step finish failed: $e\n$stack');
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _loadError != null) {
      return OnboardingScaffold(
        stepIndex: 4,
        title: 'Get paid online',
        footer: const SizedBox.shrink(),
        children: [
          SizedBox(
            height: 320,
            child: _loading
                ? const LoadingView(message: 'Loading…')
                : ErrorView(message: _loadError!, onRetry: _load),
          ),
        ],
      );
    }

    return OnboardingScaffold(
      stepIndex: 4,
      title: 'Get paid online',
      subtitle: 'Connect Razorpay so guests can pay when they book. Cash and '
          'pay-at-venue bookings work without this.',
      onBack: () => context.go(AppRoutes.onboardingOperatingHours),
      onSkip: _finishing ? null : _finish,
      skipLabel: 'Later',
      footer: _connected
          ? AuthGradientButton(
              label: 'Continue  ›',
              loadingLabel: 'Finishing…',
              isLoading: _finishing,
              onPressed: _finish,
            )
          : _GhostButton(
              label: 'Do this later',
              loading: _finishing,
              onTap: _finish,
            ),
      children: [
        if (_error != null) ...[
          _ErrorText(_error!),
          const SizedBox(height: AppSpacing.md),
        ],
        _RazorpayCard(connected: _connected, onConnect: _connectRazorpay),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          "You'll need",
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: context.tokens.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _NeedRow(icon: Icons.account_balance_outlined, label: 'Bank account for payouts', tag: 'Required'),
        const _NeedRow(icon: Icons.badge_outlined, label: 'PAN and GSTIN', tag: 'Required'),
        const _NeedRow(icon: Icons.description_outlined, label: 'Cancellation policy', tag: 'Optional'),
        const SizedBox(height: AppSpacing.xl),
        const _InfoBanner(
          'Verification usually clears in a day. Until then you can still take '
          'cash and pay-at-venue bookings.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

class _RazorpayCard extends StatelessWidget {
  const _RazorpayCard({required this.connected, required this.onConnect});

  final bool connected;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: tokens.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.payments_outlined, color: tokens.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Razorpay',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        )),
                    const SizedBox(height: 2),
                    Text('UPI, cards, netbanking, wallets',
                        style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final line in const [
            'Guests pay when they book, not at the gate',
            'Refunds and settlements reconcile themselves',
            'Payouts to your bank in 2 working days',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check, size: 18, color: tokens.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(line,
                        style: TextStyle(
                            fontSize: 14, height: 1.35, color: tokens.textPrimary)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: connected ? null : onConnect,
              icon: Icon(connected ? Icons.check_circle : Icons.open_in_new, size: 18),
              label: Text(connected ? 'Razorpay opened' : 'Connect Razorpay'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedRow extends StatelessWidget {
  const _NeedRow({required this.icon, required this.label, required this.tag});

  final IconData icon;
  final String label;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 20, color: tokens.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 15, color: tokens.textPrimary)),
          ),
          Text(
            tag,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tag == 'Required' ? tokens.warning : tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.violet.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.violet.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: tokens.violet),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: tokens.textPrimary, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.loading, required this.onTap});

  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface1,
      shape: StadiumBorder(side: BorderSide(color: tokens.borderColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label,
                  style: TextStyle(color: tokens.textPrimary, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.tokens.destructive.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(message,
          style: TextStyle(color: context.tokens.destructive, fontSize: 13)),
    );
  }
}
