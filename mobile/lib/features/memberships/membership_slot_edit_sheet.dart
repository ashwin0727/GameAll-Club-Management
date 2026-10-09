import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import 'duplicate_guards.dart';
import 'plan_slot_edit.dart';
import 'plan_wizard.dart' show planDayAbbr;

/// Edit one slot of a plan. With [capacityOnly] (Manage Slots) only the slot capacity is changed;
/// otherwise (the plan's Slots tab) the court, days and hours can change too. Saving updates the
/// slot itself, so every member on it sees the change. Pops `true` when saved.
class MembershipSlotEditSheet extends ConsumerStatefulWidget {
  const MembershipSlotEditSheet({super.key, required this.batch, required this.facilityId, this.capacityOnly = false});

  final AssignableBatch batch;
  final String facilityId;
  final bool capacityOnly;

  @override
  ConsumerState<MembershipSlotEditSheet> createState() => _MembershipSlotEditSheetState();
}

class _MembershipSlotEditSheetState extends ConsumerState<MembershipSlotEditSheet> {
  static const _weekOrder = [1, 2, 3, 4, 5, 6, 0];

  late final _capacity = TextEditingController(text: '${widget.batch.capacity}');
  late String _courtId = widget.batch.courtId;
  late Set<int> _days = {...widget.batch.daysOfWeek};
  late String _start = clockHm(widget.batch.startTime);
  late String _end = clockHm(widget.batch.endTime);

  /// Courts of the slot's own sport — the database only lets a slot move between those.
  List<({String id, String name})> _courts = const [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.capacityOnly) WidgetsBinding.instance.addPostFrameCallback((_) => _loadCourts());
  }

  @override
  void dispose() {
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _loadCourts() async {
    try {
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(widget.facilityId);
      if (!mounted) return;
      setState(() {
        _courts = [
          for (final a in areas)
            if (a.facilitySportId == widget.batch.facilitySportId && !a.archived && (a.status == 'ACTIVE' || a.id == widget.batch.courtId))
              (id: a.id, name: a.name),
        ];
      });
    } on AppException catch (_) {
      // Without the list the court simply stays as it is.
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final parts = (start ? _start : _end).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 7, minute: int.tryParse(parts[1]) ?? 0),
    );
    if (picked == null) return;
    final text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => start ? _start = text : _end = text);
  }

  Future<void> _save() async {
    final capacity = int.tryParse(_capacity.text.trim());
    final error = validateSlotEdit(
      days: _days.toList(),
      startTime: _start,
      endTime: _end,
      capacity: capacity,
      enrolled: widget.batch.enrolledCount,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!widget.capacityOnly) {
        // The plan's slots after this edit must not match another plan's exactly.
        final membershipRepo = ref.read(membershipRepositoryProvider);
        final plans = await membershipRepo.getFacilityPlans(widget.facilityId);
        final all = await membershipRepo.listAssignableBatches(widget.facilityId);
        final planId = widget.batch.planId;
        final after = [
          for (final x in all)
            if (x.planId == planId)
              if (x.batchId == widget.batch.batchId)
                SlotShape(courtId: _courtId, daysOfWeek: _days.toList(), startTime: _start, endTime: _end)
              else
                slotShapeOf(x),
        ];
        final dup = findDuplicatePlan(after, plans, all, ignorePlanId: planId);
        if (dup != null) {
          setState(() {
            _saving = false;
            _error = duplicatePlanMessage(dup.name);
          });
          return;
        }
      }
      final repo = ref.read(membershipSessionRepositoryProvider);
      if (widget.capacityOnly) {
        await repo.updateBatch(widget.batch.batchId, capacity: capacity);
      } else {
        await repo.updateBatch(
          widget.batch.batchId,
          courtId: _courtId,
          daysOfWeek: ([..._days]..sort()),
          startTime: _start,
          endTime: _end,
          capacity: capacity,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final b = widget.batch;
    final courtItems = _courts.isEmpty ? [(id: b.courtId, name: b.courtName)] : _courts;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.capacityOnly ? 'Edit Slot Settings' : 'Edit Slot', style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), icon: const Icon(Icons.close)),
              ],
            ),
            Text(
              widget.capacityOnly ? 'Update the slot configuration for this plan.' : 'Change the court, days or hours of this slot.',
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            if (!widget.capacityOnly) ...[
              AppDropdown<String>(
                initialValue: courtItems.any((c) => c.id == _courtId) ? _courtId : courtItems.first.id,
                decoration: const InputDecoration(labelText: 'Court'),
                items: [for (final c in courtItems) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => _courtId = v ?? _courtId),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Days', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in _weekOrder)
                    FilterChip(
                      label: Text(planDayAbbr[d]),
                      selected: _days.contains(d),
                      onSelected: (on) => setState(() => on ? _days = {..._days, d} : _days = _days.where((x) => x != d).toSet()),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickTime(start: true),
                      child: InputDecorator(decoration: const InputDecoration(labelText: 'Start time'), child: Text(Formatters.time12h(_start))),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickTime(start: false),
                      child: InputDecorator(decoration: const InputDecoration(labelText: 'End time'), child: Text(Formatters.time12h(_end))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: InputDecoration(
                labelText: 'Slot capacity *',
                helperText: b.enrolledCount > 0
                    ? 'Number of members who can hold this slot (${b.enrolledCount} already on it).'
                    : 'Number of members who can hold this slot.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: tokens.destructive, fontSize: 13)),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel'))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save Changes'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
