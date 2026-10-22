import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/onboarding/payout_validation.dart';

void main() {
  test('account numbers are 9 to 18 digits', () {
    expect(PayoutValidators.accountNumber('123456789012'), isNull);
    expect(PayoutValidators.accountNumber('1234'), isNotNull);
    expect(PayoutValidators.accountNumber('12345678a'), isNotNull);
  });

  test('IFSC is four letters, a zero, then six characters (any case)', () {
    expect(PayoutValidators.ifsc('hdfc0001234'), isNull);
    expect(PayoutValidators.ifsc('HDFC123'), isNotNull);
  });

  test('UPI id needs a handle and a bank', () {
    expect(PayoutValidators.upiId('Champz@OkHDFC'), isNull);
    expect(PayoutValidators.upiId('nope'), isNotNull);
  });

  test('names need at least two characters', () {
    expect(PayoutValidators.holderName('Champz Turf'), isNull);
    expect(PayoutValidators.holderName('A'), isNotNull);
    expect(PayoutValidators.bankName('HDFC Bank'), isNull);
  });

  test('masks account numbers and UPI handles', () {
    expect(PayoutValidators.maskAccountNumber('123456789012'), 'XXXXXXXX9012');
    expect(PayoutValidators.maskUpi('champz@okhdfc'), 'ch••••@okhdfc');
  });
}
