import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/core/utils/google_maps_link.dart';
import 'package:gameall_club_mobile/core/utils/validators.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/facility_image.dart';
import 'package:gameall_club_mobile/features/onboarding/facility_details_screen.dart' show AmenitiesCard, NewPhoto, PhotosPicker, VenueTypePicker;

Widget _host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))));

Map<String, dynamic> _facilityRow([Map<String, dynamic> extra = const {}]) => {
      'id': 'f1',
      'owner_id': 'o1',
      'name': 'Smash Arena',
      'facility_type': 'BADMINTON',
      'business_email': 'a@b.co',
      'business_phone': '9876543210',
      'address_line_1': '1 Main St',
      'area': 'Adyar',
      'city': 'Chennai',
      'state': 'Tamil Nadu',
      'postal_code': '600020',
      'status': 'ACTIVE',
      'onboarding_step': 'FACILITY_DETAILS',
      ...extra,
    };

void main() {
  group('Google Maps link', () {
    test('accepts what Share and the address bar give', () {
      for (final url in [
        'https://maps.app.goo.gl/AbCdEf123',
        'https://goo.gl/maps/xyz',
        'https://www.google.com/maps/place/Smash+Arena/@13.08,80.27,17z',
        'https://google.co.in/maps?q=13.08,80.27',
        'https://maps.google.com/?q=13.08,80.27',
        'https://g.page/smash-arena',
        '  https://maps.app.goo.gl/AbCdEf123  ',
      ]) {
        expect(isGoogleMapsLink(url), isTrue, reason: url);
      }
    });

    test('rejects anything else', () {
      for (final url in [
        '',
        'not a link',
        'maps.app.goo.gl/AbCdEf123',
        'https://example.com/maps/place',
        'https://www.google.com/search?q=turf',
        'https://goo.gl/other',
        'ftp://maps.google.com/x',
        'https://maps.app.goo.gl/',
        'https://evil.com/?https://maps.google.com',
      ]) {
        expect(isGoogleMapsLink(url), isFalse, reason: url);
      }
    });

    test('the form validator asks for it, then checks it', () {
      expect(Validators.googleMapsLink(''), 'Google Maps location link is required.');
      expect(Validators.googleMapsLink('   '), 'Google Maps location link is required.');
      expect(Validators.googleMapsLink('https://example.com'), startsWith('Paste a Google Maps link'));
      expect(Validators.googleMapsLink('https://maps.app.goo.gl/AbCdEf123'), isNull);
    });
  });

  group('Facility model', () {
    test('reads venue type, amenities and the admin verdict on the map link', () {
      final f = Facility.fromJson(_facilityRow({
        'location_url': 'https://maps.app.goo.gl/x',
        'location_verification_status': 'REJECTED',
        'location_verification_note': 'Wrong street',
        'venue_type': 'OUTDOOR',
        'has_parking': true,
        'has_cafeteria': true,
      }));
      expect(f.venueType, VenueType.outdoor);
      expect(f.amenities.parking, isTrue);
      expect(f.amenities.toilets, isFalse);
      expect(f.amenities.labels, ['Free Parking', 'Cafeteria']);
      expect(f.locationVerification, VerificationStatus.rejected);
      expect(f.locationVerificationNote, 'Wrong street');
    });

    test('an older facility has no venue type, no amenities and a pending link', () {
      final f = Facility.fromJson(_facilityRow());
      expect(f.venueType, isNull);
      expect(f.amenities.labels, isEmpty);
      expect(f.locationVerification, VerificationStatus.pending);
    });

    test('venue type is exactly indoor or outdoor', () {
      expect(VenueType.values, [VenueType.indoor, VenueType.outdoor]);
      expect(VenueType.fromDb('INDOOR'), VenueType.indoor);
      expect(VenueType.fromDb('COVERED'), isNull);
      expect(VenueType.outdoor.toDb(), 'OUTDOOR');
    });

    test('amenities write all five columns', () {
      expect(const FacilityAmenities(toilets: true).toDb(), {
        'has_parking': false,
        'has_changing_rooms': false,
        'has_toilets': true,
        'has_cafeteria': false,
        'has_equipment_rental': false,
      });
    });

    test('a photo reads its status and note', () {
      final i = FacilityImage.fromJson({'id': 'i', 'url': 'https://x/y.jpg', 'sort_order': 2, 'verification_status': 'VERIFIED'});
      expect(i.status, VerificationStatus.verified);
      expect(i.sortOrder, 2);
      expect(FacilityImage.fromJson({'id': 'j', 'url': 'u'}).status, VerificationStatus.pending);
    });
  });

  group('venue profile widgets', () {
    testWidgets('Indoor and Outdoor are the only two venue types, and picking one reports it', (tester) async {
      VenueType? picked;
      await tester.pumpWidget(_host(VenueTypePicker(value: null, onChanged: (v) => picked = v)));
      expect(find.text('Indoor'), findsOneWidget);
      expect(find.text('Outdoor'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('venue-type-outdoor')));
      expect(picked, VenueType.outdoor);
    });

    testWidgets('the venue type shows an error message', (tester) async {
      await tester.pumpWidget(_host(VenueTypePicker(value: null, error: 'Choose indoor or outdoor.', onChanged: (_) {})));
      expect(find.byKey(const ValueKey('venue-type-error')), findsOneWidget);
    });

    testWidgets('five amenity switches, each flipping only itself', (tester) async {
      FacilityAmenities? latest;
      var value = const FacilityAmenities(cafeteria: true);
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _host(AmenitiesCard(value: value, onChanged: (a) => setState(() => latest = value = a))),
        ),
      );
      for (final label in ['Free Parking', 'Changing Rooms', 'Toilets / Rest Room', 'Cafeteria', 'Equipment Rental']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('amenity-cafeteria'))).value, isTrue);
      await tester.tap(find.byKey(const ValueKey('amenity-parking')));
      await tester.pump();
      expect(latest?.parking, isTrue);
      expect(latest?.cafeteria, isTrue);
      expect(latest?.toilets, isFalse);
    });

    testWidgets('photos: needs one, shows a chosen photo with Cover and a remove button, and the saved ones with their verdict', (tester) async {
      final removed = <NewPhoto>[];
      var added = 0;
      final photo = NewPhoto(Uint8List.fromList(_tinyPng), 'court.png');
      await tester.pumpWidget(
        _host(
          PhotosPicker(
            saved: const [FacilityImage(id: 's', url: 'https://invalid.test/a.jpg', sortOrder: 0, status: VerificationStatus.rejected, note: 'Blurry')],
            added: [photo],
            busy: false,
            error: 'Add at least one photo of your facility.',
            onAdd: () => added++,
            onRemoveNew: removed.add,
          ),
        ),
      );
      expect(find.text('Facility Photos'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Blurry'), findsOneWidget);
      expect(find.text('Not uploaded yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('photos-error')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-photo')));
      expect(added, 1);
      await tester.tap(find.byIcon(Icons.close));
      expect(removed, [photo]);
    });

    testWidgets('the add button disappears once the maximum is reached', (tester) async {
      final saved = [for (var i = 0; i < maxFacilityPhotos; i++) FacilityImage(id: '$i', url: 'https://invalid.test/$i.jpg', sortOrder: i, status: VerificationStatus.pending)];
      await tester.pumpWidget(_host(PhotosPicker(saved: saved, added: const [], busy: false, onAdd: () {}, onRemoveNew: (_) {})));
      expect(find.byKey(const ValueKey('add-photo')), findsNothing);
    });
  });
}

// A valid 1x1 transparent PNG, so Image.memory has something real to decode.
const _tinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F, 0x00, 0x05, 0xFE, 0x02,
  0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
