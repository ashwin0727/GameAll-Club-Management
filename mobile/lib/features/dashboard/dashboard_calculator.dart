import '../../data/models/dashboard.dart';
import '../../data/models/operating_hours.dart';

/// Pure calculation logic — mirrors src/features/dashboard/summary.ts
/// exactly (same date-range rules, same utilization formula, same
/// never-fabricate-attention-items rule) so both clients agree on what a
/// number means. Independently unit-tested, never called with a live
/// Supabase client.
class DashboardCalculator {
  const DashboardCalculator._();

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static ResolvedPeriod resolveDateRange(DateRangePreset preset, DateTime now) {
    final today0 = _startOfDay(now);

    switch (preset) {
      case DateRangePreset.today:
        return ResolvedPeriod(
          current: DateRange(from: today0, to: today0.add(const Duration(days: 1))),
          previous: DateRange(
            from: today0.subtract(const Duration(days: 1)),
            to: today0,
          ),
        );
      case DateRangePreset.yesterday:
        final y = today0.subtract(const Duration(days: 1));
        return ResolvedPeriod(
          current: DateRange(from: y, to: today0),
          previous: DateRange(from: y.subtract(const Duration(days: 1)), to: y),
        );
      case DateRangePreset.thisWeek:
        final weekStart = today0.subtract(Duration(days: today0.weekday % 7));
        return ResolvedPeriod(
          current: DateRange(from: weekStart, to: today0.add(const Duration(days: 1))),
          previous: DateRange(
            from: weekStart.subtract(const Duration(days: 7)),
            to: weekStart,
          ),
        );
      case DateRangePreset.thisMonth:
        final monthStart = DateTime(today0.year, today0.month, 1);
        final prevMonthStart = DateTime(today0.year, today0.month - 1, 1);
        return ResolvedPeriod(
          current: DateRange(from: monthStart, to: today0.add(const Duration(days: 1))),
          previous: DateRange(from: prevMonthStart, to: monthStart),
        );
    }
  }

  static KpiValue computeKpiValue(num current, num? previous) {
    if (previous == null) {
      return KpiValue(value: current);
    }
    if (previous == 0) {
      return KpiValue(value: current, previousValue: previous);
    }
    final changePercent = ((current - previous) / previous) * 100;
    return KpiValue(value: current, previousValue: previous, changePercent: changePercent.toDouble());
  }

  static int _toMinutes(String time) {
    final parts = time.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return h * 60 + m;
  }

  static int operatingMinutesForDay(OperatingDay day) {
    if (day.isClosed) return 0;
    if (day.is24Hours) return 24 * 60;
    return day.slots.fold<int>(0, (sum, slot) {
      final start = _toMinutes(slot.startTime);
      var end = _toMinutes(slot.endTime);
      if (end <= start) end += 24 * 60;
      return sum + (end - start);
    });
  }

  static double bookingDurationMinutes(DateTime start, DateTime end) {
    final minutes = end.difference(start).inSeconds / 60;
    return minutes < 0 ? 0 : minutes;
  }

  /// Converts confirmed-usage membership sessions (from the
  /// `get_membership_utilization_sessions` RPC — see
  /// supabase/migrations/0015_membership_utilization.sql) into
  /// synthetic booking-shaped entries so they merge into
  /// [computeUtilization]/[buildTodaysSchedule] exactly like a real booking,
  /// rather than a second utilization algorithm. Mirrors
  /// src/features/dashboard/summary.ts's `toUtilizationBookings`.
  ///
  /// A session occupies its court for its full duration exactly once if it
  /// has at least one CONFIRMED member-or-guest slot booking — never
  /// multiplied by headcount, since the RPC already dedupes to one row per
  /// session with any confirmed booking. A session with zero confirmed
  /// bookings never appears in the RPC's result set, so it contributes zero
  /// occupied time (allocation is not usage).
  static List<({String playingAreaId, DateTime startTime, DateTime endTime, String status})> toUtilizationBookings(
    List<({String courtId, String sessionDate, String startTime, String endTime})> sessions,
  ) {
    return sessions.map((s) {
      return (
        playingAreaId: s.courtId,
        startTime: DateTime.parse('${s.sessionDate}T${s.startTime}'),
        endTime: DateTime.parse('${s.sessionDate}T${s.endTime}'),
        status: 'confirmed',
      );
    }).toList();
  }

