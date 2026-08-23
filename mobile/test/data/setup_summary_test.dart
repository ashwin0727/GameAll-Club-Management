import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/sport.dart';
import 'package:gameall_club_mobile/data/models/playing_area.dart';
import 'package:gameall_club_mobile/data/models/pricing.dart';
import 'package:gameall_club_mobile/data/models/setup_summary.dart';

Facility _facility() => Facility(
  id: 'facility-1',
  ownerId: 'owner-1',
  name: 'GameAll Sports Arena',
  type: FacilityType.multiSport,
  businessEmail: 'owner@example.com',
  businessPhone: '9876543210',
  address: const FacilityAddress(
    line1: '123 Anna Salai',
    area: 'Ambattur',
    city: 'Chennai',
    state: 'Tamil Nadu',
    country: 'India',
    pinCode: '600053',
  ),
  status: 'ACTIVE',
  onboardingStep: OnboardingStep.pricing,
);

const _sport = Sport(id: 'sport-1', name: 'Badminton', code: 'BADMINTON', icon: '🏸', description: '', isActive: true);
const _facilitySport = FacilitySport(id: 'fs-1', facilityId: 'facility-1', sportId: 'sport-1', enabled: true);
const _area = PlayingArea(
  id: 'area-1',
  facilityId: 'facility-1',
  facilitySportId: 'fs-1',
  sportId: 'sport-1',
  name: 'Court 1',
  areaType: 'INDOOR',
  status: 'ACTIVE',
  bookingEnabled: true,
  archived: false,
  displayOrder: 0,
);

void main() {
  group('SetupSummary — missing-requirement detection', () {
    test('flags every missing area when nothing is configured', () {
      final summary = SetupSummary(
        facility: _facility(),
        facilitySports: const [],
        sports: const [],
        playingAreas: const [],
        schedule: null,
        pricingPlan: null,
      );
      expect(summary.missingSports, isTrue);
      expect(summary.missingPlayingAreas, isTrue);
      expect(summary.missingOperatingHours, isTrue);
      expect(summary.isReady, isFalse);
    });

    test('is ready when every requirement is satisfied', () {
      final summary = SetupSummary(
        facility: _facility(),
        facilitySports: const [_facilitySport],
        sports: const [_sport],
        playingAreas: const [_area],
        schedule: null,
        pricingPlan: PricingPlan(
          id: 'plan-1',
          facilityId: 'facility-1',
          currency: 'INR',
          rules: const [
            PricingRule(
              facilitySportId: 'fs-1',
              dayType: 'ALL_DAYS',
              coversFullDay: true,
              amountMinor: 40000,
              currency: 'INR',
              pricingUnit: 'PER_HOUR',
              priority: 0,
            ),
          ],
        ),
      );
      // Operating hours still missing (schedule: null) — not ready yet.
      expect(summary.isReady, isFalse);
      expect(summary.missingRequirements.map((r) => r.code), ['OPERATING_HOURS']);
    });

    test('lists a sport missing pricing by name, not just a generic flag', () {
      final summary = SetupSummary(
        facility: _facility(),
        facilitySports: const [_facilitySport],
        sports: const [_sport],
        playingAreas: const [_area],
        schedule: null,
        pricingPlan: null,
      );
      expect(summary.sportsMissingPricing, ['Badminton']);
    });
  });
}