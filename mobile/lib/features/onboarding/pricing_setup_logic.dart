import '../../data/models/operating_hours.dart';
import '../../data/models/pricing.dart';
import 'hours_setup_logic.dart' show formatClock, shortDay, toMinutes;

/// Pure rules for the Pricing step — a port of the website's `pricing-setup-model.ts`, kept out of widgets so both apps agree and
/// the logic can be unit-tested. One [PriceSetup] is edited per sport (By Sport) or per court (By Court): a base price, optionally
/// broken into time slots for weekdays / weekends / chosen days, and optionally a member rate and a coaching rate.

enum PricingMode {
  bySport,
  byCourt;

  String get db => this == PricingMode.bySport ? 'BY_SPORT' : 'BY_COURT';
  static PricingMode fromDb(String? v) => v == 'BY_COURT' ? PricingMode.byCourt : PricingMode.bySport;
}

enum PriceUnit { perHour, perSession }

String unitDb(PriceUnit u) => u == PriceUnit.perHour ? 'PER_HOUR' : 'PER_SESSION';
const Map<PriceUnit, String> unitSuffix = {PriceUnit.perHour: '/ hour', PriceUnit.perSession: '/ session'};

/// The day groups a time-slot list can belong to; `all` is used when weekday / weekend pricing is switched off.
enum SlotGroup { all, weekdays, weekends, specific }

String groupDb(SlotGroup g) => const {SlotGroup.all: 'ALL_DAYS', SlotGroup.weekdays: 'WEEKDAYS', SlotGroup.weekends: 'WEEKENDS', SlotGroup.specific: 'SPECIFIC_DAYS'}[g]!;

class Slot {
  Slot({required this.id, required this.start, required this.end, this.price = '', this.tier = '', this.tierTouched = false});

  /// UI id only.
  final String id;

  /// "HH:MM"
  String start;
  String end;

  /// Typed amount in rupees ("550").
  String price;

  /// '' | PEAK | OFF_PEAK
  String tier;

  /// True once the owner picked the tag themselves, so it stops following the price.
  bool tierTouched;

  Slot copy({String? id}) => Slot(id: id ?? this.id, start: start, end: end, price: price, tier: tier, tierTouched: tierTouched);
}

int _counter = 0;
String newSlotId() => 'slot-${++_counter}';

class PriceSetup {
  PriceSetup({
    this.unit = PriceUnit.perHour,
    this.basePrice = '',
    this.timeBased = false,
    List<Slot>? allDays,
    List<Slot>? weekdays,
    List<Slot>? weekends,
    List<int>? specificDays,
    List<Slot>? specificSlots,
    this.memberPrice = '',
    this.coachingPrice = '',
  })  : allDays = allDays ?? [],
        weekdays = weekdays ?? [],
        weekends = weekends ?? [],
        specificDays = specificDays ?? [],
        specificSlots = specificSlots ?? [];

  PriceUnit unit;
  String basePrice;
  bool timeBased;
  List<Slot> allDays;
  List<Slot> weekdays;
  List<Slot> weekends;

  /// 0 = Sun .. 6 = Sat
  List<int> specificDays;
  List<Slot> specificSlots;
  String memberPrice;
  String coachingPrice;

  List<Slot> slotsOf(SlotGroup g) => switch (g) {
        SlotGroup.all => allDays,
        SlotGroup.weekdays => weekdays,
        SlotGroup.weekends => weekends,
        SlotGroup.specific => specificSlots,
      };

  void setSlots(SlotGroup g, List<Slot> slots) {
    switch (g) {
      case SlotGroup.all:
        allDays = slots;
      case SlotGroup.weekdays:
        weekdays = slots;
      case SlotGroup.weekends:
        weekends = slots;
      case SlotGroup.specific:
        specificSlots = slots;
    }
  }

  PriceSetup clone() {
    List<Slot> c(List<Slot> l) => [for (final s in l) s.copy(id: newSlotId())];
    return PriceSetup(
      unit: unit,
      basePrice: basePrice,
      timeBased: timeBased,
      allDays: c(allDays),
      weekdays: c(weekdays),
      weekends: c(weekends),
      specificDays: [...specificDays],
      specificSlots: c(specificSlots),
      memberPrice: memberPrice,
      coachingPrice: coachingPrice,
    );
  }
}

