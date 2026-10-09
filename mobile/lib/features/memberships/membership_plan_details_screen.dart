import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/page_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../staff/staff_common.dart';
import 'member_detail_screen.dart';
import 'member_row.dart';
import 'manage_plan_slots_screen.dart';
import 'membership_plan_edit_sheet.dart';
import 'membership_slot_edit_sheet.dart';
import 'membership_plans_tab.dart';
import 'plan_presentation.dart';

/// Memberships → Plans → a plan. Everything the app knows about one plan — its price and length, the
/// benefits it lists, the session slots attached to it, and the members on it — with Edit Plan and
/// Manage Slots always within reach.
///
/// Pops `true` when anything changed (an edit, an activate / deactivate, a slot change) so the list
/// behind it refreshes.
class MembershipPlanDetailsScreen extends ConsumerStatefulWidget {
  const MembershipPlanDetailsScreen({
    super.key,
    required this.plan,
    required this.facilityId,
    required this.members,
    required this.batches,
  });

  final MembershipPlan plan;
  final String facilityId;

  /// The members currently on this plan (active and unpaid).
  final List<MembershipListRow> members;

  /// This plan's own session slots.
  final List<AssignableBatch> batches;

  @override
  ConsumerState<MembershipPlanDetailsScreen> createState() => _MembershipPlanDetailsScreenState();
}

class _MembershipPlanDetailsScreenState extends ConsumerState<MembershipPlanDetailsScreen> {
  static const _tabs = ['Overview', 'Benefits', 'Slots', 'Members'];
  static const _dayLetters = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  // Monday first, the way the week reads.
  static const _weekOrder = [1, 2, 3, 4, 5, 6, 0];

  late MembershipPlan _plan = widget.plan;
  late List<AssignableBatch> _batches = widget.batches;
  int _tab = 0;
  bool _changed = false;
  bool _busy = false;

