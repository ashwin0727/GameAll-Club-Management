import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../shared/widgets/picker_chip.dart';
import 'plan_presentation.dart';

/// Memberships → Plans: a searchable, filterable list of the facility's plans. Each row is a small
/// picture tile, the plan's name and sport, its price and period, how many members and slots it has,
/// whether it is active, and an arrow into its details.
class MembershipPlansTab extends StatefulWidget {
  const MembershipPlansTab({
    super.key,
    required this.plans,
    required this.batches,
    required this.memberCount,
    required this.onOpen,
    required this.onCreate,
  });

  final List<MembershipPlan> plans;

  /// Every session slot at the facility — a plan's own are the ones whose `planId` matches.
  final List<AssignableBatch> batches;
  final int Function(MembershipPlan plan) memberCount;
  final ValueChanged<MembershipPlan> onOpen;
  final VoidCallback onCreate;

  @override
  State<MembershipPlansTab> createState() => _MembershipPlansTabState();
}

class _MembershipPlansTabState extends State<MembershipPlansTab> {
  String _query = '';
  PlanFilter _filter = PlanFilter.all;
  PlanSort _sort = PlanSort.priceLow;

  List<AssignableBatch> _batchesOf(MembershipPlan plan) => widget.batches.where((b) => b.planId == plan.id).toList();

  Future<void> _pickSort() async {
    final picked = await showPickerSheet<PlanSort>(
      context: context,
      selected: _sort,
      options: [for (final s in PlanSort.values) (value: s, label: s.label)],
    );
    if (picked != null) setState(() => _sort = picked);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final counts = planFilterCounts(widget.plans);
    final visible = sortPlans(
      filterPlans(widget.plans, filter: _filter, query: _query),
      _sort,
      memberCount: widget.memberCount,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search plans by name or sport…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.tune_rounded, size: 20),
              tooltip: 'Sort plans',
              onPressed: _pickSort,
            ),
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (filter, label, n) in [
                (PlanFilter.all, 'All', counts.all),
                (PlanFilter.active, 'Active', counts.active),
                (PlanFilter.inactive, 'Inactive', counts.inactive),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text('$label ($n)'),
                    selected: _filter == filter,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (widget.plans.isEmpty)
          _EmptyPlans(onCreate: widget.onCreate)
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(
              child: Text('No plans match.', style: TextStyle(color: tokens.textSecondary)),
            ),
          )
        else
          for (final plan in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _PlanRow(
                plan: plan,
                members: widget.memberCount(plan),
                batches: _batchesOf(plan),
                onTap: () => widget.onOpen(plan),
              ),
            ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.members, required this.batches, required this.onTap});

  final MembershipPlan plan;
  final int members;
  final List<AssignableBatch> batches;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sport = planSportLabel(plan, batches);
    final (statusLabel, statusColor) = plan.isActive ? ('Active', tokens.primary) : ('Inactive', tokens.destructive);
    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlanImageTile(plan: plan, size: 64),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(plan.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                        ),
                      ],
                    ),
                    if (sport != null) ...[
                      const SizedBox(height: 3),
                      Text(sport,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: tokens.textSecondary)),
                    ],
                    const SizedBox(height: 4),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                        text: Formatters.currencyInr(plan.priceInr),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                      ),
                      TextSpan(
                        text: ' ${planPeriodLabel(plan.durationDays)}',
                        style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                      ),
                    ])),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(Icons.groups_outlined, size: 15, color: tokens.textSecondary),
                        const SizedBox(width: 4),
                        Text('$members Member${members == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.textSecondary)),
                        const SizedBox(width: AppSpacing.md),
                        Icon(Icons.event_repeat_outlined, size: 15, color: tokens.textSecondary),
                        const SizedBox(width: 4),
                        Text('${batches.length} Slot${batches.length == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 18, left: 2),
                child: Icon(Icons.chevron_right, size: 20, color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The plan's picture. Plans don't store a photo, so this is a tinted tile carrying a sport icon —
/// the slot a real image would fill.
class PlanImageTile extends StatelessWidget {
  const PlanImageTile({super.key, required this.plan, this.size = 64, this.radius});

  final MembershipPlan plan;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tint = plan.isActive ? tokens.violet : tokens.textSecondary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? AppRadius.md),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: 0.28), tint.withValues(alpha: 0.10)],
        ),
      ),
      child: Icon(planIcon(plan), size: size * 0.45, color: tint),
    );
  }
}

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        children: [
          Icon(Icons.card_membership_outlined, size: 34, color: tokens.textSecondary),
          const SizedBox(height: AppSpacing.sm),
          Text('No plans yet', style: TextStyle(color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onCreate,
            style: FilledButton.styleFrom(backgroundColor: tokens.violet),
            child: const Text('Create a plan'),
          ),
        ],
      ),
    );
  }
}
