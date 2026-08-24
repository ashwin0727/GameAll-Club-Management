import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/features/onboarding/pricing_validation.dart';

PricingPeriodDraft _fullDay({String dayType = 'ALL_DAYS', int amountMinor = 40000}) {
  return PricingPeriodDraft(dayType: dayType, coversFullDay: true, amountMinor: amountMinor);
}

PricingPeriodDraft _window({
  String dayType = 'ALL_DAYS',
  required String start,
  required String end,
  int amountMinor = 40000,
}) {
  return PricingPeriodDraft(dayType: dayType, coversFullDay: false, startTime: start, endTime: end, amountMinor: amountMinor);
}

OperatingDay _openDay(int dow, {String start = '06:00', String end = '23:00'}) {
  return OperatingDay(
    dayOfWeek: dow,
    isClosed: false,
    is24Hours: false,
    slots: [OperatingTimeSlot(startTime: start, endTime: end, crossesMidnight: false, displayOrder: 0)],
  );
}

/// A full open week (matches how a real facility schedule always carries
/// all 7 days), so ALL_DAYS-scoped periods validate against every day.
List<OperatingDay> _openWeek({String start = '06:00', String end = '23:00'}) {
  return List.generate(7, (dow) => _openDay(dow, start: start, end: end));
}

void main() {
  group('validatePriceAmount', () {
    test('rejects zero', () => expect(validatePriceAmount(0), isNotNull));
    test('rejects a negative amount', () => expect(validatePriceAmount(-100), isNotNull));
    test('accepts a positive amount', () => expect(validatePriceAmount(40000), isNull));
  });

  group('validatePricingPeriod', () {
    test('a full-day period only needs a positive amount', () {
      expect(validatePricingPeriod(_fullDay()), isNull);
      expect(validatePricingPeriod(_fullDay(amountMinor: 0)), isNotNull);
    });

    test('a time-window period requires start and end time', () {
      final period = PricingPeriodDraft(dayType: 'ALL_DAYS', coversFullDay: false, amountMinor: 40000);
      expect(validatePricingPeriod(period), isNotNull);
    });

    test('rejects identical start and end time', () {
      expect(validatePricingPeriod(_window(start: '06:00', end: '06:00')), isNotNull);
    });

    test('accepts a valid time-window period', () {
      expect(validatePricingPeriod(_window(start: '06:00', end: '17:00')), isNull);
    });
  });

  group('hasOverlappingPricingPeriods', () {
    test('is false for non-overlapping windows in the same day-type', () {
      final periods = [_window(start: '06:00', end: '12:00'), _window(start: '12:00', end: '18:00')];
      expect(hasOverlappingPricingPeriods(periods), isFalse);
    });

    test('is true for overlapping windows in the same day-type', () {
      final periods = [_window(start: '06:00', end: '12:00'), _window(start: '10:00', end: '18:00')];
      expect(hasOverlappingPricingPeriods(periods), isTrue);
    });

    test('windows in different day-types never collide', () {
      final periods = [
        _window(dayType: 'WEEKDAYS', start: '06:00', end: '12:00'),
        _window(dayType: 'WEEKENDS', start: '06:00', end: '12:00'),
      ];
      expect(hasOverlappingPricingPeriods(periods), isFalse);
    });

    test('full-day periods are ignored (they have no window to overlap)', () {
      expect(hasOverlappingPricingPeriods([_fullDay(), _fullDay()]), isFalse);
    });
  });

  group('validatePricingAgainstOperatingHours', () {
    test('a full-day rate is valid when the facility is open every day', () {
      expect(validatePricingAgainstOperatingHours(_fullDay(), _openWeek()), isNull);
    });

    test('is invalid when any covered day is closed', () {
      final days = _openWeek();
      days[1] = OperatingDay(dayOfWeek: 1, isClosed: true, is24Hours: false, slots: const []);
      expect(validatePricingAgainstOperatingHours(_fullDay(), days), isNotNull);
    });

    test('a WEEKDAYS-scoped rate ignores weekend closures', () {
      final days = _openWeek();
      days[0] = OperatingDay(dayOfWeek: 0, isClosed: true, is24Hours: false, slots: const []);
      expect(validatePricingAgainstOperatingHours(_fullDay(dayType: 'WEEKDAYS'), days), isNull);
    });

    test('a time-window rate must fall within an operating-hours slot', () {
      final days = _openWeek(start: '06:00', end: '17:00');
      expect(validatePricingAgainstOperatingHours(_window(start: '08:00', end: '12:00'), days), isNull);
      expect(validatePricingAgainstOperatingHours(_window(start: '16:00', end: '20:00'), days), isNotNull);
    });

    test('any day is valid when the facility is open 24 hours', () {
      final days = List.generate(
        7,
        (dow) => OperatingDay(dayOfWeek: dow, isClosed: false, is24Hours: true, slots: const []),
      );
      expect(validatePricingAgainstOperatingHours(_window(start: '02:00', end: '04:00'), days), isNull);
    });
  });
}