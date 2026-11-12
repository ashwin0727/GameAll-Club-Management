import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gameall_club_mobile/data/models/app_user.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/playing_area.dart';
import 'package:gameall_club_mobile/data/models/sport.dart';
import 'package:gameall_club_mobile/data/repositories/facility_repository.dart';
import 'package:gameall_club_mobile/data/repositories/playing_area_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/data/repositories/sports_repository.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/onboarding/setup_flow.dart';
import 'package:gameall_club_mobile/features/onboarding/setup_ui.dart';
import 'package:gameall_club_mobile/features/onboarding/sports_courts_screen.dart';

Facility _facility({FacilityType type = FacilityType.multiSport}) => Facility(
      id: 'f1',
      ownerId: 'u1',
      name: 'Arena',
      type: type,
      businessEmail: 'o@x.com',
      businessPhone: '9876543210',
      address: const FacilityAddress(line1: 'a', area: 'b', city: 'c', state: 'Tamil Nadu', country: 'India', pinCode: '600001'),
      status: 'ACTIVE',
      onboardingStep: OnboardingStep.sportsCourts,
    );

Sport _sport(String key, String name) => Sport.fromJson({'id': 'sport-$key', 'key': key, 'name': name, 'is_active': true});

final _catalogue = [
  _sport('badminton', 'Badminton'),
  _sport('pickleball', 'Pickleball'),
  _sport('cricket', 'Cricket'),
  _sport('football', 'Football'),
  _sport('tennis', 'Tennis'),
  _sport('basketball', 'Basketball'),
  _sport('other', 'Other'),
];

class _FakeFacilityRepo implements FacilityRepository {
  _FakeFacilityRepo(this.facility);
  final Facility facility;
  final steps = <OnboardingStep>[];

  @override
  Future<Facility?> getFacility() async {
    _requests.add('facility');
    return facility;
  }

