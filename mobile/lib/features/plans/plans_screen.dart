import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/plan.dart';
import '../../data/repositories/repository_providers.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import '../onboarding/onboarding_scaffold.dart';
import '../profile/hub/hub_providers.dart';
import '../profile/hub/hub_widgets.dart' show hubMoney;
import '../../shared/widgets/states.dart';

final planOptionsProvider = FutureProvider.autoDispose<List<PlanOption>>((ref) {
  return ref.watch(planRepositoryProvider).listPlans();
});

/// Choose Basic or Advanced. Shared by the onboarding step after Payout ([onboarding] true) and the Plans page reached from
/// Profile. Picking a plan opens Razorpay to authorise Auto Pay; the first plan is free until its first charge date.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key, this.onboarding = false});

  final bool onboarding;

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  bool _yearly = true;
  String? _busyCode;
  String? _error;

  void _done() {
    if (!mounted) return;
    if (widget.onboarding) {
      context.go(AppRoutes.onboardingComplete);
    } else {
      ref.invalidate(hubPlanProvider);
      context.pop();
    }
  }

  Future<void> _choose(PlanOption plan) async {
    final session = ref.read(sessionControllerProvider);
    final facilityId = session.facility?.id;
    if (facilityId == null || _busyCode != null) return;
    setState(() {
      _busyCode = plan.code;
      _error = null;
    });
    try {
      final repo = ref.read(planRepositoryProvider);
      final info = await repo.startPlan(facilityId, plan.code, _yearly ? 'year' : 'month');
      final paid = await _checkout(info);
      if (paid == null) return; // closed Razorpay without paying — nothing happened
      await repo.confirmPlan(subscriptionId: info.subscriptionId, paymentId: paid.$1, signature: paid.$2);
      await ref.read(sessionControllerProvider.notifier).refresh();
      _done();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busyCode = null);
    }
  }

  /// Opens Razorpay Checkout for the subscription. Returns (paymentId, signature), or null when the owner backs out.
  Future<(String, String)?> _checkout(PlanCheckoutInfo info) async {
    final completer = Completer<(String, String)?>();
    final razorpay = Razorpay();
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      if (!completer.isCompleted) completer.complete((r.paymentId ?? '', r.signature ?? ''));
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      if (completer.isCompleted) return;
      if (r.code == Razorpay.PAYMENT_CANCELLED) {
        completer.complete(null);
      } else {
        completer.completeError(AppException(AppErrorCode.databaseError, r.message ?? 'The payment did not go through.'));
      }
    });
    razorpay.open({
      'key': info.keyId,
      'subscription_id': info.subscriptionId,
      'name': 'GameAll',
      'description': '${info.planName} plan · ${info.interval == 'year' ? 'yearly' : 'monthly'}',
    });
    try {
      return await completer.future;
    } finally {
      razorpay.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(planOptionsProvider);
    final current = ref.watch(sessionControllerProvider.select((s) => s.plan));

    final body = options.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: LoadingView()),
      error: (e, _) => ErrorView(message: "We couldn't load the plans.", onRetry: () => ref.invalidate(planOptionsProvider)),
      data: (plans) => _Body(
        plans: plans,
        current: current,
        yearly: _yearly,
        busyCode: _busyCode,
        error: _error,
        onToggle: (y) => setState(() => _yearly = y),
        onChoose: _choose,
      ),
    );

    if (widget.onboarding) {
      return OnboardingScaffold(
        stepIndex: 5,
        stepCount: 6,
        title: 'Choose Your Plan',
        subtitle: 'Try it free for 90 days. You authorise Auto Pay now and are charged only when the trial ends.',
        onBack: () => context.go(AppRoutes.onboardingPayments),
        footer: AuthGradientButton(label: 'Decide later  ›', onPressed: _busyCode == null ? _done : null),
        children: [body],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Plans')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: [body])),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.plans,
    required this.current,
    required this.yearly,
    required this.busyCode,
    required this.error,
    required this.onToggle,
    required this.onChoose,
  });

  final List<PlanOption> plans;
  final PlanSnapshot? current;
  final bool yearly;
  final String? busyCode;
  final String? error;
  final ValueChanged<bool> onToggle;
  final ValueChanged<PlanOption> onChoose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: t.destructive.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Text(error!, style: TextStyle(color: t.destructive, fontSize: 13)),
          ),
        Center(
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Monthly')),
              ButtonSegment(value: true, label: Text('Yearly · save 16%')),
            ],
            selected: {yearly},
            onSelectionChanged: (s) => onToggle(s.first),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final p in plans) ...[
          _PlanTile(
            plan: p,
            yearly: yearly,
            current: current,
            busy: busyCode == p.code,
            disabled: busyCode != null,
            onChoose: () => onChoose(p),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text(
          'You authorise Auto Pay now and pay nothing for the first ${plans.isEmpty ? 90 : plans.first.trialDays} days. After that your plan is '
          'charged automatically, monthly or yearly, until you cancel.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: t.textSecondary, height: 1.4),
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.yearly,
    required this.current,
    required this.busy,
    required this.disabled,
    required this.onChoose,
  });

  final PlanOption plan;
  final bool yearly;
  final PlanSnapshot? current;
  final bool busy;
  final bool disabled;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isCurrent = current?.planCode == plan.code && current?.interval == (yearly ? 'year' : 'month');
    final label = isCurrent
        ? 'Current plan'
        : current != null
            ? 'Switch to ${plan.name}'
            : plan.trialDays > 0
                ? 'Start ${plan.trialDays}-day free trial'
                : 'Choose plan';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: plan.isPopular ? t.primary : t.borderColor, width: plan.isPopular ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.textPrimary))),
              if (plan.isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text('Most popular', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.onPrimary)),
                ),
            ],
          ),
          if (plan.description != null) ...[
            const SizedBox(height: 4),
            Text(plan.description!, style: TextStyle(fontSize: 13, color: t.textSecondary, height: 1.35)),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(hubMoney(plan.priceFor(yearly)), style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: t.textPrimary)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('/ ${yearly ? 'year' : 'month'}', style: TextStyle(fontSize: 13, color: t.textSecondary)),
              ),
            ],
          ),
          if (yearly && plan.yearlySavingMinor > 0)
            Text('Save ${hubMoney(plan.yearlySavingMinor)} a year vs monthly', style: TextStyle(fontSize: 12, color: t.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          for (final f in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 18, color: t.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(f, style: TextStyle(fontSize: 13.5, color: t.textPrimary, height: 1.3))),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isCurrent || disabled ? null : onChoose,
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(label),
            ),
          ),
        ],
      ),
    );
  }
}
