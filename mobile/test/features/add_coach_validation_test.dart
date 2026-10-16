import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/coaching/add_coach_validation.dart';

void main() {
  test('email', () {
    expect(isValidEmail('a@b.co'), true);
    expect(isValidEmail(' a@b.co '), true);
    expect(isValidEmail('a@b'), false);
    expect(isValidEmail(''), false);
  });

  test('phone keeps digits only, caps at 10, and is valid empty or complete', () {
    expect(sanitizePhoneDigits('+91 98765-43210'), '9198765432');
    expect(sanitizePhoneDigits('abc98765'), '98765');
    expect(isValidPhoneDigits(''), true);
    expect(isValidPhoneDigits('9876543210'), true);
    expect(isValidPhoneDigits('98765'), false);
  });

  test('date of birth must be 18–100 years ago, and is optional', () {
    final today = DateTime(2026, 10, 16);
    expect(isValidDateOfBirth(null, today), true);
    expect(isValidDateOfBirth(DateTime(1995, 5, 1), today), true);
    expect(isValidDateOfBirth(DateTime(2010, 1, 1), today), false); // 16
    expect(isValidDateOfBirth(DateTime(2008, 10, 16), today), true); // exactly 18
    expect(isValidDateOfBirth(DateTime(1920, 1, 1), today), false); // 106
    expect(isValidDateOfBirth(DateTime(2030, 1, 1), today), false);
  });
}
