import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/membership.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import 'access_days.dart';
import 'membership_slot.dart';
import 'slot_format.dart';

/// The membership "Court Time Slot" step — mirrors
/// src/features/memberships/components/court-time-slot-section.tsx.
///
/// Pick a sport, then: no reserved slot, join an existing session batch, or
/// define a new one (court + days + hours + capacity). The new-slot day chips
/// seed from the facility's membership access days.
class MembershipSlotSection extends ConsumerStatefulWidget {
  const MembershipSlotSection({
    super.key,
    required this.facilityId,
    required this.accessDays,
    required this.value,
    required this.onChanged,
    this.planId,
    this.currentBatchId,
  });

  final String facilityId;
  final List<int> accessDays;
  final MembershipSlotSelection value;
  final ValueChanged<MembershipSlotSelection> onChanged;
  final String? planId;

  /// The batch the member is already in (edit mode) — always selectable even
  /// at zero spare.
  final String? currentBatchId;

  @override
  ConsumerState<MembershipSlotSection> createState() => _MembershipSlotSectionState();
}

class _MembershipSlotSectionState extends ConsumerState<MembershipSlotSection> {
  List<FacilitySport> _facilitySports = [];
  Map<String, String> _sportNames = {}; // sportId -> display name
  List<PlayingArea> _courts = [];
  List<AssignableBatch> _batches = [];
  bool _loading = true;

  String _facilitySportId = '';

  @override
  void initState() {
    super.initState();
    // Edit mode: if we already know the batch, preselect its sport once loaded.
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ref.read(sportsRepositoryProvider).getFacilitySports(widget.facilityId),
        ref.read(sportsRepositoryProvider).getActiveSports(),
        ref.read(playingAreaRepositoryProvider).getPlayingAreas(widget.facilityId),
        ref.read(membershipRepositoryProvider)
            .listAssignableBatches(widget.facilityId, planId: widget.planId),
      ]);
      if (!mounted) return;
      final facilitySports = (results[0] as List<FacilitySport>).where((f) => f.enabled).toList();
      final sports = results[1] as List<Sport>;
      final courts = (results[2] as List<PlayingArea>)
          .where((a) => !a.archived && a.status == 'ACTIVE' && a.bookingEnabled)
          .toList();
      final batches = results[3] as List<AssignableBatch>;
      setState(() {
        _facilitySports = facilitySports;
        _sportNames = {for (final s in sports) s.id: s.name};
        _courts = courts;
        _batches = batches;
        _loading = false;
        final current = widget.value;
        if (current is SlotExisting) {
          _facilitySportId = batches
                  .where((b) => b.batchId == current.batchId)
                  .map((b) => b.facilitySportId)
                  .firstOrNull ??
              '';
        } else if (current is SlotNew) {
          _facilitySportId = current.draft.facilitySportId;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sportLabel(FacilitySport fs) =>
      fs.customSportName ?? _sportNames[fs.sportId] ?? 'Sport';

  List<PlayingArea> get _courtsForSport =>
      _courts.where((c) => c.facilitySportId == _facilitySportId).toList();

  List<AssignableBatch> get _batchesForSport {
    final courtIds = _courtsForSport.map((c) => c.id).toSet();
    return _batches.where((b) => courtIds.contains(b.courtId)).toList();
  }

  void _pickSport(String? id) {
    setState(() => _facilitySportId = id ?? '');
    if (id == null || id.isEmpty) {
      widget.onChanged(const SlotNone());
    } else if (widget.value is SlotNew) {
      widget.onChanged(SlotNew(_emptyDraft(id)));
    } else if (widget.value is SlotExisting) {
      widget.onChanged(const SlotNone());
    }
  }

  NewSlotDraft _emptyDraft(String sportId) => NewSlotDraft(
        facilitySportId: sportId,
        courtId: '',
        daysOfWeek: widget.accessDays.toList(),
        startTime: '06:00',
        endTime: '07:00',
        capacity: null,
      );

  void _patchDraft(NewSlotDraft next) => widget.onChanged(SlotNew(next));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final value = widget.value;
    final draft = value is SlotNew ? value.draft : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Court Time Slot',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
          Text('Optional — reserves this court/time for the member.',
              style: TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: AppSpacing.sm),
          AppDropdown<String>(
            initialValue: _facilitySportId.isEmpty ? null : _facilitySportId,
            decoration: const InputDecoration(labelText: 'Sport (to add a time slot)'),
            items: [
              const DropdownMenuItem(value: '', child: Text('No time slot')),
              for (final fs in _facilitySports)
                DropdownMenuItem(value: fs.id, child: Text(_sportLabel(fs))),
            ],
            onChanged: _pickSport,
          ),
          if (_facilitySportId.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _RadioRow(
              label: 'No reserved slot',
              selected: value is SlotNone,
              onTap: () => widget.onChanged(const SlotNone()),
            ),
            for (final b in _batchesForSport) _batchRow(b, value),
            _RadioRow(
              label: '+ New time slot',
              selected: value is SlotNew,
              onTap: () => widget.onChanged(SlotNew(_emptyDraft(_facilitySportId))),
            ),
            if (draft != null) _newSlotEditor(draft),
          ],
        ],
      ),
    );
  }

  Widget _batchRow(AssignableBatch b, MembershipSlotSelection value) {
    final isCurrent = widget.currentBatchId == b.batchId;
    final disabled = b.spare <= 0 && !isCurrent;
    return _RadioRow(
      label: '${b.courtName} · ${formatSlot(b.daysOfWeek, b.startTime, b.endTime)} · '
          '${b.enrolledCount}/${b.capacity}'
          '${isCurrent ? ' — current' : ''}${disabled ? ' — full' : ''}',
      selected: value is SlotExisting && value.batchId == b.batchId,
      disabled: disabled,
      onTap: () => widget.onChanged(SlotExisting(b.batchId)),
    );
  }

  Widget _newSlotEditor(NewSlotDraft draft) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.lg, top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppDropdown<String>(
            initialValue: draft.courtId.isEmpty ? null : draft.courtId,
            decoration: const InputDecoration(labelText: 'Court'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Select court')),
              for (final c in _courtsForSport)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => _patchDraft(draft.copyWith(courtId: v ?? '')),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final d in allDays)
                FilterChip(
                  label: Text(dayLabel(d)),
                  selected: draft.daysOfWeek.contains(d),
                  onSelected: (_) => _patchDraft(draft.copyWith(daysOfWeek: toggleDay(draft.daysOfWeek, d))),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _timeField('Start', draft.startTime, (t) => _patchDraft(draft.copyWith(startTime: t)))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _timeField('End', draft.endTime, (t) => _patchDraft(draft.copyWith(endTime: t)))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  initialValue: draft.capacity?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  onChanged: (v) => _patchDraft(
                    v.trim().isEmpty
                        ? draft.copyWith(clearCapacity: true)
                        : draft.copyWith(capacity: int.tryParse(v.trim())),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('How many membership players share this court/time.',
              style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _timeField(String label, String value, ValueChanged<String> onPicked) {
    return InkWell(
      onTap: () async {
        final parts = value.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
            hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 6,
            minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
          ),
        );
        if (picked != null) {
          onPicked('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(formatClock(value)),
      ),
    );
  }
}

/// A tap-to-select row with a radio glyph — the codebase's radio idiom
/// (see book_guest_slot_sheet / guest_bookings_screen) rather than the now
/// deprecated `RadioListTile` group API.
class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: disabled
                  ? AppColors.muted
                  : selected
                      ? AppColors.primary
                      : AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: disabled ? AppColors.muted : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
