import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gameall_club_mobile/features/onboarding/setup_flow.dart';

import 'package:gameall_club_mobile/data/models/app_user.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/data/models/playing_area.dart';
import 'package:gameall_club_mobile/data/models/sport.dart';
import 'package:gameall_club_mobile/data/repositories/facility_repository.dart';
import 'package:gameall_club_mobile/data/repositories/operating_hours_repository.dart';
import 'package:gameall_club_mobile/data/repositories/playing_area_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/data/repositories/sports_repository.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/onboarding/hours_setup_logic.dart';
import 'package:gameall_club_mobile/features/onboarding/operating_hours_setup_screen.dart';

Facility _facility({bool allowOutside = true, String? breakStart, String? breakEnd, bool sportWise = false}) => Facility(
      id: 'f1',
      ownerId: 'u1',
      name: 'Arena',
      type: FacilityType.multiSport,
      businessEmail: 'o@x.com',
      businessPhone: '9876543210',
      address: const FacilityAddress(line1: 'a', area: 'b', city: 'c', state: 'Tamil Nadu', country: 'India', pinCode: '600001'),
      status: 'ACTIVE',
      onboardingStep: OnboardingStep.operatingHours,
      allowBookingsOutsideHours: allowOutside,
      breakStart: breakStart,
      breakEnd: breakEnd,
      sportWiseHours: sportWise,
    );

class _FakeFacilityRepo implements FacilityRepository {
  _FakeFacilityRepo(this.facility);
  final Facility facility;
  final steps = <OnboardingStep>[];
  Map<String, Object?>? settings;

  @override
  Future<Facility?> getFacility() async => facility;

  @override
  Future<void> updateOnboardingStep(String facilityId, OnboardingStep step) async => steps.add(step);