class PricingSettings {
  const PricingSettings({this.mode = PricingMode.bySport, this.differentWeekendPricing = true, this.memberPricingEnabled = false, this.coachingPricingEnabled = false});

  final PricingMode mode;
  final bool differentWeekendPricing;
  final bool memberPricingEnabled;
  final bool coachingPricingEnabled;

  PricingSettings copyWith({PricingMode? mode, bool? differentWeekendPricing, bool? memberPricingEnabled, bool? coachingPricingEnabled}) => PricingSettings(
        mode: mode ?? this.mode,
        differentWeekendPricing: differentWeekendPricing ?? this.differentWeekendPricing,
        memberPricingEnabled: memberPricingEnabled ?? this.memberPricingEnabled,
        coachingPricingEnabled: coachingPricingEnabled ?? this.coachingPricingEnabled,
      );
}

/// The groups a setup's time slots can be in, for the current settings.
List<SlotGroup> groupsFor(PricingSettings s) => s.differentWeekendPricing ? [SlotGroup.weekdays, SlotGroup.weekends, SlotGroup.specific] : [SlotGroup.all];

/// Above the base price is Peak, below it Off-Peak, equal none.
String autoTier(String price, String base) {
  final p = double.tryParse(price) ?? 0;
  final b = double.tryParse(base) ?? 0;
  if (!(p > 0) || !(b > 0) || p == b) return '';
  return p > b ? 'PEAK' : 'OFF_PEAK';
}

const Map<String, String> tierLabel = {'PEAK': 'Peak', 'OFF_PEAK': 'Off-Peak'};

bool validAmount(String v) {
  final t = v.trim();
  return RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t) && (double.tryParse(t) ?? 0) > 0;
}

int toMinor(String rupees) => (double.parse(rupees.trim()) * 100).round();

String amountText(int minor) {
  final v = minor / 100;
  return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
}

/// "₹1,200" (Indian digit grouping).
String money(num n) {
  final whole = n.round() == n ? n.round().toString() : n.toStringAsFixed(2);
  final parts = whole.split('.');
  final digits = parts.first;
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final tail = digits.substring(digits.length - 3);
    var head = digits.substring(0, digits.length - 3);
    final chunks = <String>[];
    while (head.length > 2) {
      chunks.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) chunks.insert(0, head);
    grouped = '${chunks.join(',')},$tail';
  }
  return '₹$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
}

// ── setup -> rules ───────────────────────────────────────────────────────

class Span {
  const Span(this.open, this.close);
  final String open;
  final String close;
}

/// The open window new slots start from: the earliest opening and the latest closing across the open days.
Span openSpan(List<OperatingDay>? days) {
  final slots = [for (final d in days ?? const <OperatingDay>[]) if (!d.isClosed && !d.is24Hours) ...d.slots];
  if (slots.isEmpty) return const Span('06:00', '23:00');
  final opens = slots.map((s) => s.startTime).toList()..sort();
  final closes = slots.map((s) => s.endTime).toList()..sort();
  return Span(opens.first, closes.last);
}

/// A new slot starts where the last one ended (or at opening) and runs to closing.
Slot nextSlot(List<Slot> existing, Span span) {
  var start = existing.isEmpty ? span.open : existing.last.end;
  var end = span.close;
  if (start == end) {
    start = span.open;
    end = span.close;
  }
  return Slot(id: newSlotId(), start: start, end: end);
}

class RuleScope {
  const RuleScope(this.facilitySportId, [this.playingAreaId]);
  final String facilitySportId;
  final String? playingAreaId;
}

