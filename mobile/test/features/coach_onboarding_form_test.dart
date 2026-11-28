import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/coaching.dart';
import 'package:gameall_club_mobile/features/coaching/coach_onboarding_form.dart';

CoachOnboardingForm newPersonForm() => CoachOnboardingForm()
  ..newPerson = true
  ..firstName = 'Ravi'
  ..lastName = 'Kumar'
  ..phone = '9876543210'
  ..email = 'ravi@x.com'
  ..roleId = 'r1'
  ..displayName = 'Ravi Kumar';

CoachOnboardingForm bankForm() => CoachOnboardingForm()
  ..taxId = 'abcde 1234f'
  ..accountHolderName = 'Ravi Kumar'
  ..accountNumber = '123456789012'
  ..confirmAccountNumber = '123456789012'
  ..ifsc = 'sbin 0001234';

void main() {
  group('step 1', () {
    test('a new person needs a name, a valid email and a complete phone', () {
      expect(CoachOnboardingForm().isStepValid(1), false);
      expect(newPersonForm().isStepValid(1), true);
      expect((newPersonForm()..phone = '98765').isStepValid(1), false);
      expect((newPersonForm()..phone = '').isStepValid(1), false); // the phone number is mandatory
      expect((newPersonForm()..email = 'nope').isStepValid(1), false);
    });

    test('an existing staff member needs to be picked', () {
      final f = CoachOnboardingForm()..displayName = 'Asha';
      expect(f.isStepValid(1), false);
      f.userId = 'u1';
      expect(f.isStepValid(1), true);
    });
  });

  test('step 2 needs niche, a sport, an expertise level and non-negative experience', () {
    CoachOnboardingForm ok() => CoachOnboardingForm()
      ..niche = 'Badminton'
      ..experience = '5'
      ..sportIds.add('s1')
      ..expertiseLevels.add('Beginner');
    expect(ok().isStepValid(2), true);
    expect((ok()..niche = '').isStepValid(2), false);
    expect((ok()..sportIds.clear()).isStepValid(2), false);
    expect((ok()..expertiseLevels.clear()).isStepValid(2), false);
    expect((ok()..experience = '-1').isStepValid(2), false);
  });

  test('step 3 needs a format and a duration; the three coaching amounts are optional but valid when filled', () {
    CoachOnboardingForm ok() => CoachOnboardingForm()
      ..sessionFormats.add('ONE_TO_ONE')
      ..sessionDurations.add(60);
    expect(ok().isStepValid(3), true); // all three amounts blank
    expect((ok()..perSessionRate = '500'..weeklyRate = '2000'..monthlyRate = '7000').isStepValid(3), true);
    expect((ok()..weeklyRate = '2000').isStepValid(3), true);
    for (final bad in ['0', '-5', '10.5', 'abc']) {
      expect((ok()..perSessionRate = bad).isStepValid(3), false, reason: bad);
      expect((ok()..weeklyRate = bad).isStepValid(3), false, reason: bad);
      expect((ok()..monthlyRate = bad).isStepValid(3), false, reason: bad);
    }
    expect((ok()..sessionFormats.clear()).isStepValid(3), false);
    expect((ok()..sessionDurations.clear()).isStepValid(3), false);
  });

  group('step 4', () {
    test('pasted PAN/IFSC are normalised; account confirmation must match', () {
      expect(bankForm().isStepValid(4), true);
      expect((bankForm()..confirmAccountNumber = '123456789013').isStepValid(4), false);
      expect((bankForm()..ifsc = 'abc').isStepValid(4), false);
      expect((bankForm()..taxId = '12345').isStepValid(4), false);
      expect((bankForm()..accountHolderName = '').isStepValid(4), false);
    });

    test('UPI needs a valid id; a business needs name + address', () {
      CoachOnboardingForm upi() => bankForm()
        ..payoutMethod = 'UPI'
        ..upiId = 'ravi@okhdfc';
      expect(upi().isStepValid(4), true);
      expect((upi()..upiId = 'ravi@').isStepValid(4), false);
      expect((upi()..entityType = 'BUSINESS').isStepValid(4), false);
      expect((upi()
            ..entityType = 'BUSINESS'
            ..legalName = 'Ravi Sports'
            ..businessAddress = '1 Main Rd')
          .isStepValid(4), true);
    });

    test('blank secrets are accepted when a payout is already saved (they are masked on screen)', () {
      final f = bankForm()
        ..taxId = ''
        ..accountNumber = ''
        ..confirmAccountNumber = ''
        ..ifsc = '';
      expect(f.isStepValid(4), false);
      expect(f.isStepValid(4, hasSavedPayout: true), true);
    });
  });

  test('step 5 needs all four agreements', () {
    final f = CoachOnboardingForm()
      ..agreeTerms = true
      ..agreeEthics = true
      ..agreePrivacy = true;
    expect(f.isStepValid(5), false);
    f.agreeCommission = true;
    expect(f.isStepValid(5), true);
  });

  test('payloads convert rupees to paise (blank amounts are null) and normalise codes', () {
    final f = bankForm()
      ..perSessionRate = '500'
      ..monthlyRate = '7000'
      ..sessionDurations.add(60);
    final p3 = f.stepPayload(3);
    expect(p3['perSessionRateMinor'], 50000);
    expect(p3['weeklyRateMinor'], isNull);
    expect(p3['monthlyRateMinor'], 700000);
    final p4 = f.stepPayload(4);
    expect(p4['taxId'], 'ABCDE1234F');
    expect(p4['ifsc'], 'SBIN0001234');
  });

  group('resuming a saved draft', () {
    CoachOnboarding saved({int step = 3}) => CoachOnboarding.fromJson({
          'coachId': 'c1',
          'userId': 'u1',
          'currentStep': step,
          'stepsDone': [1, 2],
          'onboardingStatus': 'DRAFT',
          'payoutStatus': 'PENDING',
          'canManagePayouts': true,
          'identity': {'displayName': 'Ravi Kumar', 'location': 'Chennai', 'languages': ['English']},
          'expertise': {'niche': 'Badminton', 'experienceYears': 5, 'sportIds': ['s1'], 'expertiseLevels': ['Beginner']},
          'services': {'perSessionRateMinor': 50000},
        });

    test('opens at the saved step with the saved values (not a blank form)', () {
      final o = saved();
      expect(o.resumeStep, 3);
      final f = CoachOnboardingForm.fromOnboarding(o);
      expect(f.userId, 'u1');
      expect(f.niche, 'Badminton');
      expect(f.experience, '5');
      expect(f.sportIds, {'s1'});
      expect(f.perSessionRate, '500');
    });

    test('clamps a bad step into 1..5', () {
      expect(saved(step: 9).resumeStep, 5);
      expect(saved(step: 0).resumeStep, 1);
    });
  });
}
