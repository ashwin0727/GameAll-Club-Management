import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/membership_session.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import 'book_guest_slot_sheet.dart';
import 'capacity.dart';

/// The single membership-slot presentation, shared by the dedicated
/// Membership Sessions page and the Bookings grid's membership-protected
/// cells — one place owns "what does this state look like" so the two
/// surfaces can never drift out of sync. Mirrors
/// src/features/membership-sessions/components/membership-slot-card.tsx,
/// including its exact emoji/copy for each state.
///
/// Never renders a bare "disabled"/"unavailable" cell — every state
/// explains what's protected, what's used, what's unused, and what action
/// (if any) the owner can take right now.
class MembershipSlotCard extends ConsumerStatefulWidget {
  const MembershipSlotCard({super.key, required this.facilityId, required this.slot, required this.onChanged});

  final String facilityId;
  final MembershipSessionSlot slot;

  /// Called after a release/restore/guest-booking succeeds, so the caller
  /// can reload whatever list/grid it owns (this card already refreshes its
  /// own numbers independently — see [_refreshCapacity]).
  final VoidCallback onChanged;

  @override
  ConsumerState<MembershipSlotCard> createState() => _MembershipSlotCardState();
}

enum _Pending { release, restore }

class _MembershipSlotCardState extends ConsumerState<MembershipSlotCard> {
  _Pending? _pending;
  String? _error;

  // Live-refreshed after any action, so the card keeps showing correct
  // numbers without the caller needing to close/reopen it — mirrors the
  // web Bookings grid's "sync an open dialog's numbers after reload" effect.
  MembershipSessionCapacity? _liveCapacity;
  String? _liveSessionId;

  MembershipSessionCapacity get _capacity => _liveCapacity ?? slotToCapacity(widget.slot);
  String? get _sessionId => _liveSessionId ?? widget.slot.sessionId;

  Future<void> _refreshCapacity(String sessionId) async {
    try {
      final capacity = await ref.read(membershipSessionRepositoryProvider).getSessionCapacity(sessionId);
      if (mounted) setState(() => _liveCapacity = capacity);
    } on AppException catch (_) {
      // Best-effort — the caller's own reload (widget.onChanged) will still
      // catch up the next time this card is rebuilt with a fresh slot.
    }
  }

  Future<void> _release(int count) async {
    setState(() {
      _pending = _Pending.release;
      _error = null;
    });
    try {
      final repo = ref.read(membershipSessionRepositoryProvider);
      // A session that has never been touched has no id yet — releasing
      // capacity can itself be the first action taken against a date.
      final sessionId = _sessionId ?? await repo.getOrCreateSession(widget.slot.batchId, widget.slot.sessionDate);
      await repo.releaseCapacity(sessionId, count);
      _liveSessionId = sessionId;
      await _refreshCapacity(sessionId);
      widget.onChanged();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Future<void> _restore(int count) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    setState(() {
      _pending = _Pending.restore;
      _error = null;
    });
    try {
      await ref.read(membershipSessionRepositoryProvider).restoreCapacity(sessionId, count);
      await _refreshCapacity(sessionId);
      widget.onChanged();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Future<void> _openBookGuestSlot() async {
    final booked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => BookGuestSlotSheet(facilityId: widget.facilityId, slot: widget.slot),
    );
    if (booked == true) {
      final sessionId = _sessionId;
      if (sessionId != null) await _refreshCapacity(sessionId);
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final capacity = _capacity;
    final state = computeSlotDisplayState(capacity);
    final releasable = maxReleasable(capacity);
    final restorable = maxRestorable(capacity);

    final String emoji;
    final String title;
    final Color tone;
    switch (state) {
      case MembershipSlotDisplayState.membershipAllocated:
      case MembershipSlotDisplayState.membershipPartiallyUsed:
        emoji = '🔒';
        title = 'Membership Protected';
        tone = AppColors.muted;
        break;
      case MembershipSlotDisplayState.membershipFull:
        emoji = '🔒';
        title = 'Membership Full';
        tone = AppColors.muted;
        break;
      case MembershipSlotDisplayState.releasedForGuest:
        emoji = '🟢';
        title = capacity.guestBookedCount == 0
            ? 'Guest Capacity Released'
            : '${capacity.guestAvailableCapacity} Guest Slot${capacity.guestAvailableCapacity == 1 ? '' : 's'} Available';
        tone = AppColors.warning;
        break;
      case MembershipSlotDisplayState.guestBooked:
        emoji = '🔴';
        title = 'Guest Capacity Full';
        tone = AppColors.destructive;
        break;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${slot.courtName} · ${slot.sportName} · ${slot.startTime.substring(0, 5)}–${slot.endTime.substring(0, 5)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      slot.batchName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$emoji $title',
                  style: TextStyle(color: tone, fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            capacity.releasedCapacity > 0
                ? '${capacity.memberBookedCount} / ${capacity.capacity} members using · ${capacity.guestBookedCount} / ${capacity.releasedCapacity} guest slots used'
                : '${capacity.memberBookedCount} / ${capacity.capacity} members using',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (state == MembershipSlotDisplayState.membershipFull)
            Text(
              'Guest Play Unavailable — no unused capacity to release.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
          if (state == MembershipSlotDisplayState.membershipAllocated ||
              state == MembershipSlotDisplayState.membershipPartiallyUsed)
            Text(
              '${capacity.unusedCapacity} unused membership slot${capacity.unusedCapacity == 1 ? '' : 's'}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(_error!, style: const TextStyle(color: AppColors.destructive)),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (releasable > 0)
                OutlinedButton(
                  onPressed: _pending != null ? null : () => _release(releasable),
                  child: Text(_pending == _Pending.release ? 'Releasing…' : 'Release $releasable for Guest Play'),
                ),
              if (restorable > 0)
                OutlinedButton(
                  onPressed: _pending != null ? null : () => _restore(restorable),
                  child: Text(
                    _pending == _Pending.restore ? 'Restoring…' : 'Restore $restorable Slot${restorable == 1 ? '' : 's'}',
                  ),
                ),
              if (capacity.releasedCapacity > 0)
                FilledButton(
                  onPressed: capacity.guestAvailableCapacity == 0 ? null : _openBookGuestSlot,
                  child: Text(capacity.guestAvailableCapacity > 0 ? 'Book Guest' : 'Guest Capacity Full'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}