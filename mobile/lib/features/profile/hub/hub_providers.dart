import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/analytics.dart';
import '../../../data/models/facility.dart';
import '../../../data/models/finance.dart';
import '../../../data/models/operating_hours.dart';
import '../../../data/models/payout_method.dart';
import '../../../data/models/playing_area.dart';
import '../../../data/models/pricing.dart';
import '../../../data/models/profile_hub.dart';
import '../../../data/models/sport.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../authentication/session_controller.dart';

/// The facility the signed-in owner is looking at.
Facility? _facilityOf(Ref ref) => ref.watch(sessionControllerProvider).facility;

final hubProfileProvider = FutureProvider.autoDispose<HubProfile>((ref) {
  return ref.watch(profileHubRepositoryProvider).getProfile();
});

/// GameAll's plan for the facility; the sample plan stands in until a real one is synced.
final hubPlanProvider = FutureProvider.autoDispose<FacilityPlan>((ref) async {
  final facility = _facilityOf(ref);
  if (facility == null) return FacilityPlan.sample();
  final plan = await ref.watch(profileHubRepositoryProvider).getPlan(facility.id);
  return plan ?? FacilityPlan.sample();
});

/// Bookings and revenue are the server's own figures for this month, read through the same repositories the Reports and
/// Finance screens use, so this page can never disagree with them.
final hubStatsProvider = FutureProvider.autoDispose<HubStats>((ref) async {
  final facility = _facilityOf(ref);
  if (facility == null) return const HubStats(bookingsThisMonth: 0, activeMembers: 0, courts: 0, revenueThisMonthMinor: 0);
  final hub = ref.watch(profileHubRepositoryProvider);
  final results = await Future.wait([
    ref.watch(reportsRepositoryProvider).getAnalyticsOverview(facility.id, AnalyticsFilter.currentMonth()),
    ref.watch(financeRepositoryProvider).getSummary(facility.id, const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth)),
    hub.countActiveMembers(facility.id),
    hub.countCourts(facility.id),
  ]);
  return HubStats(
    bookingsThisMonth: (results[0] as AnalyticsOverview).totalBookings,
    revenueThisMonthMinor: (results[1] as FinanceSummary).grossRevenueMinor,
    activeMembers: results[2] as int,
    courts: results[3] as int,
  );
});

final payoutMethodsProvider = FutureProvider.autoDispose<List<PayoutMethod>>((ref) async {
  final facility = _facilityOf(ref);
  if (facility == null) return const [];
  return ref.watch(payoutRepositoryProvider).list(facility.id);
});

final notificationPrefsProvider = FutureProvider.autoDispose<NotificationPrefs>((ref) {
  return ref.watch(profileHubRepositoryProvider).getNotificationPrefs();
});

final supportTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) async {
  final facility = _facilityOf(ref);
  if (facility == null) return const [];
  return ref.watch(profileHubRepositoryProvider).listTickets(facility.id);
});

/// Everything the facility screens show, read together so the sections never disagree.
class FacilityData {
  const FacilityData({
    required this.sports,
    required this.catalog,
    required this.areas,
    required this.schedule,
    required this.pricing,
  });

  /// Sports the facility offers (enabled ones).
  final List<FacilitySport> sports;
  final List<Sport> catalog;
  final List<PlayingArea> areas;
  final OperatingSchedule? schedule;
  final PricingPlan? pricing;

  Sport? catalogFor(FacilitySport fs) {
    for (final s in catalog) {
      if (s.id == fs.sportId) return s;
    }
    return null;
  }

  String nameOf(FacilitySport fs) {
    final custom = fs.customSportName?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return catalogFor(fs)?.name ?? 'Sport';
  }

  String iconOf(FacilitySport fs) => catalogFor(fs)?.icon ?? '🏅';

  /// "Court" / "Turf" / "Playing Area" for a sport.
  String areaLabelOf(FacilitySport fs) {
    switch (catalogFor(fs)?.code) {
      case 'BADMINTON':
      case 'PICKLEBALL':
      case 'TENNIS':
        return 'Court';
      case 'CRICKET':
      case 'FOOTBALL':
        return 'Turf';
      default:
        return 'Playing Area';
    }
  }

  List<PlayingArea> areasOf(FacilitySport fs) => areas.where((a) => a.facilitySportId == fs.id && !a.archived).toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  int get totalCourts => areas.where((a) => !a.archived).length;
  int get activeCourts => areas.where((a) => !a.archived && a.status == 'ACTIVE').length;
}

final facilityDataProvider = FutureProvider.autoDispose<FacilityData>((ref) async {
  final facility = _facilityOf(ref);
  if (facility == null) {
    return const FacilityData(sports: [], catalog: [], areas: [], schedule: null, pricing: null);
  }
  final sportsRepo = ref.watch(sportsRepositoryProvider);
  final results = await Future.wait([
    sportsRepo.getFacilitySports(facility.id),
    sportsRepo.getActiveSports(),
    ref.watch(playingAreaRepositoryProvider).getPlayingAreas(facility.id),
    ref.watch(operatingHoursRepositoryProvider).getFacilitySchedule(facility.id),
    ref.watch(pricingRepositoryProvider).getPricingPlan(facility.id),
  ]);
  return FacilityData(
    sports: (results[0] as List<FacilitySport>).where((s) => s.enabled).toList(),
    catalog: results[1] as List<Sport>,
    areas: results[2] as List<PlayingArea>,
    schedule: results[3] as OperatingSchedule?,
    pricing: results[4] as PricingPlan?,
  );
});
