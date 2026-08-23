import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/sport.dart';
import 'package:gameall_club_mobile/data/models/playing_area.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/data/models/pricing.dart';

void main() {
  group('Facility.fromJson', () {
    test('parses a full facilities row, matching the web app column names', () {
      final facility = Facility.fromJson({
        'id': 'facility-1',
        'owner_id': 'owner-1',
        'name': 'GameAll Sports Arena',
        'facility_type': 'MULTI_SPORT',
        'custom_facility_type': null,
        'business_email': 'owner@example.com',
        'business_phone': '9876543210',
        'address_line_1': '123 Anna Salai',
        'area': 'Ambattur',
        'city': 'Chennai',
        'state': 'Tamil Nadu',
        'country': 'India',
        'postal_code': '600053',
        'logo_url': null,
        'description': null,
        'status': 'ACTIVE',
        'onboarding_step': 'SPORTS',
        'onboarding_completed_at': null,
      });

      expect(facility.type, FacilityType.multiSport);
      expect(facility.onboardingStep, OnboardingStep.sports);
      expect(facility.address.city, 'Chennai');
    });

    test('defaults a missing onboarding_step to FACILITY_DETAILS', () {
      final facility = Facility.fromJson({
        'id': 'facility-1',
        'owner_id': 'owner-1',
        'name': 'X',
        'status': 'ACTIVE',
      });
      expect(facility.onboardingStep, OnboardingStep.facilityDetails);
    });
  });

  group('FacilityType round-trip', () {
    test('every value survives toDb -> fromDb', () {
      for (final type in FacilityType.values) {
        expect(FacilityType.fromDb(type.toDb()), type);
      }
    });
  });

  group('Sport.fromJson', () {
    test('derives icon/description presentation from the sport code, not a DB column', () {
      final sport = Sport.fromJson({
        'id': 'sport-1',
        'key': 'badminton',
        'name': 'Badminton',
        'is_active': true,
      });
      expect(sport.code, 'BADMINTON');
      expect(sport.icon, '🏸');
    });

    test('falls back to a default presentation for an unrecognized code', () {
      final sport = Sport.fromJson({
        'id': 'sport-1',
        'key': 'chess',
        'name': 'Chess',
        'is_active': true,
      });
      expect(sport.icon, isNotEmpty);
    });
  });

  group('playingAreaLabelFor', () {
    test('labels cricket/football as Turf', () {
      expect(playingAreaLabelFor('CRICKET'), 'Turf');
      expect(playingAreaLabelFor('FOOTBALL'), 'Turf');
    });
    test('labels badminton/pickleball/tennis as Court', () {
      expect(playingAreaLabelFor('BADMINTON'), 'Court');
      expect(playingAreaLabelFor('TENNIS'), 'Court');
    });
    test('falls back to Playing Area for OTHER', () {
      expect(playingAreaLabelFor('OTHER'), 'Playing Area');
    });
  });

  group('OperatingTimeSlot.fromJson', () {
    test('truncates a full HH:MM:SS DB time to HH:MM', () {
      final slot = OperatingTimeSlot.fromJson({
        'start_time': '06:00:00',
        'end_time': '23:00:00',
        'crosses_midnight': false,
        'display_order': 0,
      });
      expect(slot.startTime, '06:00');
      expect(slot.endTime, '23:00');
    });
  });

  group('PricingRule', () {
    test('amountRupees converts minor units back to whole rupees', () {
      const rule = PricingRule(
        facilitySportId: 'fs-1',
        dayType: 'ALL_DAYS',
        coversFullDay: true,
        amountMinor: 40000,
        currency: 'INR',
        pricingUnit: 'PER_HOUR',
        priority: 0,
      );
      expect(rule.amountRupees, 400);
    });

    test('a full-day rule omits start/end time from its save payload', () {
      const rule = PricingRule(
        facilitySportId: 'fs-1',
        dayType: 'ALL_DAYS',
        coversFullDay: true,
        startTime: '06:00',
        endTime: '23:00',
        amountMinor: 40000,
        currency: 'INR',
        pricingUnit: 'PER_HOUR',
        priority: 0,
      );
      final payload = rule.toPayload();
      expect(payload['startTime'], '');
      expect(payload['endTime'], '');
    });
  });
}