import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../data/models/facility.dart';
import '../../data/models/operating_hours.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/pricing.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../authentication/session_controller.dart';
import 'hours_setup_logic.dart' show formatClock, shortDay, timeOptions;
import 'pricing_setup_logic.dart';
import 'setup_ui.dart';

const String _customSportIcon = '🏅';

class _SportEntry {
  const _SportEntry(this.id, this.name, this.icon);
  final String id; // facility_sports.id
  final String name;
  final String icon;
}

class _CourtEntry {
  const _CourtEntry({required this.id, required this.name, required this.sportId, required this.indoor, this.surface, required this.ac});
  final String id;
  final String name;
  final String sportId;
  final bool indoor;
  final String? surface;
  final bool ac;
}

/// Step 4 of the setup: Pricing. By Sport (one set of prices per sport, applied to all its courts) or By Court (each court on its
/// own); a base price, optional time slots for weekdays / weekends / chosen days, and optional member and coaching rates.
/// Everything is saved together on Next (or Save as Draft). With [editMode] it is the profile editor: one Save, no step navigation.
class PricingSetupScreen extends ConsumerStatefulWidget {
  const PricingSetupScreen({super.key, this.editMode = false});

  final bool editMode;

  @override
  ConsumerState<PricingSetupScreen> createState() => _PricingSetupScreenState();
}

class _PricingSetupScreenState extends ConsumerState<PricingSetupScreen> {
  bool _loading = true;
  String? _loadError;
  String? _facilityId;
  List<Sport> _sports = [];
  List<FacilitySport> _facilitySports = [];
  List<PlayingArea> _areas = [];
  List<OperatingDay>? _operatingDays;

  PricingSettings _settings = const PricingSettings();
  final Map<String, PriceSetup> _sportSetups = {};
  final Map<String, PriceSetup> _courtSetups = {};
  String? _expandedSport;
  String? _selectedCourt;
  String _filter = 'ALL';
  final Map<String, SlotGroup> _tab = {};

  Map<String, SetupProblems> _problems = {};
  String? _error;
  bool _savingNext = false;
  bool _savingDraft = false;

