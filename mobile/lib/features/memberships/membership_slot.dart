/// The membership court-time-slot selection — mirrors
/// src/features/memberships/slot-form.ts.
///
/// A new membership can join an existing session batch, spin up a fresh one,
/// or reserve nothing. `create_membership_full` / `update_membership_full`
/// (0029 / 0038) take `p_batch_id` for the first and a `p_new_batch` jsonb for
/// the second — `{courtId, facilitySportId, daysOfWeek, startTime, endTime,
/// capacity}`, exactly the keys the RPC destructures.
library;

/// A fresh batch the owner is defining inline. [capacity] is nullable while
/// the field is still empty; [validateSlotSelection] rejects that.
class NewSlotDraft {
  const NewSlotDraft({
    required this.facilitySportId,
    required this.courtId,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.capacity,
  });

  final String facilitySportId;
  final String courtId;
  final List<int> daysOfWeek;

  /// `HH:MM` 24h, as the `<time>`-style pickers produce and the RPC's
  /// `::time` cast expects.
  final String startTime;
  final String endTime;
  final int? capacity;

  NewSlotDraft copyWith({
    String? courtId,
    List<int>? daysOfWeek,
    String? startTime,
    String? endTime,
    int? capacity,
    bool clearCapacity = false,
  }) {
    return NewSlotDraft(
      facilitySportId: facilitySportId,
      courtId: courtId ?? this.courtId,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      capacity: clearCapacity ? null : (capacity ?? this.capacity),
    );
  }
}

/// What the membership's court reservation should be.
sealed class MembershipSlotSelection {
  const MembershipSlotSelection();
}

class SlotNone extends MembershipSlotSelection {
  const SlotNone();
}

class SlotExisting extends MembershipSlotSelection {
  const SlotExisting(this.batchId);

  final String batchId;
}

class SlotNew extends MembershipSlotSelection {
  const SlotNew(this.draft);

  final NewSlotDraft draft;
}

/// Client-side guard mirroring `validateSlotSelection` in slot-form.ts — the
/// RPC enforces the same rules. Returns an error string, or null when valid.
String? validateSlotSelection(MembershipSlotSelection selection) {
  switch (selection) {
    case SlotNone():
      return null;
    case SlotExisting(:final batchId):
      return batchId.isNotEmpty ? null : 'Pick a time slot or clear the court.';
    case SlotNew(:final draft):
      if (draft.courtId.isEmpty) return 'Select a court for the time slot.';
      if (draft.daysOfWeek.isEmpty) return 'Select at least one day for the time slot.';
      if (draft.startTime.isEmpty ||
          draft.endTime.isEmpty ||
          draft.endTime.compareTo(draft.startTime) <= 0) {
        return 'Time slot end must be after the start.';
      }
      final cap = draft.capacity;
      if (cap == null || cap < 1) return 'Enter a time slot capacity of at least 1.';
      return null;
  }
}

/// The `p_batch_id` / `p_new_batch` pair for a `*_membership_full` RPC call.
/// Kept in one place so create and update send an identical shape.
Map<String, dynamic> slotRpcArgs(MembershipSlotSelection selection) {
  switch (selection) {
    case SlotNone():
      return {'p_batch_id': null, 'p_new_batch': null};
    case SlotExisting(:final batchId):
      return {'p_batch_id': batchId, 'p_new_batch': null};
    case SlotNew(:final draft):
      return {
        'p_batch_id': null,
        'p_new_batch': {
          'courtId': draft.courtId,
          'facilitySportId': draft.facilitySportId,
          'daysOfWeek': draft.daysOfWeek,
          'startTime': draft.startTime,
          'endTime': draft.endTime,
          'capacity': draft.capacity,
        },
      };
  }
}
