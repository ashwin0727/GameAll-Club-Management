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
          .select('court_id, start_time, end_time, status')
          .eq('facility_id', facilityId)
          .gte('start_time', earliestFrom.toIso8601String())
          .lt('start_time', period.current.to.toIso8601String());

      final membershipsRows = await _client
          .from('memberships')
          .select('status, end_date, created_at')
          .eq('facility_id', facilityId);

      final paymentsRows = await _client
          .from('payments')
          .select('status, amount_inr, created_at')
          .eq('facility_id', facilityId)
          .gte('created_at', earliestFrom.toIso8601String())
          .lt('created_at', period.current.to.toIso8601String());

      final allBookings = (bookingsRows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((b) => playingAreaIds.contains(b['court_id']))
          .map(
            (b) => (
              playingAreaId: b['court_id'] as String,
              startTime: DateTime.parse(b['start_time'] as String),
              endTime: DateTime.parse(b['end_time'] as String),
              status: b['status'] as String,
            ),
          )
          .toList();

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
      final currentPayments = allPayments
          .where((p) {
            final createdAt = DateTime.parse(p['created_at'] as String);
            return !createdAt.isBefore(period.current.from) && createdAt.isBefore(period.current.to);
          })
          .map((p) => (status: p['status'] as String, amountInr: p['amount_inr'] as int))
          .toList();
      final previousPayments = period.previous == null
          ? const <({String status, int amountInr})>[]
          : allPayments
                .where((p) {
                  final createdAt = DateTime.parse(p['created_at'] as String);
                  return !createdAt.isBefore(period.previous!.from) && createdAt.isBefore(period.previous!.to);
                })
                .map((p) => (status: p['status'] as String, amountInr: p['amount_inr'] as int))
                .toList();

      final currentPaymentSummary = DashboardCalculator.summarizePayments(currentPayments);
      final previousPaymentSummary = period.previous == null
          ? null
          : DashboardCalculator.summarizePayments(previousPayments);

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

      final memberships = DashboardCalculator.summarizeMemberships(
        (membershipsRows as List<dynamic>).cast<Map<String, dynamic>>().map((m) {
          return (
            status: m['status'] as String,
            endDate: DateTime.parse(m['end_date'] as String),
            createdAt: DateTime.parse(m['created_at'] as String),
          );
        }).toList(),
        now,
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
            currentPaymentSummary.collectedInr,
            previousPaymentSummary?.collectedInr,
          ),
          bookings: DashboardCalculator.computeKpiValue(
            currentBookings.length,
            period.previous == null ? null : previousBookings.length,
          ),
          utilizationPercent: DashboardCalculator.computeKpiValue(
            currentUtilization.overallPercent,
            previousUtilization?.overallPercent,
          ),
          activeMembers: DashboardCalculator.computeKpiValue(memberships.active, null),
        ),
        utilization: currentUtilization,
        schedule: DashboardCalculator.buildTodaysSchedule(
          playingAreas: utilizationPlayingAreas,
          facilitySports: utilizationFacilitySports,
          sports: utilizationSports,
          facilityOperatingDays: operatingDays,
          bookings: currentBookings,
          now: now,
        ),
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