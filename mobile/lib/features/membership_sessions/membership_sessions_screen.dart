import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../data/models/membership_session.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import 'book_guest_slot_sheet.dart';
import 'capacity.dart';
import 'membership_batches_sheet.dart';

String _todayIso() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

({String label, StatusTone tone}) _stateBadge(MembershipSlotDisplayState state) {
  switch (state) {
    case MembershipSlotDisplayState.membershipAllocated:
      return (label: 'Membership reserved', tone: StatusTone.neutral);
    case MembershipSlotDisplayState.membershipPartiallyUsed:
      return (label: 'Membership session', tone: StatusTone.neutral);
    case MembershipSlotDisplayState.membershipFull:
      return (label: 'Membership full', tone: StatusTone.success);
    case MembershipSlotDisplayState.releasedForGuest:
      return (label: 'Guest slots available', tone: StatusTone.warning);
    case MembershipSlotDisplayState.guestBooked:
      return (label: 'Fully booked', tone: StatusTone.danger);
  }
}

/// The Owner Availability View — date picker, list of session slots each
/// showing Capacity/Member Booked/Unused/Released/Guest Available, a status
/// badge, Release/Restore buttons, and a "Book Guest Slot" button. Mirrors
/// `membership-availability-view.tsx`.
class MembershipSessionsScreen extends ConsumerStatefulWidget {
  const MembershipSessionsScreen({super.key});

  @override
  ConsumerState<MembershipSessionsScreen> createState() => _MembershipSessionsScreenState();
}

class _MembershipSessionsScreenState extends ConsumerState<MembershipSessionsScreen> {
  String? _facilityId;
  bool _isLoading = true;
  String? _loadError;
  DateTime _date = DateTime.now();
  List<MembershipSessionSlot>? _slots;
  String? _pendingKey;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        setState(() {
          _isLoading = false;
          _loadError = 'Complete your facility setup before managing membership sessions.';
        });
        return;
      }
      setState(() {
        _facilityId = facility.id;
        _isLoading = false;
      });
      await _reload();
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _reload() async {
    if (_facilityId == null) return;
    setState(() => _slots = null);
    try {
      final slots = await ref.read(membershipSessionRepositoryProvider).listSessionsForDate(_facilityId!, _isoOf(_date));
      if (mounted) setState(() => _slots = slots);
    } on AppException catch (_) {
      if (mounted) setState(() => _slots = []);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      await _reload();
    }
  }

  Future<void> _openBatches() async {
    if (_facilityId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MembershipBatchesSheet(facilityId: _facilityId!),
    );
    await _reload();
  }

  Future<void> _release(MembershipSessionSlot slot, int count) async {
    final key = 'release-${slot.batchId}';
    setState(() {
      _pendingKey = key;
      _actionError = null;
    });
    try {
      final repo = ref.read(membershipSessionRepositoryProvider);
      // A session that has never been touched has no id yet — releasing
      // capacity is itself the first action, so materialize it first the
      // same way book_membership_slot/book_guest_slot do internally.
      final sessionId = slot.sessionId ?? await repo.getOrCreateSession(slot.batchId, slot.sessionDate);
      await repo.releaseCapacity(sessionId, count);
      await _reload();
    } on AppException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _pendingKey = null);
    }
  }

  Future<void> _restore(MembershipSessionSlot slot, int count) async {
    if (slot.sessionId == null) return;
    final key = 'restore-${slot.batchId}';
    setState(() {
      _pendingKey = key;
      _actionError = null;
    });
    try {
      await ref.read(membershipSessionRepositoryProvider).restoreCapacity(slot.sessionId!, count);
      await _reload();
    } on AppException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _pendingKey = null);
    }
  }

  Future<void> _openBookGuestSlot(MembershipSessionSlot slot) async {
    if (_facilityId == null) return;
    final booked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => BookGuestSlotSheet(facilityId: _facilityId!, slot: slot),
    );
    if (booked == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Sessions'),
        actions: [
          if (_facilityId != null)
            IconButton(icon: const Icon(Icons.event_note), tooltip: 'Manage Batches', onPressed: _openBatches),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading membership sessions…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(_isoOf(_date) == _todayIso() ? 'Today · ${_isoOf(_date)}' : _isoOf(_date)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (_actionError != null) ...[
                      Text(_actionError!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    if (_slots == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_slots!.isEmpty)
                      const EmptyStateView(message: 'No membership sessions today.')
                    else
                      ..._slots!.map((slot) => _SlotCard(
                        slot: slot,
                        pendingKey: _pendingKey,
                        onRelease: _release,
                        onRestore: _restore,
                        onBookGuest: _openBookGuestSlot,
                      )),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.pendingKey,
    required this.onRelease,
    required this.onRestore,
    required this.onBookGuest,
  });

  final MembershipSessionSlot slot;
  final String? pendingKey;
  final void Function(MembershipSessionSlot slot, int count) onRelease;
  final void Function(MembershipSessionSlot slot, int count) onRestore;
  final void Function(MembershipSessionSlot slot) onBookGuest;

  @override
  Widget build(BuildContext context) {
    final capacity = slotToCapacity(slot);
    final state = computeSlotDisplayState(capacity);
    final badge = _stateBadge(state);
    final releasable = maxReleasable(capacity);
    final restorable = maxRestorable(capacity);
    final releasePending = pendingKey == 'release-${slot.batchId}';
    final restorePending = pendingKey == 'restore-${slot.batchId}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
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
                        '${slot.courtName} · ${slot.startTime.substring(0, 5)}–${slot.endTime.substring(0, 5)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text('${slot.batchName} · ${slot.sportName}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                StatusBadge(label: badge.label, tone: badge.tone),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _StatTile(label: 'Capacity', value: capacity.capacity),
                _StatTile(label: 'Member Booked', value: capacity.memberBookedCount),
                _StatTile(label: 'Unused', value: capacity.unusedCapacity),
                _StatTile(label: 'Released', value: capacity.releasedCapacity),
                _StatTile(label: 'Guest Available', value: capacity.guestAvailableCapacity),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: releasable == 0 || releasePending ? null : () => onRelease(slot, releasable),
                  child: Text('Release${releasable > 0 ? ' $releasable' : ''} Unused Slot${releasable == 1 ? '' : 's'}'),
                ),
                OutlinedButton(
                  onPressed: restorable == 0 || restorePending ? null : () => onRestore(slot, restorable),
                  child: Text('Restore${restorable > 0 ? ' $restorable' : ''} Released Slot${restorable == 1 ? '' : 's'}'),
                ),
                FilledButton(
                  onPressed: capacity.guestAvailableCapacity == 0 ? null : () => onBookGuest(slot),
                  child: Text(capacity.guestAvailableCapacity > 0 ? 'Book Guest Slot' : 'Guest Booking Unavailable'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 90),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.muted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted)),
          Text('$value', style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}