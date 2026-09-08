import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
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
  Map<String, String> _planNames = {}; // planId -> plan name
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

  @override
  void didUpdateWidget(covariant MembershipSlotSection old) {
    super.didUpdateWidget(old);
    // A different plan means a different set of session batches.
    if (old.planId != widget.planId) _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ref.read(sportsRepositoryProvider).getFacilitySports(widget.facilityId),
        ref.read(sportsRepositoryProvider).getActiveSports(),
        ref.read(playingAreaRepositoryProvider).getPlayingAreas(widget.facilityId),
        ref.read(membershipRepositoryProvider)
            .listAssignableBatches(widget.facilityId, planId: widget.planId),
        ref.read(membershipRepositoryProvider)
            .getFacilityPlans(widget.facilityId),
      ]);
      if (!mounted) return;
      final facilitySports = (results[0] as List<FacilitySport>).where((f) => f.enabled).toList();
      final sports = results[1] as List<Sport>;
      final courts = (results[2] as List<PlayingArea>)
          .where((a) => !a.archived && a.status == 'ACTIVE' && a.bookingEnabled)
          .toList();
      final batches = results[3] as List<AssignableBatch>;
      final plans = results[4] as List<MembershipPlan>;
      setState(() {
        _facilitySports = facilitySports;
        _sportNames = {for (final s in sports) s.id: s.name};
        _planNames = {for (final p in plans) p.id: p.name};
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
    return _batches
        .where((b) =>
            courtIds.contains(b.courtId) &&
            (widget.planId == null || b.planId == widget.planId))
        .toList();
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
    final tokens = context.tokens;
    final batches = _batchesForSport;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border.all(color: tokens.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Court time slot',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary)),
          const SizedBox(height: 2),
          Text('Optional — reserves a recurring court and time for this member.',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          AppDropdown<String>(
            initialValue: _facilitySportId.isEmpty ? null : _facilitySportId,
            decoration: const InputDecoration(labelText: 'Sport'),
            items: [
              const DropdownMenuItem(value: '', child: Text('No time slot')),
              for (final fs in _facilitySports)
                DropdownMenuItem(value: fs.id, child: Text(_sportLabel(fs))),
            ],
            onChanged: _pickSport,
          ),
          if (_facilitySportId.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _OptionCard(
              selected: value is SlotNone,
              onTap: () => widget.onChanged(const SlotNone()),
              child: Text('No reserved slot',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary)),
            ),
            if (batches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(
                  'No sessions for this plan and sport yet — create one below.',
                  style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
              )
            else
              for (final b in batches) _batchCard(b, value),
            _OptionCard(
              selected: value is SlotNew,
              onTap: () => widget
                  .onChanged(SlotNew(_emptyDraft(_facilitySportId))),
              child: Row(
                children: [
                  Icon(Icons.add, size: 16, color: tokens.violet),
                  const SizedBox(width: 6),
                  Text('Create a new slot',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: tokens.violet)),
                ],
              ),
            ),
            if (draft != null) _newSlotEditor(draft),
          ],
        ],
      ),
    );
  }

  Widget _batchCard(AssignableBatch b, MembershipSlotSelection value) {
    final tokens = context.tokens;
    final isCurrent = widget.currentBatchId == b.batchId;
    final disabled = b.spare <= 0 && !isCurrent;
    final capColor = disabled
        ? tokens.warning
        : (isCurrent ? tokens.violet : tokens.primary);
    return _OptionCard(
      selected: value is SlotExisting && value.batchId == b.batchId,
      disabled: disabled,
      onTap: () => widget.onChanged(SlotExisting(b.batchId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: disabled
                            ? tokens.textSecondary
                            : tokens.textPrimary)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: capColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${b.enrolledCount}/${b.capacity}'
                  '${isCurrent ? ' · current' : disabled ? ' · full' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: capColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(Icons.place_outlined,
                  size: 13, color: tokens.textSecondary),
              const SizedBox(width: 4),
              Text(b.courtName,
                  style: TextStyle(
                      fontSize: 12, color: tokens.textSecondary)),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.card_membership,
                  size: 13, color: tokens.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _planNames[b.planId] ?? 'Membership',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: tokens.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _newSlotEditor(NewSlotDraft draft) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.tokens.violet.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: context.tokens.violet.withValues(alpha: 0.3)),
      ),
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
                  selectedColor:
                      context.tokens.violet.withValues(alpha: 0.18),
                  checkmarkColor: context.tokens.violet,
                  side: BorderSide(
                    color: draft.daysOfWeek.contains(d)
                        ? context.tokens.violet
                        : context.tokens.borderColor,
                  ),
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

/// A tappable, card-styled option with a leading radio glyph — used for the
/// "no slot" / per-batch / "new slot" choices so each reads as a distinct
/// card rather than a cramped label in a list.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.selected,
    required this.onTap,
    required this.child,
    this.disabled = false,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Material(
          color: selected
              ? tokens.violet.withValues(alpha: 0.10)
              : tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: disabled ? null : onTap,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: selected ? tokens.violet : tokens.borderColor,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected ? tokens.violet : tokens.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
