import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/coaching.dart' show AvailabilityWindow;
import 'package:gameall_club_mobile/features/coaching/add_coach_validation.dart';

void main() {
  test('IFSC is normalised before it is checked', () {
    expect(isValidIfsc('sbin0001234'), false);
    expect(isValidIfsc(normalizeIfsc(' sbin 0001234 ')), true);
    expect(isValidIfsc('SBIN1001234'), false);
    expect(isValidIfsc('SBIN000123'), false);
  });

  test('PAN and GSTIN follow their formats', () {
    expect(isValidPan('ABCDE1234F'), true);
    expect(isValidPan(normalizePan(' abcde 1234f ')), true);
    expect(isValidPan('ABCDE12345'), false);
    expect(isValidGstin('22ABCDE1234F1Z5'), true);
    expect(isValidGstin('22ABCDE1234F1X5'), false);
  });

  test('UPI id needs a handle on both sides of @', () {
    expect(isValidUpi('name@okhdfc'), true);
    expect(isValidUpi('name@'), false);
    expect(isValidUpi('@okhdfc'), false);
  });

  test('account number is 9 to 18 digits', () {
    expect(isValidAccountNumber('12345678'), false);
    expect(isValidAccountNumber('123456789'), true);
    expect(isValidAccountNumber('1234567890123456789'), false);
    expect(isValidAccountNumber('12345 6789'), false);
  });

  test('rupees are positive whole numbers and convert to paise', () {
    expect(isValidRupees('500'), true);
    for (final bad in ['0', '-5', '10.5', '', 'abc']) {
      expect(isValidRupees(bad), false, reason: bad);
    }
    expect(rupeesToMinor('500'), 50000);
  });

  test('a slot must end after it starts', () {
    expect(isValidSlot('09:00', '09:00'), false);
    expect(isValidSlot('10:00', '09:00'), false);
    expect(isValidSlot('09:00', '10:00'), true);
  });

  test('a repeated or overlapping slot on the same day is flagged, naming both', () {
    AvailabilityWindow w(int d, String s, String e) => AvailabilityWindow(dayOfWeek: d, startTime: s, endTime: e);
    expect(findAvailabilityConflict([w(1, '09:00', '12:00'), w(2, '09:00', '12:00')]), isNull);
    expect(findAvailabilityConflict([w(1, '09:00', '12:00'), w(1, '12:00', '14:00')]), isNull);
    expect(findAvailabilityConflict([w(1, '09:00', '12:00'), w(1, '09:00', '12:00')]), contains('Mon 09:00–12:00 is added twice'));
    expect(findAvailabilityConflict([w(1, '09:00', '12:00'), w(1, '11:00', '13:00')]), contains('Mon 09:00–12:00 overlaps Mon 11:00–13:00'));
    expect(findAvailabilityConflict([w(1, '11:00', '13:00'), w(3, '08:00', '09:00'), w(1, '09:00', '12:00')]), contains('overlaps'));
    expect(findAvailabilityConflict([w(1, '10:00', '09:00')]), isNull);
  });

  test('certificate files: images/PDF up to 5 MB', () {
    expect(validateCertificate('a.pdf', 6 * 1024 * 1024), contains('larger than 5MB'));
    expect(validateCertificate('a.gif', 1), contains('JPG, PNG, WEBP or PDF'));
    expect(validateCertificate('a.pdf', 1024 * 1024), isNull);
    expect(validateCertificate('A.JPG', 10), isNull);
  });
}
