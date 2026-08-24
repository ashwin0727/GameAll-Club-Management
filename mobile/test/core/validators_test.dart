import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('rejects an empty value', () {
      expect(Validators.email(''), isNotNull);
    });
    test('rejects a malformed address', () {
      expect(Validators.email('not-an-email'), isNotNull);
    });
    test('accepts a valid address', () {
      expect(Validators.email('owner@example.com'), isNull);
    });
  });

  group('Validators.password', () {
    test('rejects a short password', () {
      expect(Validators.password('short'), isNotNull);
    });
    test('accepts an 8+ character password', () {
      expect(Validators.password('longenough'), isNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('rejects a mismatch', () {
      expect(Validators.confirmPassword('abc', 'xyz'), isNotNull);
    });
    test('accepts a match', () {
      expect(Validators.confirmPassword('abc', 'abc'), isNull);
    });
  });

  group('Validators.phone', () {
    test('rejects a non-10-digit number', () {
      expect(Validators.phone('12345'), isNotNull);
    });
    test('accepts a 10-digit number', () {
      expect(Validators.phone('9876543210'), isNull);
    });
  });

  group('Validators.optionalPhone', () {
    test('is optional — empty is valid', () {
      expect(Validators.optionalPhone(''), isNull);
      expect(Validators.optionalPhone(null), isNull);
    });
    test('rejects a non-10-digit number when provided', () {
      expect(Validators.optionalPhone('12345'), isNotNull);
    });
    test('accepts a 10-digit number', () {
      expect(Validators.optionalPhone('9876543210'), isNull);
    });
  });

  group('Validators.pinCode', () {
    test('rejects a 4-digit code', () {
      expect(Validators.pinCode('1234'), isNotNull);
    });
    test('accepts a 6-digit code', () {
      expect(Validators.pinCode('600053'), isNull);
    });
  });

  group('Validators.positiveAmount', () {
    test('rejects zero', () {
      expect(Validators.positiveAmount('0'), isNotNull);
    });
    test('rejects a non-numeric value', () {
      expect(Validators.positiveAmount('abc'), isNotNull);
    });
    test('accepts a positive amount', () {
      expect(Validators.positiveAmount('400'), isNull);
    });
  });
}