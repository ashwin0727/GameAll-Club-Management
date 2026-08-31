import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/memberships/slot_format.dart';

/// Mirrors src/features/memberships/slot-format.ts.
void main() {
  group('formatClock', () {
    test('converts 24h (with or without seconds) to 12h with meridiem', () {
      expect(formatClock('06:00:00'), '6:00 AM');
      expect(formatClock('06:00'), '6:00 AM');
      expect(formatClock('13:30'), '1:30 PM');
      expect(formatClock('00:15'), '12:15 AM');
      expect(formatClock('12:00'), '12:00 PM');
    });
  });

  group('formatSlot', () {
    test('sorts days and joins with the time range', () {
      expect(formatSlot([5, 1, 3], '05:00', '06:00'), 'Mon/Wed/Fri · 5:00 AM – 6:00 AM');
    });

    test('drops the day prefix when there are no valid days', () {
      expect(formatSlot([], '18:00', '19:00'), '6:00 PM – 7:00 PM');
    });
  });
}