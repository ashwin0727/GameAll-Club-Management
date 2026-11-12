import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../data/models/facility.dart';
import '../../data/models/operating_hours.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/top_notice.dart';
import 'hours_setup_logic.dart';
import 'setup_flow.dart';
import 'setup_ui.dart';

const String _customSportIcon = '🏅';

class _Standard {
  _Standard({required this.days, required this.open, required this.close, required this.is24Hours});
  List<int> days;
  String open;
  String close;
  bool is24Hours;
}

_Standard _standardFromPlans(List<DayPlan> plans) {
  final open = plans.where((p) => p.isOpen).toList();
  return _Standard(
    days: [for (final p in open) p.dayOfWeek],
    open: open.isEmpty ? '06:00' : open.first.open,
    close: open.isEmpty ? '23:00' : open.first.close,
    is24Hours: open.isNotEmpty && open.every((p) => p.is24Hours),
  );
}

List<DayPlan> _plansFromStandard(_Standard s) => applyStandard(s.days, s.open, s.close, is24Hours: s.is24Hours);

class _SportEntry {
  _SportEntry({required this.id, required this.name, required this.icon, required this.courts});
  final String id; // facility_sports.id
  final String name;
  final String icon;
  final int courts;
}

/// Step 3 of the setup: Operating Hours. Standard hours (the same hours on the chosen days) or custom hours (each day on its own), the
/// venue's holidays and closures, and the extras — bookings outside hours, a daily break and sport-wise hours. Everything is saved
/// together on Next (or Save as Draft).
class OperatingHoursSetupScreen extends ConsumerStatefulWidget {
  const OperatingHoursSetupScreen({super.key});

  @override
  ConsumerState<OperatingHoursSetupScreen> createState() => _OperatingHoursSetupScreenState();
}

class _OperatingHoursSetupScreenState extends ConsumerState<OperatingHoursSetupScreen> {
  bool _loading = true;
  String? _loadError;
  String? _facilityId;
  List<Sport> _sports = [];
  List<FacilitySport> _facilitySports = [];
  List<PlayingArea> _areas = [];

  HoursMode _mode = HoursMode.standard;
  _Standard _standard = _standardFromPlans(defaultPlans());
  List<DayPlan> _custom = defaultPlans();
  List<ClosureEntry> _closures = [];
  bool _allowOutside = true;
  bool _breakOn = false;
  BreakTime _break = const BreakTime('13:00', '14:00');
  bool _sportWise = false;
  Map<String, List<DayPlan>> _sportPlans = {};

  PlanProblems _problems = const PlanProblems();
  Map<String, String> _sportErrors = {};
  String? _error;
  bool _savingNext = false;
  bool _autoSaving = false;

  /// Saves the hours as a draft by itself, 10 quiet seconds after the last change (see [DraftAutosave]).
  late final DraftAutosave _autosave = DraftAutosave(
    signature: _signature,
    save: () => _persist(advance: false, silent: true),
    onSaved: () {
      if (mounted) showTopNotice(context, kDraftSavedMessage, compact: true, duration: const Duration(milliseconds: 2800));
    },
  );

  static String _plansSignature(List<DayPlan> plans) => plans.map((d) => '${d.dayOfWeek}${d.isOpen ? 'o' : 'c'}${d.open}-${d.close}${d.is24Hours ? '*' : ''}').join(',');