/// The rules to save for one sport or court.
List<PricingRule> rulesFromSetup(PriceSetup setup, RuleScope scope, PricingSettings settings) {
  final priority = scope.playingAreaId != null ? 10 : 0;
  PricingRule base(String audience, String amount) => PricingRule(
        facilitySportId: scope.facilitySportId,
        playingAreaId: scope.playingAreaId,
        dayType: 'ALL_DAYS',
        coversFullDay: true,
        amountMinor: toMinor(amount),
        currency: 'INR',
        pricingUnit: unitDb(setup.unit),
        priority: priority,
        audience: audience,
      );
  final rules = <PricingRule>[];
  if (setup.basePrice.trim().isNotEmpty) rules.add(base('GENERAL', setup.basePrice));

  if (setup.timeBased) {
    for (final g in groupsFor(settings)) {
      for (final slot in setup.slotsOf(g)) {
        if (slot.price.trim().isEmpty) continue;
        rules.add(PricingRule(
          facilitySportId: scope.facilitySportId,
          playingAreaId: scope.playingAreaId,
          dayType: groupDb(g),
          daysOfWeek: g == SlotGroup.specific ? ([...setup.specificDays]..sort()) : const [],
          rateTier: slot.tier.isEmpty ? null : slot.tier,
          coversFullDay: false,
          startTime: slot.start,
          endTime: slot.end,
          amountMinor: toMinor(slot.price),
          currency: 'INR',
          pricingUnit: unitDb(setup.unit),
          priority: priority,
          audience: 'GENERAL',
        ));
      }
    }
  }
  if (settings.memberPricingEnabled && setup.memberPrice.trim().isNotEmpty) rules.add(base('MEMBER', setup.memberPrice));
  if (settings.coachingPricingEnabled && setup.coachingPrice.trim().isNotEmpty) rules.add(base('COACHING', setup.coachingPrice));
  return rules;
}

// ── rules -> setup ───────────────────────────────────────────────────────

/// Reads one sport's or court's saved rules back as a setup. [span] fills in the hours of an old day-scoped full-day rate.
PriceSetup setupFromRules(List<PricingRule> rules, Span span) {
  final setup = PriceSetup();
  if (rules.isEmpty) return setup;

  final general = rules.where((r) => r.audience == 'GENERAL').toList();
  final first = general.isNotEmpty ? general.first : rules.first;
  setup.unit = first.pricingUnit == 'PER_SESSION' ? PriceUnit.perSession : PriceUnit.perHour;

  final fullDayAll = general.where((r) => r.coversFullDay && r.dayType == 'ALL_DAYS').firstOrNull;
  final timed = general.where((r) => !r.coversFullDay).toList();
  // an old full-day rate for weekdays / weekends / chosen days becomes a slot over the open hours
  final legacy = general.where((r) => r.coversFullDay && r.dayType != 'ALL_DAYS').toList();

  Slot toSlot(PricingRule r, {String? start, String? end}) => Slot(
        id: newSlotId(),
        start: start ?? r.startTime ?? span.open,
        end: end ?? r.endTime ?? span.close,
        price: amountText(r.amountMinor),
        tier: r.rateTier ?? '',
        tierTouched: r.rateTier != null,
      );

  for (final r in [...timed, ...legacy]) {
    final slot = r.coversFullDay ? toSlot(r, start: span.open, end: span.close) : toSlot(r);
    if (r.dayType == 'WEEKDAYS') {
      setup.weekdays.add(slot);
    } else if (r.dayType == 'WEEKENDS') {
      setup.weekends.add(slot);
    } else if (r.dayType == 'SPECIFIC_DAYS') {
      setup.specificDays = {...setup.specificDays, ...r.daysOfWeek}.toList();
      setup.specificSlots.add(slot);
    } else {
      setup.allDays.add(slot);
    }
  }
  for (final l in [setup.weekdays, setup.weekends, setup.specificSlots, setup.allDays]) {
    l.sort((a, b) => a.start.compareTo(b.start));
  }

  setup.timeBased = timed.isNotEmpty || legacy.isNotEmpty;
  if (fullDayAll != null) {
    setup.basePrice = amountText(fullDayAll.amountMinor);
  } else if (general.isNotEmpty) {
    setup.basePrice = amountText(general.map((r) => r.amountMinor).reduce((a, b) => a < b ? a : b));
  }
  final member = rules.where((r) => r.audience == 'MEMBER').firstOrNull;
  final coaching = rules.where((r) => r.audience == 'COACHING').firstOrNull;
  if (member != null) setup.memberPrice = amountText(member.amountMinor);
  if (coaching != null) setup.coachingPrice = amountText(coaching.amountMinor);
  return setup;
}

