import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../data/models/facility.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/top_notice.dart';
import '../authentication/session_controller.dart';
import 'court_setup_logic.dart';
import 'setup_flow.dart';
import 'setup_ui.dart';

const _uuid = Uuid();

/// The icon a venue's own sport shows (the catalogue's "Other" icon is a plus sign, which would read as another Add button).
const _customSportIcon = '🏅';

/// The id a sport the owner added goes by while editing (it has no catalogue id of its own).
const _customPrefix = 'custom:';
String _customKey(String name) => '$_customPrefix${name.trim().toLowerCase()}';

/// Step 2 of the setup: Sports & Courts. Pick the sports on offer, then describe each court — name, indoor/outdoor, surface, lighting and
/// amenities — one by one or in bulk per sport. Everything is saved together on Next (or Save as Draft).
class SportsCourtsScreen extends ConsumerStatefulWidget {
  const SportsCourtsScreen({super.key});

  @override
  ConsumerState<SportsCourtsScreen> createState() => _SportsCourtsScreenState();
}

class _SportsCourtsScreenState extends ConsumerState<SportsCourtsScreen> {
  bool _loading = true;
  String? _loadError;
  String? _facilityId;
  List<Sport> _sports = [];

  final List<String> _selectedIds = [];
  /// The sports the owner added themselves (any number), and the box they type a new one into.
  final List<String> _customNames = [];
  final _customInput = TextEditingController();
  bool _adding = false;
  String? _customError;
  String? _sportsError;

  final List<CourtDraft> _drafts = [];
  String? _activeSportId;
  bool _bulk = false;
  CourtProblems _problems = const CourtProblems();

  /// Courts already in the database when the screen loaded, so a removal can archive them on save.
  final Set<String> _loadedCourtIds = {};

  String? _error;
  bool _savingNext = false;
  bool _autoSaving = false;

  /// Saves the courts as a draft by itself, 10 quiet seconds after the last change (see [DraftAutosave]).
  late final DraftAutosave _autosave = DraftAutosave(
    signature: _signature,
    save: () => _persist(advance: false, silent: true),
    onSaved: () {
      if (mounted) showTopNotice(context, kDraftSavedMessage, compact: true, duration: const Duration(milliseconds: 2800));
    },
  );

