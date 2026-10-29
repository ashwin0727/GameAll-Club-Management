import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/payout_method.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import 'onboarding_scaffold.dart';
import '../profile/hub/payout_widgets.dart';
import '../../shared/widgets/smooth_switcher.dart';

/// The last onboarding step — "Payout details". The owner must add at least one
/// bank account or UPI ID before reaching the dashboard: it is where what the
/// facility collects is paid out. GameAll verifies each method by hand
/// afterwards (shown as a pending/verified badge), so this step only needs it to
/// be present. Mirrors the web `/onboarding/payments` step.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  bool _loading = true;
  String? _loadError;
  String? _facilityId;
  List<PayoutMethod> _methods = const [];
  bool _finishing = false;
  bool _busy = false;
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
      final methods = await ref.read(payoutRepositoryProvider).list(facility.id);
      if (!mounted) return;
      setState(() {
        _facilityId = facility.id;
        _methods = methods;
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

  Future<void> _reload() async {
    final id = _facilityId;
    if (id == null) return;
    final methods = await ref.read(payoutRepositoryProvider).list(id);
    if (mounted) setState(() => _methods = methods);
  }

  Future<void> _run(Future<void> Function() action, String fallback) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _reload();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stack) {
      debugPrint('Payout action failed: $e\n$stack');
      if (mounted) setState(() => _error = fallback);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    if (await showPayoutMethodSheet(context, facilityId: facilityId, dark: true)) await _reload();
  }

  Future<void> _finish() async {
    final facilityId = _facilityId;
    if (facilityId == null || _methods.isEmpty) return;
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      await ref.read(onboardingRepositoryProvider).completeSetup(facilityId);
      // Plans are bought on the web, not in the app: a club created here simply starts its free trial.
      await ref.read(planRepositoryProvider).startFreeTrial(facilityId);
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
        title: 'Payout Details',
        footer: const SizedBox.shrink(),
        children: [
          SizedBox(
            height: 320,
            child: SmoothSwitcher(child: _loading
                ? const LoadingView(message: 'Loading…')
                : ErrorView(message: _loadError!, onRetry: _load)),
          ),
        ],
      );
    }

    final tokens = context.tokens;
    return OnboardingScaffold(
      stepIndex: 4,
      title: 'Payout Details',
      subtitle: 'Tell us where to send the money you collect for bookings and '
          'other payments. You need this before you can use your dashboard.',
      onBack: () => context.go(AppRoutes.onboardingOperatingHours),
      footer: AuthGradientButton(
        label: 'Continue  ›',
        loadingLabel: 'Finishing…',
        isLoading: _finishing,
        onPressed: _methods.isEmpty || _busy ? null : _finish,
      ),
      children: [
        if (_error != null) ...[
          _ErrorText(_error!),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_methods.isEmpty)
          _EmptyCard(onAdd: _add)
        else ...[
          for (final m in _methods)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: PayoutMethodCard(
                method: m,
                busy: _busy,
                onMakePrimary: () => _run(
                  () => ref.read(payoutRepositoryProvider).setPrimary(m.id),
                  'Could not change the primary method.',
                ),
                onDelete: () => _run(
                  () => ref.read(payoutRepositoryProvider).delete(m.id),
                  'Could not remove this payment method.',
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another'),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: tokens.violet.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: tokens.violet.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, size: 20, color: tokens.violet),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'We verify every payout method by hand before sending money to '
                  'it — you’ll see a Verified badge once it’s done. Only you can '
                  'see these details.',
                  style: TextStyle(fontSize: 13, color: tokens.textPrimary, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: tokens.primary.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.account_balance_outlined, color: tokens.primary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Where should we send your payouts?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text('Add the bank account or UPI ID that receives what you collect.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tokens.textSecondary, height: 1.4)),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add payment method'),
          ),
        ],
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
      child: Text(message, style: TextStyle(color: context.tokens.destructive, fontSize: 13)),
    );
  }
}
