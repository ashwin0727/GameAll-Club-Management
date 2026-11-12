import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gameall_club_mobile/data/models/app_user.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/data/models/playing_area.dart';
import 'package:gameall_club_mobile/data/models/pricing.dart';
import 'package:gameall_club_mobile/data/models/sport.dart';
import 'package:gameall_club_mobile/data/repositories/facility_repository.dart';
import 'package:gameall_club_mobile/data/repositories/operating_hours_repository.dart';
import 'package:gameall_club_mobile/data/repositories/playing_area_repository.dart';
import 'package:gameall_club_mobile/data/repositories/pricing_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/data/repositories/sports_repository.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/onboarding/pricing_setup_screen.dart';

Facility _facility() => const Facility(
      id: 'f1',
      ownerId: 'u1',
      name: 'Arena',
      type: FacilityType.multiSport,
      businessEmail: 'o@x.com',
      businessPhone: '9876543210',
      address: FacilityAddress(line1: 'a', area: 'b', city: 'c', state: 'Tamil Nadu', country: 'India', pinCode: '600001'),
      status: 'ACTIVE',
      onboardingStep: OnboardingStep.pricing,
    );

class _FakeFacilityRepo implements FacilityRepository {
  final steps = <OnboardingStep>[];
  Map<String, Object?>? settings;

  @override
  Future<Facility?> getFacility() async => _facility();

  @override
  Future<void> updateOnboardingStep(String facilityId, OnboardingStep step) async => steps.add(step);

