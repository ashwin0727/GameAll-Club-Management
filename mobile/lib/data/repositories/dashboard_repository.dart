import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../../features/dashboard/dashboard_calculator.dart';
import '../models/dashboard.dart';
import 'facility_repository.dart';
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
    this._facilityRepo,
    this._sportsRepo,
    this._playingAreaRepo,
    this._operatingHoursRepo,
  );

  final SupabaseClient _client;
  final FacilityRepository _facilityRepo;
  final SportsRepository _sportsRepo;
  final PlayingAreaRepository _playingAreaRepo;
  final OperatingHoursRepository _operatingHoursRepo;

  Future<DashboardSummary> getDashboardSummary(
    String facilityId, {
    String? facilitySportId,
    required DateRangePreset preset,
    int revenueMonthOffset = 0,
  }) async {
    final facility = await _facilityRepo.getFacility();
    if (facility == null || facility.id != facilityId) {
      throw AppException(AppErrorCode.facilityNotFound);
    }

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

    final earliestFrom = (period.previous ?? period.current).from;

    try {
      final bookingsRows = await _client
          .from('bookings')
          .select('id, court_id, start_time, end_time, status, customer_type, guest_name, member_id, payment_status')
          .eq('facility_id', facilityId)
          .gte('start_time', earliestFrom.toIso8601String())
          .lt('start_time', period.current.to.toIso8601String());

      final membershipsRows = await _client
          .from('memberships')
          .select('id, status, end_date, created_at')
          .eq('facility_id', facilityId);

      final paymentsRows = await _client
          .from('payments')
          .select('status, amount_inr, created_at, booking_id, membership_id')
          .eq('facility_id', facilityId)
          .gte('created_at', earliestFrom.toIso8601String())
          .lt('created_at', period.current.to.toIso8601String());

      // Revenue Overview has its own month filter, independent of [preset].
      final revWindowFrom = DateTime(now.year, now.month - revenueMonthOffset - 1, 1);
      final revWindowTo = DateTime(now.year, now.month - revenueMonthOffset + 1, 1);
      final revenuePaymentsRows = await _client
          .from('payments')
          .select('status, amount_inr, created_at, booking_id, membership_id')
          .eq('facility_id', facilityId)
          .gte('created_at', revWindowFrom.toIso8601String())
          .lt('created_at', revWindowTo.toIso8601String());

      // Actual usage of a membership-protected slot (member or guest)
      // occupies court-time exactly like a regular booking, even though
      // it's tracked in a different table — merged into allBookings below
      // so utilization/today's-schedule never treat a fully-attended
      // membership court as 0% used. See 0015_membership_utilization.sql.
      final membershipSessionRows = await _client.rpc(
        'get_membership_utilization_sessions',
        params: {
          'p_facility_id': facilityId,
          'p_from': earliestFrom.toIso8601String().substring(0, 10),
          'p_to': period.current.to.toIso8601String().substring(0, 10),
        },
      );

      final membershipUtilizationBookings = DashboardCalculator.toUtilizationBookings(
        (membershipSessionRows as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((s) => playingAreaIds.contains(s['court_id']))
            .map(
              (s) => (
                courtId: s['court_id'] as String,
                sessionDate: s['session_date'] as String,
                startTime: s['start_time'] as String,
                endTime: s['end_time'] as String,
              ),
            )
            .toList(),
      );

      final allBookings = [
        ...(bookingsRows as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((b) => playingAreaIds.contains(b['court_id']))
            .map(
              (b) => (
                playingAreaId: b['court_id'] as String,
                startTime: DateTime.parse(b['start_time'] as String),
                endTime: DateTime.parse(b['end_time'] as String),
                status: b['status'] as String,
              ),
            ),
        ...membershipUtilizationBookings,
      ];

      final currentBookings = allBookings
          .where((b) => !b.startTime.isBefore(period.current.from) && b.startTime.isBefore(period.current.to))
          .where((b) => b.status != 'cancelled')
          .toList();
      final previousBookings = period.previous == null
          ? const <({String playingAreaId, DateTime startTime, DateTime endTime, String status})>[]
          : allBookings
                .where(
                  (b) =>
                      !b.startTime.isBefore(period.previous!.from) &&
                      b.startTime.isBefore(period.previous!.to),
                )
                .where((b) => b.status != 'cancelled')
                .toList();

      final allPayments = (paymentsRows as List<dynamic>).cast<Map<String, dynamic>>();

      List<({String status, int amountInr, String? bookingId, String? membershipId, DateTime createdAt})>
          paymentsInWindow(DateRange w) => allPayments
              .map((p) => (
                    status: p['status'] as String,
                    amountInr: p['amount_inr'] as int,
                    bookingId: p['booking_id'] as String?,
                    membershipId: p['membership_id'] as String?,
                    createdAt: DateTime.parse(p['created_at'] as String),
                  ))
              .where((p) => !p.createdAt.isBefore(w.from) && p.createdAt.isBefore(w.to))
              .toList();
      final currentPayments = paymentsInWindow(period.current);
      final previousPayments = period.previous == null ? null : paymentsInWindow(period.previous!);

      // When a specific sport is selected, revenue/active-membership are
      // narrowed via booking court + membership batch enrolment (mirrors
      // src/services/dashboard/supabase-dashboard.service.ts).
      ({Set<String> bookingIds, Set<String> membershipIds})? sportScope;
      Set<String>? sportMembershipIds;
      if (facilitySportId != null) {
        final batchRows = await _client
            .from('membership_batches')
            .select('id, facility_sport_id')
            .eq('facility_id', facilityId);
        final batchMemberRows =
            await _client.from('membership_batch_members').select('membership_id, batch_id');
        final batchSport = <String, String>{
          for (final b in (batchRows as List).cast<Map<String, dynamic>>())
            b['id'] as String: b['facility_sport_id'] as String,
        };
        sportMembershipIds = {
          for (final m in (batchMemberRows as List).cast<Map<String, dynamic>>())
            if (m['membership_id'] != null && batchSport[m['batch_id']] == facilitySportId)
              m['membership_id'] as String,
        };
        sportScope = (
          bookingIds: {
            for (final b in bookingsRows.where((b) => playingAreaIds.contains(b['court_id']))) b['id'] as String,
          },
          membershipIds: sportMembershipIds,
        );
      }

      final scope = sportScope;
      bool paymentInScope(
              ({String status, int amountInr, String? bookingId, String? membershipId, DateTime createdAt}) p) =>
          scope == null ||
          (p.bookingId != null && scope.bookingIds.contains(p.bookingId)) ||
          (p.membershipId != null && scope.membershipIds.contains(p.membershipId));

      ({String status, int amountInr, String? bookingId, String? membershipId}) revenueShape(
              ({String status, int amountInr, String? bookingId, String? membershipId, DateTime createdAt}) p) =>
          (status: p.status, amountInr: p.amountInr, bookingId: p.bookingId, membershipId: p.membershipId);

      final scopedCurrentPayments = scope == null ? currentPayments : currentPayments.where(paymentInScope).toList();

      final currentPaymentSummary = DashboardCalculator.summarizePayments(
        scopedCurrentPayments.map((p) => (status: p.status, amountInr: p.amountInr)).toList(),
      );

      final revenuePayments = (revenuePaymentsRows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((p) {
            if (scope == null) return true;
            final bid = p['booking_id'] as String?;
            final mid = p['membership_id'] as String?;
            return (bid != null && scope.bookingIds.contains(bid)) ||
                (mid != null && scope.membershipIds.contains(mid));
          })
          .map((p) => (
                status: p['status'] as String,
                amountInr: p['amount_inr'] as int,
                createdAt: DateTime.parse(p['created_at'] as String),
                bookingId: p['booking_id'] as String?,
                membershipId: p['membership_id'] as String?,
              ))
          .toList();
      final revenueOverview = DashboardCalculator.buildRevenueOverview(revenuePayments, now, revenueMonthOffset);

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
        bookings: currentBookings,
        period: period.current,
      );
      final previousUtilization = period.previous == null
          ? null
          : DashboardCalculator.computeUtilization(
              playingAreas: utilizationPlayingAreas,
              facilitySports: utilizationFacilitySports,
              sports: utilizationSports,
              facilityOperatingDays: operatingDays,
              bookings: previousBookings,
              period: period.previous!,
            );

      final membershipMaps = (membershipsRows as List<dynamic>).cast<Map<String, dynamic>>().toList();
      final memberships = DashboardCalculator.summarizeMemberships(
        membershipMaps.map((m) {
          return (
            status: m['status'] as String,
            endDate: DateTime.parse(m['end_date'] as String),
            createdAt: DateTime.parse(m['created_at'] as String),
          );
        }).toList(),
        now,
      );

      // Guest-booking KPI: guest bookings that are booked (not cancelled) and
      // paid, on the (sport-filtered) courts, within a given window.
      List<({String customerType, String paymentStatus, String status})> guestBookingShapes(DateRange w) => bookingsRows
          .cast<Map<String, dynamic>>()
          .where((b) => playingAreaIds.contains(b['court_id']))
          .where((b) {
            final st = DateTime.parse(b['start_time'] as String);
            return !st.isBefore(w.from) && st.isBefore(w.to);
          })
          .map((b) => (
                customerType: b['customer_type'] as String,
                paymentStatus: b['payment_status'] as String? ?? 'PENDING',
                status: b['status'] as String,
              ))
          .toList();

      // "Today's Schedule" timeline — member names need a profiles lookup
      // (bookings carry only member_id); guests carry their own name.
      final todayBookingMaps =
          bookingsRows.where((b) => playingAreaIds.contains(b['court_id'])).toList();
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

      final timelineBookings =
          <({String id, String playingAreaId, DateTime startTime, DateTime endTime, String status, ScheduleBlockType type, String label})>[
        ...todayBookingMaps.map((b) {
          final isGuest = b['customer_type'] == 'GUEST';
          final memberId = b['member_id'] as String?;
          return (
            id: b['id'] as String,
            playingAreaId: b['court_id'] as String,
            startTime: DateTime.parse(b['start_time'] as String),
            endTime: DateTime.parse(b['end_time'] as String),
            status: b['status'] as String,
            type: isGuest ? ScheduleBlockType.guest : ScheduleBlockType.member,
            label: isGuest
                ? (b['guest_name'] as String? ?? 'Guest booking')
                : (memberId != null ? memberNames[memberId] ?? 'Member booking' : 'Member booking'),
          );
        }),
        ...membershipSessionRows
            .cast<Map<String, dynamic>>()
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
                label: 'Membership session',
              ),
            ),
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
            DashboardCalculator.sumPaidRevenueInr(currentPayments.map(revenueShape).toList(), scope),
            previousPayments == null
                ? null
                : DashboardCalculator.sumPaidRevenueInr(previousPayments.map(revenueShape).toList(), scope),
          ),
          activeMemberships: DashboardCalculator.computeKpiValue(
            DashboardCalculator.countActiveMemberships(
              membershipMaps.map((m) => (id: m['id'] as String, status: m['status'] as String)).toList(),
              sportMembershipIds,
            ),
            null,
          ),
          guestBookings: DashboardCalculator.computeKpiValue(
            DashboardCalculator.countPaidGuestBookings(guestBookingShapes(period.current)),
            period.previous == null
                ? null
                : DashboardCalculator.countPaidGuestBookings(guestBookingShapes(period.previous!)),
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
        payments: currentPaymentSummary,
        attentionItems: DashboardCalculator.buildAttentionItems(
          membershipsExpiringSoon: memberships.expiringSoon,
          paymentsPendingInr: currentPaymentSummary.pendingInr,
        ),
      );
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

extension _FirstOrNullSafe<T> on Iterable<T> {
  T? get firstOrNullSafe => isEmpty ? null : first;
}