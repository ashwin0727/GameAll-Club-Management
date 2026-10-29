import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../../features/dashboard/dashboard_calculator.dart';
import '../models/dashboard.dart';
import '../models/facility.dart';
import '../models/playing_area.dart';
import 'operating_hours_repository.dart';
import 'playing_area_repository.dart';
import 'sports_repository.dart';

/// Mirrors src/services/dashboard/supabase-dashboard.service.ts — same
/// facility-scoped reads of `bookings`/`memberships`/`payments` (the old
/// web dashboard queried these with NO facility filter at all, a
/// cross-tenant bug already fixed there; this mobile implementation never
/// repeats it), same "what's genuinely unavailable stays unavailable"
/// discipline for revenue-by-sport/guests/expenses/live-activity.
class DashboardRepository {
  DashboardRepository(
    this._client,
    this._sportsRepo,
    this._playingAreaRepo,
    this._operatingHoursRepo,
  );

  final SupabaseClient _client;
  final SportsRepository _sportsRepo;
  final PlayingAreaRepository _playingAreaRepo;
  final OperatingHoursRepository _operatingHoursRepo;

  /// Takes the already-resolved [facility] (not just its id) so the caller's
  /// existing facility fetch (e.g. SessionController's cache) can be reused
  /// instead of this repository fetching it again internally.
  ///
  /// Every period total (payments, memberships, booked court time, the revenue chart) is added up by the database
  /// (migrations 0165 and 0166), so the phone downloads only today's bookings for the schedule. If those migrations are not
  /// applied yet, each total falls back to downloading the rows and adding them up here, as before.
  Future<DashboardSummary> getDashboardSummary(
    Facility facility, {
    String? facilitySportId,
    required DateRangePreset preset,
    int revenueMonthOffset = 0,
  }) async {
    final facilityId = facility.id;
    final now = DateTime.now();
    final period = DashboardCalculator.resolveDateRange(preset, now);

    final facilitySportsAllFuture = _sportsRepo.getFacilitySports(facilityId);
    final sportsFuture = _sportsRepo.getActiveSports();
    final playingAreasAllFuture = _playingAreaRepo.getPlayingAreas(facilityId);
    final scheduleFuture = _operatingHoursRepo.getFacilitySchedule(facilityId);

    final facilitySportsAll = await facilitySportsAllFuture;
    final sports = await sportsFuture;
    final playingAreasAll = await playingAreasAllFuture;
    final schedule = await scheduleFuture;

    final facilitySports = facilitySportId == null
        ? facilitySportsAll
        : facilitySportsAll.where((fs) => fs.id == facilitySportId).toList();
    final playingAreas = facilitySportId == null
        ? playingAreasAll
        : playingAreasAll.where((a) => a.facilitySportId == facilitySportId).toList();
    final playingAreaIds = playingAreas.map((a) => a.id).toSet();
    final courtIds = playingAreaIds.toList();

    // Only today's rows are downloaded (for the Today's Schedule panel).
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day + 1);
    final todayKey = _dateKey(dayStart);

