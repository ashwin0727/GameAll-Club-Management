// Membership Schedule — pure helpers shared by the screen and its tests. Mirrors
// src/features/memberships/member-schedule.ts so the two apps group and read a member's weekly
// court slots identically.

/// One row of `list_member_schedules` — a (member, batch) pair.
class MemberScheduleRow {
  const MemberScheduleRow({
    required this.memberId,
    required this.fullName,
    required this.phone,
    required this.status,
    required this.membershipId,
    required this.batchId,
    required this.batchName,
    required this.courtId,
    required this.courtName,
    required this.facilitySportId,
    required this.sportName,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
  });

  final String memberId;
  final String fullName;
  final String phone;
  final String status;

  /// The membership this batch assignment was made under — null for an older assignment made before
  /// memberships were linked to batch enrolment.
  final String? membershipId;
  final String batchId;
  final String batchName;
  final String courtId;
  final String courtName;
  final String facilitySportId;
  final String sportName;

  /// 0 = Sunday … 6 = Saturday.
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;

  static String _hhmm(dynamic v) {
    final t = (v as String?) ?? '';
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  factory MemberScheduleRow.fromJson(Map<String, dynamic> j) => MemberScheduleRow(
        memberId: j['member_id'] as String,
        fullName: j['full_name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        status: j['status'] as String? ?? 'ACTIVE',
        membershipId: j['membership_id'] as String?,
        batchId: j['batch_id'] as String,
        batchName: j['batch_name'] as String? ?? '',
        courtId: j['court_id'] as String,
        courtName: j['court_name'] as String? ?? '',
        facilitySportId: j['facility_sport_id'] as String? ?? '',
        sportName: j['sport_name'] as String? ?? '',
        daysOfWeek: ((j['days_of_week'] as List<dynamic>?) ?? const []).map((e) => (e as num).toInt()).toList(),
        startTime: _hhmm(j['start_time']),
        endTime: _hhmm(j['end_time']),
      );
}

class MemberBatchSlot {
  const MemberBatchSlot({
    required this.batchId,
    required this.batchName,
    required this.courtId,
    required this.courtName,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
  });
  final String batchId;
  final String batchName;
  final String courtId;
  final String courtName;
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;

  /// Whether this slot recurs on [date] (Dart's Mon=1…Sun=7 mapped onto the database's Sun=0…Sat=6).
  bool occursOn(DateTime date) => daysOfWeek.contains(date.weekday % 7);
}

class MemberScheduleSummary {
  MemberScheduleSummary({
    required this.memberId,
    required this.fullName,
    required this.phone,
    required this.status,
    required this.membershipId,
    required this.slots,
  });
  final String memberId;
  final String fullName;
  final String phone;
  final String status;
  String? membershipId;
  final List<MemberBatchSlot> slots;

  bool get isActive => status == 'ACTIVE';

  /// Every distinct court the member plays on, in the order their slots list them.
  List<({String id, String name})> get courts {
    final seen = <String>{};
    return [
      for (final s in slots)
        if (seen.add(s.courtId)) (id: s.courtId, name: s.courtName),
    ];
  }

  /// "Morning (07:00 – 08:00), Evening (18:00 – 19:00)" — the distinct time ranges, banded by
  /// whether they start before noon.
  String get preferredTime {
    final seen = <String>{};
    final parts = <String>[];
    for (final s in slots) {
      if (!seen.add('${s.startTime}-${s.endTime}')) continue;
      final hour = int.tryParse(s.startTime.split(':').first) ?? 0;
      parts.add('${hour < 12 ? 'Morning' : 'Evening'} (${s.startTime} – ${s.endTime})');
    }
    return parts.join(', ');
  }
}

/// `list_member_schedules` returns one row per (member, batch) — this groups them into one entry
/// per member with their full list of slots, sorted by name.
List<MemberScheduleSummary> groupMemberSchedules(List<MemberScheduleRow> rows) {
  final byMember = <String, MemberScheduleSummary>{};
  for (final row in rows) {
    final entry = byMember.putIfAbsent(
      row.memberId,
      () => MemberScheduleSummary(
        memberId: row.memberId,
        fullName: row.fullName,
        phone: row.phone,
        status: row.status,
        membershipId: row.membershipId,
        slots: [],
      ),
    );
    // Prefer any non-null membershipId — a member's batches almost always share one membership.
    entry.membershipId ??= row.membershipId;
    entry.slots.add(MemberBatchSlot(
      batchId: row.batchId,
      batchName: row.batchName,
      courtId: row.courtId,
      courtName: row.courtName,
      daysOfWeek: row.daysOfWeek,
      startTime: row.startTime,
      endTime: row.endTime,
    ));
  }
  return byMember.values.toList()..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
}
