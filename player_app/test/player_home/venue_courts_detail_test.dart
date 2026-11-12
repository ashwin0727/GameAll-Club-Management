import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_player/features/venues/domain/venue.dart';
import 'package:gameall_player/features/venues/domain/venue_detail.dart';

Map<String, dynamic> _json({Map<String, dynamic> extra = const {}}) => {
      'id': 'v1',
      'name': 'Champz Turf',
      'city': 'Chennai',
      'sports': [
        {'facilitySportId': 'fs-bad', 'name': 'Badminton'},
        {'facilitySportId': 'fs-foot', 'name': 'Football'},
      ],
      'courts': [
        {'id': 'c1', 'name': 'Badminton Court 1', 'facilitySportId': 'fs-bad', 'type': 'INDOOR', 'surface': 'Wooden', 'lighting': 'LED', 'amenities': ['ac', 'shower']},
        {'id': 'c2', 'name': 'Football Turf 1', 'facilitySportId': 'fs-foot', 'type': 'OUTDOOR', 'surface': 'Artificial Turf', 'lighting': 'FLOODLIGHT', 'amenities': []},
        {'id': 'c3', 'name': 'Old Court', 'facilitySportId': 'fs-bad'},
      ],
      'courtCount': 3,
      ...extra,
    };

void main() {
  group('court details from the venue owner', () {
    test('each court carries its type, surface, lighting and amenities', () {
      final d = VenueDetail.fromJson(_json());
      final c1 = d.courts.firstWhere((c) => c.id == 'c1');
      expect(c1.type, VenueType.indoor);
      expect(c1.surface, 'Wooden');
      expect(c1.lightingLabel, 'LED');
      expect(c1.amenityLabels, ['AC', 'Shower']);
      expect(c1.hasDetails, isTrue);

      final c2 = d.courts.firstWhere((c) => c.id == 'c2');
      expect(c2.type, VenueType.outdoor);
      expect(c2.lightingLabel, 'Floodlight');
      expect(c2.amenityLabels, isEmpty);
    });

    test('a court saved before the details existed has none, and says so', () {
      final old = VenueDetail.fromJson(_json()).courts.firstWhere((c) => c.id == 'c3');
      expect((old.type, old.surface, old.lighting, old.amenities.length), (null, null, null, 0));
      expect(old.hasDetails, isFalse);
      expect(old.lightingLabel, isNull);
    });

    test('every lighting value has a readable label', () {
      String? label(String v) => VenueCourt(id: 'x', name: 'x', lighting: v).lightingLabel;
      expect((label('LED'), label('FLOODLIGHT'), label('NATURAL'), label('NONE')), ('LED', 'Floodlight', 'Natural Light', 'No Lighting'));
    });
  });

  group('the amenities the owner ticked', () {
    test('shows the owner\'s own list, in a fixed order, with custom ones after', () {
      final d = VenueDetail.fromJson(_json(extra: {
        'amenityKeys': ['wifi', 'car_parking', 'shower'],
        'customAmenities': ['Physio room', '  '],
      }));
      expect(d.facilityLabels, ['Car Parking', 'Shower', 'Wi-Fi', 'Physio room']);
    });

    test('the "View All" list is all 12 plus the custom ones', () {
      final d = VenueDetail.fromJson(_json(extra: {
        'amenityKeys': ['wifi'],
        'customAmenities': ['Physio room'],
      }));
      expect(d.facilityCatalogue, hasLength(13));
      expect(d.facilityCatalogue.last, 'Physio room');
      expect(d.facilityCatalogue, containsAll(['Car Parking', 'Two-Wheeler Parking', 'First Aid', 'Lockers']));
    });

    test('a venue set up before the 12-item list keeps showing its five', () {
      final d = VenueDetail.fromJson(_json(extra: {
        'amenities': {'parking': true, 'cafeteria': true},
      }));
      expect(d.amenityKeys, isEmpty);
      expect(d.facilityLabels, ['Free Parking', 'Cafeteria']);
      expect(d.facilityCatalogue, ['Free Parking', 'Changing Rooms', 'Toilets / Rest Room', 'Cafeteria', 'Equipment Rental']);
    });
  });
}
