import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/features/onboarding/operating_hours_validation.dart';

OperatingDay _openDay({
  int dayOfWeek = 1,
  List<OperatingTimeSlot> slots = const [
    OperatingTimeSlot(startTime: '06:00', endTime: '23:00', crossesMidnight: false, displayOrder: 0),
  ],
}) {
  return OperatingDay(dayOfWeek: dayOfWeek, isClosed: false, is24Hours: false, slots: slots);
}

void main() {
  group('isOvernightSlot', () {
    test('is false for a normal same-day slot', () {
      const slot = OperatingTimeSlot(startTime: '06:00', endTime: '23:00', crossesMidnight: false, displayOrder: 0);
      expect(isOvernightSlot(slot), isFalse);
    });

    test('is true when end time is not after start time', () {
      const slot = OperatingTimeSlot(startTime: '22:00', endTime: '02:00', crossesMidnight: false, displayOrder: 0);
      expect(isOvernightSlot(slot), isTrue);
    });
  });

  group('hasOverlappingSlots', () {
    test('is false for non-overlapping slots', () {
      const slots = [
        OperatingTimeSlot(startTime: '06:00', endTime: '12:00', crossesMidnight: false, displayOrder: 0),
        OperatingTimeSlot(startTime: '13:00', endTime: '18:00', crossesMidnight: false, displayOrder: 1),
      ];
      expect(hasOverlappingSlots(slots), isFalse);
    });

    test('is true for overlapping slots', () {
      const slots = [
        OperatingTimeSlot(startTime: '06:00', endTime: '12:00', crossesMidnight: false, displayOrder: 0),
        OperatingTimeSlot(startTime: '11:00', endTime: '18:00', crossesMidnight: false, displayOrder: 1),
      ];
      expect(hasOverlappingSlots(slots), isTrue);
    });

    test('detects an overnight slot colliding with an early-morning slot the next day', () {
      const slots = [
        OperatingTimeSlot(startTime: '22:00', endTime: '02:00', crossesMidnight: true, displayOrder: 0),
        OperatingTimeSlot(startTime: '01:00', endTime: '05:00', crossesMidnight: false, displayOrder: 1),
      ];
      expect(hasOverlappingSlots(slots), isTrue);
    });
  });

  group('validateTimeSlot', () {
    test('rejects a malformed start time', () {
      const slot = OperatingTimeSlot(startTime: '25:00', endTime: '23:00', crossesMidnight: false, displayOrder: 0);
      expect(validateTimeSlot(slot), isNotNull);
    });

    test('rejects identical start and end times', () {
      const slot = OperatingTimeSlot(startTime: '06:00', endTime: '06:00', crossesMidnight: false, displayOrder: 0);
      expect(validateTimeSlot(slot), 'Opening and closing time cannot be the same.');
    });

    test('accepts a valid slot', () {
      const slot = OperatingTimeSlot(startTime: '06:00', endTime: '23:00', crossesMidnight: false, displayOrder: 0);
      expect(validateTimeSlot(slot), isNull);
    });
  });

  group('validateOperatingDay', () {
    test('a closed day is always valid, regardless of slots', () {
      final day = _openDay().copyWith(isClosed: true);
      expect(validateOperatingDay(day), isNull);
    });

    test('a 24-hour day is always valid, regardless of slots', () {
      final day = _openDay().copyWith(is24Hours: true);
      expect(validateOperatingDay(day), isNull);
    });

    test('an open day with no slots is invalid', () {
      final day = _openDay(slots: const []);
      expect(validateOperatingDay(day), isNotNull);
    });

    test('an open day with overlapping slots is invalid', () {
      final day = _openDay(
        slots: const [
          OperatingTimeSlot(startTime: '06:00', endTime: '12:00', crossesMidnight: false, displayOrder: 0),
          OperatingTimeSlot(startTime: '10:00', endTime: '14:00', crossesMidnight: false, displayOrder: 1),
        ],
      );
      expect(validateOperatingDay(day), 'Operating hours cannot overlap.');
    });

    test('a valid open day passes', () {
      expect(validateOperatingDay(_openDay()), isNull);
    });
  });

  group('validateSchedule', () {
    test('returns no errors for a fully valid week', () {
      final days = daysOfWeek.map((d) => _openDay(dayOfWeek: d)).toList();
      expect(validateSchedule(days), isEmpty);
    });

    test('maps an error to its exact day of week', () {
      final days = daysOfWeek.map((d) => _openDay(dayOfWeek: d, slots: d == 2 ? const [] : _openDay().slots)).toList();
      final errors = validateSchedule(days);
      expect(errors.keys, [2]);
    });
  });

  group('withComputedOvernight', () {
    test('recomputes crossesMidnight from each slot\'s own times', () {
      final day = _openDay(
        slots: const [
          OperatingTimeSlot(startTime: '22:00', endTime: '02:00', crossesMidnight: false, displayOrder: 0),
        ],
      );
      final result = withComputedOvernight(day);
      expect(result.slots.single.crossesMidnight, isTrue);
    });
  });
}