  @override
  Future<void> updateOnboardingStep(String facilityId, OnboardingStep step) async => steps.add(step);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSportsRepo implements SportsRepository {
  _FakeSportsRepo({List<String> saved = const [], List<String> customs = const []})
      : saved = [
          for (final id in saved) FacilitySport(id: 'fs-$id', facilityId: 'f1', sportId: id, enabled: true),
          for (final n in customs) FacilitySport(id: 'fs-other-$n', facilityId: 'f1', sportId: 'sport-other', enabled: true, customSportName: n),
        ];
  List<FacilitySport> saved;

  @override
  Future<List<FacilitySport>> saveFacilitySportsMulti(String facilityId, {required List<String> sportIds, List<String> customSportNames = const []}) async {
    saved = [
      for (final id in sportIds) FacilitySport(id: 'fs-$id', facilityId: facilityId, sportId: id, enabled: true),
      for (final n in customSportNames) FacilitySport(id: 'fs-other-$n', facilityId: facilityId, sportId: 'sport-other', enabled: true, customSportName: n),
    ];
    return saved;
  }

  @override
  Future<List<Sport>> getActiveSports() async {
    _requests.add('catalogue');
    return _catalogue;
  }

  @override
  Future<List<FacilitySport>> getFacilitySports(String facilityId) async {
    _requests.add('facilitySports');
    return saved;
  }

  @override
  Future<List<FacilitySport>> saveFacilitySports(String facilityId, List<String> sportIds, {String? customSportName}) async {
    saved = [for (final id in sportIds) FacilitySport(id: 'fs-$id', facilityId: facilityId, sportId: id, enabled: true, customSportName: id == 'sport-other' ? customSportName : null)];
    return saved;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAreaRepo implements PlayingAreaRepository {
  _FakeAreaRepo([List<PlayingArea> initial = const []]) : rows = List.of(initial);
  List<PlayingArea> rows;
  final removed = <String>[];

  @override
  Future<List<PlayingArea>> getPlayingAreas(String facilityId) async {
    _requests.add('areas');
    return rows.where((r) => !r.archived).toList();
  }

  @override
  Future<PlayingArea> createPlayingArea(PlayingArea input) async {
    rows.add(input);
    return input;
  }

  @override
  Future<PlayingArea> updatePlayingArea(String id, {String? name, String? areaType, String? surface, String? lightingType, List<String>? courtAmenities, int? displayOrder, String? status, bool? bookingEnabled}) async {
    final i = rows.indexWhere((r) => r.id == id);
    final old = rows[i];
    rows[i] = PlayingArea(
      id: old.id, facilityId: old.facilityId, facilitySportId: old.facilitySportId, sportId: old.sportId,
      name: name ?? old.name, areaType: areaType ?? old.areaType, surface: surface ?? old.surface, lightingType: lightingType ?? old.lightingType,
      courtAmenities: courtAmenities ?? old.courtAmenities, status: old.status, bookingEnabled: old.bookingEnabled, archived: old.archived, displayOrder: displayOrder ?? old.displayOrder,
    );
    return rows[i];
  }

  @override
  Future<void> removePlayingArea(String id) async {
    removed.add(id);
    rows.removeWhere((r) => r.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The data requests the screen has made so far, in the order it made them.
final _requests = <String>[];

/// While set, the session refresh does not finish: Next must not wait for it.
Completer<void>? _holdRefresh;

class _FakeSession extends SessionController {
  @override
  SessionState build() => SessionState(
        user: const AppUser(id: 'u1', fullName: 'Ravi', email: 'o@x.com', role: 'owner', onboardingCompleted: false),
        facility: _facility(),
        isLoading: false,
      );

  @override
  Future<void> refresh() async {
    await _holdRefresh?.future;
  }
}

late _FakeFacilityRepo _facilityRepo;
late GoRouter _router;
late _FakeSportsRepo _sportsRepo;
late _FakeAreaRepo _areaRepo;

Future<void> _pump(WidgetTester tester, {Facility? facility, List<String> savedSports = const [], List<String> customSports = const [], List<PlayingArea> areas = const [], bool settle = true}) async {
  _requests.clear();
  _holdRefresh = null;
  tester.view.physicalSize = const Size(390 * 3, 6000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  _facilityRepo = _FakeFacilityRepo(facility ?? _facility());
  _sportsRepo = _FakeSportsRepo(saved: savedSports, customs: customSports);
  _areaRepo = _FakeAreaRepo(areas);

  final router = _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SportsCourtsScreen()),
      GoRoute(path: '/onboarding/facility', builder: (_, _) => const Scaffold(body: Text('FACILITY PAGE'))),
      GoRoute(path: '/onboarding/operating-hours', builder: (_, _) => const Scaffold(body: Text('HOURS PAGE'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        facilityRepositoryProvider.overrideWithValue(_facilityRepo),
        sportsRepositoryProvider.overrideWithValue(_sportsRepo),
        playingAreaRepositoryProvider.overrideWithValue(_areaRepo),
        sessionControllerProvider.overrideWith(_FakeSession.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _tapSport(WidgetTester tester, String code) async {
  await tester.tap(find.byKey(ValueKey('sport-$code')));
  await tester.pumpAndSettle();
}

PlayingArea _area(String id, String sportKey, String name, {String type = 'INDOOR', String surface = 'Wooden', String lighting = 'LED', List<String> amenities = const []}) => PlayingArea(
      id: id, facilityId: 'f1', facilitySportId: 'fs-sport-$sportKey', sportId: 'sport-$sportKey', name: name, areaType: type, surface: surface, lightingType: lighting,
      courtAmenities: amenities, status: 'ACTIVE', bookingEnabled: true, archived: false, displayOrder: 0,
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

group('loading', () {
    testWidgets('the first frame is a skeleton shaped like the page: no spinner, and no "Step 2 of 5" floating in the middle', (tester) async {
      await _pump(tester, settle: false);

      expect(find.byType(SetupLoadingPage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Step 2 of 5'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(SetupLoadingPage), findsNothing);
      expect(find.text('Sports & Courts'), findsWidgets);
    });

    testWidgets('the skeleton sits at the top of the page, like the real content, not in the middle of the screen', (tester) async {
      await _pump(tester, settle: false);
      final first = tester.getTopLeft(find.byType(SetupSkeletonBox).first);
      // just under the 60 px header: the page's own top padding, never centred in a 6000 px screen
      expect(first.dy, lessThan(120));
      await tester.pumpAndSettle();
    });

    testWidgets('everything the page needs is requested at the same moment, not one request after another', (tester) async {
      await _pump(tester, settle: false);
      // nothing has finished yet, but all four requests are already on their way
      expect(_requests, containsAll(['facility', 'catalogue', 'facilitySports', 'areas']));
      await tester.pumpAndSettle();
    });
  });

  group('navigation', () {
    testWidgets('Next opens the next step at once; it does not wait for the session refresh', (tester) async {
      await _pump(tester);
      await _tapSport(tester, 'badminton');
      _holdRefresh = Completer<void>(); // the refresh never finishes during this test

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('HOURS PAGE'), findsOneWidget);
      _holdRefresh!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Back from the next step returns to this one exactly as it was left, without loading it again', (tester) async {
      await _pump(tester);
      await _tapSport(tester, 'badminton');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('HOURS PAGE'), findsOneWidget);
      final loadsBefore = _requests.where((r) => r == 'facility').length;

      _router.pop(); // what Back on the next step does
      await tester.pumpAndSettle();

      expect(find.text('Badminton Courts (1)'), findsOneWidget, reason: 'the ticked sport is still there');
      expect(_requests.where((r) => r == 'facility').length, loadsBefore, reason: 'nothing was fetched again');
      expect(find.byType(SetupLoadingPage), findsNothing);
    });

    testWidgets('Back on this step goes back one step; with nothing behind it, it opens Facility Information', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('FACILITY PAGE'), findsOneWidget);
    });

    testWidgets('Back pops when there is a step behind this one', (tester) async {
      await _pump(tester);
      _router.go('/onboarding/facility');
      await tester.pumpAndSettle();
      _router.push('/');
      await tester.pumpAndSettle();
      expect(_router.canPop(), isTrue);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('FACILITY PAGE'), findsOneWidget);
      expect(_router.canPop(), isFalse);
    });
  });

  group('footer and draft', () {
    testWidgets('the footer is one slim row: Back and Next only, no Save as Draft', (tester) async {
      await _pump(tester);
      expect(find.text('Save as Draft'), findsNothing);
      expect(find.byKey(const ValueKey('save-draft')), findsNothing);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      final next = tester.getSize(find.widgetWithText(FilledButton, 'Next'));
      expect(next.height, 48);
    });

    testWidgets('a change is saved as a draft after 10 quiet seconds, with a small notice at the top, and the page stays', (tester) async {
      await _pump(tester);
      await _tapSport(tester, 'badminton');
      await tester.pump(const Duration(seconds: 6));
      expect(_sportsRepo.saved, isEmpty, reason: 'not before 10 seconds');

      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(_sportsRepo.saved.map((r) => r.sportId), ['sport-badminton']);
      expect(_areaRepo.rows, hasLength(1));
      expect(find.text(kDraftSavedMessage), findsOneWidget);
      expect(find.text('HOURS PAGE'), findsNothing);
      expect(_facilityRepo.steps, isEmpty, reason: 'a draft does not move the setup on');
    });

    testWidgets('a step that is not valid yet is not auto-saved, and nothing is shown about it', (tester) async {
      await _pump(tester);
      await _tapSport(tester, 'badminton');
      // blank the court's name: it can't be saved like that
      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pump(const Duration(seconds: 15));
      expect(_sportsRepo.saved, isEmpty);
      expect(find.text(kDraftSavedMessage), findsNothing);
      expect(find.text('Please fix the highlighted fields to continue.'), findsNothing);
    });

    testWidgets('nothing changed, nothing saved', (tester) async {
      await _pump(tester, savedSports: ['sport-badminton'], areas: [_area('c1', 'badminton', 'Badminton Court 1')]);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(kDraftSavedMessage), findsNothing);
    });
  });

  testWidgets('starts empty for a multi-sport venue; ticking a sport adds its first court with the sport\'s usual settings', (tester) async {
    await _pump(tester);

    expect(find.text('Select at least one sport above to add its courts.'), findsOneWidget);
    expect(find.text('Preview of Courts (0)'), findsOneWidget);

    await _tapSport(tester, 'badminton');
    expect(find.text('Badminton Courts (1)'), findsOneWidget);
    expect(find.text('Badminton Court 1'), findsWidgets);
    expect(find.text('Preview of Courts (1)'), findsOneWidget);
    expect(find.text('Wooden · LED'), findsOneWidget);
    expect(find.text('Indoor'), findsWidgets);
  });

  testWidgets('a single-sport facility type preselects its sport', (tester) async {
    await _pump(tester, facility: _facility(type: FacilityType.football));
    expect(find.text('Football Courts (1)'), findsOneWidget);
    expect(find.text('Football Turf 1'), findsWidgets);
  });

  testWidgets('adds and removes courts, numbering from the highest name', (tester) async {
    await _pump(tester);
    await _tapSport(tester, 'badminton');

    await tester.tap(find.byKey(const ValueKey('add-court')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-court')));
    await tester.pump();
    expect(find.text('Badminton Courts (3)'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Badminton Court 2').first);
    await tester.pump();
    expect(find.text('Badminton Courts (2)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-court')));
    await tester.pump();
    expect(find.text('Badminton Court 4'), findsWidgets);
    expect(find.text('Badminton Court 2'), findsNothing);
  });

  testWidgets('Next with no sport selected says so and does not continue', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sports-error')), findsOneWidget);
    expect(find.text('Select at least one sport to continue.'), findsOneWidget);
    expect(find.text('HOURS PAGE'), findsNothing);
  });

  testWidgets('a blank court name is refused', (tester) async {
    await _pump(tester);
    await _tapSport(tester, 'badminton');

    final nameField = find.descendant(of: find.byType(Form).evaluate().isEmpty ? find.byType(MaterialApp) : find.byType(Form), matching: find.byType(TextFormField));
    expect(nameField, findsWidgets);
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Name must be between 2 and 50 characters.'), findsOneWidget);
    expect(find.text('HOURS PAGE'), findsNothing);
  });

  testWidgets('Bulk mode sets the surface for every court of the sport at once', (tester) async {
    await _pump(tester);
    await _tapSport(tester, 'badminton');
    await tester.tap(find.byKey(const ValueKey('add-court')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mode-bulk (same)')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bulk-card')), findsOneWidget);

    // switch AC on in the bulk card: it reaches both courts
    await tester.tap(find.byKey(const ValueKey('bulk-sport-badminton-amenity-ac')));
    await tester.pumpAndSettle();
    expect(find.text('AC'), findsWidgets);
    // both preview rows now list AC
    final previews = find.byKey(const ValueKey('preview-edit-placeholder'));
    expect(previews, findsNothing);
    expect(find.descendant(of: find.byType(SportsCourtsScreen), matching: find.text('AC')), findsNWidgets(3)); // bulk chip + 2 previews
  });

  Future<void> addSport(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('add-sport')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('custom-sport-input')), name);
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
  }

  testWidgets('an owner can add as many of their own sports as they like, each with its own courts', (tester) async {
    await _pump(tester);

    await addSport(tester, 'Table Tennis');
    expect(find.text('Table Tennis Courts (1)'), findsOneWidget);
    // Add Sport is still there for another one, and another
    expect(find.byKey(const ValueKey('add-sport')), findsOneWidget);
    await addSport(tester, 'Squash');
    await addSport(tester, 'Kabaddi');

    expect(find.text('Kabaddi Courts (1)'), findsOneWidget);
    for (final name in ['table tennis', 'squash', 'kabaddi']) {
      expect(find.byKey(ValueKey('custom-sport-$name')), findsOneWidget, reason: name);
    }
    expect(find.text('Preview of Courts (3)'), findsOneWidget);

    await _tapSport(tester, 'badminton');
    expect(find.text('Preview of Courts (4)'), findsOneWidget);
  });

  testWidgets('refuses a sport name that is too short or already in the list', (tester) async {
    await _pump(tester);

    await addSport(tester, 'x');
    expect(find.text('Sport name must be at least 2 characters.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('custom-sport-input')), 'football');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    expect(find.text('"football" is already in the list.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('custom-sport-input')), 'Squash');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await addSport(tester, 'squash');
    expect(find.text('"squash" is already in the list.'), findsOneWidget);
  });

  testWidgets('a sport the owner added has its own delete button on its card, which also removes its courts', (tester) async {
    await _pump(tester);
    await addSport(tester, 'Squash');
    await addSport(tester, 'Table Tennis');
    expect(find.text('Preview of Courts (2)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remove-custom-squash')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('custom-sport-squash')), findsNothing);
    expect(find.byKey(const ValueKey('custom-sport-table tennis')), findsOneWidget);
    expect(find.text('Preview of Courts (1)'), findsOneWidget);
    // catalogue sports have no delete button: they are ticked and unticked
    expect(find.byKey(const ValueKey('remove-custom-badminton')), findsNothing);
  });

  testWidgets('saves every added sport with its name and its courts, and loads them back', (tester) async {
    await _pump(tester);
    await addSport(tester, 'Table Tennis');
    await addSport(tester, 'Squash');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('HOURS PAGE'), findsOneWidget);
    expect(_sportsRepo.saved.map((r) => r.customSportName).toSet(), {'Table Tennis', 'Squash'});
    expect(_sportsRepo.saved.every((r) => r.sportId == 'sport-other'), isTrue);
    expect(_areaRepo.rows, hasLength(2));
    expect(_areaRepo.rows.map((c) => c.facilitySportId).toSet(), hasLength(2), reason: 'one court under each sport');
    expect(_areaRepo.rows.every((c) => c.sportId == 'sport-other'), isTrue);

    // open it again: both come back
    final saved = [..._areaRepo.rows];
    await _pump(tester, customSports: ['Table Tennis', 'Squash'], areas: saved);
    expect(find.byKey(const ValueKey('custom-sport-table tennis')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-sport-squash')), findsOneWidget);
    expect(find.text('Preview of Courts (2)'), findsOneWidget);
  });

  testWidgets('Next saves the sports and every court\'s details, advances setup and goes on to Operating Hours', (tester) async {
    await _pump(tester);
    await _tapSport(tester, 'badminton');
    await _tapSport(tester, 'football');
    await tester.tap(find.byKey(const ValueKey('active-sport-badminton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('court-${_courtIdFor(tester, 'Badminton Court 1')}-amenity-ac')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('HOURS PAGE'), findsOneWidget);
    expect(_sportsRepo.saved.map((s) => s.sportId).toSet(), {'sport-badminton', 'sport-football'});
    expect(_areaRepo.rows, hasLength(2));
    final bad = _areaRepo.rows.firstWhere((c) => c.name == 'Badminton Court 1');
    expect((bad.areaType, bad.surface, bad.lightingType, bad.courtAmenities.join(',')), ('INDOOR', 'Wooden', 'LED', 'ac'));
    final foot = _areaRepo.rows.firstWhere((c) => c.name.startsWith('Football'));
    expect((foot.areaType, foot.surface, foot.lightingType), ('OUTDOOR', 'Artificial Turf', 'FLOODLIGHT'));
    expect(_facilityRepo.steps, [OnboardingStep.operatingHours]);
  });

  testWidgets('loads what was saved before, and switching a sport off archives its courts on save', (tester) async {
    await _pump(
      tester,
      savedSports: ['sport-badminton', 'sport-football'],
      areas: [_area('c-bad-1', 'badminton', 'Court A', amenities: ['shower']), _area('c-foot-1', 'football', 'Turf A', type: 'OUTDOOR', surface: 'Artificial Turf', lighting: 'FLOODLIGHT')],
    );
    expect(find.text('Preview of Courts (2)'), findsOneWidget);

    await _tapSport(tester, 'football'); // switch Football off
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('HOURS PAGE'), findsOneWidget);
    expect(_areaRepo.removed, ['c-foot-1']);
    expect(_areaRepo.rows.map((r) => r.id), ['c-bad-1']);
    expect(_areaRepo.rows.single.courtAmenities, ['shower']);
  });

  testWidgets('Back returns to Facility Information', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('FACILITY PAGE'), findsOneWidget);
  });
}

/// The session id of the court draft named [name] (the key suffix the screen uses).
String _courtIdFor(WidgetTester tester, String name) {
  for (final e in find.byType(TextFormField).evaluate()) {
    final key = e.widget.key;
    if (key is ValueKey<String> && key.value.startsWith('name-')) {
      final field = e.widget as TextFormField;
      if (field.initialValue == name) return key.value.substring('name-'.length);
    }
  }
  throw StateError('no court named $name');
}
