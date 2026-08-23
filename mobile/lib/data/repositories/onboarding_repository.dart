import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/facility.dart';
import '../models/setup_summary.dart';
import 'facility_repository.dart';
import 'operating_hours_repository.dart';
import 'playing_area_repository.dart';
import 'pricing_repository.dart';
import 'sports_repository.dart';

/// Mirrors src/services/onboarding/supabase-onboarding.service.ts — same
/// `complete_facility_setup` RPC, which re-validates every requirement
/// server-side before flipping the facility to COMPLETED (idempotent: a
/// second call on an already-COMPLETED facility is a no-op read).
class OnboardingRepository {
  OnboardingRepository(
    this._client,
    this._facilityRepo,
    this._sportsRepo,
    this._playingAreaRepo,
    this._operatingHoursRepo,
    this._pricingRepo,
  );

  final SupabaseClient _client;
  final FacilityRepository _facilityRepo;
  final SportsRepository _sportsRepo;
  final PlayingAreaRepository _playingAreaRepo;
  final OperatingHoursRepository _operatingHoursRepo;
  final PricingRepository _pricingRepo;

  Future<SetupSummary> getSetupSummary(String facilityId) async {
    final facility = await _facilityRepo.getFacility();
    if (facility == null || facility.id != facilityId) {
      throw AppException(AppErrorCode.facilityNotFound);
    }

    // Each call starts executing immediately (Dart futures are eager), so
    // awaiting them in sequence below still runs them concurrently — no
    // need for Future.wait, which would lose static typing across this
    // heterogeneous result set.
    final facilitySportsFuture = _sportsRepo.getFacilitySports(facilityId);
    final sportsFuture = _sportsRepo.getActiveSports();
    final playingAreasFuture = _playingAreaRepo.getPlayingAreas(facilityId);
    final scheduleFuture = _operatingHoursRepo.getFacilitySchedule(facilityId);
    final pricingFuture = _pricingRepo.getPricingPlan(facilityId);

    return SetupSummary(
      facility: facility,
      facilitySports: await facilitySportsFuture,
      sports: await sportsFuture,
      playingAreas: await playingAreasFuture,
      schedule: await scheduleFuture,
      pricingPlan: await pricingFuture,
    );
  }

  Future<Facility> completeSetup(String facilityId) async {
    try {
      final row = await _client.rpc(
        'complete_facility_setup',
        params: {'p_facility_id': facilityId},
      );
      return Facility.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, invalid: AppErrorCode.setupIncomplete);
    }
  }
}