/// Whether saved rules use weekday / weekend / specific-day pricing (so "different pricing" should start on).
bool usesDayGroups(List<PricingRule> rules) => rules.any((r) => r.dayType != 'ALL_DAYS');

// ── checking ─────────────────────────────────────────────────────────────

class SetupProblems {
  SetupProblems({this.base, this.member, this.coaching, Map<String, String>? slots, Map<SlotGroup, String>? groups})
      : slots = slots ?? {},
        groups = groups ?? {};

  String? base;
  String? member;
  String? coaching;

  /// keyed by slot id
  final Map<String, String> slots;

  /// about a whole group, e.g. no days chosen or overlapping slots
  final Map<SlotGroup, String> groups;

  bool get any => base != null || member != null || coaching != null || slots.isNotEmpty || groups.isNotEmpty;
}

List<int> _dayNumbers(String dayType, List<int> days) {
  if (dayType == 'SPECIFIC_DAYS') return days;
  if (dayType == 'WEEKDAYS') return const [1, 2, 3, 4, 5];
  if (dayType == 'WEEKENDS') return const [0, 6];
  return const [0, 1, 2, 3, 4, 5, 6];
}

bool _fits(int ruleStart, int ruleEnd, String slotStart, String slotEnd) {
  var re = ruleEnd;
  if (re <= ruleStart) re += 1440;
  final ss = toMinutes(slotStart);
  var se = toMinutes(slotEnd);
  if (se <= ss) se += 1440;
  return ruleStart >= ss && re <= se;
}

/// A price window must fall inside the opening hours on every day it covers; a daily break counts as part of the open span.
String? _hoursProblem(PricingRule r, List<OperatingDay> operating) {
  for (final dow in _dayNumbers(r.dayType, r.daysOfWeek)) {
    final day = operating.where((d) => d.dayOfWeek == dow).firstOrNull;
    if (day == null || day.isClosed) return 'This pricing period falls on a day the facility is closed.';
    if (day.is24Hours) continue;
    final s = toMinutes(r.startTime!);
    final e = toMinutes(r.endTime!);
    final spanFits = day.slots.length > 1 && _fits(s, e, day.slots.first.startTime, day.slots.last.endTime);
    if (!day.slots.any((slot) => _fits(s, e, slot.startTime, slot.endTime)) && !spanFits) return "Pricing hours must fall within your facility's operating hours.";
  }
  return null;
}

SetupProblems validateSetup(PriceSetup setup, RuleScope scope, PricingSettings settings, List<OperatingDay>? operatingDays) {
  final p = SetupProblems();

  if (setup.basePrice.trim().isEmpty) {
    p.base = 'Enter the base price.';
  } else if (!validAmount(setup.basePrice)) {
    p.base = 'Enter a valid amount greater than 0.';
  }
  if (settings.memberPricingEnabled) {
    if (setup.memberPrice.trim().isEmpty) {
      p.member = 'Enter the member price.';
    } else if (!validAmount(setup.memberPrice)) {
      p.member = 'Enter a valid amount greater than 0.';
    }
  }
  if (settings.coachingPricingEnabled) {
    if (setup.coachingPrice.trim().isEmpty) {
      p.coaching = 'Enter the coaching price.';
    } else if (!validAmount(setup.coachingPrice)) {
      p.coaching = 'Enter a valid amount greater than 0.';
    }
  }

  if (setup.timeBased) {
    final groups = groupsFor(settings);
    for (final g in groups) {
      final slots = setup.slotsOf(g);
      if (g == SlotGroup.specific && slots.isNotEmpty && setup.specificDays.isEmpty) p.groups[g] = 'Choose at least one day.';
      for (final s in slots) {
        if (s.price.trim().isEmpty) {
          p.slots[s.id] = 'Enter a price.';
        } else if (!validAmount(s.price)) {
          p.slots[s.id] = 'Enter a valid amount greater than 0.';
        } else if (s.start.isEmpty || s.end.isEmpty) {
          p.slots[s.id] = 'Select start and end time.';
        } else if (s.start == s.end) {
          p.slots[s.id] = 'Start and end time cannot be the same.';
        }
      }
    }
    // the slots must fit the opening hours and must not overlap each other
    if (p.slots.isEmpty && p.groups.isEmpty) {
      final timed = rulesFromSetup(setup, scope, settings).where((r) => !r.coversFullDay && r.audience == 'GENERAL').toList();
      String? message;
      if (operatingDays != null) {
        for (final r in timed) {
          message = _hoursProblem(r, operatingDays);
          if (message != null) break;
        }
      }
      message ??= _overlaps(timed) ? 'Pricing periods cannot overlap.' : null;
      if (message != null) {
        final target = groups.where((g) => setup.slotsOf(g).isNotEmpty).firstOrNull ?? groups.first;
        p.groups[target] = message;
      }
    }
  }
  return p;
}

