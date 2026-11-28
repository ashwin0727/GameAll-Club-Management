import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/data/models/coaching.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/sport.dart';
import 'package:gameall_club_mobile/data/repositories/coaching_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/data/repositories/sports_repository.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/coaching/coach_onboarding_screen.dart';

/// The 5-step Add Coach screen: opens a saved draft on its saved step with its saved values, and every step lays out
/// without overflow on a 320 px-wide phone.

Facility _facility() => Facility(
      id: 'facility-1',
      ownerId: 'owner-1',
      name: 'Test Arena',
      type: FacilityType.multiSport,
      businessEmail: 'o@x.com',
      businessPhone: '900',
      address: const FacilityAddress(line1: 'a', area: 'b', city: 'c', state: 'd', country: 'India', pinCode: '600001'),
      status: 'ACTIVE',
      onboardingStep: OnboardingStep.completed,
    );

class _FakeSession extends SessionController {
  @override
  SessionState build() => SessionState(facility: _facility(), baseRole: 'owner', isLoading: false);
}

CoachOnboarding _saved({int step = 3, bool canManagePayouts = true}) => CoachOnboarding.fromJson({
      'coachId': 'c1',
      'userId': 'u1',
      'currentStep': step,
      'stepsDone': [1, 2],
      'onboardingStatus': 'DRAFT',
      'payoutStatus': 'PENDING',
      'canManagePayouts': canManagePayouts,
      'identity': {'displayName': 'Ravi Kumar', 'location': 'Chennai', 'languages': ['English']},
      'expertise': {'niche': 'Badminton', 'experienceYears': 5, 'sportIds': ['s1'], 'expertiseLevels': ['Beginner']},
      'services': {
        'perSessionRateMinor': 50000,
        'weeklyRateMinor': 200000,
        'sessionFormats': ['GROUP'],
        'sessionDurations': [60],
      },
    });

class _FakeCoaching implements CoachingRepository {
  _FakeCoaching(this.onboarding);
  final CoachOnboarding onboarding;

  @override
  Future<CoachOnboarding> getCoachOnboarding(String coachId) async => onboarding;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSports implements SportsRepository {
  @override
  Future<List<FacilitySport>> getFacilitySports(String facilityId) async => const [];

  @override
  Future<List<Sport>> getActiveSports() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, CoachOnboarding saved, {int? step, Size size = const Size(320, 700)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(_FakeSession.new),
        coachingRepositoryProvider.overrideWithValue(_FakeCoaching(saved)),
        sportsRepositoryProvider.overrideWithValue(_FakeSports()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: CoachOnboardingScreen(resumeCoachId: 'c1', initialStep: step)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a saved draft opens on its saved step', (tester) async {
    await _pump(tester, _saved(step: 3));
    expect(find.text('Step 3 of 5 · Sessions & Pricing'), findsOneWidget);
    expect(find.text('Save & continue'), findsOneWidget);
  });

  testWidgets('going back shows the saved values, not a blank form', (tester) async {
    await _pump(tester, _saved(step: 3));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 5 · Expertise & Credentials'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Badminton'), findsOneWidget);
  });

  for (final step in [1, 2, 3, 4, 5]) {
    testWidgets('step $step lays out without overflow at 320 px', (tester) async {
      await _pump(tester, _saved(step: step));
      expect(find.textContaining('Step $step of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('?step overrides the saved step (Add payout details opens step 4)', (tester) async {
    await _pump(tester, _saved(step: 5), step: 4);
    expect(find.text('Step 4 of 5 · Payments, Payouts & KYC'), findsOneWidget);
    expect(find.text('Finish later'), findsOneWidget);
  });

  testWidgets('without the payouts permission step 4 is locked and can be skipped', (tester) async {
    await _pump(tester, _saved(step: 4, canManagePayouts: false));
    expect(find.textContaining('restricted'), findsOneWidget);
    expect(find.text('Finish later'), findsNothing);
  });
}