  /// Everything the person can change on this step, as one short string.
  String _signature() => [
        _mode.name,
        '${_standard.days.join(',')}|${_standard.open}|${_standard.close}|${_standard.is24Hours}',
        _plansSignature(_custom),
        _closures.map((c) => '${c.date}:${c.name}').join(';'),
        '$_allowOutside',
        '$_breakOn:${_break.start}-${_break.end}',
        '$_sportWise',
        for (final e in (_sportPlans.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) '${e.key}=${_plansSignature(e.value)}',
      ].join('\n');

  @override
  void dispose() {
    _autosave.dispose();
    super.dispose();
  }

  bool _hadSportWise = false;
  final Set<String> _courtsWithOverride = {};

  List<DayPlan> get _plans => _mode == HoursMode.standard ? _plansFromStandard(_standard) : _custom;
  BreakTime? get _activeBreak => _breakOn ? _break : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final areaRepo = ref.read(playingAreaRepositoryProvider);
      final hours = ref.read(operatingHoursRepositoryProvider);
      final knownId = knownFacilityId(ref);
      // Requested together, not one after another. When the app already knows the facility's id, its sports, courts, hours and closures
      // are asked for at the same moment as the facility itself.
      final facilityFuture = ref.read(facilityRepositoryProvider).getFacility()..ignore();
      final catalogueFuture = sportsRepo.getActiveSports()..ignore();
      final facSportsFuture = knownId == null ? null : (sportsRepo.getFacilitySports(knownId)..ignore());
      final courtsFuture = knownId == null ? null : (areaRepo.getPlayingAreas(knownId)..ignore());
      final scheduleFuture = knownId == null ? null : (hours.getFacilitySchedule(knownId)..ignore());
      final closuresFuture = knownId == null ? null : (hours.getClosures(knownId)..ignore());

      final facility = await facilityFuture;
      if (facility == null) {
        if (mounted) context.go(AppRoutes.onboardingFacility);
        return;
      }
      final same = knownId == facility.id;
      final catalogue = await catalogueFuture;
      final facSports = await (same ? facSportsFuture! : sportsRepo.getFacilitySports(facility.id));
      final courts = await (same ? courtsFuture! : areaRepo.getPlayingAreas(facility.id));
      if (facSports.isEmpty || courts.isEmpty) {
        if (mounted) context.go(AppRoutes.onboardingSportsCourts);
        return;
      }
      final schedule = await (same ? scheduleFuture! : hours.getFacilitySchedule(facility.id));
      final closures = await (same ? closuresFuture! : hours.getClosures(facility.id));
      // every court's own hours, all at once
      final courtSchedules = await Future.wait([for (final c in courts) hours.getPlayingAreaSchedule(c.id)]);
      final overrides = <String, List<DayPlan>>{};
      for (var i = 0; i < courts.length; i++) {
        final o = courtSchedules[i];
        if (o != null) overrides[courts[i].id] = plansFromSchedule(o.days);
      }
      if (!mounted) return;

      final savedBreak = (facility.breakStart != null && facility.breakEnd != null) ? BreakTime(facility.breakStart!, facility.breakEnd!) : null;
      final loaded = schedule != null && schedule.days.isNotEmpty ? plansFromSchedule(schedule.days) : defaultPlans();

      final perSport = <String, List<DayPlan>>{};
      for (final fs in facSports) {
        final first = courts.where((c) => c.facilitySportId == fs.id && overrides.containsKey(c.id)).firstOrNull;
        perSport[fs.id] = first != null ? overrides[first.id]! : [for (final p in loaded) p.copy()];
      }
      _courtsWithOverride
        ..clear()
        ..addAll(overrides.keys);
      _hadSportWise = facility.sportWiseHours;

      setState(() {
        _facilityId = facility.id;
        _sports = catalogue;
        _facilitySports = facSports;
        _areas = courts;
        _mode = detectMode(loaded);
        _standard = _standardFromPlans(loaded);
        _custom = loaded;
        _closures = closures;
        _allowOutside = facility.allowBookingsOutsideHours;
        _breakOn = savedBreak != null;
        if (savedBreak != null) _break = savedBreak;
        _sportWise = facility.sportWiseHours;
        _sportPlans = perSport;
        _loading = false;
      });
      // what is on screen now counts as saved: only what the person changes from here is auto-saved
      _autosave.start();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      debugPrint('Operating hours load failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'We couldn’t load your operating hours. Please try again.';
      });
    }
  }

  // ── editing ─────────────────────────────────────────────────────────

  void _clearProblems() {
    _problems = const PlanProblems();
    _error = null;
  }

  void _switchMode(HoursMode next) {
    if (next == _mode) return;
    setState(() {
      if (next == HoursMode.custom) {
        _custom = _plansFromStandard(_standard);
      } else {
        _standard = _standardFromPlans(_custom);
      }
      _mode = next;
      _clearProblems();
    });
  }

  void _toggleSportWise(bool on) {
    setState(() {
      _sportWise = on;
      if (on) {
        final current = _plans;
        for (final fs in _facilitySports) {
          _sportPlans.putIfAbsent(fs.id, () => [for (final p in current) p.copy()]);
        }
      }
      _sportErrors = {};
    });
  }

  List<_SportEntry> get _sportEntries => [
        for (final fs in _facilitySports)
          () {
            final sport = _sports.where((s) => s.id == fs.sportId).firstOrNull;
            final custom = sport?.code == otherSportCode;
            return _SportEntry(
              id: fs.id,
              name: custom ? (fs.customSportName ?? 'Sport') : (sport?.name ?? 'Sport'),
              icon: custom ? _customSportIcon : (sport?.icon ?? _customSportIcon),
              courts: _areas.where((a) => a.facilitySportId == fs.id).length,
            );
          }(),
      ];

  // ── save ────────────────────────────────────────────────────────────

  /// Saves the hours. With [silent] (the auto-save) nothing is shown or changed on screen, and a step that is not valid yet is simply
  /// skipped. Returns whether it saved.
  Future<bool> _persist({required bool advance, bool silent = false}) async {
    final facilityId = _facilityId;
    if (facilityId == null) return false;
    if (silent && (_savingNext || _autoSaving)) return false;
    if (!silent) setState(() => _error = null);

    // with sport-wise hours on, the venue-wide hours and break are not used, so they are not checked
    final found = _sportWise ? validatePlans(_plans, null) : validatePlans(_plans, _activeBreak);
    final sportProblems = <String, String>{};
    if (_sportWise) {
      for (final e in _sportEntries) {
        final r = validatePlans(_sportPlans[e.id] ?? const [], null);
        final message = r.general ?? (r.byDay.values.isEmpty ? null : r.byDay.values.first);
        if (message != null) sportProblems[e.id] = message;
      }
    }
    if (silent) {
      if (found.any || sportProblems.isNotEmpty) return false;
    } else {
      setState(() {
        _problems = found;
        _sportErrors = sportProblems;
      });
      if (found.any || sportProblems.isNotEmpty) {
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
      final hours = ref.read(operatingHoursRepositoryProvider);
      // the three venue-wide saves touch different tables: all at once
      await Future.wait([
        hours.saveFacilitySchedule(facilityId, scheduleFromPlans(_plans, _activeBreak)),
        hours.replaceClosures(facilityId, _closures),
        ref.read(facilityRepositoryProvider).updateHoursSettings(
              facilityId,
              allowBookingsOutsideHours: _allowOutside,
              breakStart: _activeBreak?.start,
              breakEnd: _activeBreak?.end,
              sportWiseHours: _sportWise,
            ),
      ]);

      if (_sportWise) {
        final jobs = <Future<void>>[];
        for (final e in _sportEntries) {
          final days = scheduleFromPlans(_sportPlans[e.id] ?? const [], null);
          for (final court in _areas.where((a) => a.facilitySportId == e.id)) {
            jobs.add(hours.savePlayingAreaSchedule(court.id, facilityId, days));
            _courtsWithOverride.add(court.id);
          }
        }
        await Future.wait(jobs);
      } else if (_hadSportWise) {
        // sport-wise hours were on and are now off: the courts go back to the venue's hours
        await Future.wait([for (final id in _courtsWithOverride.toList()) hours.deletePlayingAreaOverride(id)]);
        _courtsWithOverride.clear();
      }
      _hadSportWise = _sportWise;

      if (advance) {
        await ref.read(facilityRepositoryProvider).updateOnboardingStep(facilityId, OnboardingStep.pricing);
        _autosave.markSaved();
        // the next step opens now; the app's copy of the session catches up behind it
        refreshSessionInBackground(ref);
        if (!mounted) return true;
        context.push(AppRoutes.onboardingPricing);
      }
      return true;
    } on AppException catch (e) {
      if (silent) {
        debugPrint('Operating hours auto-save skipped: ${e.message}');
        return false;
      }
      if (mounted) setState(() => _error = e.message);
      return false;
    } catch (e, stack) {
      debugPrint('Operating hours save failed: $e\n$stack');
      if (silent) return false;
      if (mounted) setState(() => _error = 'We couldn’t save your operating hours. Please try again.');
      return false;
    } finally {
      _autoSaving = false;
      if (!silent && mounted) setState(() => _savingNext = false);
    }
  }

  // ── pickers ─────────────────────────────────────────────────────────

  /// A time chosen from a list of half hours in a bottom sheet (the chosen time is highlighted and scrolled into view).
  Future<String?> _pickTime(String title, String current) {
    final options = [
      if (current.isNotEmpty && !timeOptions.any((o) => o.value == current)) (value: current, label: formatClock(current)),
      ...timeOptions,
    ];
    final index = options.indexWhere((o) => o.value == current);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: SetupColors.background,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheet).size.height * 0.6,
          child: Column(
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text(title, style: setupText(size: 17, weight: FontWeight.w600)))),
              Expanded(
                child: ListView.builder(
                  controller: ScrollController(initialScrollOffset: ((index < 0 ? 0 : index) - 2).clamp(0, 1000) * 52.0),
                  itemExtent: 52,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final o = options[i];
                    final on = o.value == current;
                    return InkWell(
                      key: ValueKey('time-option-${o.value}'),
                      onTap: () => Navigator.pop(sheet, o.value),
                      child: Container(
                        color: on ? SetupColors.activeBg : null,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Expanded(child: Text(o.label, style: setupText(size: 16, weight: on ? FontWeight.w600 : FontWeight.w400, color: on ? SetupColors.primary : SetupColors.text))),
                            if (on) const Icon(Icons.check, color: SetupColors.primary, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeBox({required String id, required String label, required String value, required ValueChanged<String> onChanged, bool enabled = true, bool invalid = false}) {
    return Semantics(
      button: true,
      label: '$label ${value.isEmpty ? '' : formatClock(value)}',
      child: InkWell(
        key: ValueKey('time-$id'),
        borderRadius: BorderRadius.circular(10),
        onTap: !enabled
            ? null
            : () async {
                final picked = await _pickTime(label, value);
                if (picked != null) {
                  setState(() {
                    onChanged(picked);
                    _clearProblems();
                  });
                }
              },
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled ? SetupColors.background : SetupColors.mutedFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: invalid ? SetupColors.error : SetupColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.access_time, size: 18, color: SetupColors.secondary),
              const SizedBox(width: 8),
              Expanded(child: Text(value.isEmpty ? '–' : formatClock(value), style: setupText(size: 15, color: enabled ? SetupColors.text : SetupColors.placeholder))),
              const Icon(Icons.keyboard_arrow_down, size: 20, color: SetupColors.text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelled(String text, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(text, style: setupText(size: 13))), child]);

  Widget _errorText(String message) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(message, style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error)));

  // ── pieces ──────────────────────────────────────────────────────────

  Widget _modeCards() {
    Widget card(HoursMode mode, String title, String hint, IconData icon) {
      final on = _mode == mode;
      return GestureDetector(
        key: ValueKey('mode-${mode.name}'),
        onTap: () => _switchMode(mode),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: on ? SetupColors.activeBg : SetupColors.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? SetupColors.primary : SetupColors.border, width: on ? 1.5 : 1)),
          child: Row(
            children: [
              Icon(icon, size: 30, color: SetupColors.text),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: setupText(size: 16, weight: FontWeight.w600)),
                    Text(hint, style: setupText(size: 13, color: SetupColors.secondary, height: 1.3)),
                  ],
                ),
              ),
              Container(
                height: 22,
                width: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? SetupColors.primary : const Color(0xFFB9B4C9), width: 2)),
                child: on ? Container(height: 10, width: 10, decoration: const BoxDecoration(color: SetupColors.primary, shape: BoxShape.circle)) : null,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        card(HoursMode.standard, 'Standard Hours', 'Same operating hours for selected days', Icons.event_available_outlined),
        const SizedBox(height: 10),
        card(HoursMode.custom, 'Custom Hours', 'Set different hours for each day', Icons.tune),
      ],
    );
  }

  Widget _dayChips(List<int> selected, void Function(List<int>) onChange, String keyPrefix) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in displayOrder)
          GestureDetector(
            key: ValueKey('$keyPrefix-$d'),
            onTap: () => setState(() {
              onChange(selected.contains(d) ? (List.of(selected)..remove(d)) : [...selected, d]);
              _clearProblems();
            }),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected.contains(d) ? SetupColors.activeBg : SetupColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected.contains(d) ? SetupColors.primary.withValues(alpha: 0.5) : SetupColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 18,
                    width: 18,
                    decoration: BoxDecoration(color: selected.contains(d) ? SetupColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(5), border: Border.all(color: selected.contains(d) ? SetupColors.primary : SetupColors.border, width: 1.5)),
                    child: selected.contains(d) ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 8),
                  Text(shortDay[d]!, style: setupText(size: 14, weight: FontWeight.w600, color: selected.contains(d) ? SetupColors.primary : SetupColors.text)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _standardCard() {
    final total = formatHours(_standard.is24Hours ? 1440 : dailyMinutes(DayPlan(dayOfWeek: 1, isOpen: true, open: _standard.open, close: _standard.close), _activeBreak));
    final timeError = _problems.byDay.values.isEmpty ? null : _problems.byDay.values.first;
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.event_available_outlined, title: 'Set Operating Days & Hours'),
          const SetupLabel('Operating Days', required: true),
          _dayChips(_standard.days, (d) => _standard.days = d, 'std-day'),
          if (_problems.general != null) _errorText(_problems.general!),
          const SizedBox(height: 16),
          const SetupLabel('Working Hours', required: true),
          if (_standard.is24Hours)
            Container(
              height: 48,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: SetupColors.activeBg, borderRadius: BorderRadius.circular(10)),
              child: Text('Open all day, $total', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.primary)),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _labelled('Opens At', _timeBox(id: 'std-open', label: 'Opens at', value: _standard.open, onChanged: (v) => _standard.open = v, invalid: timeError != null))),
                const SizedBox(width: 12),
                Expanded(child: _labelled('Closes At', _timeBox(id: 'std-close', label: 'Closes at', value: _standard.close, onChanged: (v) => _standard.close = v, invalid: timeError != null))),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('daily-total'),
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFEDE7FF), borderRadius: BorderRadius.circular(10)),
              child: Text('Total Hours: $total', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.primary)),
            ),
          ],
          if (timeError != null) _errorText(timeError),
          const SizedBox(height: 8),
          InkWell(
            key: const ValueKey('std-24h'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() {
              _standard.is24Hours = !_standard.is24Hours;
              _clearProblems();
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 22, width: 22, child: Checkbox(value: _standard.is24Hours, onChanged: (v) => setState(() => _standard.is24Hours = v ?? false), activeColor: SetupColors.primary, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
                  const SizedBox(width: 10),
                  Text('Open 24 hours', style: setupText(size: 14, weight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(bool open) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: open ? const Color(0xFFE8F5E9) : const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(99)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 6, width: 6, decoration: BoxDecoration(color: open ? SetupColors.success : SetupColors.error, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(open ? 'Open' : 'Closed', style: setupText(size: 12, weight: FontWeight.w600, color: open ? SetupColors.success : SetupColors.error)),
          ],
        ),
      );

  Widget _previewCard() {
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.calendar_month_outlined, title: 'Weekly Schedule Preview', description: 'Here’s how your facility will be available for bookings.'),
          for (final p in orderedPlans(_plans))
            Container(
              key: ValueKey('preview-${p.dayOfWeek}'),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEFECF6)))),
              child: Row(
                children: [
                  SizedBox(width: 48, child: Text(shortDay[p.dayOfWeek]!, style: setupText(size: 14, weight: FontWeight.w600))),
                  Expanded(child: Text(p.isOpen ? describePlan(p) : '—', style: setupText(size: 14, color: p.isOpen ? SetupColors.text : SetupColors.secondary))),
                  _statusPill(p.isOpen),
                ],
              ),
            ),
          if (_activeBreak != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Daily break: ${formatClock(_activeBreak!.start)} – ${formatClock(_activeBreak!.end)} (not bookable).', style: setupText(size: 12, color: SetupColors.secondary))),
        ],
      ),
    );
  }

  Widget _customCard() {
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.event_available_outlined, title: 'Set Custom Operating Hours', description: 'Configure opening and closing time for each day based on your facility’s availability.'),
          if (_problems.general != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: SetupErrorBanner(_problems.general!)),
          for (final p in orderedPlans(_custom))
            Container(
              key: ValueKey('custom-${p.dayOfWeek}'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: SetupColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        key: ValueKey('custom-open-${p.dayOfWeek}'),
                        onTap: () => setState(() {
                          p.isOpen = !p.isOpen;
                          if (!p.isOpen) p.is24Hours = false;
                          _clearProblems();
                        }),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Container(
                              height: 22,
                              width: 22,
                              decoration: BoxDecoration(color: p.isOpen ? SetupColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.isOpen ? SetupColors.primary : SetupColors.border, width: 1.6)),
                              child: p.isOpen ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
                            ),
                            const SizedBox(width: 10),
                            Text(dayLabels[p.dayOfWeek], style: setupText(size: 15, weight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _statusPill(p.isOpen),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (p.is24Hours)
                    Text('Open 24 hours', style: setupText(size: 14, weight: FontWeight.w500, color: SetupColors.primary))
                  else
                    Row(
                      children: [
                        Expanded(child: _timeBox(id: 'day-${p.dayOfWeek}-open', label: '${dayLabels[p.dayOfWeek]} opens at', value: p.isOpen ? p.open : '', onChanged: (v) => p.open = v, enabled: p.isOpen, invalid: _problems.byDay.containsKey(p.dayOfWeek))),
                        const SizedBox(width: 10),
                        Expanded(child: _timeBox(id: 'day-${p.dayOfWeek}-close', label: '${dayLabels[p.dayOfWeek]} closes at', value: p.isOpen ? p.close : '', onChanged: (v) => p.close = v, enabled: p.isOpen, invalid: _problems.byDay.containsKey(p.dayOfWeek))),
                      ],
                    ),
                  if (_problems.byDay[p.dayOfWeek] != null) _errorText(_problems.byDay[p.dayOfWeek]!),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: SetupColors.activeBg, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.access_time, size: 20, color: SetupColors.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('Weekly Total Operating Hours', style: setupText(size: 14, weight: FontWeight.w600))),
                Text(formatHours(weeklyMinutes(_custom, _activeBreak)), key: const ValueKey('weekly-total'), style: setupText(size: 15, weight: FontWeight.w700, color: SetupColors.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── holidays ────────────────────────────────────────────────────────

  Future<void> _editClosure(ClosureEntry? existing) async {
    final result = await showDialog<ClosureEntry>(
      context: context,
      builder: (_) => _ClosureDialog(existing: existing, others: _closures),
    );
    if (result == null) return;
    setState(() {
      if (existing == null) {
        _closures = [..._closures, result];
      } else {
        _closures = [for (final c in _closures) identical(c, existing) ? result : c];
      }
    });
  }

  Widget _closuresCard() {
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.event_busy_outlined, title: 'Holiday / Special Closure', description: 'Mark dates when the facility will be closed (e.g., maintenance, events, public holidays).'),
          for (final c in sortClosures(_closures))
            Container(
              key: ValueKey('closure-${c.date}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(color: const Color(0xFFFBFAFE), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFEFECF6))),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 18, color: SetupColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatClosureDate(c.date), style: setupText(size: 14, weight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFEDE7FF), borderRadius: BorderRadius.circular(6)),
                          child: Text(c.name, style: setupText(size: 12, weight: FontWeight.w600, color: SetupColors.primary)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Edit ${c.name}', onPressed: () => _editClosure(c), icon: const Icon(Icons.edit_outlined, size: 18)),
                  IconButton(tooltip: 'Remove ${c.name}', onPressed: () => setState(() => _closures = _closures.where((x) => !identical(x, c)).toList()), icon: const Icon(Icons.delete_outline, size: 18, color: SetupColors.error)),
                ],
              ),
            ),
          const SizedBox(height: 4),
          GestureDetector(
            key: const ValueKey('add-closure'),
            onTap: () => _editClosure(null),
            child: Container(
              height: 48,
              decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: SetupColors.primary.withValues(alpha: 0.55))),
              // scales down on a narrow phone instead of overflowing
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 18, color: SetupColors.primary),
                    const SizedBox(width: 6),
                    Text('Add Holiday / Closure', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.primary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── additional settings ─────────────────────────────────────────────

  Widget _toggleRow({required Key switchKey, required String title, required String hint, required String description, required bool value, required ValueChanged<bool> onChanged, Widget? child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Switch(
                key: switchKey,
                value: value,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: SetupColors.primary,
                inactiveTrackColor: const Color(0xFFC9C5D6),
                inactiveThumbColor: Colors.white,
                trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(title, style: setupText(size: 15, weight: FontWeight.w600, height: 1.25))),
                          const SizedBox(width: 6),
                          Tooltip(message: hint, triggerMode: TooltipTriggerMode.tap, child: const Icon(Icons.info_outline, size: 17, color: SetupColors.secondary)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(description, style: setupText(size: 12.5, color: SetupColors.secondary, height: 1.35)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (child != null) Padding(padding: const EdgeInsets.only(top: 10, left: 8), child: child),
        ],
      ),
    );
  }

  Widget _settingsCard() {
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.tune, title: 'Additional Settings'),
          _toggleRow(
            switchKey: const ValueKey('switch-outside'),
            title: 'Allow bookings outside operating hours',
            hint: 'Your team can create a booking at any time, even when you are closed or on a holiday. Players on the booking page still follow your hours.',
            description: 'Let admins create special bookings even outside working hours.',
            value: _allowOutside,
            onChanged: (v) => setState(() => _allowOutside = v),
          ),
          const Divider(height: 1, color: Color(0xFFEFECF6)),
          _toggleRow(
            switchKey: const ValueKey('switch-break'),
            title: 'Set a break time',
            hint: 'Courts cannot be booked during this time on any open day.',
            description: 'Block a fixed time (e.g., maintenance, cleaning) within working hours.',
            value: _breakOn,
            onChanged: (v) => setState(() {
              _breakOn = v;
              _clearProblems();
            }),
            child: !_breakOn
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _labelled('Break starts', _timeBox(id: 'break-start', label: 'Break starts at', value: _break.start, onChanged: (v) => _break = BreakTime(v, _break.end), invalid: _problems.breakTime != null))),
                          const SizedBox(width: 10),
                          Expanded(child: _labelled('Break ends', _timeBox(id: 'break-end', label: 'Break ends at', value: _break.end, onChanged: (v) => _break = BreakTime(_break.start, v), invalid: _problems.breakTime != null))),
                        ],
                      ),
                      if (_problems.breakTime != null) _errorText(_problems.breakTime!),
                    ],
                  ),
          ),
          const Divider(height: 1, color: Color(0xFFEFECF6)),
          _toggleRow(
            switchKey: const ValueKey('switch-sportwise'),
            title: 'Apply sport-wise operating hours',
            hint: 'Give each sport its own days and times. Each of its courts then follows them instead of the venue’s hours.',
            description: 'Set different timings for each sport (e.g., Badminton: 6 AM – 10 PM).',
            value: _sportWise,
            onChanged: _toggleSportWise,
          ),
        ],
      ),
    );
  }

  Widget _sportHoursCard() {
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.emoji_events_outlined, title: 'Sport-wise Operating Hours', description: 'Each sport’s courts follow these days and times instead of the venue’s hours.'),
          for (final e in _sportEntries) _sportSection(e),
        ],
      ),
    );
  }

  Widget _sportSection(_SportEntry e) {
    final list = _sportPlans[e.id] ?? const <DayPlan>[];
    final openDays = [for (final p in list) if (p.isOpen) p.dayOfWeek];
    final first = list.where((p) => p.isOpen).firstOrNull ?? (list.isEmpty ? null : list.first);
    final open = first?.open ?? '06:00';
    final close = first?.close ?? '23:00';
    final is24 = first?.is24Hours ?? false;
    void apply(List<int> days, String o, String c, {bool? all}) {
      _sportPlans[e.id] = [for (final p in list) DayPlan(dayOfWeek: p.dayOfWeek, isOpen: days.contains(p.dayOfWeek), open: o, close: c, is24Hours: all ?? is24)];
    }

    void toggle24() => setState(() {
          apply(openDays, open, close, all: !is24);
          _sportErrors = {};
          _error = null;
        });

    return Container(
      key: ValueKey('sport-hours-${e.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: SetupColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(e.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(child: Text(e.name, style: setupText(size: 15, weight: FontWeight.w600))),
              Text('${e.courts} ${e.courts == 1 ? 'court' : 'courts'}', style: setupText(size: 12, color: SetupColors.secondary)),
            ],
          ),
          const SizedBox(height: 10),
          _dayChips(openDays, (days) => apply(days, open, close), 'sport-${e.id}-day'),
          const SizedBox(height: 10),
          if (is24)
            Text('Open all day, 24 Hours', key: ValueKey('sport-${e.id}-24h-note'), style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.primary))
          else
          Row(
            children: [
              Expanded(child: _labelled('Opens At', _timeBox(id: 'sport-${e.id}-open', label: '${e.name} opens at', value: open, onChanged: (v) => apply(openDays, v, close), invalid: _sportErrors.containsKey(e.id)))),
              const SizedBox(width: 10),
              Expanded(child: _labelled('Closes At', _timeBox(id: 'sport-${e.id}-close', label: '${e.name} closes at', value: close, onChanged: (v) => apply(openDays, open, v), invalid: _sportErrors.containsKey(e.id)))),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            key: ValueKey('sport-${e.id}-24h'),
            onTap: toggle24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 22, width: 22, child: Checkbox(value: is24, onChanged: (_) => toggle24(), activeColor: SetupColors.primary, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
                const SizedBox(width: 10),
                Text('Open 24 hours', style: setupText(size: 14, weight: FontWeight.w500)),
              ],
            ),
          ),
          if (_sportErrors[e.id] != null) _errorText(_sportErrors[e.id]!),
        ],
      ),
    );
  }

  // ── build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return SetupPage(
        footer: SetupButton(label: 'Try again', primary: true, onPressed: _load),
        children: [const SetupStepper(current: 3), const SizedBox(height: 18), SetupErrorBanner(_loadError!)],
      );
    }
    if (_loading) return const SetupLoadingPage(cards: [2, 3, 2]);

    return SetupPage(
      footer: SetupNavFooter(
        onBack: () => goBackOr(context, AppRoutes.onboardingSportsCourts),
        next: SetupButton(label: 'Next', primary: true, trailingIcon: Icons.arrow_forward, loading: _savingNext, loadingLabel: 'Saving…', onPressed: () => _persist(advance: true)),
      ),
      children: [
        const SetupStepper(current: 3),
        const SizedBox(height: 18),
        Text('Operating Hours', style: setupText(size: 28, weight: FontWeight.w700, height: 1.1)),
        const SizedBox(height: 6),
        Text('Set your facility’s working days, opening & closing time, and special closures.', style: setupText(size: 14, color: SetupColors.secondary, height: 1.4)),
        const SizedBox(height: 18),
        if (_error != null) SetupErrorBanner(_error!),
        // with sport-wise hours on, each sport sets its own hours below, so the venue-wide ones are not shown
        if (!_sportWise) ...[
          _modeCards(),
          const SizedBox(height: 16),
          if (_mode == HoursMode.standard) ...[
            _standardCard(),
            const SizedBox(height: 16),
            _previewCard(),
          ] else
            _customCard(),
          const SizedBox(height: 16),
        ],
        _closuresCard(),
        const SizedBox(height: 16),
        _settingsCard(),
        if (_sportWise) ...[
          const SizedBox(height: 16),
          _sportHoursCard(),
        ],
      ],
    );
  }
}