  Span get _span => openSpan(_operatingDays);

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _priced(PriceSetup? s) => s != null && (double.tryParse(s.basePrice) ?? 0) > 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        if (mounted) context.go(AppRoutes.onboardingFacility);
        return;
      }
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final catalogue = await sportsRepo.getActiveSports();
      final facSports = await sportsRepo.getFacilitySports(facility.id);
      final courts = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id);
      if (facSports.isEmpty || courts.isEmpty) {
        if (mounted) context.go(AppRoutes.onboardingSportsCourts);
        return;
      }
      final schedule = await ref.read(operatingHoursRepositoryProvider).getFacilitySchedule(facility.id);
      final plan = await ref.read(pricingRepositoryProvider).getPricingPlan(facility.id);
      if (!mounted) return;

      final rules = plan?.rules ?? const <PricingRule>[];
      final span = openSpan(schedule?.days);
      final sportMap = <String, PriceSetup>{
        for (final fs in facSports) fs.id: setupFromRules(rules.where((r) => r.facilitySportId == fs.id && r.playingAreaId == null).toList(), span),
      };
      final courtMap = <String, PriceSetup>{};
      for (final c in courts) {
        final own = rules.where((r) => r.playingAreaId == c.id).toList();
        // a court with no rate of its own starts from its sport's, so switching to By Court is one tap
        courtMap[c.id] = own.isNotEmpty ? setupFromRules(own, span) : (sportMap[c.facilitySportId] ?? PriceSetup()).clone();
      }

      setState(() {
        _facilityId = facility.id;
        _sports = catalogue;
        _facilitySports = facSports;
        _areas = courts;
        _operatingDays = schedule?.days;
        _settings = PricingSettings(
          mode: PricingMode.fromDb(facility.pricingMode),
          differentWeekendPricing: rules.isEmpty ? facility.differentWeekendPricing : (facility.differentWeekendPricing || usesDayGroups(rules)),
          memberPricingEnabled: facility.memberPricingEnabled,
          coachingPricingEnabled: facility.coachingPricingEnabled,
        );
        _sportSetups
          ..clear()
          ..addAll(sportMap);
        _courtSetups
          ..clear()
          ..addAll(courtMap);
        _expandedSport = facSports.where((fs) => !_priced(sportMap[fs.id])).firstOrNull?.id ?? facSports.first.id;
        _selectedCourt = courts.first.id;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      debugPrint('Pricing load failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'We couldn’t load your pricing. Please try again.';
      });
    }
  }

  List<_SportEntry> get _sportEntries => [
        for (final fs in _facilitySports)
          () {
            final sport = _sports.where((s) => s.id == fs.sportId).firstOrNull;
            final custom = sport?.code == otherSportCode;
            return _SportEntry(fs.id, custom ? (fs.customSportName ?? 'Sport') : (sport?.name ?? 'Sport'), custom ? _customSportIcon : (sport?.icon ?? _customSportIcon));
          }(),
      ];

  List<_CourtEntry> get _courtEntries => [
        for (final a in _areas) _CourtEntry(id: a.id, name: a.name, sportId: a.facilitySportId, indoor: a.areaType == 'INDOOR', surface: a.surface, ac: a.courtAmenities.contains('ac')),
      ];

  // ── editing ─────────────────────────────────────────────────────────

  void _edit(String id, VoidCallback change) {
    setState(() {
      change();
      _problems.remove(id);
      _error = null;
    });
  }

  void _setMode(PricingMode mode) {
    if (mode == _settings.mode) return;
    setState(() {
      if (mode == PricingMode.byCourt) {
        // a court with nothing entered yet starts from its sport's price as it is now
        for (final c in _areas) {
          final own = _courtSetups[c.id];
          final sportSetup = _sportSetups[c.facilitySportId];
          if (_priced(sportSetup) && (own == null || (own.basePrice.trim().isEmpty && !own.timeBased))) _courtSetups[c.id] = sportSetup!.clone();
        }
      }
      _settings = _settings.copyWith(mode: mode);
      _problems = {};
      _error = null;
    });
  }

  void _addSportPricing() {
    final next = _facilitySports.where((fs) => !_priced(_sportSetups[fs.id])).firstOrNull;
    if (next != null) setState(() => _expandedSport = next.id);
  }

  // ── save ────────────────────────────────────────────────────────────

  List<({String id, PriceSetup setup, RuleScope scope})> get _scopes => _settings.mode == PricingMode.bySport
      ? [for (final fs in _facilitySports) (id: fs.id, setup: _sportSetups[fs.id] ?? PriceSetup(), scope: RuleScope(fs.id))]
      : [for (final a in _areas) (id: a.id, setup: _courtSetups[a.id] ?? PriceSetup(), scope: RuleScope(a.facilitySportId, a.id))];

  Future<void> _persist({required bool advance}) async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    setState(() => _error = null);

    final found = <String, SetupProblems>{};
    for (final s in _scopes) {
      final p = validateSetup(s.setup, s.scope, _settings, _operatingDays);
      if (p.any) found[s.id] = p;
    }
    setState(() => _problems = found);
    if (found.isNotEmpty) {
      final firstBad = found.keys.first;
      final name = _settings.mode == PricingMode.bySport ? _sportEntries.where((s) => s.id == firstBad).firstOrNull?.name : _areas.where((a) => a.id == firstBad).firstOrNull?.name;
      setState(() {
        if (_settings.mode == PricingMode.bySport) {
          _expandedSport = firstBad;
        } else {
          _selectedCourt = firstBad;
        }
        _error = 'Please fix the highlighted fields to continue${name == null ? '' : ' ($name)'}.';
      });
      return;
    }

    setState(() => advance ? _savingNext = true : _savingDraft = true);
    try {
      final rules = [for (final s in _scopes) ...rulesFromSetup(s.setup, s.scope, _settings)];
      await ref.read(pricingRepositoryProvider).savePricingRules(facilityId, rules);
      final facilityRepo = ref.read(facilityRepositoryProvider);
      await facilityRepo.updatePricingSettings(
        facilityId,
        mode: _settings.mode.db,
        differentWeekendPricing: _settings.differentWeekendPricing,
        memberPricingEnabled: _settings.memberPricingEnabled,
        coachingPricingEnabled: _settings.coachingPricingEnabled,
      );
      if (advance && widget.editMode) {
        if (!mounted) return;
        context.pop(true);
        return;
      }
      if (advance) {
        await facilityRepo.updateOnboardingStep(facilityId, OnboardingStep.payments);
        await ref.read(sessionControllerProvider.notifier).refresh();
        if (!mounted) return;
        context.push(AppRoutes.onboardingPayments);
      } else if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Draft saved. You can pick up where you left off.')));
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e, stack) {
      debugPrint('Pricing save failed: $e\n$stack');
      if (!mounted) return;
      setState(() => _error = 'We couldn’t save your pricing. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _savingNext = false;
          _savingDraft = false;
        });
      }
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

  Widget _timeBox({required String id, required String label, required String value, required ValueChanged<String> onChanged, bool invalid = false}) {
    return Semantics(
      button: true,
      label: '$label ${value.isEmpty ? '' : formatClock(value)}',
      child: InkWell(
        key: ValueKey('time-$id'),
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final picked = await _pickTime(label, value);
          if (picked != null) onChanged(picked);
        },
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: SetupColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: invalid ? SetupColors.error : SetupColors.border)),
          child: Row(
            children: [
              const Icon(Icons.access_time, size: 17, color: SetupColors.secondary),
              const SizedBox(width: 6),
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value.isEmpty ? '–' : formatClock(value), style: setupText(size: 15)))),
              const Icon(Icons.keyboard_arrow_down, size: 20, color: SetupColors.text),
            ],
          ),
        ),
      ),
    );
  }

  // ── pieces ──────────────────────────────────────────────────────────

  Widget _errorText(String message) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(message, style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error)));

  Widget _modeCards() {
    Widget card(PricingMode mode, String title, String hint, IconData icon) {
      final on = _settings.mode == mode;
      return GestureDetector(
        key: ValueKey('mode-${mode.name}'),
        onTap: () => _setMode(mode),
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
        card(PricingMode.bySport, 'By Sport', 'Set prices for each sport (applies to all its courts)', Icons.layers_outlined),
        const SizedBox(height: 10),
        card(PricingMode.byCourt, 'By Court', 'Set prices for individual courts', Icons.grid_view_outlined),
      ],
    );
  }

  Widget _chip(String text, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFEDE7FF), borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 12, color: SetupColors.primary), const SizedBox(width: 4)],
            Text(text, style: setupText(size: 11.5, weight: FontWeight.w600, color: SetupColors.primary)),
          ],
        ),
      );

  /// The editor for one sport's or court's prices.
  Widget _editor(String id, PriceSetup s, SetupProblems p) {
    final per = s.unit == PriceUnit.perHour ? 'hour' : 'session';
    final groups = groupsFor(_settings);
    final group = groups.contains(_tab[id]) ? _tab[id]! : groups.first;
    final slots = s.slotsOf(group);

    void retag() {
      for (final g in SlotGroup.values) {
        for (final slot in s.slotsOf(g)) {
          if (!slot.tierTouched) slot.tier = autoTier(slot.price, s.basePrice);
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupSegmented<PriceUnit>(
          label: 'Pricing Type',
          keyPrefix: 'unit-$id',
          value: s.unit,
          options: const [(value: PriceUnit.perHour, label: 'Hourly'), (value: PriceUnit.perSession, label: 'Per Session')],
          onChanged: (v) => _edit(id, () => s.unit = v),
        ),
        const SizedBox(height: 14),
        _AmountField(
          key: ValueKey('base-$id'),
          label: 'Base Price (per $per)',
          required: true,
          value: s.basePrice,
          error: p.base,
          onChanged: (v) => _edit(id, () {
            s.basePrice = v;
            retag();
          }),
        ),
        const SizedBox(height: 6),
        SetupCheckRow(
          key: ValueKey('timebased-$id'),
          label: 'Enable Time-based Pricing',
          hint: 'Charge different rates at different times of day.',
          value: s.timeBased,
          onChanged: (v) => _edit(id, () {
            s.timeBased = v;
            if (v && s.slotsOf(groups.first).isEmpty) {
              s.setSlots(groups.first, [nextSlot(const [], _span)]);
            }
          }),
        ),
        if (s.timeBased) ...[
          const SizedBox(height: 10),
          if (groups.length > 1) _tabs(id, groups, group, s),
          if (group == SlotGroup.specific) ...[
            const SizedBox(height: 10),
            _specificDays(id, s),
          ],
          const SizedBox(height: 10),
          for (final slot in slots) _slotRow(id, s, group, slot, p),
          if (p.groups[group] != null) _errorText(p.groups[group]!),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: ValueKey('add-slot-$id'),
            onPressed: () => _edit(id, () {
              final slot = nextSlot(slots, _span);
              s.setSlots(group, [...slots, slot]);
            }),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Time Slot'),
            style: OutlinedButton.styleFrom(foregroundColor: SetupColors.primary, side: BorderSide(color: SetupColors.primary.withValues(alpha: 0.5)), minimumSize: const Size.fromHeight(44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
        ],
        if (_settings.memberPricingEnabled) ...[
          const SizedBox(height: 14),
          _AmountField(key: ValueKey('member-$id'), label: 'Member Price (per $per)', required: true, value: s.memberPrice, error: p.member, onChanged: (v) => _edit(id, () => s.memberPrice = v)),
        ],
        if (_settings.coachingPricingEnabled) ...[
          const SizedBox(height: 14),
          _AmountField(key: ValueKey('coaching-$id'), label: 'Coaching Price (per $per)', required: true, value: s.coachingPrice, error: p.coaching, onChanged: (v) => _edit(id, () => s.coachingPrice = v)),
        ],
      ],
    );
  }

  Widget _tabs(String id, List<SlotGroup> groups, SlotGroup current, PriceSetup s) {
    const names = {SlotGroup.weekdays: ('Weekdays', 'Mon – Fri'), SlotGroup.weekends: ('Weekends', 'Sat – Sun'), SlotGroup.specific: ('Specific Days', 'Choose days')};
    return Row(
      children: [
        for (final g in groups) ...[
          Expanded(
            child: GestureDetector(
              key: ValueKey('tab-$id-${g.name}'),
              onTap: () => setState(() => _tab[id] = g),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(color: g == current ? SetupColors.activeBg : SetupColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: g == current ? SetupColors.primary : SetupColors.border)),
                child: Column(
                  children: [
                    FittedBox(fit: BoxFit.scaleDown, child: Text(names[g]!.$1, style: setupText(size: 13, weight: FontWeight.w600, color: g == current ? SetupColors.primary : SetupColors.text))),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(names[g]!.$2, style: setupText(size: 11, color: SetupColors.secondary))),
                  ],
                ),
              ),
            ),
          ),
          if (g != groups.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _specificDays(String id, PriceSetup s) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in displayOrder)
          GestureDetector(
            key: ValueKey('day-$id-$d'),
            onTap: () => _edit(id, () => s.specificDays = s.specificDays.contains(d) ? (List.of(s.specificDays)..remove(d)) : [...s.specificDays, d]),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: s.specificDays.contains(d) ? SetupColors.activeBg : SetupColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: s.specificDays.contains(d) ? SetupColors.primary.withValues(alpha: 0.5) : SetupColors.border),
              ),
              child: Text(shortDay[d]!, style: setupText(size: 14, weight: FontWeight.w600, color: s.specificDays.contains(d) ? SetupColors.primary : SetupColors.text)),
            ),
          ),
      ],
    );
  }

  Widget _slotRow(String id, PriceSetup s, SlotGroup group, Slot slot, SetupProblems p) {
    final problem = p.slots[slot.id];
    return Container(
      key: ValueKey('slot-${slot.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFFBFAFE), borderRadius: BorderRadius.circular(12), border: Border.all(color: problem != null ? SetupColors.error : const Color(0xFFEFECF6))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Time slot', style: setupText(size: 13, weight: FontWeight.w600, color: SetupColors.secondary))),
              InkResponse(
                key: ValueKey('remove-slot-${slot.id}'),
                onTap: () => _edit(id, () => s.setSlots(group, [for (final x in s.slotsOf(group)) if (x.id != slot.id) x])),
                radius: 20,
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 20, color: SetupColors.secondary, semanticLabel: 'Remove time slot')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _timeBox(id: '${slot.id}-start', label: 'Slot start', value: slot.start, invalid: problem != null, onChanged: (v) => _edit(id, () => slot.start = v))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('–', style: setupText(size: 15))),
              Expanded(child: _timeBox(id: '${slot.id}-end', label: 'Slot end', value: slot.end, invalid: problem != null, onChanged: (v) => _edit(id, () => slot.end = v))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _AmountField(
                  key: ValueKey('slot-price-${slot.id}'),
                  label: 'Price',
                  value: slot.price,
                  invalid: problem != null,
                  onChanged: (v) => _edit(id, () {
                    slot.price = v;
                    if (!slot.tierTouched) slot.tier = autoTier(v, s.basePrice);
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: SetupDropdown<String>(
                  key: ValueKey('slot-tier-${slot.id}-${slot.tier}'),
                  label: 'Tag',
                  value: slot.tier,
                  items: const [DropdownMenuItem(value: '', child: Text('None')), DropdownMenuItem(value: 'PEAK', child: Text('Peak')), DropdownMenuItem(value: 'OFF_PEAK', child: Text('Off-Peak'))],
                  onChanged: (v) => _edit(id, () {
                    slot.tier = v ?? '';
                    slot.tierTouched = true;
                  }),
                ),
              ),
            ],
          ),
          if (problem != null) _errorText(problem),
        ],
      ),
    );
  }

  Widget _sportPricingCard() {
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.layers_outlined, title: 'Sport Pricing', description: 'Add and manage booking rates for each sport.'),
          OutlinedButton.icon(
            key: const ValueKey('add-sport-pricing'),
            onPressed: _facilitySports.any((fs) => !_priced(_sportSetups[fs.id])) ? _addSportPricing : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Sport Pricing'),
            style: OutlinedButton.styleFrom(foregroundColor: SetupColors.primary, side: BorderSide(color: SetupColors.primary.withValues(alpha: 0.5)), minimumSize: const Size.fromHeight(44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
          const SizedBox(height: 12),
          for (final sport in _sportEntries) _sportTile(sport),
        ],
      ),
    );
  }

  Widget _sportTile(_SportEntry sport) {
    final setup = _sportSetups[sport.id] ?? PriceSetup();
    final open = _expandedSport == sport.id;
    final p = _problems[sport.id];
    return Container(
      key: ValueKey('sport-tile-${sport.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p?.base != null ? SetupColors.error : (open ? SetupColors.border : const Color(0xFFEFECF6)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey('sport-toggle-${sport.id}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expandedSport = open ? null : sport.id),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: open ? SetupColors.activeBg : const Color(0xFFFBFAFE), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Text(sport.icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sport.name, style: setupText(size: 15, weight: FontWeight.w600)),
                        if (!open) Text(priceRangeLabel(setup, _settings), style: setupText(size: 12.5, color: SetupColors.secondary)),
                      ],
                    ),
                  ),
                  Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: SetupColors.text),
                ],
              ),
            ),
          ),
          if (open) Padding(padding: const EdgeInsets.all(12), child: _editor('sport-${sport.id}', setup, p ?? SetupProblems())),
        ],
      ),
    );
  }

  Widget _courtListCard() {
    final sports = _sportEntries.where((s) => _filter == 'ALL' || s.id == _filter).toList();
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.grid_view_outlined, title: 'Select Court'),
          SetupDropdown<String>(
            key: ValueKey('filter-$_filter'),
            label: 'Sport',
            value: _filter,
            items: [const DropdownMenuItem(value: 'ALL', child: Text('All Sports')), for (final s in _sportEntries) DropdownMenuItem(value: s.id, child: Text(s.name))],
            onChanged: (v) => setState(() => _filter = v ?? 'ALL'),
          ),
          const SizedBox(height: 12),
          for (final sport in sports) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: SetupColors.activeBg, borderRadius: BorderRadius.circular(8)),
              child: Text('${sport.icon}  ${sport.name} (${_courtEntries.where((c) => c.sportId == sport.id).length})', style: setupText(size: 14, weight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            for (final c in _courtEntries.where((c) => c.sportId == sport.id)) _courtRow(c),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _courtRow(_CourtEntry c) {
    final on = c.id == _selectedCourt;
    final done = _priced(_courtSetups[c.id]);
    return GestureDetector(
      key: ValueKey('court-${c.id}'),
      onTap: () => setState(() => _selectedCourt = c.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: on ? const Color(0xFFF8F4FF) : SetupColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? SetupColors.primary : const Color(0xFFEFECF6))),
        child: Row(
          children: [
            Container(
              height: 20,
              width: 20,
              decoration: BoxDecoration(shape: BoxShape.circle, color: done ? const Color(0xFF2E7D32) : SetupColors.background, border: Border.all(color: done ? const Color(0xFF2E7D32) : const Color(0xFFD6D2E3))),
              child: done ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: setupText(size: 14.5, weight: FontWeight.w500))),
            _chip(c.ac ? 'AC' : 'Non-AC', icon: Icons.ac_unit),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 20, color: SetupColors.text),
          ],
        ),
      ),
    );
  }

  Widget _courtPanel() {
    final court = _courtEntries.where((c) => c.id == _selectedCourt).firstOrNull;
    final setup = court == null ? null : _courtSetups[court.id];
    if (court == null || setup == null) {
      return SetupCard(child: Text('Choose a court to set its price.', style: setupText(size: 14, color: SetupColors.secondary)));
    }
    final sport = _sportEntries.where((s) => s.id == court.sportId).firstOrNull;
    return SetupCard(
      key: ValueKey('court-panel-${court.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sport?.icon ?? _customSportIcon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${court.name} – ${sport?.name ?? ''}', style: setupText(size: 17, weight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _chip(court.indoor ? 'Indoor' : 'Outdoor', icon: Icons.home_outlined),
                      if (court.surface != null && court.surface!.isNotEmpty) _chip(court.surface!, icon: Icons.grass),
                      if (court.ac) _chip('AC', icon: Icons.ac_unit),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFEFECF6)),
          _editor('court-${court.id}', setup, _problems[court.id] ?? SetupProblems()),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF7F5FB), borderRadius: BorderRadius.circular(10)),
            child: Text('This pricing applies only to ${court.name}. Set prices for other courts from the list.', style: setupText(size: 12.5, color: SetupColors.secondary, height: 1.35)),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({required Key switchKey, required String title, required String hint, required String description, required bool value, required ValueChanged<bool> onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
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
    );
  }

  Widget _settingsCard() {
    return SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupCardHeading(icon: Icons.tune, title: 'Pricing Settings'),
          _toggleRow(
            switchKey: const ValueKey('switch-weekend'),
            title: 'Allow different pricing for weekdays & weekends',
            hint: 'Charge different rates on Monday to Friday, on Saturday and Sunday, and on days you choose. Off means one set of prices for every day.',
            description: 'Set separate rates for Mon – Fri and Sat – Sun.',
            value: _settings.differentWeekendPricing,
            onChanged: (v) => setState(() {
              _settings = _settings.copyWith(differentWeekendPricing: v);
              _problems = {};
            }),
          ),
          const Divider(height: 1, color: Color(0xFFEFECF6)),
          _toggleRow(
            switchKey: const ValueKey('switch-member'),
            title: 'Enable member pricing',
            hint: 'Adds a member rate to each sport or court. It is saved for membership bookings; it does not change what players pay today.',
            description: 'Offer special rates for membership bookings.',
            value: _settings.memberPricingEnabled,
            onChanged: (v) => setState(() {
              _settings = _settings.copyWith(memberPricingEnabled: v);
              _problems = {};
            }),
          ),
          const Divider(height: 1, color: Color(0xFFEFECF6)),
          _toggleRow(
            switchKey: const ValueKey('switch-coaching'),
            title: 'Enable coaching pricing',
            hint: 'Adds a coaching rate to each sport or court. It is saved for coaching sessions; it does not change what players pay today.',
            description: 'Set separate pricing for coaching sessions.',
            value: _settings.coachingPricingEnabled,
            onChanged: (v) => setState(() {
              _settings = _settings.copyWith(coachingPricingEnabled: v);
              _problems = {};
            }),
          ),
        ],
      ),
    );
  }

  Widget _previewCard() {
    if (_settings.mode == PricingMode.byCourt) {
      final court = _courtEntries.where((c) => c.id == _selectedCourt).firstOrNull;
      final setup = court == null ? null : _courtSetups[court.id];
      final rows = setup == null ? const <PreviewRow>[] : previewRows(setup, _settings);
      return SetupCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SetupCardHeading(icon: Icons.visibility_outlined, title: court == null ? 'Pricing Preview' : 'Pricing Preview – ${court.name}', description: 'Booking rate summary for this court.'),
            if (rows.isEmpty)
              Text('Set a price to see the summary.', style: setupText(size: 13.5, color: SetupColors.secondary))
            else
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFEFECF6))),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: const BoxDecoration(color: SetupColors.activeBg, borderRadius: BorderRadius.vertical(top: Radius.circular(9))),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text('Day', style: setupText(size: 12, weight: FontWeight.w600))),
                        Expanded(flex: 5, child: Text('Time Slot', style: setupText(size: 12, weight: FontWeight.w600))),
                        Expanded(flex: 3, child: Text('Rate', textAlign: TextAlign.right, style: setupText(size: 12, weight: FontWeight.w600))),
                      ]),
                    ),
                    for (final r in rows)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEFECF6)))),
                        child: Row(children: [
                          Expanded(flex: 3, child: Text(r.day, style: setupText(size: 13, weight: FontWeight.w500))),
                          Expanded(flex: 5, child: Text(r.time, style: setupText(size: 13))),
                          Expanded(flex: 3, child: Text(r.rate, textAlign: TextAlign.right, style: setupText(size: 13, weight: FontWeight.w500))),
                        ]),
                      ),
                  ],
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
          const SetupCardHeading(icon: Icons.visibility_outlined, title: 'Pricing Preview', description: 'Here’s a quick summary of your pricing setup.'),
          for (final s in _sportEntries)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFF7F5FB), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Text(s.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.name, style: setupText(size: 14, weight: FontWeight.w600))),
                  Flexible(child: Text(priceRangeLabel(_sportSetups[s.id] ?? PriceSetup(), _settings), textAlign: TextAlign.right, style: setupText(size: 13.5, weight: FontWeight.w600))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading || _loadError != null) {
      return SetupPage(
        footer: _loadError == null ? const SizedBox(height: 52) : SetupButton(label: 'Try again', primary: true, onPressed: _load),
        children: [
          if (!widget.editMode) const SetupStepper(current: 4),
          const SizedBox(height: 18),
          if (_loadError != null) SetupErrorBanner(_loadError!) else const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    final byCourt = _settings.mode == PricingMode.byCourt;
    return SetupPage(
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) SetupErrorBanner(_error!),
          Row(
            children: [
              Expanded(child: SetupButton(label: widget.editMode ? 'Cancel' : 'Back', icon: Icons.arrow_back, onPressed: () => widget.editMode ? context.pop() : context.go(AppRoutes.onboardingOperatingHours))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: SetupButton(label: widget.editMode ? 'Save' : 'Next', primary: true, trailingIcon: widget.editMode ? null : Icons.arrow_forward, loading: _savingNext, loadingLabel: 'Saving…', onPressed: _savingDraft ? null : () => _persist(advance: true))),
            ],
          ),
          if (!widget.editMode) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              key: const ValueKey('save-draft'),
              onPressed: (_savingNext || _savingDraft) ? null : () => _persist(advance: false),
              icon: _savingDraft ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.description_outlined, size: 18, color: SetupColors.secondary),
              label: Text('Save as Draft', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.secondary)),
            ),
          ],
        ],
      ),
      children: [
        if (!widget.editMode) ...[const SetupStepper(current: 4), const SizedBox(height: 18)],
        Text('Pricing', style: setupText(size: 28, weight: FontWeight.w700, height: 1.1)),
        const SizedBox(height: 6),
        Text('Set the booking rates for your courts. You can add different pricing for each sport, court, or time slot.', style: setupText(size: 14, color: SetupColors.secondary, height: 1.4)),
        const SizedBox(height: 18),
        _modeCards(),
        const SizedBox(height: 16),
        if (byCourt) ...[
          _courtListCard(),
          const SizedBox(height: 16),
          _courtPanel(),
        ] else
          _sportPricingCard(),
        const SizedBox(height: 16),
        _settingsCard(),
        const SizedBox(height: 16),
        _previewCard(),
      ],
    );
  }
}

/// A rupee amount field: digits and one decimal point, with its own controller so typing is never interrupted by a rebuild.
class _AmountField extends StatefulWidget {
  const _AmountField({super.key, required this.label, required this.value, required this.onChanged, this.required = false, this.error, this.invalid = false});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool required;
  final String? error;
  final bool invalid;

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupLabel(widget.label, required: widget.required),
        TextFormField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          onChanged: widget.onChanged,
          style: setupText(size: 15),
          decoration: setupDecoration(hint: '0', prefix: Padding(padding: const EdgeInsets.only(left: 14, right: 6), child: Text('₹', style: setupText(size: 15, color: SetupColors.secondary)))).copyWith(
                errorText: widget.error,
                enabledBorder: widget.invalid ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SetupColors.error)) : null,
              ),
        ),
      ],
    );
  }
}