  static int computeUtilizationPercent(double bookedMinutes, double availableMinutes) {
    if (availableMinutes <= 0) return 0;
    final percent = (bookedMinutes / availableMinutes) * 100;
    return percent > 100 ? 100 : percent.round();
  }

  static List<DateTime> _datesInRange(DateRange period) {
    final dates = <DateTime>[];
    var cursor = _startOfDay(period.from);
    final end = _startOfDay(period.to);
    while (cursor.isBefore(end)) {
      dates.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return dates;
  }

  static UtilizationSummary computeUtilization({
    required List<({String id, String name, String facilitySportId})> playingAreas,
    required List<({String id, String sportId})> facilitySports,
    required List<({String id, String name})> sports,
    required List<OperatingDay> facilityOperatingDays,
    required List<({String playingAreaId, DateTime startTime, DateTime endTime, String status})> bookings,
    required DateRange period,
  }) {
    final availableMinutesPerCourt = _datesInRange(period).fold<double>(0, (sum, date) {
      final dow = date.weekday % 7; // Dart: Mon=1..Sun=7 -> convert to Sun=0..Sat=6
      OperatingDay? day;
      for (final d in facilityOperatingDays) {
        if (d.dayOfWeek == dow) {
          day = d;
          break;
        }
      }
      return sum + (day != null ? operatingMinutesForDay(day) : 0);
    });

    final bookedMinutesByArea = <String, double>{};
    for (final booking in bookings) {
      if (booking.status == 'cancelled') continue;
      final minutes = bookingDurationMinutes(booking.startTime, booking.endTime);
      bookedMinutesByArea[booking.playingAreaId] =
          (bookedMinutesByArea[booking.playingAreaId] ?? 0) + minutes;
    }

    final totalAvailable = availableMinutesPerCourt * playingAreas.length;
    final totalBooked = bookedMinutesByArea.values.fold<double>(0, (a, b) => a + b);
    final overallPercent = computeUtilizationPercent(totalBooked, totalAvailable);

    final bySport = facilitySports.map((fs) {
      final sport = sports.where((s) => s.id == fs.sportId).firstOrNull;
      final areasForSport = playingAreas.where((a) => a.facilitySportId == fs.id).toList();
      final courts = areasForSport
          .map(
            (area) => CourtUtilization(
              playingAreaId: area.id,
              playingAreaName: area.name,
              utilizationPercent: computeUtilizationPercent(
                bookedMinutesByArea[area.id] ?? 0,
                availableMinutesPerCourt,
              ),
            ),
          )
          .toList();
      final sportAvailable = availableMinutesPerCourt * areasForSport.length;
      final sportBooked = areasForSport.fold<double>(
        0,
        (sum, a) => sum + (bookedMinutesByArea[a.id] ?? 0),
      );
      return SportUtilization(
        facilitySportId: fs.id,
        sportName: sport?.name ?? 'Sport',
        utilizationPercent: computeUtilizationPercent(sportBooked, sportAvailable),
        courts: courts,
      );
    }).toList();

    return UtilizationSummary(overallPercent: overallPercent, bySport: bySport);
  }

  static String _formatSlotTime(String time24) {
    final parts = time24.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    final meridiem = h < 12 ? 'AM' : 'PM';
    return '${hour12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $meridiem';
  }

  /// One row per (playing area × operating slot) for today — real, derived
  /// from actual operating hours + actual bookings.
  static List<ScheduleEntry> buildTodaysSchedule({
    required List<({String id, String name, String facilitySportId})> playingAreas,
    required List<({String id, String sportId})> facilitySports,
    required List<({String id, String name})> sports,
    required List<OperatingDay> facilityOperatingDays,
    required List<({String playingAreaId, DateTime startTime, DateTime endTime, String status})> bookings,
    required DateTime now,
  }) {
    final todayDow = now.weekday % 7;
    OperatingDay? todayDay;
    for (final d in facilityOperatingDays) {
      if (d.dayOfWeek == todayDow) {
        todayDay = d;
        break;
      }
    }
    if (todayDay == null || todayDay.isClosed || todayDay.slots.isEmpty) return const [];

    final activeBookings = bookings.where((b) => b.status != 'cancelled').toList();
    final entries = <ScheduleEntry>[];

    for (final area in playingAreas) {
      final facilitySport = facilitySports.where((fs) => fs.id == area.facilitySportId).firstOrNull;
      final sport = sports.where((s) => s.id == facilitySport?.sportId).firstOrNull;

      for (final slot in todayDay.slots) {
        final slotStart = _toMinutes(slot.startTime);
        var slotEnd = _toMinutes(slot.endTime);
        if (slotEnd <= slotStart) slotEnd += 24 * 60;

        final isBooked = activeBookings.any((b) {
          if (b.playingAreaId != area.id) return false;
          if (b.startTime.weekday % 7 != todayDow) return false;
          final bStart = b.startTime.hour * 60 + b.startTime.minute;
          var bEnd = b.endTime.hour * 60 + b.endTime.minute;
          if (bEnd <= bStart) bEnd += 24 * 60;
          return bStart < slotEnd && slotStart < bEnd;
        });

        entries.add(
          ScheduleEntry(
            time: _formatSlotTime(slot.startTime),
            sportName: sport?.name ?? 'Sport',
            playingAreaName: area.name,
            status: isBooked ? ScheduleSlotStatus.booked : ScheduleSlotStatus.available,
          ),
        );
      }
    }

    entries.sort((a, b) => a.time.compareTo(b.time));
    return entries;
  }

  static MembershipSummary summarizeMemberships(
    List<({String status, DateTime endDate, DateTime createdAt})> memberships,
    DateTime now,
  ) {
    final soon = _startOfDay(now).add(const Duration(days: 7));
    final monthStart = DateTime(now.year, now.month, 1);

    var active = 0, expiringSoon = 0, expired = 0, newThisMonth = 0;
    for (final m in memberships) {
      if (m.status == 'active') {
        active++;
        if (!m.endDate.isAfter(soon)) expiringSoon++;
      }
      if (m.status == 'expired') expired++;
      if (!m.createdAt.isBefore(monthStart)) newThisMonth++;
    }
    return MembershipSummary(
      active: active,
      expiringSoon: expiringSoon,
      expired: expired,
      newThisMonth: newThisMonth,
    );
  }

  static PaymentSummary summarizePayments(List<({String status, int amountInr})> payments) {
    var collected = 0, pending = 0, refunds = 0;
    for (final p in payments) {
      if (p.status == 'paid') collected += p.amountInr;
      if (p.status == 'created') pending += p.amountInr;
      if (p.status == 'refunded') refunds += p.amountInr;
    }
    return PaymentSummary(collectedInr: collected, pendingInr: pending, refundsInr: refunds);
  }

  static List<AttentionItem> buildAttentionItems({
    required int membershipsExpiringSoon,
    required int paymentsPendingInr,
  }) {
    final items = <AttentionItem>[];
    if (membershipsExpiringSoon > 0) {
      items.add(
        AttentionItem(
          id: 'memberships-expiring',
          message:
              '$membershipsExpiringSoon membership${membershipsExpiringSoon == 1 ? '' : 's'} expiring soon.',
        ),
      );
    }
    if (paymentsPendingInr > 0) {
      items.add(
        AttentionItem(id: 'payments-pending', message: '₹$paymentsPendingInr in payments pending.'),
      );
    }
    return items;
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}