/// Add / edit a holiday: a name and a date chosen in the Material calendar.
class _ClosureDialog extends StatefulWidget {
  const _ClosureDialog({required this.existing, required this.others});

  final ClosureEntry? existing;
  final List<ClosureEntry> others;

  @override
  State<_ClosureDialog> createState() => _ClosureDialogState();
}

class _ClosureDialogState extends State<_ClosureDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _date = widget.existing?.date ?? '';
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final existing = _date.isEmpty ? null : DateTime.tryParse(_date);
    final first = existing != null && existing.isBefore(today) ? existing : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing ?? today,
      firstDate: first,
      lastDate: DateTime(today.year + 5, 12, 31),
      helpText: 'Select date',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: SetupColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _date = isoDate(picked);
        _problem = null;
      });
    }
  }

  void _submit() {
    final now = DateTime.now();
    final next = ClosureEntry(id: widget.existing?.id, date: _date, name: _name.text.trim());
    final why = closureProblem(next, widget.others, isoDate(DateTime(now.year, now.month, now.day)), editing: widget.existing);
    if (why != null) {
      setState(() => _problem = why);
      return;
    }
    Navigator.pop(context, next);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SetupColors.background,
      title: Text(widget.existing == null ? 'Add Holiday / Closure' : 'Edit Holiday / Closure', style: setupText(size: 18, weight: FontWeight.w600)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SetupLabel('Name', required: true),
            TextField(
              key: const ValueKey('closure-name'),
              controller: _name,
              maxLength: 60,
              style: setupText(size: 15),
              onChanged: (_) => setState(() => _problem = null),
              decoration: setupDecoration(hint: 'e.g. Independence Day', counterText: ''),
            ),
            const SizedBox(height: 14),
            const SetupLabel('Date', required: true),
            InkWell(
              key: const ValueKey('closure-date'),
              borderRadius: BorderRadius.circular(10),
              onTap: _pickDate,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: SetupColors.border)),
                child: Row(
                  children: [
                    Expanded(child: Text(_date.isEmpty ? 'Select date' : formatClosureDate(_date), style: setupText(size: 15, color: _date.isEmpty ? SetupColors.placeholder : SetupColors.text))),
                    const Icon(Icons.calendar_today_outlined, size: 18, color: SetupColors.primary),
                  ],
                ),
              ),
            ),
            if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, key: const ValueKey('closure-error'), style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.secondary))),
        FilledButton(
          key: const ValueKey('closure-save'),
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: SetupColors.primary),
          child: Text(widget.existing == null ? 'Add' : 'Save', style: setupText(size: 14, weight: FontWeight.w600, color: Colors.white)),
        ),
      ],
    );
  }
}
