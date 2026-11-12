import '../../data/models/playing_area.dart';

/// Pure rules for the Sports & Courts step — the same options, defaults and checks as the website's `court-draft.ts` /
/// `courts-setup/constants.ts`, kept out of widgets so they can be unit-tested and never drift between the two apps.

class CourtOption {
  const CourtOption(this.value, this.label);
  final String value;
  final String label;
}

const List<CourtOption> kCourtTypes = [CourtOption('INDOOR', 'Indoor'), CourtOption('OUTDOOR', 'Outdoor')];

const List<CourtOption> kLightingOptions = [
  CourtOption('LED', 'LED'),
  CourtOption('FLOODLIGHT', 'Floodlight'),
  CourtOption('NATURAL', 'Natural Light'),
  CourtOption('NONE', 'No Lighting'),
];

const List<CourtOption> kCourtAmenities = [CourtOption('ac', 'AC'), CourtOption('shower', 'Shower'), CourtOption('locker', 'Locker')];

const Map<String, List<String>> _surfacesBySport = {
  'BADMINTON': ['Wooden', 'Synthetic (PU)', 'Vinyl Mat', 'Cement'],
  'PICKLEBALL': ['Acrylic', 'Concrete', 'Wooden', 'Synthetic'],
  'TENNIS': ['Hard Court', 'Clay', 'Grass', 'Synthetic'],
  'CRICKET': ['Turf', 'Artificial Turf', 'Matting', 'Cement'],
  'FOOTBALL': ['Artificial Turf', 'Natural Grass', 'Hybrid Turf', 'Concrete'],
  'BASKETBALL': ['Wooden', 'Concrete', 'Synthetic', 'Rubber'],
};
const List<String> _genericSurfaces = ['Wooden', 'Synthetic', 'Artificial Turf', 'Natural Grass', 'Concrete', 'Other'];

List<String> surfaceOptionsFor(String sportCode) => _surfacesBySport[sportCode] ?? _genericSurfaces;

typedef CourtDefaults = ({String type, String surface, String lighting});

const Map<String, CourtDefaults> _defaults = {
  'BADMINTON': (type: 'INDOOR', surface: 'Wooden', lighting: 'LED'),
  'PICKLEBALL': (type: 'OUTDOOR', surface: 'Acrylic', lighting: 'FLOODLIGHT'),
  'TENNIS': (type: 'OUTDOOR', surface: 'Hard Court', lighting: 'FLOODLIGHT'),
  'CRICKET': (type: 'OUTDOOR', surface: 'Turf', lighting: 'FLOODLIGHT'),
  'FOOTBALL': (type: 'OUTDOOR', surface: 'Artificial Turf', lighting: 'FLOODLIGHT'),
  'BASKETBALL': (type: 'INDOOR', surface: 'Wooden', lighting: 'LED'),
};
const CourtDefaults _genericDefault = (type: 'INDOOR', surface: 'Wooden', lighting: 'LED');

/// What a brand-new court starts as, per sport.
CourtDefaults courtDefaultsFor(String sportCode) => _defaults[sportCode] ?? _genericDefault;

String lightingLabel(String? value) => kLightingOptions.where((o) => o.value == value).map((o) => o.label).firstOrNull ?? '';

/// A court as it is edited on the screen, before it is saved.
class CourtDraft {
  CourtDraft({
    required this.id,
    this.savedId,
    required this.sportId,
    required this.name,
    required this.type,
    required this.surface,
    required this.lighting,
    List<String>? amenities,
  }) : amenities = amenities ?? [];

  /// Stable id for the editing session (the database id once saved).
  final String id;

  /// Set when the court already exists in the database.
  String? savedId;
  final String sportId;
  String name;
  String type;
  String surface;
  String lighting;
  List<String> amenities;

  CourtDraft copy() => CourtDraft(id: id, savedId: savedId, sportId: sportId, name: name, type: type, surface: surface, lighting: lighting, amenities: List.of(amenities));

