import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/membership_session.dart';
import '../../data/repositories/repository_providers.dart';
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
    final t = context.tokens;
    final slot = widget.slot;
    final capacity = _capacity;
    final state = computeSlotDisplayState(capacity);
    final releasable = maxReleasable(capacity);
    final restorable = maxRestorable(capacity);

    // Each state gets a real accent rather than an emoji: violet is this
    // app's membership colour, marigold means "open to guests, money on
    // the table", red means nothing more can be sold here.
    final IconData icon;
    final String title;
    final Color tone;
    switch (state) {
      case MembershipSlotDisplayState.membershipAllocated:
      case MembershipSlotDisplayState.membershipPartiallyUsed:
        icon = Icons.lock_outline_rounded;
        title = 'Protected';
        tone = t.violet;
        break;
      case MembershipSlotDisplayState.membershipFull:
        icon = Icons.lock_rounded;
        title = 'Full';
        tone = t.violet;
        break;
      case MembershipSlotDisplayState.releasedForGuest:
        icon = Icons.lock_open_rounded;
        title = capacity.guestBookedCount == 0
            ? 'Open to guests'
            : '${capacity.guestAvailableCapacity} guest slot${capacity.guestAvailableCapacity == 1 ? '' : 's'} left';
        tone = t.warning;
        break;
      case MembershipSlotDisplayState.guestBooked:
        icon = Icons.event_busy_rounded;
        title = 'Guests full';
        tone = t.destructive;
        break;
    }

    // Capacity, split the way an owner actually thinks about it.
    final total = capacity.capacity <= 0 ? 1 : capacity.capacity;
    final members = capacity.memberBookedCount.clamp(0, total);
    final guestsIn = capacity.guestBookedCount.clamp(0, total);
    final guestsOpen =
        (capacity.releasedCapacity - capacity.guestBookedCount).clamp(0, total);

    Widget seg(int n, Color c) => n <= 0
        ? const SizedBox.shrink()
        : Expanded(flex: n, child: ColoredBox(color: c));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.borderColor),
      ),
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
                      '${slot.startTime.substring(0, 5)} – ${slot.endTime.substring(0, 5)}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: t.textPrimary),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${slot.courtName} · ${slot.sportName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: t.accentSolid(tone),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: t.onAccent(tone)),
                    const SizedBox(width: 4),
                    Text(title,
                        style: TextStyle(
                            color: t.onAccent(tone),
                            fontWeight: FontWeight.w800,
                            fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(slot.batchName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.violet)),
          const SizedBox(height: AppSpacing.md),

          // Who is holding this hour — members, guests in, guests still
          // sellable, and dead space — as one bar instead of a sentence.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 7,
              child: Row(
                children: [
                  seg(members, t.accentSolid(t.violet)),
                  seg(guestsIn, t.accentSolid(t.warning)),
                  seg(
                      guestsOpen,
                      Color.alphaBlend(
                          t.warning.withValues(alpha: 0.35), t.surface1)),
                  seg(
                      (total - members - guestsIn - guestsOpen)
                          .clamp(0, total),
                      t.surface2),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            capacity.releasedCapacity > 0
                ? '${capacity.memberBookedCount}/${capacity.capacity} members · ${capacity.guestBookedCount}/${capacity.releasedCapacity} guest slots used'
                : '${capacity.memberBookedCount}/${capacity.capacity} members · ${capacity.unusedCapacity} unused',
            style: TextStyle(fontSize: 11.5, color: t.textSecondary),
          ),
          if (state == MembershipSlotDisplayState.membershipFull) ...[
            const SizedBox(height: 2),
            Text('No unused capacity to release for guest play.',
                style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                    t.destructive.withValues(alpha: 0.12), t.surface1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(_error!,
                  style: TextStyle(color: t.destructive, fontSize: 12)),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (releasable > 0)
                _SlotAction(
                  label: _pending == _Pending.release
                      ? 'Releasing…'
                      : 'Release $releasable to guests',
                  accent: t.warning,
                  onTap: _pending != null ? null : () => _release(releasable),
                ),
              if (restorable > 0)
                _SlotAction(
                  label: _pending == _Pending.restore
                      ? 'Restoring…'
                      : 'Restore $restorable',
                  onTap: _pending != null ? null : () => _restore(restorable),
                ),
              if (capacity.releasedCapacity > 0)
                _SlotAction(
                  label: capacity.guestAvailableCapacity > 0
                      ? 'Book guest'
                      : 'Guests full',
                  accent: t.primary,
                  onTap: capacity.guestAvailableCapacity == 0
                      ? null
                      : _openBookGuestSlot,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A pill action. Solid when it carries an accent, quiet outline otherwise —
/// so "Release to guests" and "Book guest" read as the money-making moves
/// and "Restore" stays secondary.
class _SlotAction extends StatelessWidget {
  const _SlotAction({required this.label, required this.onTap, this.accent});

  final String label;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final disabled = onTap == null;
    final solid = accent != null && !disabled;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 9),
          decoration: BoxDecoration(
            color: solid ? t.accentSolid(accent!) : t.surface2,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: solid ? null : Border.all(color: t.borderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: solid ? t.onAccent(accent!) : t.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}