  @override
  Future<void> updateHoursSettings(String facilityId, {required bool allowBookingsOutsideHours, String? breakStart, String? breakEnd, required bool sportWiseHours}) async {
    settings = {'outside': allowBookingsOutsideHours, 'breakStart': breakStart, 'breakEnd': breakEnd, 'sportWise': sportWiseHours};
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
  OperatingSchedule? schedule;
  List<ClosureEntry> closures = [];
  final areaSchedules = <String, OperatingSchedule>{};
  final deleted = <String>[];
  List<OperatingDay>? savedDays;
  List<ClosureEntry>? savedClosures;

  @override
  Future<OperatingSchedule?> getFacilitySchedule(String facilityId) async => schedule;

  @override
  Future<void> saveFacilitySchedule(String facilityId, List<OperatingDay> days) async => savedDays = days;

  @override
  Future<List<ClosureEntry>> getClosures(String facilityId) async => closures;

  @override
  Future<List<ClosureEntry>> replaceClosures(String facilityId, List<ClosureEntry> c) async => savedClosures = c;

  @override
  Future<OperatingSchedule?> getPlayingAreaSchedule(String playingAreaId) async => areaSchedules[playingAreaId];

  @override
  Future<void> savePlayingAreaSchedule(String playingAreaId, String facilityId, List<OperatingDay> days) async {
    areaSchedules[playingAreaId] = OperatingSchedule(id: 's', facilityId: facilityId, scopeType: 'PLAYING_AREA', playingAreaId: playingAreaId, timezone: 'Asia/Kolkata', days: days);
  }

  @override
  Future<void> deletePlayingAreaOverride(String playingAreaId) async {
    deleted.add(playingAreaId);
    areaSchedules.remove(playingAreaId);
  }

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
late _FakeHoursRepo _hoursRepo;

Future<void> _pump(WidgetTester tester, {Facility? facility, void Function(_FakeHoursRepo)? seed}) async {
  tester.view.physicalSize = const Size(390 * 3, 7000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  _facilityRepo = _FakeFacilityRepo(facility ?? _facility());
  _hoursRepo = _FakeHoursRepo();
  seed?.call(_hoursRepo);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const OperatingHoursSetupScreen()),
      GoRoute(path: '/onboarding/sports-courts', builder: (_, _) => const Scaffold(body: Text('SPORTS PAGE'))),
      GoRoute(path: '/onboarding/pricing', builder: (_, _) => const Scaffold(body: Text('PRICING PAGE'))),
      GoRoute(path: '/onboarding/facility', builder: (_, _) => const Scaffold(body: Text('FACILITY PAGE'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        facilityRepositoryProvider.overrideWithValue(_facilityRepo),
        sportsRepositoryProvider.overrideWithValue(_FakeSportsRepo()),
        playingAreaRepositoryProvider.overrideWithValue(_FakeAreaRepo()),
        operatingHoursRepositoryProvider.overrideWithValue(_hoursRepo),
        sessionControllerProvider.overrideWith(_FakeSession.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens a time box and picks one of the half hours in its sheet.
Future<void> _pickTime(WidgetTester tester, String id, String value) async {
  await tester.tap(find.byKey(ValueKey('time-$id')));
  await tester.pumpAndSettle();
  final option = find.byKey(ValueKey('time-option-$value'));
  await tester.scrollUntilVisible(option, 200, scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _addClosure(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('add-closure')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('closure-name')), name);
  await tester.tap(find.byKey(const ValueKey('closure-date')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK')); // the calendar opens on today
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('closure-save')));
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('starts with Standard Hours: Monday to Saturday, 6 AM to 11 PM, Sunday closed', (tester) async {
    await _pump(tester);

    expect(find.text('Operating Hours'), findsWidgets);
    expect(find.text('Step 3 of 5 · Operating Hours'), findsOneWidget);
    expect(find.text('Total Hours: 17 Hours'), findsOneWidget);
    expect(find.text('6:00 AM'), findsOneWidget);
    expect(find.text('11:00 PM'), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-0')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('preview-0')), matching: find.text('Closed')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('preview-1')), matching: find.text('6:00 AM – 11:00 PM')), findsOneWidget);
  });

  testWidgets('choosing a time from the list updates the total and the preview', (tester) async {
    await _pump(tester);

    await _pickTime(tester, 'std-close', '22:00');
    expect(find.text('Total Hours: 16 Hours'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('preview-2')), matching: find.text('6:00 AM – 10:00 PM')), findsOneWidget);

    await _pickTime(tester, 'std-close', '00:00');
    expect(find.text('Total Hours: 18 Hours'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('preview-2')), matching: find.text('6:00 AM – 12:00 AM (next day)')), findsOneWidget);
  });

  testWidgets('days can be switched off, and with none open Next refuses', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('std-day-6')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('preview-6')), matching: find.text('Closed')), findsOneWidget);

    for (final d in [1, 2, 3, 4, 5]) {
      await tester.tap(find.byKey(ValueKey('std-day-$d')));
      await tester.pump();
    }
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Select at least one operating day.'), findsOneWidget);
    expect(find.text('PRICING PAGE'), findsNothing);
  });

  testWidgets('Custom Hours: each day has its own times and status, with a weekly total', (tester) async {
    await _pump(tester);

    await _toggle(tester, 'mode-custom');
    expect(find.text('Set Custom Operating Hours'), findsOneWidget);
    expect(find.text('102 Hours'), findsOneWidget);

    await _pickTime(tester, 'day-3-close', '22:00');
    expect(find.text('101 Hours'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('custom-open-5')));
    await tester.pumpAndSettle();
    expect(find.text('84 Hours'), findsOneWidget);
  });

  testWidgets('switching to Custom keeps the standard hours, and back to Standard takes the first open day\'s hours', (tester) async {
    await _pump(tester);

    await _pickTime(tester, 'std-open', '07:00');
    await _toggle(tester, 'mode-custom');
    expect(find.text('7:00 AM'), findsWidgets);
    await _toggle(tester, 'mode-standard');
    expect(find.text('Total Hours: 16 Hours'), findsOneWidget);
  });

  testWidgets('a break must be a real range inside the working hours, shows in the preview and takes hours off', (tester) async {
    await _pump(tester);

    await _toggle(tester, 'switch-break');
    expect(find.text('Total Hours: 16 Hours'), findsOneWidget);
    expect(find.textContaining('Daily break: 1:00 PM – 2:00 PM'), findsOneWidget);

    await _pickTime(tester, 'break-start', '05:00');
    await _pickTime(tester, 'break-end', '05:30');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('The break must fall inside the working hours of every open day.'), findsOneWidget);
    expect(find.text('PRICING PAGE'), findsNothing);
  });

  testWidgets('adds, edits and removes a holiday, and refuses a duplicate date', (tester) async {
    await _pump(tester);

    await _addClosure(tester, 'Diwali');
    expect(find.text('Diwali'), findsOneWidget);

    // the same date again
    await _addClosure(tester, 'Another');
    expect(find.byKey(const ValueKey('closure-error')), findsOneWidget);
    expect(find.text('This date is already marked as closed.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit Diwali'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('closure-name')), 'Deepavali');
    await tester.tap(find.byKey(const ValueKey('closure-save')));
    await tester.pumpAndSettle();
    expect(find.text('Deepavali'), findsOneWidget);
    expect(find.text('Diwali'), findsNothing);

    await tester.tap(find.byTooltip('Remove Deepavali'));
    await tester.pumpAndSettle();
    expect(find.text('Deepavali'), findsNothing);
  });

  testWidgets('a holiday needs a name and a date', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('add-closure')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('closure-save')));
    await tester.pumpAndSettle();
    expect(find.text('Select a date.'), findsOneWidget);
  });

  testWidgets('Next saves the schedule, closures and settings, advances setup and goes on to Pricing', (tester) async {
    await _pump(tester);

    await _pickTime(tester, 'std-close', '22:00');
    await _toggle(tester, 'switch-outside'); // on by default -> off
    await _toggle(tester, 'switch-break');
    await _addClosure(tester, 'Diwali');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('PRICING PAGE'), findsOneWidget);
    final mon = _hoursRepo.savedDays!.firstWhere((d) => d.dayOfWeek == 1);
    expect([for (final s in mon.slots) (s.startTime, s.endTime)], [('06:00', '13:00'), ('14:00', '22:00')]);
    expect(_hoursRepo.savedDays!.firstWhere((d) => d.dayOfWeek == 0).isClosed, isTrue);
    expect(_hoursRepo.savedClosures!.single.name, 'Diwali');
    expect(_facilityRepo.settings, {'outside': false, 'breakStart': '13:00', 'breakEnd': '14:00', 'sportWise': false});
    expect(_facilityRepo.steps, [OnboardingStep.pricing]);
  });

  testWidgets('a change is saved as a draft by itself after 10 quiet seconds: it stays on the page, and a small notice shows at the top', (tester) async {
    await _pump(tester);
    expect(find.text('Save as Draft'), findsNothing);

    await _pickTime(tester, 'std-close', '22:00');
    await tester.pump(const Duration(seconds: 6));
    expect(_hoursRepo.savedDays, isNull, reason: 'not before 10 seconds');

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(_hoursRepo.savedDays, isNotNull);
    expect(find.text(kDraftSavedMessage), findsOneWidget);
    expect(find.text('PRICING PAGE'), findsNothing);
    expect(_facilityRepo.steps, isEmpty);
  });

  testWidgets('hours that are not valid yet are not auto-saved, and nothing is shown about it', (tester) async {
    await _pump(tester);

    for (final d in [1, 2, 3, 4, 5, 6]) {
      await tester.tap(find.byKey(ValueKey('std-day-$d')));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 15));
    expect(_hoursRepo.savedDays, isNull);
    expect(find.text(kDraftSavedMessage), findsNothing);
    expect(find.text('Please fix the highlighted fields to continue.'), findsNothing);
  });

  testWidgets('unchanged hours are not auto-saved', (tester) async {
    await _pump(tester);
    await tester.pump(const Duration(seconds: 30));
    expect(_hoursRepo.savedDays, isNull);
    expect(find.text(kDraftSavedMessage), findsNothing);
  });

  testWidgets('Sport-wise hours: each sport gets its own hours, applied to each of its courts', (tester) async {
    await _pump(tester);

    await _toggle(tester, 'switch-sportwise');
    expect(find.byKey(const ValueKey('sport-hours-fs-bad')), findsOneWidget);
    expect(find.byKey(const ValueKey('sport-hours-fs-foot')), findsOneWidget);

    await _pickTime(tester, 'sport-fs-bad-close', '22:00');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('PRICING PAGE'), findsOneWidget);
    OperatingTimeSlot mondaySlot(String court) => _hoursRepo.areaSchedules[court]!.days.firstWhere((d) => d.dayOfWeek == 1).slots.first;
    expect((mondaySlot('court-1').startTime, mondaySlot('court-1').endTime), ('06:00', '22:00'));
    expect((mondaySlot('court-2').startTime, mondaySlot('court-2').endTime), ('06:00', '23:00'));
    expect(_facilityRepo.settings!['sportWise'], isTrue);
  });

  testWidgets('Sport-wise hours hides the venue-wide hours and lets a sport be open 24 hours', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('mode-standard')), findsOneWidget);

    await _toggle(tester, 'switch-sportwise');
    expect(find.byKey(const ValueKey('mode-standard')), findsNothing);
    expect(find.byKey(const ValueKey('mode-custom')), findsNothing);

    await _toggle(tester, 'sport-fs-bad-24h');
    expect(find.byKey(const ValueKey('sport-fs-bad-24h-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('time-sport-fs-bad-open')), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('PRICING PAGE'), findsOneWidget);
    expect(_hoursRepo.areaSchedules['court-1']!.days.firstWhere((d) => d.dayOfWeek == 1).is24Hours, isTrue);
    expect(_hoursRepo.areaSchedules['court-2']!.days.firstWhere((d) => d.dayOfWeek == 1).is24Hours, isFalse);
  });

  testWidgets('turning sport-wise hours off clears the courts\' own hours', (tester) async {
    await _pump(
      tester,
      facility: _facility(sportWise: true),
      seed: (h) => h.areaSchedules['court-1'] = OperatingSchedule(id: 's', facilityId: 'f1', scopeType: 'PLAYING_AREA', playingAreaId: 'court-1', timezone: 'Asia/Kolkata', days: scheduleFromPlans(defaultPlans(), null)),
    );

    expect(find.byKey(const ValueKey('sport-hours-fs-bad')), findsOneWidget);
    await _toggle(tester, 'switch-sportwise');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(_hoursRepo.deleted, contains('court-1'));
    expect(_hoursRepo.areaSchedules.containsKey('court-1'), isFalse);
  });

  testWidgets('loads what was saved: custom hours, a break, closures and the settings', (tester) async {
    final plans = defaultPlans()..firstWhere((p) => p.dayOfWeek == 2).close = '21:00';
    await _pump(
      tester,
      facility: _facility(allowOutside: false, breakStart: '12:00', breakEnd: '13:00'),
      seed: (h) {
        h.schedule = OperatingSchedule(id: 's', facilityId: 'f1', scopeType: 'FACILITY', timezone: 'Asia/Kolkata', days: scheduleFromPlans(plans, const BreakTime('12:00', '13:00')));
        h.closures = [const ClosureEntry(id: 'c1', date: '2099-08-15', name: 'Independence Day')];
      },
    );

    expect(find.text('Set Custom Operating Hours'), findsOneWidget); // Tuesday differs
    expect(find.text('9:00 PM'), findsOneWidget);
    expect(find.text('Independence Day'), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('switch-break'))).value, isTrue);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('switch-outside'))).value, isFalse);
  });

  testWidgets('Back returns to Sports & Courts', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('SPORTS PAGE'), findsOneWidget);
  });
}
