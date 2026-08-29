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

  static String _formatClock(int minuteOfDay) {
    final wrapped = ((minuteOfDay % 1440) + 1440) % 1440;
    final h = wrapped ~/ 60;
    final m = wrapped % 60;
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    final meridiem = h < 12 ? 'AM' : 'PM';
    return '$hour12:${m.toString().padLeft(2, '0')} $meridiem';
  }

  /// "5:00 – 6:00 PM" when both ends share a meridiem, else "11:30 AM – 1:00 PM".
  static String _formatTimeRange(int startMinute, int endMinute) {
    final sh = ((((startMinute % 1440) + 1440) % 1440)) ~/ 60;
    final eh = ((((endMinute % 1440) + 1440) % 1440)) ~/ 60;
    final sameMeridiem = (sh < 12) == (eh < 12);
    final start = sameMeridiem
        ? _formatClock(startMinute).replaceAll(RegExp(r' (AM|PM)$'), '')
        : _formatClock(startMinute);
    return '$start – ${_formatClock(endMinute)}';
  }

  /// Greedy lane assignment so overlapping blocks in one court sit side by side.
  static List<int> _packLanes(List<({int startMinute, int endMinute})> blocks) {
    final laneEnds = <int>[];
    final lanes = List<int>.filled(blocks.length, 0);
    final order = List<int>.generate(blocks.length, (i) => i)
      ..sort((a, b) => blocks[a].startMinute.compareTo(blocks[b].startMinute));
    for (final i in order) {
      final b = blocks[i];
      var lane = laneEnds.indexWhere((end) => end <= b.startMinute);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(b.endMinute);
      } else {
        laneEnds[lane] = b.endMinute;
      }
      lanes[i] = lane;
    }
    return lanes;
  }

  /// A positioned, court-by-court view of today's activity — one row per
  /// playing area (already sport-filtered by the caller), each block a real
  /// non-cancelled booking or a confirmed membership session, positioned by
  /// its actual local start/end within a window from today's real operating
  /// hours. Mirrors src/features/dashboard/summary.ts `buildScheduleTimeline`.
  static ScheduleTimeline buildScheduleTimeline({
    required List<({String id, String name, String facilitySportId})> playingAreas,
    required List<({String id, String sportId})> facilitySports,
    required List<({String id, String name})> sports,
    required List<OperatingDay> facilityOperatingDays,
    required List<
            ({
              String id,
              String playingAreaId,
              DateTime startTime,
              DateTime endTime,
              String status,
              ScheduleBlockType type,
              String label,
            })>
        bookings,
    required DateTime now,
  }) {
    if (playingAreas.isEmpty) {
      return const ScheduleTimeline(startHour: 0, endHour: 0, courts: []);
    }

    final todayDow = now.weekday % 7;
    OperatingDay? todayDay;
    for (final d in facilityOperatingDays) {
      if (d.dayOfWeek == todayDow) {
        todayDay = d;
        break;
      }
    }

    final areaIds = playingAreas.map((a) => a.id).toSet();
    final activeBookings =
        bookings.where((b) => b.status != 'cancelled' && areaIds.contains(b.playingAreaId)).toList();

    // Each of today's blocks as an absolute local minute-of-day span.
    final blockSpans =
        <({String id, String playingAreaId, String label, ScheduleBlockType type, int startMin, int endMin})>[];
    for (final b in activeBookings) {
      if (b.startTime.weekday % 7 != todayDow) continue;
      final startMin = b.startTime.hour * 60 + b.startTime.minute;
      var endMin = b.endTime.hour * 60 + b.endTime.minute;
      if (endMin <= startMin) endMin += 1440;
      blockSpans.add((
        id: b.id,
        playingAreaId: b.playingAreaId,
        label: b.label,
        type: b.type,
        startMin: startMin,
        endMin: endMin,
      ));
    }

    // Base window: operating hours if present, else the bookings' span, else a default day.
    const defaultStartHour = 6;
    const defaultEndHour = 22;
    final hasOperatingHours =
        todayDay != null && !todayDay.isClosed && (todayDay.is24Hours || todayDay.slots.isNotEmpty);
    int windowStart;
    int windowEnd;
    if (hasOperatingHours && todayDay.is24Hours) {
      windowStart = 0;
      windowEnd = 1440;
    } else if (hasOperatingHours) {
      windowStart = 1440;
      windowEnd = 0;
      for (final slot in todayDay.slots) {
        final start = _toMinutes(slot.startTime);
        var end = _toMinutes(slot.endTime);
        if (end <= start) end += 1440;
        if (start < windowStart) windowStart = start;
        if (end > windowEnd) windowEnd = end;
      }
    } else if (blockSpans.isNotEmpty) {
      windowStart = blockSpans.map((b) => b.startMin).reduce((a, b) => a < b ? a : b);
      windowEnd = blockSpans.map((b) => b.endMin).reduce((a, b) => a > b ? a : b);
    } else {
      windowStart = defaultStartHour * 60;
      windowEnd = defaultEndHour * 60;
    }

    // Extend the axis so a booking outside operating hours is still visible.
    for (final b in blockSpans) {
      if (b.startMin < windowStart) windowStart = b.startMin;
      if (b.endMin > windowEnd) windowEnd = b.endMin;
    }

    var startHour = windowStart ~/ 60;
    var endHour = (windowEnd / 60).ceil().toInt();
    const minSpanHours = 6;
    if (endHour - startHour < minSpanHours) {
      final pad = minSpanHours - (endHour - startHour);
      startHour = (startHour - pad ~/ 2).clamp(0, 24);
      endHour = startHour + minSpanHours;
    }
    if (endHour > 30) endHour = 30;
    final winStartMin = startHour * 60;
    final winEndMin = endHour * 60;

    final courts = playingAreas.map((area) {
      final facilitySport = facilitySports.where((fs) => fs.id == area.facilitySportId).firstOrNull;
      final sport = sports.where((s) => s.id == facilitySport?.sportId).firstOrNull;

      final raw = <({String id, String label, ScheduleBlockType type, int startMinute, int endMinute, String timeLabel})>[];
      for (final b in blockSpans) {
        if (b.playingAreaId != area.id) continue;
        final timeLabel = _formatTimeRange(b.startMin, b.endMin);
        final startMin = b.startMin < winStartMin ? winStartMin : b.startMin;
        final endMin = b.endMin > winEndMin ? winEndMin : b.endMin;
        if (endMin <= startMin) continue;
        raw.add((id: b.id, label: b.label, type: b.type, startMinute: startMin, endMinute: endMin, timeLabel: timeLabel));
      }
      raw.sort((a, b) => a.startMinute.compareTo(b.startMinute));

      final lanes = _packLanes(raw.map((r) => (startMinute: r.startMinute, endMinute: r.endMinute)).toList());
      final blocks = <ScheduleBlock>[
        for (var i = 0; i < raw.length; i++)
          ScheduleBlock(
            id: raw[i].id,
            label: raw[i].label,
            startMinute: raw[i].startMinute,
            endMinute: raw[i].endMinute,
            timeLabel: raw[i].timeLabel,
            type: raw[i].type,
            lane: lanes[i],
          ),
      ];
      final laneCount = blocks.fold<int>(1, (max, b) => b.lane + 1 > max ? b.lane + 1 : max);

      return ScheduleCourtRow(
        courtId: area.id,
        courtName: area.name,
        sportName: sport?.name ?? 'Sport',
        laneCount: laneCount,
        blocks: blocks,
      );
    }).toList()
      ..sort((a, b) => a.courtName.compareTo(b.courtName));

    return ScheduleTimeline(startHour: startHour, endHour: endHour, courts: courts);
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

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// One bucket per calendar date in the period, summing paid revenue whose
  /// `createdAt` lands on that day (local). Mirrors
  /// src/features/dashboard/summary.ts `buildRevenueTrend` — derived from
  /// payments already fetched for the KPIs, no extra query.
  static List<RevenueTrendPoint> buildRevenueTrend(
    List<({String status, int amountInr, DateTime createdAt})> payments,
    DateRange period,
  ) {
    final byDay = <String, int>{};
    for (final p in payments) {
      if (p.status != 'paid') continue;
      final key = _dayKey(_startOfDay(p.createdAt));
      byDay[key] = (byDay[key] ?? 0) + p.amountInr;
    }
    return _datesInRange(period)
        .map((d) => RevenueTrendPoint(date: _dayKey(d), amountInr: byDay[_dayKey(d)] ?? 0))
        .toList();
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Revenue for one calendar month plus the day-by-day series to plot it.
  /// [payments] must cover at least the previous month through the selected
  /// month. The series is always one point per day (zero-filled). Mirrors
  /// src/features/dashboard/summary.ts `buildRevenueOverview`.
  static RevenueOverview buildRevenueOverview(
    List<({String status, int amountInr, DateTime createdAt, String? bookingId, String? membershipId})> payments,
    DateTime now,
    int monthOffset,
  ) {
    final monthStart = DateTime(now.year, now.month - monthOffset, 1);
    final monthEnd = DateTime(now.year, now.month - monthOffset + 1, 1);
    final prevMonthStart = DateTime(now.year, now.month - monthOffset - 1, 1);

    Iterable<({String status, int amountInr, DateTime createdAt, String? bookingId, String? membershipId})>
        paidBetween(DateTime from, DateTime to) => payments.where(
              (p) => p.status == 'paid' && !p.createdAt.isBefore(from) && p.createdAt.isBefore(to),
            );

    final monthPaid = paidBetween(monthStart, monthEnd).toList();
    final totalInr = monthPaid.fold<int>(0, (sum, p) => sum + p.amountInr);
    final prevTotal = paidBetween(prevMonthStart, monthStart).fold<int>(0, (sum, p) => sum + p.amountInr);
    final changePercent = prevTotal == 0 ? null : ((totalInr - prevTotal) / prevTotal) * 100;

    final points = buildRevenueTrend(
      payments.map((p) => (status: p.status, amountInr: p.amountInr, createdAt: p.createdAt)).toList(),
      DateRange(from: monthStart, to: monthEnd),
    );

    var bookingCount = 0, bookingInr = 0, membershipCount = 0, membershipInr = 0, otherCount = 0, otherInr = 0;
    for (final p in monthPaid) {
      if (p.membershipId != null) {
        membershipCount++;
        membershipInr += p.amountInr;
      } else if (p.bookingId != null) {
        bookingCount++;
        bookingInr += p.amountInr;
      } else {
        otherCount++;
        otherInr += p.amountInr;
      }
    }

    return RevenueOverview(
      monthLabel: '${_monthNames[monthStart.month - 1]} ${monthStart.year}',
      totalInr: totalInr,
      changePercent: changePercent?.toDouble(),
      points: points,
      breakdown: [
        RevenueBreakdownSegment(
          key: RevenueBreakdownKey.bookings,
          label: 'Bookings',
          amountInr: bookingInr,
          count: bookingCount,
          unavailable: false,
        ),
        RevenueBreakdownSegment(
          key: RevenueBreakdownKey.memberships,
          label: 'Memberships',
          amountInr: membershipInr,
          count: membershipCount,
          unavailable: false,
        ),
        const RevenueBreakdownSegment(
          key: RevenueBreakdownKey.coaching,
          label: 'Coaching',
          amountInr: 0,
          count: null,
          unavailable: true,
        ),
        RevenueBreakdownSegment(
          key: RevenueBreakdownKey.other,
          label: 'Other',
          amountInr: otherInr,
          count: otherCount == 0 ? null : otherCount,
          unavailable: otherInr == 0,
        ),
      ],
    );
  }

  /// Paid revenue in whole rupees. When [sportScope] is given, a payment
  /// counts only if it's for a booking on the sport's courts or a membership
  /// enrolled in one of that sport's batches. Mirrors
  /// src/features/dashboard/summary.ts `sumPaidRevenueInr`.
  static int sumPaidRevenueInr(
    List<({String status, int amountInr, String? bookingId, String? membershipId})> payments,
    ({Set<String> bookingIds, Set<String> membershipIds})? sportScope,
  ) {
    var total = 0;
    for (final p in payments) {
      if (p.status != 'paid') continue;
      if (sportScope != null) {
        final inScope = (p.bookingId != null && sportScope.bookingIds.contains(p.bookingId)) ||
            (p.membershipId != null && sportScope.membershipIds.contains(p.membershipId));
        if (!inScope) continue;
      }
      total += p.amountInr;
    }
    return total;
  }

  /// Count of memberships active as of now. [restrictToIds] (batch-derived)
  /// narrows to a single sport.
  static int countActiveMemberships(
    List<({String id, String status})> memberships,
    Set<String>? restrictToIds,
  ) {
    return memberships
        .where((m) => m.status == 'active' && (restrictToIds == null || restrictToIds.contains(m.id)))
        .length;
  }

  /// Guest bookings that are both booked (not cancelled) and paid. Caller
  /// pre-filters by court and period.
  static int countPaidGuestBookings(
    List<({String customerType, String paymentStatus, String status})> bookings,
  ) {
    return bookings
        .where((b) => b.customerType == 'GUEST' && b.paymentStatus == 'PAID' && b.status != 'cancelled')
        .length;
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