  factory CourtDraft.fromPlayingArea(PlayingArea area, String sportCode) {
    final d = courtDefaultsFor(sportCode);
    return CourtDraft(
      id: area.id,
      savedId: area.id,
      sportId: area.sportId,
      name: area.name,
      type: area.areaType,
      // a court saved before surface / lighting were asked starts from the sport's usual values, which the owner confirms
      surface: (area.surface == null || area.surface!.trim().isEmpty) ? d.surface : area.surface!,
      lighting: area.lightingType ?? d.lighting,
      amenities: List.of(area.courtAmenities),
    );
  }
}

/// "Court 3" / "Turf 2": numbered after the highest number already used for the sport (not the count), so a removal never repeats a name.
String nextCourtName(String sportCode, List<String> existingNames) {
  final label = playingAreaLabelFor(sportCode);
  var highest = 0;
  for (final n in existingNames) {
    final m = RegExp(r'(\d+)\s*$').firstMatch(n.trim());
    final v = m == null ? 0 : int.parse(m.group(1)!);
    if (v > highest) highest = v;
  }
  return '$label ${highest + 1}';
}

/// A new court copies the sport's last court (so "add another" is one tap), else the sport's usual defaults.
CourtDraft newCourtDraft({required String id, required String sportId, required String sportCode, required String sportName, required List<CourtDraft> existing}) {
  final forSport = existing.where((c) => c.sportId == sportId).toList();
  final last = forSport.isEmpty ? null : forSport.last;
  final d = courtDefaultsFor(sportCode);
  final base = nextCourtName(sportCode, forSport.map((c) => c.name).toList());
  return CourtDraft(
    id: id,
    sportId: sportId,
    name: sportCode == 'OTHER' ? base : '$sportName $base',
    type: last?.type ?? d.type,
    surface: last?.surface ?? d.surface,
    lighting: last?.lighting ?? d.lighting,
    amenities: last == null ? [] : List.of(last.amenities),
  );
}

class CourtProblems {
  const CourtProblems({this.byCourt = const {}, this.bySport = const {}});

  /// problems keyed by court id, then by field (`name`, `surface`, `lighting`)
  final Map<String, Map<String, String>> byCourt;

  /// a sport with no court at all
  final Map<String, String> bySport;

  bool get ok => byCourt.isEmpty && bySport.isEmpty;
}

typedef SelectedSportInfo = ({String id, String name, String code});

CourtProblems validateCourtDrafts(List<CourtDraft> drafts, List<SelectedSportInfo> sports) {
  final byCourt = <String, Map<String, String>>{};
  final bySport = <String, String>{};
  final seen = <String, Set<String>>{};

  for (final court in drafts) {
    final problems = <String, String>{};
    final name = court.name.trim();
    if (name.length < 2 || name.length > 50) {
      problems['name'] = 'Name must be between 2 and 50 characters.';
    } else {
      final set = seen.putIfAbsent(court.sportId, () => <String>{});
      if (!set.add(name.toLowerCase())) problems['name'] = 'This name is already used for this sport.';
    }
    if (court.surface.trim().isEmpty) problems['surface'] = 'Select a surface.';
    if (court.lighting.isEmpty) problems['lighting'] = 'Select lighting.';
    if (problems.isNotEmpty) byCourt[court.id] = problems;
  }

  for (final sport in sports) {
    if (!drafts.any((c) => c.sportId == sport.id)) {
      bySport[sport.id] = 'Add at least one ${playingAreaLabelFor(sport.code).toLowerCase()} for ${sport.name}.';
    }
  }
  return CourtProblems(byCourt: byCourt, bySport: bySport);
}

/// The display order of the sport tiles (the design's), then anything else the catalogue holds.
const List<String> kSportDisplayOrder = ['BADMINTON', 'FOOTBALL', 'CRICKET', 'TENNIS', 'BASKETBALL', 'PICKLEBALL'];

int sportRank(String code) {
  final i = kSportDisplayOrder.indexOf(code);
  return i == -1 ? kSportDisplayOrder.length : i;
}