bool _overlaps(List<PricingRule> rules) {
  for (var i = 0; i < rules.length; i++) {
    for (var j = i + 1; j < rules.length; j++) {
      final a = rules[i];
      final b = rules[j];
      if (a.dayType != b.dayType) continue;
      if (a.dayType == 'SPECIFIC_DAYS' && !a.daysOfWeek.any(b.daysOfWeek.contains)) continue;
      final aS = toMinutes(a.startTime!);
      final aE = toMinutes(a.endTime!);
      final bS = toMinutes(b.startTime!);
      final bE = toMinutes(b.endTime!);
      if (aS < bE && bS < aE) return true;
    }
  }
  return false;
}

// ── preview ──────────────────────────────────────────────────────────────

/// "Mon – Fri", "Sat – Sun", "All days", "Mon, Wed, Fri"
String dayGroupLabel(SlotGroup g, [List<int> days = const []]) {
  if (g == SlotGroup.weekdays) return 'Mon – Fri';
  if (g == SlotGroup.weekends) return 'Sat – Sun';
  if (g == SlotGroup.all) return 'All days';
  const order = [1, 2, 3, 4, 5, 6, 0];
  final picked = order.where(days.contains).toList();
  return picked.isEmpty ? 'No days' : picked.map((d) => shortDay[d]).join(', ');
}

/// The lowest and highest price a setup charges, in rupees (the base price and every slot); null when nothing is priced.
({num min, num max})? priceRange(PriceSetup setup, PricingSettings settings) {
  final prices = <num>[];
  if (validAmount(setup.basePrice)) prices.add(double.parse(setup.basePrice));
  if (setup.timeBased) {
    for (final g in groupsFor(settings)) {
      for (final s in setup.slotsOf(g)) {
        if (validAmount(s.price)) prices.add(double.parse(s.price));
      }
    }
  }
  if (prices.isEmpty) return null;
  prices.sort();
  return (min: prices.first, max: prices.last);
}

/// "₹400 – ₹650 / hour", "₹2,000 / hour", or "Not set"
String priceRangeLabel(PriceSetup setup, PricingSettings settings) {
  final r = priceRange(setup, settings);
  if (r == null) return 'Not set';
  final text = r.min == r.max ? money(r.min) : '${money(r.min)} – ${money(r.max)}';
  return '$text ${unitSuffix[setup.unit]}';
}

class PreviewRow {
  const PreviewRow(this.day, this.time, this.rate);
  final String day;
  final String time;
  final String rate;
}

/// The table under "Pricing Preview" for one court.
List<PreviewRow> previewRows(PriceSetup setup, PricingSettings settings) {
  final rows = <PreviewRow>[];
  if (setup.timeBased) {
    for (final g in groupsFor(settings)) {
      final label = dayGroupLabel(g, setup.specificDays);
      for (final s in setup.slotsOf(g)) {
        if (!validAmount(s.price)) continue;
        rows.add(PreviewRow(label, '${formatClock(s.start)} – ${formatClock(s.end)}', '${money(double.parse(s.price))}${setup.unit == PriceUnit.perSession ? ' / session' : ''}'));
      }
    }
  }
  if (validAmount(setup.basePrice)) {
    rows.add(PreviewRow(setup.timeBased ? 'Other times' : 'All days', setup.timeBased ? 'Outside the slots above' : 'Full day', '${money(double.parse(setup.basePrice))} ${unitSuffix[setup.unit]}'));
  }
  return rows;
}
