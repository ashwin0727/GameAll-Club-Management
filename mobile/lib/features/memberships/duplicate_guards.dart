// Duplicate guards — the same rules as the web's duplicate-guards.ts.
//
// * A plan can't repeat another plan's courts, days and hours exactly. Mon-Fri 5-6 AM twice is a
//   duplicate; Mon-Sun 5-6 AM beside it is a different plan.
// * The same person (same phone number) can't be put on the same plan twice.

import '../../data/models/membership.dart';

/// The part of a slot that makes two plans "the same": court, days, hours.
class SlotShape {
  const SlotShape({required this.courtId, required this.daysOfWeek, required this.startTime, required this.endTime});

  final String courtId;
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;
}

String _clock(String t) => t.length >= 5 ? t.substring(0, 5) : t;

/// One slot as a comparable string — day order and a ":00" seconds suffix don't matter.
String slotSignature(SlotShape s) {
  final days = ({...s.daysOfWeek}.toList()..sort()).join(',');
  return '${s.courtId}|$days|${_clock(s.startTime)}|${_clock(s.endTime)}';
}

/// A plan's whole slot set as one comparable string (slot order doesn't matter).
String slotSetSignature(Iterable<SlotShape> slots) => (slots.map(slotSignature).toSet().toList()..sort()).join(';');

SlotShape slotShapeOf(AssignableBatch b) =>
    SlotShape(courtId: b.courtId, daysOfWeek: b.daysOfWeek, startTime: b.startTime, endTime: b.endTime);

/// The plan whose slots are exactly [draft], or null. [batches] are every plan's slots (a slot with
/// no plan is ignored); [plans] supplies the names. A draft with no slots is never a duplicate.
/// [ignorePlanId] is the plan being edited.
MembershipPlan? findDuplicatePlan(
  List<SlotShape> draft,
  List<MembershipPlan> plans,
  List<AssignableBatch> batches, {
  String? ignorePlanId,
}) {
  if (draft.isEmpty) return null;
  final wanted = slotSetSignature(draft);
  for (final p in plans) {
    if (p.id == ignorePlanId) continue;
    final slots = batches.where((b) => b.planId == p.id).map(slotShapeOf).toList();
    if (slots.isNotEmpty && slotSetSignature(slots) == wanted) return p;
  }
  return null;
}

String duplicatePlanMessage(String name) =>
    'A plan with the same courts, days and timings already exists (“$name”). Change the days or hours to create a different plan.';

/// Digits only, last ten — "+91 98765 43210" and "9876543210" are the same number.
String normalizePhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}

/// The membership that already puts this person on [plan], or null. A lapsed (inactive) membership
/// doesn't count, so someone can rejoin after theirs ends.
MembershipListRow? findDuplicateMember(List<MembershipListRow> rows, MembershipPlan plan, String phone) {
  final wanted = normalizePhone(phone);
  if (wanted.length < 7) return null;
  for (final r in rows) {
    if (r.status == MembershipListStatus.inactive) continue;
    if (normalizePhone(r.memberPhone) != wanted) continue;
    if (r.planId == plan.id || r.planName.trim().toLowerCase() == plan.name.trim().toLowerCase()) return r;
  }
  return null;
}

const duplicateMemberMessage = 'This member is already on this plan.';
