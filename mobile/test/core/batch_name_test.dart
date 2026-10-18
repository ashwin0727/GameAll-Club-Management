import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/utils/batch_name.dart';

void main() {
  test('a start-time-only slot name shows its whole range', () {
    expect(
      displayBatchName('Morning Monthly Membership (5 AM to 6 AM) — 05:00', '05:00:00', '06:00:00'),
      'Morning Monthly Membership (5 AM to 6 AM) — 05:00 to 06:00',
    );
    expect(displayBatchName('Evening Plan - 18:30:00', '18:30:00', '19:30:00'), 'Evening Plan — 18:30 to 19:30');
  });

  test('other names are left alone', () {
    expect(displayBatchName('Plan — 05:00 to 06:00', '05:00', '06:00'), 'Plan — 05:00 to 06:00');
    expect(displayBatchName('Batch 1', '05:00', '06:00'), 'Batch 1');
    expect(displayBatchName('Plan — 05:00', '', ''), 'Plan — 05:00');
  });

  test('a new slot is named with its whole range', () {
    expect(newBatchName('Morning Plan', '05:00', '06:00'), 'Morning Plan — 05:00 to 06:00');
  });
}
