import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:gameall_club_mobile/features/onboarding/setup_flow.dart';
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

/// A tiny valid picture, so the thumbnails decode.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

/// A fake photo gallery: one tap on "select several" returns [ticked] photos, and it remembers the limit the screen asked for.
class _FakeGallery extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  _FakeGallery(this.ticked);

  final int ticked;
  int? limitAsked;
  int multiCalls = 0;
  int singleCalls = 0;

  @override
  Future<List<XFile>> getMultiImageWithOptions({MultiImagePickerOptions options = const MultiImagePickerOptions()}) async {
    multiCalls++;
    limitAsked = options.limit;
    return [for (var i = 0; i < ticked; i++) XFile.fromData(_png, name: 'photo-$i.png', mimeType: 'image/png')];
  }

  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    singleCalls++;
    return XFile.fromData(_png, name: 'single.png', mimeType: 'image/png');
  }
}

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
      // drafts are saved by themselves now: there is no Save as Draft button
      expect(find.text('Save as Draft'), findsNothing);
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

group('dropdowns', () {
      testWidgets('State opens a list of every state and union territory, with a search box; the chosen one shows in the field', (tester) async {
        await _pump(tester, const FacilityDetailsScreen());

        expect(find.text('Select state'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('select-State')));
        await tester.tap(find.byKey(const ValueKey('select-State')));
        await tester.pumpAndSettle();

        final search = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
        expect(search, findsOneWidget, reason: 'a long list has a search box');
        expect(find.text('Tamil Nadu'), findsWidgets);
        await tester.enterText(search, 'tamil');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tamil Nadu').last);
        await tester.pumpAndSettle();

        expect(find.text('Tamil Nadu'), findsOneWidget);
        expect(find.text('Select state'), findsNothing);
      });

      testWidgets('Facility Type and Contact Person Role list their options too', (tester) async {
        await _pump(tester, const FacilityDetailsScreen());

        await tester.ensureVisible(find.byKey(const ValueKey('select-Facility Type')));
        await tester.tap(find.byKey(const ValueKey('select-Facility Type')));
        await tester.pumpAndSettle();
        for (final t in FacilityType.values) {
          expect(find.text(t.label), findsWidgets, reason: t.label);
        }
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        final role = find.byKey(const ValueKey('select-Role / Designation'));
        await tester.ensureVisible(role);
        await tester.tap(role);
        await tester.pumpAndSettle();
        expect(find.text('Facility Owner'), findsWidgets);
      });
    });

    group('photos', () {
      /// Taps a source in the sheet and lets the (really asynchronous) file reading finish.
      Future<void> choose(WidgetTester tester, String label) async {
        await tester.tap(find.text(label));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
      }

      Future<_FakeGallery> openPicker(WidgetTester tester, {required int ticked}) async {
        final gallery = _FakeGallery(ticked);
        ImagePickerPlatform.instance = gallery;
        await _pump(tester, const FacilityDetailsScreen());
        // a normal phone window now: the photo list is a bottom sheet, which belongs at the bottom of a screen you can see
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        await tester.pump();
        await tester.ensureVisible(find.byKey(const ValueKey('add-photo')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('add-photo')));
        // the add tile shows a spinner while the picker is open, so step the clock instead of waiting for everything to stop
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        return gallery;
      }

      testWidgets('the gallery lets several be ticked in one go (up to 5): all of them are added at once', (tester) async {
        final gallery = await openPicker(tester, ticked: 4);
        expect(find.text('Choose from gallery (select several)'), findsOneWidget);
        await choose(tester, 'Choose from gallery (select several)');

        expect(gallery.multiCalls, 1);
        expect(gallery.limitAsked, 5);
        expect(find.byIcon(Icons.close), findsNWidgets(4), reason: 'four new photos, each with its remove button');
        expect(find.text('Cover'), findsOneWidget);
        expect(find.text('Upload More'), findsOneWidget);
      });

      testWidgets('five at once fills the grid', (tester) async {
        await openPicker(tester, ticked: 5);
        await choose(tester, 'Choose from gallery (select several)');
        expect(find.byIcon(Icons.close), findsNWidgets(5));
        expect(find.byKey(const ValueKey('add-photo')), findsNothing, reason: 'no room for a sixth');
      });

      testWidgets('if more than 5 come back (an older phone ignores the limit), only 5 are kept and the person is told', (tester) async {
        await openPicker(tester, ticked: 8);
        await choose(tester, 'Choose from gallery (select several)');
        expect(find.byIcon(Icons.close), findsNWidgets(5));
        expect(find.textContaining('3 were left out'), findsOneWidget);
      });

      testWidgets('with some photos already added, the gallery is asked only for what still fits', (tester) async {
        final gallery = await openPicker(tester, ticked: 2);
        await choose(tester, 'Choose from gallery (select several)');
        expect(find.byIcon(Icons.close), findsNWidgets(2));

        await tester.ensureVisible(find.byKey(const ValueKey('add-photo')));
        await tester.tap(find.byKey(const ValueKey('add-photo')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await choose(tester, 'Choose from gallery (select several)');
        expect(gallery.limitAsked, 3);
        expect(find.byIcon(Icons.close), findsNWidgets(4)); // the fake hands back two more
      });

      testWidgets('with one place left, the gallery picks a single photo', (tester) async {
        final gallery = await openPicker(tester, ticked: 4);
        await choose(tester, 'Choose from gallery (select several)');
        expect(find.byIcon(Icons.close), findsNWidgets(4));

        await tester.ensureVisible(find.byKey(const ValueKey('add-photo')));
        await tester.tap(find.byKey(const ValueKey('add-photo')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Choose from gallery or files'), findsOneWidget, reason: 'one place left: no "select several"');
        await choose(tester, 'Choose from gallery or files');
        expect(gallery.singleCalls, 1);
        expect(find.byIcon(Icons.close), findsNWidgets(5));
      });

      testWidgets('backing out of the gallery adds nothing', (tester) async {
        await openPicker(tester, ticked: 0);
        await choose(tester, 'Choose from gallery (select several)');
        expect(find.byIcon(Icons.close), findsNothing);
      });
    });

    group('draft auto-save', () {
      Future<String?> savedDraft() async => (await SharedPreferences.getInstance()).getString('facility_setup_draft_v1');

      testWidgets('what was typed is saved as a draft after 10 quiet seconds, with a small notice at the top', (tester) async {
        await _pump(tester, const FacilityDetailsScreen());

        await tester.enterText(find.byType(TextFormField).first, 'Champz Turf'); // Facility Name is the first field
        await tester.pump(const Duration(seconds: 6));
        expect(await savedDraft(), isNull, reason: 'not before 10 seconds');
        expect(find.text(kDraftSavedMessage), findsNothing);

        await tester.pump(const Duration(seconds: 6));
        await tester.pump();
        expect(await savedDraft(), contains('Champz Turf'));
        expect(find.text(kDraftSavedMessage), findsOneWidget);

        // the notice goes away by itself
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(kDraftSavedMessage), findsNothing);
      });

      testWidgets('typing again starts the 10 seconds over, so it never saves in the middle of typing', (tester) async {
        await _pump(tester, const FacilityDetailsScreen());
        final name = find.byType(TextFormField).first;

        await tester.enterText(name, 'Champz');
        await tester.pump(const Duration(seconds: 8));
        await tester.enterText(name, 'Champz Turf');
        await tester.pump(const Duration(seconds: 8)); // 16 s in, but only 8 since the last change
        expect(await savedDraft(), isNull);

        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(await savedDraft(), contains('Champz Turf'));
      });

      testWidgets('nothing is saved, and no notice shows, when nothing was changed', (tester) async {
        await _pump(tester, const FacilityDetailsScreen());
        await tester.pump(const Duration(seconds: 30));
        expect(await savedDraft(), isNull);
        expect(find.text(kDraftSavedMessage), findsNothing);
      });

      testWidgets('the same content is not saved twice', (tester) async {
        await _pump(tester, const FacilityDetailsScreen());
        await tester.enterText(find.byType(TextFormField).first, 'Champz Turf');
        await tester.pump(const Duration(seconds: 12));
        await tester.pump();
        expect(find.text(kDraftSavedMessage), findsOneWidget);

        await tester.pump(const Duration(seconds: 6)); // the notice has gone
        await tester.pump(const Duration(seconds: 30)); // and nothing new is saved
        expect(find.text(kDraftSavedMessage), findsNothing);
      });
    });
  });
}
