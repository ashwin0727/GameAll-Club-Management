import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../membership_sessions/membership_batches_sheet.dart';
import '../staff/staff_common.dart';
import 'member_row.dart';
import 'membership_slot_edit_sheet.dart';
import 'plan_presentation.dart';
import 'plan_wizard.dart' show planDayAbbr;

/// Manage Slots — a plan's slots and how many members each can hold. Slot Configuration shows each
/// slot with its capacity and an Edit button (change the number, then Save and it applies at once,
/// for every member on the slot); Usage & Members shows how full each slot is and who is on the plan.
///
/// Pops `true` when anything changed so the plan and its list refresh.
class ManagePlanSlotsScreen extends ConsumerStatefulWidget {
  const ManagePlanSlotsScreen({
    super.key,
    required this.plan,
    required this.facilityId,
    required this.batches,
    required this.members,
  });

  final MembershipPlan plan;
  final String facilityId;
  final List<AssignableBatch> batches;
  final List<MembershipListRow> members;

  @override
  ConsumerState<ManagePlanSlotsScreen> createState() => _ManagePlanSlotsScreenState();
}

class _ManagePlanSlotsScreenState extends ConsumerState<ManagePlanSlotsScreen> {
  static const _tabs = ['Slot Configuration', 'Usage & Members'];
  static const _weekOrder = [1, 2, 3, 4, 5, 6, 0];

  late List<AssignableBatch> _batches = widget.batches;
  int _tab = 0;
  bool _changed = false;

  Future<void> _reload() async {
    try {
      final all = await ref.read(membershipRepositoryProvider).listAssignableBatches(widget.facilityId);
      if (mounted) setState(() => _batches = all.where((b) => b.planId == widget.plan.id).toList());
    } on AppException {
      // keep what is on screen
    }
  }

  Future<void> _editCapacity(AssignableBatch b) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MembershipSlotEditSheet(batch: b, facilityId: widget.facilityId, capacityOnly: true),
    );
    if (saved == true) {
      _changed = true;
      await _reload();
    }
  }

  Future<void> _addOrRemove() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MembershipBatchesSheet(facilityId: widget.facilityId),
    );
    _changed = true;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final plan = widget.plan;
    final recurring = plan.planType == 'RECURRING';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Manage Slots')),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: tokens.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(planIcon(plan), color: tokens.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      _pill(tokens, plan.isActive ? 'Active' : 'Inactive', plan.isActive ? tokens.primary : tokens.destructive),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: _infoCard(tokens, Icons.event_available_outlined, 'Validity Period', planDurationLabel(plan.durationDays))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _infoCard(
                    tokens,
                    Icons.autorenew,
                    'Auto Renewal',
                    recurring ? 'Enabled' : 'Disabled',
                    valueColor: recurring ? tokens.primary : tokens.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            if (_tab == 0) ..._configuration(tokens),
            if (_tab == 1) ..._usage(tokens),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton.icon(onPressed: _addOrRemove, icon: const Icon(Icons.tune, size: 18), label: const Text('Add or remove slots')),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _pill(AppColorTokens tokens, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _infoCard(AppColorTokens tokens, IconData icon, String label, String value, {Color? valueColor}) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surface1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tokens.borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tokens.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11.5, color: tokens.textSecondary)),
                  Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: valueColor)),
                ],
              ),
            ),
          ],
        ),
      );

  String _days(List<int> days) => _weekOrder.where(days.contains).map((d) => planDayAbbr[d]).join(', ');

  List<Widget> _configuration(AppColorTokens tokens) {
    if (_batches.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(child: Text('No slots on this plan yet. Use "Add or remove slots".', style: TextStyle(color: tokens.textSecondary))),
        ),
      ];
    }
    final courts = {for (final b in _batches) b.courtName}.where((c) => c.isNotEmpty).toList();
    final usedDays = {for (final b in _batches) ...b.daysOfWeek}.toList();
    final starts = _batches.map((b) => b.startTime).toList()..sort();
    final ends = _batches.map((b) => b.endTime).toList()..sort();
    return [
      const Text('Slots', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text("How many members each of this plan's slots can hold.", style: TextStyle(fontSize: 12.5, color: tokens.textSecondary)),
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
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: tokens.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(Icons.event_note_outlined, color: tokens.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${b.courtName} · ${Formatters.time12h(b.startTime)} - ${Formatters.time12h(b.endTime)}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text(_days(b.daysOfWeek), style: TextStyle(fontSize: 11.5, color: tokens.textSecondary)),
                      const SizedBox(height: 2),
                      Text('Capacity', style: TextStyle(fontSize: 11.5, color: tokens.textSecondary)),
                      Text('${b.capacity}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                OutlinedButton(onPressed: () => _editCapacity(b), child: const Text('Edit')),
              ],
            ),
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
      const Text('Slot Rules', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: AppSpacing.sm),
      Container(
        decoration: BoxDecoration(border: Border.all(color: tokens.borderColor), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          children: [
            _rule(tokens, 'Slot Validity', 'Within the plan validity period', first: true),
            _rule(tokens, 'Applicable Days', _days(usedDays)),
            _rule(tokens, 'Available Hours', '${Formatters.time12h(starts.first)} - ${Formatters.time12h(ends.last)}'),
            _rule(tokens, 'Applicable Courts', courts.isEmpty ? '—' : courts.join(', ')),
            _rule(tokens, 'Number of Slots', '${_batches.length}'),
          ],
        ),
      ),
    ];
  }

  Widget _rule(AppColorTokens tokens, String k, String v, {bool first = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: tokens.borderColor))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: Text(k, style: TextStyle(fontSize: 12.5, color: tokens.textSecondary))),
            Expanded(flex: 5, child: Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  List<Widget> _usage(AppColorTokens tokens) {
    return [
      const Text('Slot Usage', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: AppSpacing.sm),
      if (_batches.isEmpty)
        Text('No slots on this plan yet.', style: TextStyle(color: tokens.textSecondary))
      else
        for (final b in _batches)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${b.courtName} · ${Formatters.time12h(b.startTime)} - ${Formatters.time12h(b.endTime)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Text('${b.enrolledCount} / ${b.capacity}', style: TextStyle(fontWeight: FontWeight.w800, color: tokens.primary)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: b.capacity <= 0 ? 0 : (b.enrolledCount / b.capacity).clamp(0, 1).toDouble(),
                    minHeight: 8,
                    backgroundColor: tokens.surface2,
                  ),
                ),
              ],
            ),
          ),
      const SizedBox(height: AppSpacing.sm),
      const Text('Members', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: AppSpacing.sm),
      if (widget.members.isEmpty)
        Text('No members are on this plan yet.', style: TextStyle(color: tokens.textSecondary))
      else
        for (final m in widget.members)
          Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: MemberRow(row: m, onTap: () {})),
    ];
  }
}