  @override
  Future<void> updatePricingSettings(String facilityId, {required String mode, required bool differentWeekendPricing, required bool memberPricingEnabled, required bool coachingPricingEnabled}) async {
    settings = {'mode': mode, 'weekend': differentWeekendPricing, 'member': memberPricingEnabled, 'coaching': coachingPricingEnabled};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSportsRepo implements SportsRepository {
  final all = [Sport.fromJson({'id': 'sport-badminton', 'key': 'badminton', 'name': 'Badminton', 'is_active': true}), Sport.fromJson({'id': 'sport-football', 'key': 'football', 'name': 'Football', 'is_active': true})];

  @override
  Future<List<Sport>> getActiveSports() async => all;

  @override
  Future<List<FacilitySport>> getFacilitySports(String facilityId) async => [
        const FacilitySport(id: 'fs-bad', facilityId: 'f1', sportId: 'sport-badminton', enabled: true),
        const FacilitySport(id: 'fs-foot', facilityId: 'f1', sportId: 'sport-football', enabled: true),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAreaRepo implements PlayingAreaRepository {
  @override
  Future<List<PlayingArea>> getPlayingAreas(String facilityId) async => const [
        PlayingArea(id: 'court-1', facilityId: 'f1', facilitySportId: 'fs-bad', sportId: 'sport-badminton', name: 'Court 1', areaType: 'INDOOR', status: 'ACTIVE', bookingEnabled: true, archived: false, displayOrder: 0),
        PlayingArea(id: 'court-2', facilityId: 'f1', facilitySportId: 'fs-foot', sportId: 'sport-football', name: 'Turf 1', areaType: 'OUTDOOR', status: 'ACTIVE', bookingEnabled: true, archived: false, displayOrder: 0),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHoursRepo implements OperatingHoursRepository {
  @override
  Future<OperatingSchedule?> getFacilitySchedule(String facilityId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePricingRepo implements PricingRepository {
  List<PricingRule>? saved;

  @override
  Future<PricingPlan?> getPricingPlan(String facilityId) async => null;

  @override
  Future<void> savePricingRules(String facilityId, List<PricingRule> rules) async => saved = rules;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSession extends SessionController {
  @override
  SessionState build() => SessionState(
        user: const AppUser(id: 'u1', fullName: 'Ravi', email: 'o@x.com', role: 'owner', onboardingCompleted: false),
        facility: _facility(),
        isLoading: false,
      );

  @override
  Future<void> refresh() async {}
}

late _FakeFacilityRepo _facilityRepo;
late _FakePricingRepo _pricingRepo;

Future<void> _pump(WidgetTester tester, {double width = 390}) async {
  tester.view.physicalSize = Size(width * 3, 9000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  _facilityRepo = _FakeFacilityRepo();
  _pricingRepo = _FakePricingRepo();

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PricingSetupScreen()),
      GoRoute(path: '/onboarding/operating-hours', builder: (_, _) => const Scaffold(body: Text('HOURS PAGE'))),
      GoRoute(path: '/onboarding/payments', builder: (_, _) => const Scaffold(body: Text('PAYMENTS PAGE'))),
      GoRoute(path: '/onboarding/sports-courts', builder: (_, _) => const Scaffold(body: Text('SPORTS PAGE'))),
      GoRoute(path: '/onboarding/facility', builder: (_, _) => const Scaffold(body: Text('FACILITY PAGE'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        facilityRepositoryProvider.overrideWithValue(_facilityRepo),
        sportsRepositoryProvider.overrideWithValue(_FakeSportsRepo()),
        playingAreaRepositoryProvider.overrideWithValue(_FakeAreaRepo()),
        operatingHoursRepositoryProvider.overrideWithValue(_FakeHoursRepo()),
        pricingRepositoryProvider.overrideWithValue(_pricingRepo),
        sessionControllerProvider.overrideWith(_FakeSession.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.enterText(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextFormField)), text);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('opens on By Sport with the first sport open and the settings and preview shown', (tester) async {
    await _pump(tester);
    expect(find.text('Pricing'), findsWidgets);
    expect(find.text('Sport Pricing'), findsOneWidget);
    expect(find.byKey(const ValueKey('base-sport-fs-bad')), findsOneWidget);
    expect(find.text('Pricing Settings'), findsOneWidget);
    expect(find.text('Pricing Preview'), findsOneWidget);
  });

  testWidgets('Next without a price is refused and nothing is saved', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Please fix the highlighted fields'), findsOneWidget);
    expect(find.text('Enter the base price.'), findsOneWidget);
    expect(_pricingRepo.saved, isNull);
  });

  testWidgets('both sports priced saves their rules, the settings and moves to Payments', (tester) async {
    await _pump(tester);
    await _type(tester, 'base-sport-fs-bad', '400');
    await _tap(tester, 'sport-toggle-fs-foot');
    await _type(tester, 'base-sport-fs-foot', '1500');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('PAYMENTS PAGE'), findsOneWidget);
    final rules = _pricingRepo.saved!;
    expect(rules.map((r) => r.amountMinor), [40000, 150000]);
    expect(rules.every((r) => r.playingAreaId == null && r.audience == 'GENERAL'), isTrue);
    expect(_facilityRepo.settings, {'mode': 'BY_SPORT', 'weekend': true, 'member': false, 'coaching': false});
    expect(_facilityRepo.steps, [OnboardingStep.payments]);
  });

  testWidgets('time-based pricing: a slot is added, priced and tagged Peak above the base', (tester) async {
    await _pump(tester);
    await _type(tester, 'base-sport-fs-bad', '400');
    await _tap(tester, 'timebased-sport-fs-bad');
    // a first slot is added for Weekdays, open from 6 AM
    expect(find.byKey(const ValueKey('add-slot-sport-fs-bad')), findsOneWidget);
    final price = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('slot-price-'));
    await tester.enterText(find.descendant(of: price, matching: find.byType(TextFormField)), '650');
    await tester.pumpAndSettle();
    expect(find.text('Peak'), findsWidgets);
    expect(find.text('₹400 – ₹650 / hour'), findsOneWidget); // the preview line
  });

  testWidgets('member and coaching prices appear once their settings are on, and are required', (tester) async {
    await _pump(tester);
    await _type(tester, 'base-sport-fs-bad', '400');
    await _tap(tester, 'switch-member');
    expect(find.byKey(const ValueKey('member-sport-fs-bad')), findsOneWidget);
    await _tap(tester, 'switch-coaching');
    expect(find.byKey(const ValueKey('coaching-sport-fs-bad')), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the member price.'), findsOneWidget);
    expect(find.text('Enter the coaching price.'), findsOneWidget);
  });

  testWidgets('By Court lists the courts, starts each from its sport and saves per-court rules', (tester) async {
    await _pump(tester);
    await _type(tester, 'base-sport-fs-bad', '400');
    await _tap(tester, 'mode-byCourt');
    expect(find.text('Select Court'), findsOneWidget);
    expect(find.text('Court 1 – Badminton'), findsOneWidget);
    expect(find.textContaining('This pricing applies only to Court 1'), findsOneWidget);
    // Court 1 started from Badminton's 400; Turf 1 has no price yet
    await _tap(tester, 'court-court-2');
    await _type(tester, 'base-court-court-2', '1500');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    final rules = _pricingRepo.saved!;
    expect(rules.map((r) => (r.playingAreaId, r.amountMinor, r.priority)), [('court-1', 40000, 10), ('court-2', 150000, 10)]);
    expect(_facilityRepo.settings!['mode'], 'BY_COURT');
  });

  testWidgets('Back returns to Operating Hours', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('HOURS PAGE'), findsOneWidget);
  });

  testWidgets('fits a 320 px wide phone without overflow', (tester) async {
    await _pump(tester, width: 320);
    await _type(tester, 'base-sport-fs-bad', '400');
    await _tap(tester, 'timebased-sport-fs-bad');
    await _tap(tester, 'mode-byCourt');
    expect(tester.takeException(), isNull);
  });
}