  Future<void> _edit({PlanEditSection section = PlanEditSection.overview}) async {
    final saved = await showModalBottomSheet<MembershipPlan>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MembershipPlanEditSheet(plan: _plan, section: section),
    );
    if (saved != null && mounted) {
      setState(() {
        _plan = saved;
        _changed = true;
      });
    }
  }

  Future<void> _toggleActive() async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(membershipRepositoryProvider).updatePlan(_plan.id, isActive: !_plan.isActive);
      if (mounted) {
        setState(() {
          _plan = saved;
          _changed = true;
        });
      }
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageSlots() async {
    final changed = await Navigator.of(context).push<bool>(
      AppPageRoute(
        builder: (_) => ManagePlanSlotsScreen(plan: _plan, facilityId: widget.facilityId, batches: _batches, members: widget.members),
      ),
    );
    if (changed == true) {
      await _reloadSlots();
      if (mounted) setState(() => _changed = true);
    }
  }

  /// Slots may have been added, changed or removed — read them again.
  Future<void> _reloadSlots() async {
    try {
      final all = await ref.read(membershipRepositoryProvider).listAssignableBatches(widget.facilityId);
      if (mounted) setState(() => _batches = all.where((b) => b.planId == _plan.id).toList());
    } on AppException {
      // keep what is on screen; the list behind refreshes on return regardless
    }
  }

  Future<void> _editSlot(AssignableBatch b) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MembershipSlotEditSheet(batch: b, facilityId: widget.facilityId),
    );
    if (saved == true) {
      await _reloadSlots();
      if (mounted) setState(() => _changed = true);
    }
  }

  Future<void> _openMember(MembershipListRow row) async {
    final changed = await Navigator.of(context).push<bool>(
      AppPageRoute(builder: (_) => MemberDetailScreen(membershipId: row.membershipId)),
    );
    if (changed == true && mounted) setState(() => _changed = true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plan Details'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More',
              enabled: !_busy,
              onSelected: (v) {
                if (v == 'toggle') _toggleActive();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'toggle', child: Text(_plan.isActive ? 'Deactivate plan' : 'Activate plan')),
              ],
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            decoration: BoxDecoration(color: tokens.surface0, border: Border(top: BorderSide(color: tokens.borderColor))),
            child: Row(
              children: [
                // Overview edits the plan, Benefits edits its benefits; Slots edits per slot (each has its
                // own Edit) and Members has nothing to edit.
                if (_tab <= 1) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _edit(section: _tab == 0 ? PlanEditSection.overview : PlanEditSection.benefits),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(_tab == 0 ? 'Edit Plan' : 'Edit Benefits'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _manageSlots,
                    icon: const Icon(Icons.grid_view_rounded, size: 18),
                    label: const Text('Manage Slots'),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _hero(tokens),
            const SizedBox(height: AppSpacing.md),
            _header(tokens),
            const SizedBox(height: AppSpacing.md),
            _stats(tokens),
            const SizedBox(height: AppSpacing.md),
            _priceCard(tokens),
            const SizedBox(height: AppSpacing.md),
            SegmentedTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            if (_tab == 0) ..._overview(tokens),
            if (_tab == 1) ..._benefits(tokens),
            if (_tab == 2) ..._slots(tokens),
            if (_tab == 3) ..._members(tokens),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  // ── header ─────────────────────────────────────────────────────────────

  Widget _hero(AppColorTokens tokens) {
    final (label, color) = _plan.isActive ? ('Active', tokens.primary) : ('Inactive', tokens.destructive);
    return SizedBox(
      height: 150,
      child: Stack(
        children: [
          Positioned.fill(child: PlanImageTile(plan: _plan, size: 150, radius: AppRadius.lg)),
          Positioned(
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: tokens.surface1, borderRadius: BorderRadius.circular(999)),
              child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppColorTokens tokens) {
    final description = _plan.description?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_plan.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
            ),
            if (_plan.badgeText != null && _plan.badgeText!.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: tokens.violet.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                child: Text(_plan.badgeText!.trim(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tokens.violet)),
              ),
          ],
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(description, style: TextStyle(fontSize: 12.5, color: tokens.textSecondary)),
        ],
      ],
    );
  }

  Widget _stats(AppColorTokens tokens) {
    final sport = planSportLabel(_plan, _batches);
    Widget stat(IconData icon, Color color, String value, String label) => Expanded(
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 6),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
              Text(label, style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
            ],
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        stat(planIcon(_plan), tokens.primary, sport ?? '—', 'Sport'),
        stat(Icons.event_repeat_outlined, tokens.warning, '${_batches.length}', 'Total Slots'),
        stat(Icons.groups_outlined, tokens.electricBlue, '${widget.members.length}', 'Active Members'),
      ],
    );
  }

  Widget _priceCard(AppColorTokens tokens) {
    final perMonth = planMonthlyEquivalentInr(_plan.priceInr, _plan.durationDays);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.violet.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.violet.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: Formatters.currencyInr(_plan.priceInr),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: tokens.textPrimary),
              ),
              TextSpan(
                text: ' ${planPeriodLabel(_plan.durationDays)}',
                style: TextStyle(fontSize: 14, color: tokens.textSecondary),
              ),
            ]),
          ),
          if (perMonth != null) ...[
            const SizedBox(height: 2),
            Text('(${Formatters.currencyInr(perMonth)} / month)', style: TextStyle(fontSize: 12.5, color: tokens.textSecondary)),
          ],
        ],
      ),
    );
  }

  // ── tabs ───────────────────────────────────────────────────────────────

  Widget _kv(AppColorTokens tokens, IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: tokens.textSecondary),
            const SizedBox(width: AppSpacing.md),
            SizedBox(width: 118, child: Text(label, style: TextStyle(fontSize: 13, color: tokens.textSecondary))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  List<Widget> _overview(AppColorTokens tokens) {
    final p = _plan;
    final description = p.description?.trim();
    return [
      _kv(tokens, Icons.calendar_today_outlined, 'Duration', planDurationLabel(p.durationDays)),
      _kv(tokens, Icons.schedule_outlined, 'Validity', '${p.durationDays} Days'),
      _kv(tokens, Icons.autorenew_rounded, 'Auto Renewal', p.isRecurring ? 'Yes — renews each cycle' : 'No'),
      _kv(tokens, Icons.event_available_outlined, 'Created', Formatters.dateShort(p.createdAt.toLocal())),
      _kv(tokens, Icons.sell_outlined, 'Plan Type', p.isRecurring ? 'Recurring' : 'Time-based'),
      if (p.category != null && p.category!.trim().isNotEmpty) _kv(tokens, Icons.category_outlined, 'Category', p.category!.trim()),
      if (p.joiningFeeInr != null) _kv(tokens, Icons.payments_outlined, 'Joining Fee', Formatters.currencyInr(p.joiningFeeInr!)),
      if (p.securityDepositInr != null)
        _kv(tokens, Icons.lock_outline_rounded, 'Security Deposit', Formatters.currencyInr(p.securityDepositInr!)),
      if (description != null && description.isNotEmpty) _kv(tokens, Icons.notes_rounded, 'Description', description),
      if (p.features.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Text('Highlights', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (final f in p.features.take(4)) _featureChip(tokens, f)],
        ),
      ],
    ];
  }

  Widget _featureChip(AppColorTokens tokens, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface1,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tokens.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 16, color: tokens.primary),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  List<Widget> _benefits(AppColorTokens tokens) {
    if (_plan.features.isEmpty) {
      return [_emptyNote(tokens, 'No benefits are listed for this plan.')];
    }
    return [
      Text('Plan Benefits', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
      const SizedBox(height: 2),
      Text('Features and benefits included in this plan.', style: TextStyle(fontSize: 12.5, color: tokens.textSecondary)),
      const SizedBox(height: AppSpacing.md),
      for (final f in _plan.features)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: tokens.borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: tokens.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(Icons.check_rounded, size: 20, color: tokens.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(f, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _slots(AppColorTokens tokens) {
    if (_batches.isEmpty) {
      return [_emptyNote(tokens, 'No session slots are attached to this plan yet. Use Manage Slots to add one.')];
    }
    final usedDays = {for (final b in _batches) ...b.daysOfWeek};
    final starts = _batches.map((b) => b.startTime).toList()..sort();
    final ends = _batches.map((b) => b.endTime).toList()..sort();
    final courts = {for (final b in _batches) b.courtName}.where((c) => c.isNotEmpty).toList();
    return [
      Text('Included Slots', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
      const SizedBox(height: 2),
      Text('Time slots available for this plan.', style: TextStyle(fontSize: 12.5, color: tokens.textSecondary)),
      const SizedBox(height: AppSpacing.md),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final d in _weekOrder)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: usedDays.contains(d) ? tokens.primary.withValues(alpha: 0.16) : tokens.surface2,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(_dayLetters[d],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: usedDays.contains(d) ? tokens.primary : tokens.textSecondary,
                  )),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _kv(tokens, Icons.schedule_outlined, 'Available Hours', '${Formatters.time12h(starts.first)} - ${Formatters.time12h(ends.last)}'),
      _kv(tokens, Icons.grid_view_rounded, 'Applicable Courts', courts.isEmpty ? '—' : courts.join(', ')),
      const SizedBox(height: AppSpacing.md),
      for (final b in _batches)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: tokens.borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${([...b.daysOfWeek]..sort()).map((d) => _dayLetters[d % 7]).join(', ')} · '
                        '${Formatters.time12h(b.startTime)}–${Formatters.time12h(b.endTime)}',
                        style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                      ),
                      Text('${b.courtName} · ${b.sportName}', style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${b.enrolledCount}/${b.capacity}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: b.enrolledCount >= b.capacity ? tokens.warning : tokens.primary,
                        )),
                    TextButton.icon(
                      onPressed: () => _editSlot(b),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _members(AppColorTokens tokens) {
    if (widget.members.isEmpty) {
      return [_emptyNote(tokens, 'No members are on this plan yet.')];
    }
    return [
      for (final m in widget.members)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: MemberRow(row: m, onTap: () => _openMember(m)),
        ),
    ];
  }

  Widget _emptyNote(AppColorTokens tokens, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary))),
      );
}
