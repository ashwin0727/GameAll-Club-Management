import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gameall_club_mobile/data/models/app_user.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/facility_image.dart';
import 'package:gameall_club_mobile/data/repositories/facility_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/onboarding/facility_details_screen.dart';
import 'package:gameall_club_mobile/features/onboarding/onboarding_welcome_screen.dart';

/// `implements` (not `extends`) so no real SupabaseClient is built.
class _FakeFacilityRepository implements FacilityRepository {
  @override
  Future<Facility?> getFacility() async => null;

  @override
  Future<List<FacilityImage>> listFacilityImages(String facilityId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String? _verifiedMobile;

class _FakeSession extends SessionController {
  @override
  SessionState build() => SessionState(
        user: AppUser(id: 'u1', fullName: 'Ravi Kumar', email: 'owner@yourturf.com', role: 'owner', onboardingCompleted: false, verifiedMobile: _verifiedMobile),
        isLoading: false,
      );
}

Future<void> _pump(WidgetTester tester, Widget screen, {String initial = '/', String? verifiedMobile}) async {
  _verifiedMobile = verifiedMobile;
  // A phone-width, very tall window so the whole scrolling form is laid out and tappable.
  tester.view.physicalSize = const Size(390 * 3, 6000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/onboarding/welcome', builder: (_, _) => const Scaffold(body: Text('WELCOME PAGE'))),
      GoRoute(path: '/onboarding/facility', builder: (_, _) => const Scaffold(body: Text('FACILITY PAGE'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        facilityRepositoryProvider.overrideWithValue(_FakeFacilityRepository()),
        sessionControllerProvider.overrideWith(_FakeSession.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // No webfont is bundled for tests; the screens fall back to the platform font.
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('welcome screen', () {
    testWidgets('shows the intro and the five-point checklist, and Get Started moves on', (tester) async {
      await _pump(tester, const OnboardingWelcomeScreen());

      expect(find.text('Set Up Your Facility'), findsOneWidget);
      expect(find.text('Get your venue live on GameAll in a few simple steps.'), findsOneWidget);
      for (final item in OnboardingWelcomeScreen.checklist) {
        expect(find.text(item), findsOneWidget);
      }
      expect(find.text('Need Help?'), findsOneWidget);

      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      expect(find.text('FACILITY PAGE'), findsOneWidget);
    });
  });

  group('facility information screen', () {
    testWidgets('lays out every section of the design', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      expect(find.text('Step 1 of 5 · Facility Information'), findsOneWidget);
      expect(find.text('Facility Information'), findsWidgets);
      for (final text in ['Facility Name', 'Facility Type', 'Ownership Type', 'Address', 'Set Location on Map', 'Contact Number', 'WhatsApp Number', 'Email Address', 'Facility Description', 'Facility Photos', 'Facility Contact Person', 'Facility Policies', 'Amenities & Facilities']) {
        expect(find.textContaining(text), findsWidgets, reason: text);
      }
      expect(find.text('owner@yourturf.com'), findsOneWidget);
      expect(find.text('Save as Draft'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('does not ask for indoor or outdoor here (it is set per sport on the Sports step)', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      expect(find.textContaining('Venue Type'), findsNothing);
      expect(find.byKey(const ValueKey('venue-type-indoor')), findsNothing);
      expect(find.byKey(const ValueKey('venue-type-outdoor')), findsNothing);
    });

    testWidgets('the contact number is the mobile verified at signup: locked, with a Verified badge', (tester) async {
      await _pump(tester, const FacilityDetailsScreen(), verifiedMobile: '9876501234');

      expect(find.byKey(const ValueKey('verified-contact')), findsOneWidget);
      expect(find.text('+91 9876501234'), findsOneWidget);
      expect(find.text('Verified'), findsNWidgets(2)); // email + contact number

      // it is not asked for again, so Next does not complain about it
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Contact number is required.'), findsNothing);
    });

    testWidgets('an account with no verified mobile types the contact number', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      expect(find.byKey(const ValueKey('verified-contact')), findsNothing);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Contact number is required.'), findsOneWidget);
    });

    testWidgets('the contact person starts as the signed-in account holder, with the Facility Owner role', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Facility Owner'), findsOneWidget);
    });

    testWidgets('Next on an empty form shows every problem together and does not continue', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Please fix the highlighted fields to continue.'), findsOneWidget);
      expect(find.text('Facility name must be at least 2 characters.'), findsOneWidget);
      expect(find.text('Address is required.'), findsOneWidget);
      expect(find.text('Area / locality is required.'), findsOneWidget);
      expect(find.text('City is required.'), findsOneWidget);
      expect(find.text('State is required.'), findsOneWidget);
      expect(find.text('Contact number is required.'), findsOneWidget);
      expect(find.text('Google Maps location link is required.'), findsOneWidget);
      expect(find.text('Add at least one photo of your facility.'), findsOneWidget);
    });

    testWidgets('the standard policy defaults are on, except Advance Payment', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      bool checked(String label) {
        final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
        return tester.widget<Checkbox>(find.descendant(of: row, matching: find.byType(Checkbox))).value ?? false;
      }

      expect(checked('Allow Online Booking'), isTrue);
      expect(checked('Allow Walk-in / Offline Booking'), isTrue);
      expect(checked('Advance Payment Required'), isFalse);
      expect(checked('Allow Cancellations'), isTrue);
      expect(checked('Require Player Details'), isTrue);
    });

    testWidgets('offers the 12 amenities and lets one be switched on', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      for (final a in kFacilityAmenities) {
        expect(find.byKey(ValueKey('amenity-${a.key}')), findsOneWidget, reason: a.label);
      }
      await tester.tap(find.byKey(const ValueKey('amenity-wifi')));
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('amenity-wifi')), matching: find.byIcon(Icons.check)), findsOneWidget);
    });

    testWidgets('adds a custom amenity, refuses a duplicate or a too-short name, and removes it again', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      await tester.tap(find.byKey(const ValueKey('add-custom-amenity')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('custom-amenity-input'));

      await tester.enterText(input, 'x');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Amenity name must be at least 2 characters.'), findsOneWidget);

      await tester.enterText(input, 'wi-fi');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('"wi-fi" is already in the list.'), findsOneWidget);

      await tester.enterText(input, 'Physio room');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Physio room'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const ValueKey('custom-Physio room')), matching: find.byIcon(Icons.close)));
      await tester.pump();
      expect(find.text('Physio room'), findsNothing);
    });

    testWidgets('validates the phone numbers and keeps the alternate number different', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      Finder field(String label) => find.descendant(of: find.ancestor(of: find.textContaining(label), matching: find.byType(Column)).first, matching: find.byType(TextFormField));

      await tester.enterText(field('Contact Number'), '1234567890');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Mobile number must start with 6, 7, 8 or 9.'), findsOneWidget);

      await tester.enterText(field('Contact Number'), '9876543210');
      await tester.enterText(field('Alternate Number'), '9876543210');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Use a different number from the contact number.'), findsOneWidget);
    });

    testWidgets('Back returns to the welcome page', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('WELCOME PAGE'), findsOneWidget);
    });

    testWidgets('Save as Draft keeps what was typed', (tester) async {
      await _pump(tester, const FacilityDetailsScreen());

      final nameField = find.byType(TextFormField).first; // Facility Name is the first field
      await tester.enterText(nameField, 'Champz Turf');
      await tester.tap(find.byKey(const ValueKey('save-draft')));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('facility_setup_draft_v1'), contains('Champz Turf'));
    });
  });
}
