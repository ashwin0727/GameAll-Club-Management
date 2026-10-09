import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/routing/page_transitions.dart';
import '../../data/models/membership.dart';
import '../../shared/widgets/app_card.dart';
import 'add_member_wizard.dart' show addMemberPlanFeatures;
import 'membership_plan_details_screen.dart';
import 'membership_plan_wizard_screen.dart';
import 'plan_presentation.dart';
import 'plan_wizard.dart' show planBillingIntervalLabel;

/// What the plan costs a new member up front: its price plus any joining fee and security deposit.
int planTotalAmountInr(MembershipPlan plan) => plan.priceInr + (plan.joiningFeeInr ?? 0) + (plan.securityDepositInr ?? 0);

/// "Regular Membership" → "Regular Plan"; any other category is shown as it is.
String? planCategoryLabel(String? category) {
  final c = category?.trim();
  if (c == null || c.isEmpty) return null;
  return c.replaceFirst(RegExp(r'\s+Membership$', caseSensitive: false), ' Plan');
}

/// "Regular Plan • Badminton" — whichever parts exist.
String planSubtitle(String? category, String? sport) =>
    [planCategoryLabel(category), if (sport != null && sport.trim().isNotEmpty) sport.trim()].whereType<String>().join(' • ');

String featureCountLabel(int count) => '$count ${count == 1 ? 'feature' : 'features'}';

/// "15 Sep 2026, 10:30 AM".
String planCreatedOn(DateTime t) {
  final local = t.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final mm = local.minute.toString().padLeft(2, '0');
  return '${Formatters.dateShort(local)}, $h:$mm ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// Shown right after a plan is saved — the plan at a glance, then three ways on: open the plan,
/// start another, or go back to the plan list. Mirrors the web's Plan Created screen.
class PlanCreatedScreen extends StatelessWidget {
  const PlanCreatedScreen({
    super.key,
    required this.plan,
    required this.facilityId,
    required this.sportLabel,
    this.batches = const [],
  });

  final MembershipPlan plan;
  final String facilityId;
  final String? sportLabel;

  /// The plan's own session slots, for the plan page's Slots tab.
  final List<AssignableBatch> batches;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final features = addMemberPlanFeatures(plan, planBillingIntervalLabel(plan.durationDays));
    final rows = <(String, String)>[
      ('Duration', planDurationLabel(plan.durationDays)),
      ('Price', Formatters.currencyInr(plan.priceInr)),
      ('Total Amount', Formatters.currencyInr(planTotalAmountInr(plan))),
      ('Benefits', featureCountLabel(features.length)),
      ('Created On', planCreatedOn(plan.createdAt)),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: tokens.primary.withValues(alpha: 0.10)),
                  alignment: Alignment.center,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: tokens.primary.withValues(alpha: 0.20)),
                    alignment: Alignment.center,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: tokens.primary),
                      child: Icon(Icons.check, size: 34, color: tokens.onPrimary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Plan Created Successfully!', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Your membership plan has been created and is now active.',
                textAlign: TextAlign.center,
                style: AppTypography.secondary(context),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(color: tokens.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.md)),
                          child: Icon(planIcon(plan), size: 30, color: tokens.primary),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(plan.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              Text(planSubtitle(plan.category, sportLabel), style: AppTypography.caption(context)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                                decoration: BoxDecoration(color: tokens.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                                child: Text('Active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.primary)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final r in rows) ...[
                      Divider(height: 1, color: tokens.borderColor),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(r.$1, style: AppTypography.secondary(context)),
                            const SizedBox(width: AppSpacing.md),
                            Flexible(child: Text(r.$2, textAlign: TextAlign.end, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => _viewPlan(context),
                child: const Text('View Plan'),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.of(context).pushReplacement(AppPageRoute(builder: (_) => const MembershipPlanWizardScreen())),
                child: const Text('Create Another Plan'),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Go to Membership Plans'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The plan's page; coming back from it lands on the plan list.
  Future<void> _viewPlan(BuildContext context) async {
    final navigator = Navigator.of(context);
    await navigator.pushReplacement(
      AppPageRoute<bool>(
        builder: (_) => MembershipPlanDetailsScreen(plan: plan, facilityId: facilityId, members: const [], batches: batches),
      ),
    );
  }
}