  /// Everything the person can change on this step, as one short string.
  String _signature() => [
        _selectedIds.join(','),
        _customNames.join('|'),
        for (final d in _drafts) '${d.id}:${d.sportId}:${d.name}:${d.type}:${d.surface}:${d.lighting}:${d.amenities.join(',')}',
      ].join('\n');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autosave.dispose();
    _customInput.dispose();
    super.dispose();
  }

  Sport? get _otherSport => _sports.where((s) => s.code == otherSportCode).firstOrNull;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final areaRepo = ref.read(playingAreaRepositoryProvider);
      final knownId = knownFacilityId(ref);
      // Requested together, not one after another: the facility, the sports list, and (when the app already knows the facility's id)
      // this facility's sports and courts.
      final facilityFuture = ref.read(facilityRepositoryProvider).getFacility()..ignore();
      final catalogueFuture = sportsRepo.getActiveSports()..ignore();
      final existingFuture = knownId == null ? null : (sportsRepo.getFacilitySports(knownId)..ignore());
      final areasFuture = knownId == null ? null : (areaRepo.getPlayingAreas(knownId)..ignore());

      final facility = await facilityFuture;
      if (facility == null) {
        if (mounted) context.go(AppRoutes.onboardingFacility);
        return;
      }
      final catalogue = await catalogueFuture;
      final sameFacility = knownId == facility.id;
      final existingSports = await (sameFacility ? existingFuture! : sportsRepo.getFacilitySports(facility.id));
      final areas = await (sameFacility ? areasFuture! : areaRepo.getPlayingAreas(facility.id));
      if (!mounted) return;

      final otherId = catalogue.where((s) => s.code == otherSportCode).firstOrNull?.id;
      String codeOf(String id) => catalogue.where((s) => s.id == id).firstOrNull?.code ?? otherSportCode;
      // every saved sport gets an editing key: its catalogue id, or custom:<name> for one the owner added
      String keyOf(FacilitySport r) => r.sportId == otherId ? _customKey(r.customSportName ?? '') : r.sportId;
      final keyByFacilitySport = {for (final r in existingSports) r.id: keyOf(r)};

      var ids = existingSports.where((r) => r.sportId != otherId).map((r) => r.sportId).toList();
      final customs = [
        for (final r in existingSports)
          if (r.sportId == otherId && (r.customSportName ?? '').trim().isNotEmpty) r.customSportName!.trim(),
      ];
      if (ids.isEmpty && customs.isEmpty) {
        // a single-sport venue starts with its sport ticked
        final code = switch (facility.type) {
          FacilityType.badminton => 'BADMINTON',
          FacilityType.pickleball => 'PICKLEBALL',
          FacilityType.cricket => 'CRICKET',
          FacilityType.football => 'FOOTBALL',
          FacilityType.tennis => 'TENNIS',
          _ => null,
        };
        final pre = code == null ? null : catalogue.where((s) => s.code == code).firstOrNull;
        if (pre != null) ids = [pre.id];
      }
      final initial = <CourtDraft>[];
      for (final a in areas) {
        final key = keyByFacilitySport[a.facilitySportId];
        if (key == null) continue;
        final d = CourtDraft.fromPlayingArea(a, codeOf(a.sportId));
        initial.add(CourtDraft(id: d.id, savedId: d.savedId, sportId: key, name: d.name, type: d.type, surface: d.surface, lighting: d.lighting, amenities: d.amenities));
      }

      setState(() {
        _facilityId = facility.id;
        _sports = catalogue;
        _selectedIds
          ..clear()
          ..addAll(ids);
        _customNames
          ..clear()
          ..addAll(customs);
        _drafts
          ..clear()
          ..addAll(initial);
        _loadedCourtIds
          ..clear()
          ..addAll(areas.map((a) => a.id));
        _loading = false;
      });
      _ensureCourts();
      // what is on screen now counts as saved: only what the person changes from here is auto-saved
      _autosave.start();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      debugPrint('Sports & courts load failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'We couldn’t load your sports and courts. Please try again.';
      });
    }
  }

  // ── selection ────────────────────────────────────────────────────────

  List<({String id, String name, String code, String icon})> get _selectedSports {
    final list = <({String id, String name, String code, String icon})>[];
    final catalogue = [..._sports.where((s) => s.code != otherSportCode)]..sort((a, b) => sportRank(a.code).compareTo(sportRank(b.code)));
    for (final s in catalogue) {
      if (_selectedIds.contains(s.id)) list.add((id: s.id, name: s.name, code: s.code, icon: s.icon));
    }
    for (final name in _customNames) {
      list.add((id: _customKey(name), name: name, code: otherSportCode, icon: _customSportIcon));
    }
    return list;
  }

  /// A selected sport always starts with one court, so there is something to configure.
  void _ensureCourts() {
    for (final s in _selectedSports) {
      if (!_drafts.any((d) => d.sportId == s.id)) {
        _drafts.add(newCourtDraft(id: _uuid.v4(), sportId: s.id, sportCode: s.code, sportName: s.name, existing: _drafts));
      }
    }
    final sports = _selectedSports;
    if (sports.isEmpty) {
      _activeSportId = null;
    } else if (!sports.any((s) => s.id == _activeSportId)) {
      _activeSportId = sports.first.id;
    }
    if (mounted) setState(() {});
  }

  void _toggleSport(String sportId) {
    setState(() {
      _sportsError = null;
      _selectedIds.contains(sportId) ? _selectedIds.remove(sportId) : _selectedIds.add(sportId);
      _activeSportId = sportId;
    });
    _ensureCourts();
  }

  void _startAdd() => setState(() {
        _adding = true;
        _customError = null;
      });

  void _cancelAdd() => setState(() {
        _adding = false;
        _customError = null;
        _customInput.clear();
      });

  /// Adds the sport typed in the box: any number are allowed, each with its own courts.
  void _confirmCustom() {
    final name = _customInput.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    String? problem;
    if (name.length < 2) {
      problem = 'Sport name must be at least 2 characters.';
    } else if (name.length > 50) {
      problem = 'Keep this under 50 characters.';
    } else if (_customNames.any((n) => n.toLowerCase() == name.toLowerCase()) ||
        _sports.any((s) => s.code != otherSportCode && s.name.toLowerCase() == name.toLowerCase())) {
      problem = '"$name" is already in the list.';
    }
    if (problem != null) {
      setState(() => _customError = problem);
      return;
    }
    setState(() {
      _customNames.add(name);
      _customError = null;
      _adding = false;
      _sportsError = null;
      _customInput.clear();
      _activeSportId = _customKey(name);
    });
    _ensureCourts();
  }

  void _removeCustom(String name) {
    final key = _customKey(name);
    setState(() {
      _customNames.remove(name);
      _drafts.removeWhere((d) => d.sportId == key);
    });
    _ensureCourts();
  }

  // ── editing courts ───────────────────────────────────────────────────

  void _changeCourt(CourtDraft court, void Function(CourtDraft) edit) {
    setState(() {
      edit(court);
      final byCourt = Map<String, Map<String, String>>.of(_problems.byCourt)..remove(court.id);
      _problems = CourtProblems(byCourt: byCourt, bySport: _problems.bySport);
    });
  }

  void _addCourt(String sportId) {
    final sport = _selectedSports.where((s) => s.id == sportId).firstOrNull;
    if (sport == null) return;
    setState(() {
      _drafts.add(newCourtDraft(id: _uuid.v4(), sportId: sportId, sportCode: sport.code, sportName: sport.name, existing: _drafts));
      final bySport = Map<String, String>.of(_problems.bySport)..remove(sportId);
      _problems = CourtProblems(byCourt: _problems.byCourt, bySport: bySport);
    });
  }

  void _removeCourt(String id) => setState(() => _drafts.removeWhere((c) => c.id == id));

  void _bulkApply(String sportId, void Function(CourtDraft) edit) {
    setState(() {
      for (final c in _drafts.where((c) => c.sportId == sportId)) {
        edit(c);
      }
    });
  }

  // ── save ─────────────────────────────────────────────────────────────

  /// Saves the sports and courts. With [silent] (the auto-save) nothing is shown or changed on screen, and a step that is not valid yet
  /// is simply skipped. Returns whether it saved.
  Future<bool> _persist({required bool advance, bool silent = false}) async {
    final facilityId = _facilityId;
    if (facilityId == null) return false;
    if (silent && (_savingNext || _autoSaving)) return false;

    final selected = _selectedSports;
    final keep = _drafts.where((d) => selected.any((s) => s.id == d.sportId)).toList();
    final found = validateCourtDrafts(keep, [for (final s in selected) (id: s.id, name: s.name, code: s.code)]);
    final noSports = _selectedIds.isEmpty && _customNames.isEmpty;
    final noOther = _customNames.isNotEmpty && _otherSport == null;

    if (silent) {
      if (noSports || noOther || !found.ok) return false;
    } else {
      setState(() => _error = null);
      String? sportsProblem;
      if (noSports) {
        sportsProblem = 'Select at least one sport to continue.';
      } else if (noOther) {
        sportsProblem = 'Adding your own sport isn’t available right now. Please pick from the list.';
      }
      setState(() {
        _sportsError = sportsProblem;
        _problems = found;
      });
      if (sportsProblem != null || !found.ok) {
        setState(() => _error = 'Please fix the highlighted fields to continue.');
        return false;
      }
    }

    if (silent) {
      _autoSaving = true;
    } else {
      setState(() => _savingNext = true);
    }
    try {
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final areaRepo = ref.read(playingAreaRepositoryProvider);
      final keepSaved = keep.map((d) => d.savedId).whereType<String>().toSet();

      // 1. courts that were removed (or belong to a sport that was switched off) are archived first, all at once
      final removed = _loadedCourtIds.where((id) => !keepSaved.contains(id)).toList();
      await Future.wait([for (final id in removed) areaRepo.removePlayingArea(id)]);
      _loadedCourtIds.removeAll(removed);

      // 2. the sports
      final saved = await sportsRepo.saveFacilitySportsMulti(
        facilityId,
        sportIds: _selectedIds.toList(),
        customSportNames: _customNames.toList(),
      );
      final otherId = _otherSport?.id;
      FacilitySport? savedFor(String key) => key.startsWith(_customPrefix)
          ? saved.where((r) => r.sportId == otherId && (r.customSportName ?? '').trim().toLowerCase() == key.substring(_customPrefix.length)).firstOrNull
          : saved.where((r) => r.sportId == key && (r.customSportName ?? '').isEmpty).firstOrNull;

      // 3. the courts, all at once
      final order = <String, int>{};
      final jobs = <Future<void>>[];
      for (final court in keep) {
        final fs = savedFor(court.sportId);
        if (fs == null) throw AppException(AppErrorCode.facilitySportNotFound);
        final index = order[court.sportId] = (order[court.sportId] ?? -1) + 1;
        if (court.savedId != null) {
          jobs.add(areaRepo.updatePlayingArea(
            court.savedId!,
            name: court.name.trim(),
            areaType: court.type,
            surface: court.surface.trim(),
            lightingType: court.lighting,
            courtAmenities: court.amenities,
            displayOrder: index,
          ));
        } else {
          jobs.add(areaRepo
              .createPlayingArea(PlayingArea(
                id: court.id,
                facilityId: facilityId,
                facilitySportId: fs.id,
                // a sport the owner added is the catalogue's "Other" sport with its own name
                sportId: court.sportId.startsWith(_customPrefix) ? otherId! : court.sportId,
                name: court.name.trim(),
                areaType: court.type,
                surface: court.surface.trim(),
                lightingType: court.lighting,
                courtAmenities: List.of(court.amenities),
                status: 'ACTIVE',
                bookingEnabled: true,
                archived: false,
                displayOrder: index,
              ))
              .then((created) {
            court.savedId = created.id;
            _loadedCourtIds.add(created.id);
          }));
        }
      }
      await Future.wait(jobs);

      if (advance) {
        final step = ref.read(sessionControllerProvider).facility?.onboardingStep;
        if (step == null || step == OnboardingStep.facilityDetails || step == OnboardingStep.sportsCourts) {
          await ref.read(facilityRepositoryProvider).updateOnboardingStep(facilityId, OnboardingStep.operatingHours);
        }
        _autosave.markSaved();
        // the next step opens now; the app's copy of the session catches up behind it
        refreshSessionInBackground(ref);
        if (!mounted) return true;
        context.push(AppRoutes.onboardingOperatingHours);
      }
      return true;
    } on AppException catch (e) {
      if (silent) {
        debugPrint('Sports & courts auto-save skipped: ${e.message}');
        return false;
      }
      if (mounted) setState(() => _error = e.message);
      return false;
    } catch (e, stack) {
      debugPrint('Sports & courts save failed: $e\n$stack');
      if (silent) return false;
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
      return false;
    } finally {
      _autoSaving = false;
      if (!silent && mounted) setState(() => _savingNext = false);
    }
  }

  // ── build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return SetupPage(
        footer: SetupButton(label: 'Try again', primary: true, onPressed: _load),
        children: [const SetupStepper(current: 2), const SizedBox(height: 18), SetupErrorBanner(_loadError!)],
      );
    }
    if (_loading) return const SetupLoadingPage(cards: [3, 3, 2]);

    final selected = _selectedSports;
    final visible = _drafts.where((d) => selected.any((s) => s.id == d.sportId)).toList();

    return SetupPage(
      footer: SetupNavFooter(
        onBack: () => goBackOr(context, AppRoutes.onboardingFacility),
        next: SetupButton(label: 'Next', primary: true, trailingIcon: Icons.arrow_forward, loading: _savingNext, loadingLabel: 'Saving…', onPressed: () => _persist(advance: true)),
      ),
      children: [
        const SetupStepper(current: 2),
        const SizedBox(height: 18),
        Text('Sports & Courts', style: setupText(size: 28, weight: FontWeight.w700, height: 1.1)),
        const SizedBox(height: 6),
        Text('Select the sports available at your facility and add court details easily.', style: setupText(size: 14, color: SetupColors.secondary, height: 1.4)),
        const SizedBox(height: 18),
        if (_error != null) SetupErrorBanner(_error!),
        _sportsCard(),
        const SizedBox(height: 16),
        _configureCard(selected),
        const SizedBox(height: 16),
        _previewCard(selected, visible),
      ],
    );
  }

  // ── Select Sports ────────────────────────────────────────────────────

  Widget _sportsCard() {
    final catalogue = [..._sports.where((s) => s.code != otherSportCode)]..sort((a, b) => sportRank(a.code).compareTo(sportRank(b.code)));

    Widget frame({required Key key, required bool on, required Widget child, VoidCallback? onTap}) {
      return GestureDetector(
        key: key,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 92,
          decoration: BoxDecoration(
            color: on ? SetupColors.activeBg : SetupColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? SetupColors.primary : SetupColors.border, width: on ? 1.5 : 1),
          ),
          child: child,
        ),
      );
    }

    Widget content(String icon, String label) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: setupText(size: 13, weight: FontWeight.w500)),
              ),
            ],
          ),
        );

    Widget tile({required Key key, required String icon, required String label, required bool on, required VoidCallback onTap}) {
      return frame(
        key: key,
        on: on,
        onTap: onTap,
        child: Stack(
          children: [
            content(icon, label),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                height: 18,
                width: 18,
                decoration: BoxDecoration(color: on ? SetupColors.primary : SetupColors.background, borderRadius: BorderRadius.circular(5), border: Border.all(color: on ? SetupColors.primary : SetupColors.border)),
                child: on ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
              ),
            ),
          ],
        ),
      );
    }

    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.layers_outlined, title: 'Select Sports', description: 'Choose the sports you offer at your venue.'),
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 20) / 3;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in catalogue)
                    SizedBox(width: w, child: tile(key: ValueKey('sport-${s.code.toLowerCase()}'), icon: s.icon, label: s.name, on: _selectedIds.contains(s.id), onTap: () => _toggleSport(s.id))),
                  // a sport the owner added: its own card, with its own delete button
                  for (final name in _customNames)
                    SizedBox(
                      width: w,
                      child: frame(
                        key: ValueKey('custom-sport-${name.toLowerCase()}'),
                        on: true,
                        child: Stack(
                          children: [
                            content(_customSportIcon, name),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: IconButton(
                                key: ValueKey('remove-custom-${name.toLowerCase()}'),
                                tooltip: 'Remove $name',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                padding: EdgeInsets.zero,
                                onPressed: () => _removeCustom(name),
                                icon: const Icon(Icons.delete_outline, size: 18, color: SetupColors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_otherSport != null)
                    SizedBox(
                      width: w,
                      child: GestureDetector(
                        key: const ValueKey('add-sport'),
                        onTap: _startAdd,
                        child: Container(
                          height: 92,
                          decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: SetupColors.primary.withValues(alpha: 0.55))),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add, color: SetupColors.primary, size: 26),
                              Text('Add Sport', style: setupText(size: 13, weight: FontWeight.w600, color: SetupColors.primary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_adding) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: SetupColors.mutedFill, borderRadius: BorderRadius.circular(10), border: Border.all(color: SetupColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SetupLabel('Sport name'),
                  TextField(
                    key: const ValueKey('custom-sport-input'),
                    controller: _customInput,
                    autofocus: true,
                    maxLength: 50,
                    style: setupText(size: 15),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _confirmCustom(),
                    onChanged: (_) => setState(() => _customError = null),
                    decoration: setupDecoration(hint: 'e.g. Table Tennis', counterText: ''),
                  ),
                  if (_customError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_customError!, key: const ValueKey('custom-sport-error'), style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error))),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: SetupButton(label: 'Cancel', onPressed: _cancelAdd)),
                      const SizedBox(width: 10),
                      Expanded(child: SetupButton(label: 'Add', primary: true, onPressed: _confirmCustom)),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (_sportsError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_sportsError!, key: const ValueKey('sports-error'), style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error))),
        ],
      ),
    );
  }

  // ── Configure Courts ─────────────────────────────────────────────────

  Widget _configureCard(List<({String id, String name, String code, String icon})> selected) {
    final active = selected.where((s) => s.id == _activeSportId).firstOrNull ?? (selected.isEmpty ? null : selected.first);
    final courts = active == null ? <CourtDraft>[] : _drafts.where((d) => d.sportId == active.id).toList();

    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.grid_view_outlined, title: 'Configure Courts', description: 'Add and manage courts for each selected sport.'),
          SetupSegmented<bool>(
            label: 'How do you want to set them up?',
            keyPrefix: 'mode',
            value: _bulk,
            options: const [(value: false, label: 'By Court'), (value: true, label: 'Bulk (Same)')],
            onChanged: (v) => setState(() => _bulk = v),
          ),
          const SizedBox(height: 4),
          Text('By Court sets each court on its own. Bulk applies one set of type, surface, lighting and amenities to every court of the sport.', style: setupText(size: 12, color: SetupColors.secondary, height: 1.35)),
          const SizedBox(height: 14),
          if (active == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: SetupColors.border)),
              child: Text('Select at least one sport above to add its courts.', textAlign: TextAlign.center, style: setupText(size: 13, color: SetupColors.secondary)),
            )
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in selected)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        key: ValueKey('active-${s.id}'),
                        onTap: () => setState(() => _activeSportId = s.id),
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: s.id == active.id ? SetupColors.activeBg : SetupColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _problems.bySport.containsKey(s.id) ? SetupColors.error : (s.id == active.id ? SetupColors.primary : SetupColors.border)),
                          ),
                          child: Row(
                            children: [
                              Text(s.icon, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Text('${s.name} (${_drafts.where((d) => d.sportId == s.id).length})', style: setupText(size: 13, weight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('${active.name} Courts (${courts.length})', key: const ValueKey('active-heading'), style: setupText(size: 17, weight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (_bulk && courts.isNotEmpty) _bulkCard(active, courts.first),
            for (var i = 0; i < courts.length; i++) _courtCard(active, courts[i], i),
            if (_problems.bySport[active.id] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_problems.bySport[active.id]!, style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error))),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('add-court'),
                onPressed: () => _addCourt(active.id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SetupColors.primary,
                  backgroundColor: const Color(0xFFF8F4FF),
                  side: BorderSide(color: SetupColors.primary.withValues(alpha: 0.45)),
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text('Add Court', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.primary)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// type / surface / lighting / amenities for one court (or for every court in bulk mode).
  Widget _settingsFields({required String keyPrefix, required String sportCode, required CourtDraft court, required void Function(void Function(CourtDraft)) apply, Map<String, String>? problems}) {
    final surfaces = surfaceOptionsFor(sportCode);
    final surfaceItems = [if (court.surface.isNotEmpty && !surfaces.contains(court.surface)) court.surface, ...surfaces];
    const gap = SizedBox(height: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupDropdown<String>(
          key: ValueKey('$keyPrefix-type-${court.type}'),
          label: 'Court Type',
          required: true,
          value: court.type,
          items: [for (final o in kCourtTypes) DropdownMenuItem(value: o.value, child: Text(o.label))],
          onChanged: (v) => apply((c) => c.type = v ?? c.type),
        ),
        gap,
        SetupDropdown<String>(
          key: ValueKey('$keyPrefix-surface-${court.surface}'),
          label: 'Surface Type',
          required: true,
          value: court.surface.isEmpty ? null : court.surface,
          hint: 'Select',
          items: [for (final s in surfaceItems) DropdownMenuItem(value: s, child: Text(s))],
          onChanged: (v) => apply((c) => c.surface = v ?? c.surface),
        ),
        if (problems?['surface'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(problems!['surface']!, style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error))),
        gap,
        SetupDropdown<String>(
          key: ValueKey('$keyPrefix-lighting-${court.lighting}'),
          label: 'Lighting',
          required: true,
          value: court.lighting.isEmpty ? null : court.lighting,
          hint: 'Select',
          items: [for (final o in kLightingOptions) DropdownMenuItem(value: o.value, child: Text(o.label))],
          onChanged: (v) => apply((c) => c.lighting = v ?? c.lighting),
        ),
        if (problems?['lighting'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(problems!['lighting']!, style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error))),
        gap,
        const SetupLabel('Amenities', optional: true),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in kCourtAmenities)
              GestureDetector(
                key: ValueKey('$keyPrefix-amenity-${a.value}'),
                onTap: () => apply((c) => c.amenities.contains(a.value) ? c.amenities.remove(a.value) : c.amenities.add(a.value)),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: court.amenities.contains(a.value) ? SetupColors.activeBg : SetupColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: court.amenities.contains(a.value) ? SetupColors.primary.withValues(alpha: 0.5) : SetupColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 18,
                        width: 18,
                        decoration: BoxDecoration(
                          color: court.amenities.contains(a.value) ? SetupColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: court.amenities.contains(a.value) ? SetupColors.primary : SetupColors.border, width: 1.5),
                        ),
                        child: court.amenities.contains(a.value) ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 8),
                      Text(a.label, style: setupText(size: 13, weight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bulkCard(({String id, String name, String code, String icon}) sport, CourtDraft first) {
    return Container(
      key: const ValueKey('bulk-card'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: SetupColors.primary.withValues(alpha: 0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('All ${sport.name} courts', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.primary)),
          const SizedBox(height: 10),
          _settingsFields(keyPrefix: 'bulk-${sport.id}', sportCode: sport.code, court: first, apply: (edit) => _bulkApply(sport.id, edit)),
        ],
      ),
    );
  }

  Widget _courtCard(({String id, String name, String code, String icon}) sport, CourtDraft court, int index) {
    final p = _problems.byCourt[court.id];
    return Container(
      key: ValueKey('court-${court.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: SetupColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 24,
                width: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: SetupColors.activeBg, shape: BoxShape.circle),
                child: Text('${index + 1}', style: setupText(size: 12, weight: FontWeight.w600, color: SetupColors.primary)),
              ),
              const SizedBox(width: 10),
              const Expanded(child: SetupLabel('Court Name', required: true)),
              IconButton(
                key: ValueKey('remove-${court.id}'),
                tooltip: 'Remove ${court.name}',
                onPressed: () => _removeCourt(court.id),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.delete_outline, color: SetupColors.error, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey('name-${court.id}'),
            initialValue: court.name,
            maxLength: 50,
            style: setupText(size: 15),
            onChanged: (v) => _changeCourt(court, (c) => c.name = v),
            decoration: setupDecoration(counterText: '').copyWith(errorText: p?['name']),
          ),
          const SizedBox(height: 12),
          if (_bulk)
            Text('Uses the settings for all ${sport.name} courts above.', style: setupText(size: 12, color: SetupColors.secondary))
          else
            _settingsFields(keyPrefix: 'court-${court.id}', sportCode: sport.code, court: court, problems: p, apply: (edit) => _changeCourt(court, edit)),
        ],
      ),
    );
  }

  // ── Preview ──────────────────────────────────────────────────────────

  Widget _previewCard(List<({String id, String name, String code, String icon})> selected, List<CourtDraft> visible) {
    final rows = [
      for (final s in selected)
        for (final c in visible.where((d) => d.sportId == s.id)) (court: c, sport: s),
    ];
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SetupCardHeading(icon: Icons.visibility_outlined, title: 'Preview of Courts (${rows.length})', description: 'All configured courts across selected sports.'),
          if (rows.isEmpty)
            Text('Courts you add will appear here.', style: setupText(size: 13, color: SetupColors.secondary))
          else
            for (final r in rows)
              Container(
                key: ValueKey('preview-${r.court.id}'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: SetupColors.mutedFill, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.sport.icon, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.court.name, style: setupText(size: 14, weight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(color: r.court.type == 'INDOOR' ? const Color(0xFFEDE7FF) : const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(99)),
                                child: Text(r.court.type == 'INDOOR' ? 'Indoor' : 'Outdoor', style: setupText(size: 11, weight: FontWeight.w600, color: r.court.type == 'INDOOR' ? SetupColors.primary : SetupColors.success)),
                              ),
                              Text('${r.court.surface} · ${lightingLabel(r.court.lighting)}', style: setupText(size: 12, color: SetupColors.secondary)),
                              for (final a in r.court.amenities)
                                Text(kCourtAmenities.where((o) => o.value == a).first.label, style: setupText(size: 11, weight: FontWeight.w600, color: SetupColors.primary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('preview-edit-${r.court.id}'),
                      tooltip: 'Edit ${r.court.name}',
                      onPressed: () => setState(() {
                        _bulk = false;
                        _activeSportId = r.sport.id;
                      }),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      key: ValueKey('preview-remove-${r.court.id}'),
                      tooltip: 'Remove ${r.court.name}',
                      onPressed: () => _removeCourt(r.court.id),
                      icon: const Icon(Icons.delete_outline, size: 18, color: SetupColors.error),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