    try {
      final fetched = await Future.wait<dynamic>([
        _fetchTotals(facilityId: facilityId, period: period, courtIds: courtIds, sportId: facilitySportId, now: now),
        _fetchBookedMinutes(facilityId: facilityId, period: period, courtIds: courtIds),
        _fetchRevenueOverview(
          facilityId: facilityId,
          now: now,
          monthOffset: revenueMonthOffset,
          sportId: facilitySportId,
          playingAreasAll: playingAreasAll,
        ),
        _client
            .from('bookings')
            .select('id, court_id, start_time, end_time, status, customer_type, guest_name, member_id, payment_status')
            .eq('facility_id', facilityId)
            .gte('start_time', dayStart.toUtc().toIso8601String())
            .lt('start_time', dayEnd.toUtc().toIso8601String()),
        // Actual usage of a membership-protected slot occupies court-time exactly like a regular booking, and belongs on
        // today's timeline. See 0015_membership_utilization.sql.
        _client.rpc(
          'get_membership_utilization_sessions',
          params: {'p_facility_id': facilityId, 'p_from': todayKey, 'p_to': _dateKey(dayEnd)},
        ),
      ]);
      final totals = fetched[0] as _Totals;
      final minutes = fetched[1] as _BookedMinutes;
      final revenueOverview = fetched[2] as RevenueOverview;
      final todayBookingMaps = (fetched[3] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((b) => playingAreaIds.contains(b['court_id']))
          .toList();
      final membershipSessionRows = (fetched[4] as List<dynamic>).cast<Map<String, dynamic>>();

      final utilizationPlayingAreas = playingAreas
          .map((a) => (id: a.id, name: a.name, facilitySportId: a.facilitySportId))
          .toList();
      final utilizationFacilitySports = facilitySports
          .map((fs) => (id: fs.id, sportId: fs.sportId))
          .toList();
      final utilizationSports = sports.map((s) => (id: s.id, name: s.name)).toList();
      final operatingDays = schedule?.days ?? const [];

      final currentUtilization = DashboardCalculator.computeUtilization(
        playingAreas: utilizationPlayingAreas,
        facilitySports: utilizationFacilitySports,
        sports: utilizationSports,
        facilityOperatingDays: operatingDays,
        bookings: const [],
        bookedMinutesByArea: minutes.current,
        period: period.current,
      );
      final previousUtilization = period.previous == null
          ? null
          : DashboardCalculator.computeUtilization(
              playingAreas: utilizationPlayingAreas,
              facilitySports: utilizationFacilitySports,
              sports: utilizationSports,
              facilityOperatingDays: operatingDays,
              bookings: const [],
              bookedMinutesByArea: minutes.previous,
              period: period.previous!,
            );

      final memberships = totals.memberships;

      // "Today's Schedule" timeline — member names need a profiles lookup
      // (bookings carry only member_id); guests carry their own name.
      final memberIds = todayBookingMaps
          .map((b) => b['member_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final memberNames = <String, String>{};
      if (memberIds.isNotEmpty) {
        final profileRows = await _client.from('profiles').select('id, full_name').inFilter('id', memberIds);
        for (final p in (profileRows as List<dynamic>).cast<Map<String, dynamic>>()) {
          memberNames[p['id'] as String] = p['full_name'] as String;
        }
      }

      // What else is on a court today. A membership batch holds its court at its time for its members whether or not a
      // slot booking has been materialised yet, and a coaching session holds its court too — so both belong on the
      // timeline (and in "On Court Now"), not just bookings and booked membership slots.
      final extraBlocks = await _todaysMembershipAndCoachingBlocks(
        facilityId: facilityId,
        now: now,
        todayKey: todayKey,
        playingAreaIds: playingAreaIds,
        alreadyShown: membershipSessionRows
            .where((s) => s['session_date'] == todayKey)
            .map((s) => '${s['court_id']}|${s['start_time']}|${s['end_time']}')
            .toSet(),
      );

      final timelineBookings =
          <({String id, String playingAreaId, DateTime startTime, DateTime endTime, String status, ScheduleBlockType type, String label})>[
        ...todayBookingMaps.map((b) {
          final isGuest = b['customer_type'] == 'GUEST';
          final memberId = b['member_id'] as String?;
          return (
            id: b['id'] as String,
            playingAreaId: b['court_id'] as String,
            // Supabase returns timestamptz in UTC — the schedule window and
            // the "now" line are local, so these must be too.
            startTime: DateTime.parse(b['start_time'] as String).toLocal(),
            endTime: DateTime.parse(b['end_time'] as String).toLocal(),
            status: b['status'] as String,
            type: isGuest ? ScheduleBlockType.guest : ScheduleBlockType.member,
            label: isGuest
                ? (b['guest_name'] as String? ?? 'Guest booking')
                : (memberId != null ? memberNames[memberId] ?? 'Member booking' : 'Member booking'),
          );
        }),
        ...membershipSessionRows
            .where((s) => playingAreaIds.contains(s['court_id']))
            .toList()
            .asMap()
            .entries
            .map(
              (e) => (
                id: 'session-${e.key}',
                playingAreaId: e.value['court_id'] as String,
                startTime: DateTime.parse('${e.value['session_date']}T${e.value['start_time']}'),
                endTime: DateTime.parse('${e.value['session_date']}T${e.value['end_time']}'),
                status: 'confirmed',
                type: ScheduleBlockType.session,
                label: 'Membership Session',
              ),
            ),
        ...extraBlocks,
      ];

      final scheduleTimeline = DashboardCalculator.buildScheduleTimeline(
        playingAreas: utilizationPlayingAreas,
        facilitySports: utilizationFacilitySports,
        sports: utilizationSports,
        facilityOperatingDays: operatingDays,
        bookings: timelineBookings,
        now: now,
      );

      return DashboardSummary(
        facilityName: facility.name,
        facilityCity: facility.address.city,
        sports: facilitySportsAll.map((fs) {
          final sport = sports.where((s) => s.id == fs.sportId).firstOrNullSafe;
          return AvailableSportOption(
            facilitySportId: fs.id,
            sportName: fs.customSportName ?? sport?.name ?? 'Sport',
            sportIcon: sport?.icon ?? '🏅',
          );
        }).toList(),
        selectedFacilitySportId: facilitySportId,
        kpis: DashboardKpis(
          revenueInr: DashboardCalculator.computeKpiValue(
            totals.payments.collectedInr,
            period.previous == null ? null : totals.previousCollectedInr,
          ),
          activeMemberships: DashboardCalculator.computeKpiValue(totals.activeMembershipsInScope, null),
          totalBookings: DashboardCalculator.computeKpiValue(
            totals.bookings,
            period.previous == null ? null : totals.previousBookings,
          ),
          utilizationPercent: DashboardCalculator.computeKpiValue(
            currentUtilization.overallPercent,
            previousUtilization?.overallPercent,
          ),
        ),
        utilization: currentUtilization,
        scheduleTimeline: scheduleTimeline,
        revenueOverview: revenueOverview,
        memberships: memberships,
        payments: totals.payments,
        attentionItems: DashboardCalculator.buildAttentionItems(
          membershipsExpiringSoon: memberships.expiringSoon,
          paymentsPendingInr: totals.payments.pendingInr,
        ),
      );
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _iso(DateTime d) => d.toUtc().toIso8601String();
  static bool _functionMissing(PostgrestException e) => e.code == 'PGRST202' || e.code == '42883';

  /// Payment, booking and membership totals for the KPI cards and panels.
  Future<_Totals> _fetchTotals({
    required String facilityId,
    required ResolvedPeriod period,
    required List<String> courtIds,
    required String? sportId,
    required DateTime now,
  }) async {
    final prev = period.previous;
    // "Expiring soon" = an active membership whose end date is within a week. End dates are plain dates, so compare them
    // against the date a week from now (as a UTC midnight, which is how the database reads a date).
    final soonDate = DateTime(now.year, now.month, now.day + 7);
    try {
      final r = await Future.wait<dynamic>([
        _client.rpc('dashboard_totals', params: {
          'p_facility_id': facilityId,
          'p_cur_from': _iso(period.current.from),
          'p_cur_to': _iso(period.current.to),
          'p_prev_from': prev == null ? null : _iso(prev.from),
          'p_prev_to': prev == null ? null : _iso(prev.to),
          'p_court_ids': courtIds,
          'p_facility_sport_ids': sportId == null ? null : [sportId],
          'p_soon': DateTime.utc(soonDate.year, soonDate.month, soonDate.day).toIso8601String(),
          'p_month_start': _iso(DateTime(now.year, now.month, 1)),
        }),
        _client.rpc('dashboard_booking_counts', params: {
          'p_facility_id': facilityId,
          'p_cur_from': _iso(period.current.from),
          'p_cur_to': _iso(period.current.to),
          'p_prev_from': prev == null ? null : _iso(prev.from),
          'p_prev_to': prev == null ? null : _iso(prev.to),
          'p_court_ids': courtIds,
        }),
      ]);
      final t = Map<String, dynamic>.from(r[0] as Map);
      final c = Map<String, dynamic>.from(r[1] as Map);
      final m = Map<String, dynamic>.from(t['memberships'] as Map);
      int n(dynamic v) => (v as num).toInt();
      return _Totals(
        payments: PaymentSummary(collectedInr: n(t['collectedInr']), pendingInr: n(t['pendingInr']), refundsInr: n(t['refundsInr'])),
        previousCollectedInr: n(t['previousCollectedInr']),
        bookings: n(c['current']),
        previousBookings: n(c['previous']),
        activeMembershipsInScope: n(t['activeMembershipsInScope']),
        memberships: MembershipSummary(
          active: n(m['active']),
          expiringSoon: n(m['expiringSoon']),
          expired: n(m['expired']),
          newThisMonth: n(m['newThisMonth']),
        ),
      );
    } on PostgrestException catch (e) {
      if (!_functionMissing(e)) rethrow;
    }
    return _legacyTotals(facilityId: facilityId, period: period, courtIds: courtIds, sportId: sportId, now: now);
  }

  /// The totals added up on the phone from downloaded rows (used until migration 0165 is applied).
  Future<_Totals> _legacyTotals({
    required String facilityId,
    required ResolvedPeriod period,
    required List<String> courtIds,
    required String? sportId,
    required DateTime now,
  }) async {
    final earliestFrom = (period.previous ?? period.current).from;
    final courts = courtIds.toSet();
    final results = await Future.wait<dynamic>([
      _client
          .from('bookings')
          .select('id, court_id, start_time, status, customer_type, payment_status')
          .eq('facility_id', facilityId)
          .gte('start_time', _iso(earliestFrom))
          .lt('start_time', _iso(period.current.to)),
      _client.from('memberships').select('id, status, end_date, created_at').eq('facility_id', facilityId),
      _client
          .from('payments')
          .select('status, amount_inr, created_at, booking_id, membership_id')
          .eq('facility_id', facilityId)
          .gte('created_at', _iso(earliestFrom))
          .lt('created_at', _iso(period.current.to)),
    ]);
    final bookingRows =
        (results[0] as List<dynamic>).cast<Map<String, dynamic>>().where((b) => courts.contains(b['court_id'])).toList();
    final membershipMaps = (results[1] as List<dynamic>).cast<Map<String, dynamic>>();
    final paymentMaps = (results[2] as List<dynamic>).cast<Map<String, dynamic>>();

    Set<String>? sportMembershipIds;
    ({Set<String> bookingIds, Set<String> membershipIds})? scope;
    if (sportId != null) {
      final batchRows = (await _client
              .from('membership_batches')
              .select('id')
              .eq('facility_id', facilityId)
              .eq('facility_sport_id', sportId) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final batchIds = batchRows.map((b) => b['id'] as String).toList();
      sportMembershipIds = <String>{};
      if (batchIds.isNotEmpty) {
        final memberRows = (await _client.from('membership_batch_members').select('membership_id').inFilter('batch_id', batchIds)
                as List<dynamic>)
            .cast<Map<String, dynamic>>();
        for (final m in memberRows) {
          if (m['membership_id'] != null) sportMembershipIds.add(m['membership_id'] as String);
        }
      }
      scope = (bookingIds: {for (final b in bookingRows) b['id'] as String}, membershipIds: sportMembershipIds);
    }

    bool inWindow(DateTime t, DateRange w) => !t.isBefore(w.from) && t.isBefore(w.to);
    List<({String status, int amountInr, String? bookingId, String? membershipId})> paymentsIn(DateRange w) => paymentMaps
        .where((p) => inWindow(DateTime.parse(p['created_at'] as String), w))
        .map((p) => (
              status: p['status'] as String,
              amountInr: p['amount_inr'] as int,
              bookingId: p['booking_id'] as String?,
              membershipId: p['membership_id'] as String?,
            ))
        .where((p) =>
            scope == null ||
            (p.bookingId != null && scope.bookingIds.contains(p.bookingId)) ||
            (p.membershipId != null && scope.membershipIds.contains(p.membershipId)))
        .toList();
    int bookingsIn(DateRange w) => bookingRows
        .where((b) => inWindow(DateTime.parse(b['start_time'] as String), w) && b['status'] != 'cancelled')
        .length;

    final current = paymentsIn(period.current);
    final previous = period.previous == null ? null : paymentsIn(period.previous!);
    return _Totals(
      payments: DashboardCalculator.summarizePayments(current.map((p) => (status: p.status, amountInr: p.amountInr)).toList()),
      previousCollectedInr: previous == null ? 0 : DashboardCalculator.sumPaidRevenueInr(previous, null),
      bookings: bookingsIn(period.current),
      previousBookings: period.previous == null ? 0 : bookingsIn(period.previous!),
      activeMembershipsInScope: DashboardCalculator.countActiveMemberships(
        membershipMaps.map((m) => (id: m['id'] as String, status: m['status'] as String)).toList(),
        sportMembershipIds,
      ),
      memberships: DashboardCalculator.summarizeMemberships(
        membershipMaps
            .map((m) => (
                  status: m['status'] as String,
                  endDate: DateTime.parse(m['end_date'] as String),
                  createdAt: DateTime.parse(m['created_at'] as String),
                ))
            .toList(),
        now,
      ),
    );
  }

  /// Booked court time (minutes) per court for the current and previous period, from the database.
  Future<_BookedMinutes> _fetchBookedMinutes({
    required String facilityId,
    required ResolvedPeriod period,
    required List<String> courtIds,
  }) async {
    final prev = period.previous;
    try {
      final rows = await _client.rpc('dashboard_booked_minutes', params: {
        'p_facility_id': facilityId,
        'p_cur_from': _iso(period.current.from),
        'p_cur_to': _iso(period.current.to),
        'p_prev_from': prev == null ? null : _iso(prev.from),
        'p_prev_to': prev == null ? null : _iso(prev.to),
        'p_cur_from_date': _dateKey(period.current.from),
        'p_cur_to_date': _dateKey(period.current.to),
        'p_prev_from_date': prev == null ? null : _dateKey(prev.from),
        'p_prev_to_date': prev == null ? null : _dateKey(prev.to),
        'p_court_ids': courtIds,
      });
      final current = <String, double>{};
      final previous = <String, double>{};
      for (final r in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
        current[r['court_id'] as String] = (r['cur_minutes'] as num).toDouble();
        previous[r['court_id'] as String] = (r['prev_minutes'] as num).toDouble();
      }
      return _BookedMinutes(current, previous);
    } on PostgrestException catch (e) {
      if (!_functionMissing(e)) rethrow;
    }

    // Migration 0166 not applied yet: download the period's bookings and add them up here.
    final earliest = (prev ?? period.current).from;
    final courts = courtIds.toSet();
    final results = await Future.wait<dynamic>([
      _client
          .from('bookings')
          .select('court_id, start_time, end_time, status')
          .eq('facility_id', facilityId)
          .gte('start_time', _iso(earliest))
          .lt('start_time', _iso(period.current.to)),
      _client.rpc('get_membership_utilization_sessions', params: {
        'p_facility_id': facilityId,
        'p_from': _dateKey(earliest),
        'p_to': _dateKey(period.current.to),
      }),
    ]);
    final current = <String, double>{};
    final previous = <String, double>{};
    void add(Map<String, double> m, String court, double mins) => m[court] = (m[court] ?? 0) + mins;
    bool inWindow(DateTime t, DateRange w) => !t.isBefore(w.from) && t.isBefore(w.to);
    for (final b in (results[0] as List<dynamic>).cast<Map<String, dynamic>>()) {
      if (b['status'] == 'cancelled' || !courts.contains(b['court_id'])) continue;
      final start = DateTime.parse(b['start_time'] as String);
      final mins = DashboardCalculator.bookingDurationMinutes(start, DateTime.parse(b['end_time'] as String));
      if (inWindow(start, period.current)) {
        add(current, b['court_id'] as String, mins);
      } else if (prev != null && inWindow(start, prev)) {
        add(previous, b['court_id'] as String, mins);
      }
    }
    for (final s in (results[1] as List<dynamic>).cast<Map<String, dynamic>>()) {
      if (!courts.contains(s['court_id'])) continue;
      final mins = DashboardCalculator.bookingDurationMinutes(
        DateTime.parse('${s['session_date']}T${s['start_time']}'),
        DateTime.parse('${s['session_date']}T${s['end_time']}'),
      );
      final date = s['session_date'] as String;
      if (date.compareTo(_dateKey(period.current.from)) >= 0 && date.compareTo(_dateKey(period.current.to)) < 0) {
        add(current, s['court_id'] as String, mins);
      } else if (prev != null && date.compareTo(_dateKey(prev.from)) >= 0 && date.compareTo(_dateKey(prev.to)) < 0) {
        add(previous, s['court_id'] as String, mins);
      }
    }
    return _BookedMinutes(current, previous);
  }

  /// The Revenue Overview panel (its own month filter, independent of the period). Money actually received, dated the day
  /// it arrived and counted on the viewer's local calendar day.
  Future<RevenueOverview> _fetchRevenueOverview({
    required String facilityId,
    required DateTime now,
    required int monthOffset,
    required String? sportId,
    required List<PlayingArea> playingAreasAll,
  }) async {
    final monthStart = DateTime(now.year, now.month - monthOffset, 1);
    final monthEnd = DateTime(now.year, now.month - monthOffset + 1, 1);
    final prevStart = DateTime(now.year, now.month - monthOffset - 1, 1);
    try {
      final r = await _client.rpc('dashboard_revenue_overview', params: {
        'p_facility_id': facilityId,
        'p_month_start': _iso(monthStart),
        'p_month_end': _iso(monthEnd),
        'p_prev_start': _iso(prevStart),
        'p_tz': '',
        'p_facility_sport_ids': sportId == null ? null : [sportId],
        'p_utc_offset_minutes': now.timeZoneOffset.inMinutes,
      });
      final m = Map<String, dynamic>.from(r as Map);
      final b = Map<String, dynamic>.from(m['breakdown'] as Map);
      ({int count, int inr}) seg(String key) {
        final s = Map<String, dynamic>.from((b[key] ?? const {'count': 0, 'inr': 0}) as Map);
        return (count: (s['count'] as num).toInt(), inr: (s['inr'] as num).toInt());
      }

      return DashboardCalculator.buildRevenueOverviewFromTotals(
        totalInr: (m['totalInr'] as num).toInt(),
        previousTotalInr: (m['previousTotalInr'] as num).toInt(),
        byDay: {for (final e in Map<String, dynamic>.from(m['byDay'] as Map).entries) e.key: (e.value as num).toInt()},
        breakdown: {
          'bookings': seg('bookings'),
          'memberships': seg('memberships'),
          'coaching': seg('coaching'),
          'other': seg('other'),
        },
        now: now,
        monthOffset: monthOffset,
      );
    } on PostgrestException catch (e) {
      if (!_functionMissing(e)) rethrow;
    }

    // Migration 0166 not applied yet: download two months of payments and add them up here.
    final rows = (await _client
            .from('payments')
            .select('status, amount_inr, created_at, booking_id, membership_id, coaching_enrollment_id')
            .eq('facility_id', facilityId)
            .gte('created_at', _iso(prevStart))
            .lt('created_at', _iso(monthEnd)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    Set<String>? sportBookingIds;
    Set<String>? sportMembershipIds;
    if (sportId != null) {
      final courts = playingAreasAll.where((a) => a.facilitySportId == sportId).map((a) => a.id).toList();
      final bookingRows = courts.isEmpty
          ? <Map<String, dynamic>>[]
          : (await _client
                  .from('bookings')
                  .select('id')
                  .eq('facility_id', facilityId)
                  .inFilter('court_id', courts)
                  .gte('start_time', _iso(prevStart))
                  .lt('start_time', _iso(monthEnd)) as List<dynamic>)
              .cast<Map<String, dynamic>>();
      sportBookingIds = {for (final b in bookingRows) b['id'] as String};
      final batchIds = (await _client.from('membership_batches').select('id').eq('facility_id', facilityId).eq('facility_sport_id', sportId)
              as List<dynamic>)
          .map((b) => (b as Map)['id'] as String)
          .toList();
      sportMembershipIds = <String>{};
      if (batchIds.isNotEmpty) {
        final memberRows =
            (await _client.from('membership_batch_members').select('membership_id').inFilter('batch_id', batchIds) as List<dynamic>)
                .cast<Map<String, dynamic>>();
        for (final m in memberRows) {
          if (m['membership_id'] != null) sportMembershipIds.add(m['membership_id'] as String);
        }
      }
    }
    final payments = rows
        .where((p) {
          if (sportId == null) return true;
          final bid = p['booking_id'] as String?;
          final mid = p['membership_id'] as String?;
          return (bid != null && sportBookingIds!.contains(bid)) || (mid != null && sportMembershipIds!.contains(mid));
        })
        .map((p) => (
              status: p['status'] as String,
              amountInr: p['amount_inr'] as int,
              // Supabase hands back UTC — bucket by the LOCAL calendar day or a payment taken before 05:30 IST lands on yesterday.
              createdAt: DateTime.parse(p['created_at'] as String).toLocal(),
              bookingId: p['booking_id'] as String?,
              membershipId: p['membership_id'] as String?,
              coachingEnrollmentId: p['coaching_enrollment_id'] as String?,
            ))
        .toList();
    return DashboardCalculator.buildRevenueOverview(payments, now, monthOffset);
  }

  /// Today's active membership batches (with members, not blocked today) and today's coaching sessions, as timeline
  /// entries. Each read is best-effort: someone without access to coaching, say, simply sees no coaching blocks rather
  /// than losing the dashboard.
  Future<List<({String id, String playingAreaId, DateTime startTime, DateTime endTime, String status, ScheduleBlockType type, String label})>>
      _todaysMembershipAndCoachingBlocks({
    required String facilityId,
    required DateTime now,
    required String todayKey,
    required Set<String> playingAreaIds,
    required Set<String> alreadyShown,
  }) async {
    final out = <({String id, String playingAreaId, DateTime startTime, DateTime endTime, String status, ScheduleBlockType type, String label})>[];
    final dow = now.weekday % 7; // 0 = Sunday, as in the database

    try {
      final batchRows = (await _client
              .from('membership_batches')
              .select('id, court_id, name, days_of_week, start_time, end_time')
              .eq('facility_id', facilityId)
              .eq('is_active', true) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((b) => playingAreaIds.contains(b['court_id']) && ((b['days_of_week'] as List<dynamic>?) ?? const []).map((d) => (d as num).toInt()).contains(dow))
          .toList();
      if (batchRows.isNotEmpty) {
        final ids = batchRows.map((b) => b['id'] as String).toList();
        final withMembers = (await _client.from('membership_batch_members').select('batch_id').inFilter('batch_id', ids) as List<dynamic>)
            .map((r) => (r as Map)['batch_id'] as String)
            .toSet();
        final blockedToday = (await _client.from('membership_batch_blocked_dates').select('batch_id').inFilter('batch_id', ids).eq('blocked_date', todayKey) as List<dynamic>)
            .map((r) => (r as Map)['batch_id'] as String)
            .toSet();
        for (final b in batchRows) {
          final id = b['id'] as String;
          if (!withMembers.contains(id) || blockedToday.contains(id)) continue;
          final start = b['start_time'] as String;
          final end = b['end_time'] as String;
          // A booked slot for this same session is already on the timeline.
          if (alreadyShown.contains('${b['court_id']}|$start|$end')) continue;
          out.add((
            id: 'batch-$id',
            playingAreaId: b['court_id'] as String,
            startTime: DateTime.parse('${todayKey}T$start'),
            endTime: DateTime.parse('${todayKey}T$end'),
            status: 'confirmed',
            type: ScheduleBlockType.session,
            label: 'Membership · ${b['name']}',
          ));
        }
      }
    } catch (_) {
      // Membership detail is a bonus on this timeline; the bookings already on it still show.
    }

    try {
      final dayStart = DateTime(now.year, now.month, now.day);
      final rows = (await _client
              .from('coaching_sessions')
              .select('id, court_id, start_at, end_at, status, coaching_programs(name)')
              .eq('facility_id', facilityId)
              .inFilter('status', ['SCHEDULED', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED'])
              .gte('start_at', dayStart.toUtc().toIso8601String())
              .lt('start_at', dayStart.add(const Duration(days: 1)).toUtc().toIso8601String()) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((r) => playingAreaIds.contains(r['court_id']));
      for (final r in rows) {
        final program = (r['coaching_programs'] as Map?)?['name'] as String?;
        out.add((
          id: 'coaching-${r['id']}',
          playingAreaId: r['court_id'] as String,
          startTime: DateTime.parse(r['start_at'] as String).toLocal(),
          endTime: DateTime.parse(r['end_at'] as String).toLocal(),
          status: 'confirmed',
          type: ScheduleBlockType.coaching,
          label: program == null || program.isEmpty ? 'Coaching session' : 'Coaching · $program',
        ));
      }
    } catch (_) {
      // No access to coaching (or it isn't set up): no coaching blocks, nothing else changes.
    }
    return out;
  }

}

extension _FirstOrNullSafe<T> on Iterable<T> {
  T? get firstOrNullSafe => isEmpty ? null : first;
}
/// Period totals for the KPI cards and panels (see [DashboardRepository._fetchTotals]).
class _Totals {
  const _Totals({
    required this.payments,
    required this.previousCollectedInr,
    required this.bookings,
    required this.previousBookings,
    required this.activeMembershipsInScope,
    required this.memberships,
  });
  final PaymentSummary payments;
  final int previousCollectedInr;
  final int bookings;
  final int previousBookings;
  final int activeMembershipsInScope;
  final MembershipSummary memberships;
}

/// Booked court time in minutes, per court id.
class _BookedMinutes {
  const _BookedMinutes(this.current, this.previous);
  final Map<String, double> current;
  final Map<String, double> previous;
}
