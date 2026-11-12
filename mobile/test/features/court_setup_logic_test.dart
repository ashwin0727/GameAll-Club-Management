import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/data/models/playing_area.dart';
import 'package:gameall_club_mobile/features/onboarding/court_setup_logic.dart';

CourtDraft _draft({String id = 'c1', String sportId = 's-bad', String name = 'Badminton Court 1', String type = 'INDOOR', String surface = 'Wooden', String lighting = 'LED', List<String>? amenities}) =>
    CourtDraft(id: id, sportId: sportId, name: name, type: type, surface: surface, lighting: lighting, amenities: amenities);

const _sports = <SelectedSportInfo>[(id: 's-bad', name: 'Badminton', code: 'BADMINTON')];

void main() {
  group('court names', () {
    test('numbers from the highest used number, not the count', () {
      expect(nextCourtName('BADMINTON', []), 'Court 1');
      expect(nextCourtName('BADMINTON', ['Court 1', 'Court 2']), 'Court 3');
      expect(nextCourtName('BADMINTON', ['Court 2']), 'Court 3');
      expect(nextCourtName('CRICKET', ['Turf 1']), 'Turf 2');
    });
  });

  group('a new court', () {
    test('starts from the sport\'s usual settings', () {
      final c = newCourtDraft(id: 'n', sportId: 's-bad', sportCode: 'BADMINTON', sportName: 'Badminton', existing: []);
      expect((c.name, c.type, c.surface, c.lighting, c.amenities.join(',')), ('Badminton Court 1', 'INDOOR', 'Wooden', 'LED', ''));
      final f = newCourtDraft(id: 'n', sportId: 's-foot', sportCode: 'FOOTBALL', sportName: 'Football', existing: []);
      expect((f.name, f.type, f.surface, f.lighting), ('Football Turf 1', 'OUTDOOR', 'Artificial Turf', 'FLOODLIGHT'));
    });

    test('copies the sport\'s last court, so adding another is one tap', () {
      final first = _draft(surface: 'Synthetic (PU)', lighting: 'FLOODLIGHT', amenities: ['ac', 'shower']);
      final second = newCourtDraft(id: 'c2', sportId: 's-bad', sportCode: 'BADMINTON', sportName: 'Badminton', existing: [first]);
      expect((second.name, second.surface, second.lighting, second.amenities.join(',')), ('Badminton Court 2', 'Synthetic (PU)', 'FLOODLIGHT', 'ac,shower'));
      second.amenities.add('locker');
      expect(first.amenities, ['ac', 'shower'], reason: 'a copy, not shared');
    });

    test('other sports\' courts are not copied', () {
      final cricket = _draft(id: 'x', sportId: 's-cri', surface: 'Turf');
      final c = newCourtDraft(id: 'n', sportId: 's-bad', sportCode: 'BADMINTON', sportName: 'Badminton', existing: [cricket]);
      expect(c.surface, 'Wooden');
    });
  });

  group('validation', () {
    test('accepts a complete court', () {
      expect(validateCourtDrafts([_draft()], _sports).ok, isTrue);
    });

    test('needs a name of 2-50 characters, unique within the sport', () {
      expect(validateCourtDrafts([_draft(name: '')], _sports).byCourt['c1']?['name'], 'Name must be between 2 and 50 characters.');
      expect(validateCourtDrafts([_draft(name: 'x' * 51)], _sports).ok, isFalse);
      final dupes = validateCourtDrafts([_draft(id: 'a', name: 'Court A'), _draft(id: 'b', name: 'court a')], _sports);
      expect(dupes.byCourt['b']?['name'], 'This name is already used for this sport.');
      expect(dupes.byCourt['a'], isNull);
    });

    test('the same name is fine on two different sports', () {
      final ok = validateCourtDrafts(
        [_draft(id: 'a', name: 'Net 1'), _draft(id: 'b', sportId: 's-cri', name: 'Net 1')],
        const [(id: 's-bad', name: 'Badminton', code: 'BADMINTON'), (id: 's-cri', name: 'Cricket', code: 'CRICKET')],
      );
      expect(ok.ok, isTrue);
    });

    test('needs a surface and lighting', () {
      final r = validateCourtDrafts([_draft(surface: ' ', lighting: '')], _sports);
      expect(r.byCourt['c1'], {'surface': 'Select a surface.', 'lighting': 'Select lighting.'});
    });

    test('every selected sport needs at least one court', () {
      final r = validateCourtDrafts([], const [(id: 's-bad', name: 'Badminton', code: 'BADMINTON'), (id: 's-foot', name: 'Football', code: 'FOOTBALL')]);
      expect(r.bySport['s-bad'], 'Add at least one court for Badminton.');
      expect(r.bySport['s-foot'], 'Add at least one turf for Football.');
      expect(r.ok, isFalse);
    });
  });

  group('option lists', () {
    test('every sport offers its own surfaces, and the defaults are among them', () {
      for (final code in ['BADMINTON', 'PICKLEBALL', 'TENNIS', 'CRICKET', 'FOOTBALL', 'BASKETBALL']) {
        expect(surfaceOptionsFor(code), contains(courtDefaultsFor(code).surface), reason: code);
      }
      expect(surfaceOptionsFor('OTHER').length, greaterThan(2));
    });

    test('lighting and amenity values match the database checks', () {
      expect(kLightingOptions.map((o) => o.value), ['LED', 'FLOODLIGHT', 'NATURAL', 'NONE']);
      expect(kCourtAmenities.map((o) => o.value), ['ac', 'shower', 'locker']);
      expect(lightingLabel('FLOODLIGHT'), 'Floodlight');
    });
  });

  group('court model', () {
    test('reads the new columns, and an older court gets the sport\'s usual values', () {
      final area = PlayingArea.fromJson({
        'id': 'c1', 'facility_id': 'f', 'facility_sport_id': 'fs', 'sport_id': 's-bad', 'name': 'Court A', 'area_type': 'OUTDOOR',
        'surface': 'Cement', 'lighting_type': 'FLOODLIGHT', 'court_amenities': ['ac', 'locker'],
      });
      final d = CourtDraft.fromPlayingArea(area, 'BADMINTON');
      expect((d.type, d.surface, d.lighting, d.amenities.join(',')), ('OUTDOOR', 'Cement', 'FLOODLIGHT', 'ac,locker'));

      final old = PlayingArea.fromJson({'id': 'c2', 'facility_id': 'f', 'facility_sport_id': 'fs', 'sport_id': 's-bad', 'name': 'Court B'});
      final od = CourtDraft.fromPlayingArea(old, 'BADMINTON');
      expect((od.type, od.surface, od.lighting, od.amenities.join(',')), ('INDOOR', 'Wooden', 'LED', ''));
    });

    test('the insert payload carries them', () {
      final area = PlayingArea.fromJson({'id': 'c1', 'facility_id': 'f', 'facility_sport_id': 'fs', 'sport_id': 's', 'name': 'A', 'surface': 'Wooden', 'lighting_type': 'LED', 'court_amenities': ['shower']});
      final json = area.toInsertJson();
      expect((json['surface'], json['lighting_type'], (json['court_amenities'] as List).join(',')), ('Wooden', 'LED', 'shower'));
    });
  });
}
