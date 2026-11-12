import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/data/models/pricing.dart';
import 'package:gameall_club_mobile/features/onboarding/pricing_setup_logic.dart';

const _settings = PricingSettings();
const _scope = RuleScope('fs-1');
const _span = Span('06:00', '23:00');

List<OperatingDay> _openDays({String start = '06:00', String end = '23:00'}) => [
      for (var d = 0; d < 7; d++)
        OperatingDay(dayOfWeek: d, isClosed: false, is24Hours: false, slots: [OperatingTimeSlot(startTime: start, endTime: end, crossesMidnight: false, displayOrder: 0)]),
    ];

Slot _slot(String start, String end, String price) => Slot(id: newSlotId(), start: start, end: end, price: price);

PricingRule _saved(String dayType, int minor) => PricingRule(
      facilitySportId: 'fs-1',
      dayType: dayType,
      coversFullDay: true,
      amountMinor: minor,
      currency: 'INR',
      pricingUnit: 'PER_HOUR',
      priority: 0,
    );

void main() {
  group('amounts', () {
    test('money groups digits the Indian way', () {
      expect(money(400), '₹400');
      expect(money(2000), '₹2,000');
      expect(money(125000), '₹1,25,000');
    });
    test('minor <-> text round trips', () {
      expect(toMinor('550'), 55000);
      expect(amountText(55000), '550');
      expect(amountText(55050), '550.50');
    });
  });

  group('rulesFromSetup', () {
    test('a base price alone is one full-day rule', () {
      final rules = rulesFromSetup(PriceSetup(basePrice: '400'), _scope, _settings);
      expect(rules, hasLength(1));
      expect(rules.single.coversFullDay, isTrue);
      expect(rules.single.amountMinor, 40000);
      expect(rules.single.audience, 'GENERAL');
      expect(rules.single.priority, 0);
    });

    test('a court rule has higher priority and its court id', () {
      final rules = rulesFromSetup(PriceSetup(basePrice: '400'), const RuleScope('fs-1', 'c-1'), _settings);
      expect(rules.single.playingAreaId, 'c-1');
      expect(rules.single.priority, 10);
    });

    test('time slots become timed rules per day group; specific days carry their days', () {
      final setup = PriceSetup(
        basePrice: '400',
        timeBased: true,
        weekdays: [_slot('06:00', '17:00', '400')],
        weekends: [_slot('06:00', '23:00', '500')],
        specificDays: [5, 1],
        specificSlots: [_slot('18:00', '22:00', '650')],
      );
      final rules = rulesFromSetup(setup, _scope, _settings);
      expect(rules.map((r) => r.dayType), ['ALL_DAYS', 'WEEKDAYS', 'WEEKENDS', 'SPECIFIC_DAYS']);
      expect(rules.last.daysOfWeek, [1, 5]);
      expect(rules.last.coversFullDay, isFalse);
    });

    test('with weekday pricing off only the all-days slots are used', () {
      final setup = PriceSetup(basePrice: '400', timeBased: true, allDays: [_slot('06:00', '12:00', '300')], weekdays: [_slot('06:00', '12:00', '999')]);
      final rules = rulesFromSetup(setup, _scope, const PricingSettings(differentWeekendPricing: false));
      expect(rules.map((r) => r.amountMinor), [40000, 30000]);
      expect(rules.last.dayType, 'ALL_DAYS');
    });

    test('member and coaching rates are saved only when their setting is on', () {
      final setup = PriceSetup(basePrice: '400', memberPrice: '300', coachingPrice: '200');
      expect(rulesFromSetup(setup, _scope, _settings), hasLength(1));
      final all = rulesFromSetup(setup, _scope, const PricingSettings(memberPricingEnabled: true, coachingPricingEnabled: true));
      expect(all.map((r) => r.audience), ['GENERAL', 'MEMBER', 'COACHING']);
    });
  });

  group('setupFromRules', () {
    test('round trips a setup', () {
      final setup = PriceSetup(
        basePrice: '400',
        timeBased: true,
        weekdays: [_slot('06:00', '17:00', '350')..tier = 'OFF_PEAK'],
        specificDays: [6],
        specificSlots: [_slot('18:00', '22:00', '650')],
        memberPrice: '300',
      );
      const withMember = PricingSettings(memberPricingEnabled: true);
      final back = setupFromRules(rulesFromSetup(setup, _scope, withMember), _span);
      expect(back.basePrice, '400');
      expect(back.timeBased, isTrue);
      expect(back.weekdays.single.price, '350');
      expect(back.weekdays.single.tier, 'OFF_PEAK');
      expect(back.specificDays, [6]);
      expect(back.specificSlots.single.start, '18:00');
      expect(back.memberPrice, '300');
    });

    test('an old weekend full-day rate becomes a slot over the open hours', () {
      final rules = [_saved('ALL_DAYS', 40000), _saved('WEEKENDS', 60000)];
      final s = setupFromRules(rules, _span);
      expect(s.basePrice, '400');
      expect(s.timeBased, isTrue);
      expect(s.weekends.single.start, '06:00');
      expect(s.weekends.single.end, '23:00');
      expect(s.weekends.single.price, '600');
      expect(usesDayGroups(rules), isTrue);
    });

    test('no rules is an empty setup', () {
      expect(setupFromRules(const [], _span).basePrice, '');
    });
  });

  group('validateSetup', () {
    test('needs a base price', () {
      expect(validateSetup(PriceSetup(), _scope, _settings, null).base, isNotNull);
      expect(validateSetup(PriceSetup(basePrice: '0'), _scope, _settings, null).base, isNotNull);
      expect(validateSetup(PriceSetup(basePrice: '400'), _scope, _settings, null).any, isFalse);
    });

    test('member / coaching prices are required once their setting is on', () {
      final p = validateSetup(PriceSetup(basePrice: '400'), _scope, const PricingSettings(memberPricingEnabled: true, coachingPricingEnabled: true), null);
      expect(p.member, isNotNull);
      expect(p.coaching, isNotNull);
    });

    test('a slot needs a price and different start and end times', () {
      final empty = _slot('06:00', '10:00', '');
      final same = _slot('10:00', '10:00', '300');
      final p = validateSetup(PriceSetup(basePrice: '400', timeBased: true, weekdays: [empty, same]), _scope, _settings, null);
      expect(p.slots[empty.id], 'Enter a price.');
      expect(p.slots[same.id], 'Start and end time cannot be the same.');
    });

    test('specific-day slots need at least one day', () {
      final p = validateSetup(PriceSetup(basePrice: '400', timeBased: true, specificSlots: [_slot('06:00', '10:00', '300')]), _scope, _settings, null);
      expect(p.groups[SlotGroup.specific], 'Choose at least one day.');
    });

    test('overlapping slots are refused', () {
      final p = validateSetup(PriceSetup(basePrice: '400', timeBased: true, weekdays: [_slot('06:00', '12:00', '300'), _slot('11:00', '14:00', '350')]), _scope, _settings, _openDays());
      expect(p.groups[SlotGroup.weekdays], 'Pricing periods cannot overlap.');
    });

    test('slots outside the opening hours are refused', () {
      final p = validateSetup(PriceSetup(basePrice: '400', timeBased: true, weekdays: [_slot('05:00', '08:00', '300')]), _scope, _settings, _openDays());
      expect(p.groups[SlotGroup.weekdays], contains('operating hours'));
    });

    test('a slot may run across a daily break', () {
      final days = [
        for (var d = 0; d < 7; d++)
          OperatingDay(dayOfWeek: d, isClosed: false, is24Hours: false, slots: const [
            OperatingTimeSlot(startTime: '06:00', endTime: '13:00', crossesMidnight: false, displayOrder: 0),
            OperatingTimeSlot(startTime: '14:00', endTime: '23:00', crossesMidnight: false, displayOrder: 1),
          ]),
      ];
      final p = validateSetup(PriceSetup(basePrice: '400', timeBased: true, weekdays: [_slot('12:00', '16:00', '300')]), _scope, _settings, days);
      expect(p.any, isFalse);
    });

    test('a slot on a closed day is refused', () {
      final days = _openDays().map((d) => d.dayOfWeek == 0 ? const OperatingDay(dayOfWeek: 0, isClosed: true, is24Hours: false, slots: []) : d).toList();
      final p = validateSetup(PriceSetup(basePrice: '400', timeBased: true, weekends: [_slot('06:00', '10:00', '300')]), _scope, _settings, days);
      expect(p.groups[SlotGroup.weekends], contains('closed'));
    });
  });

  group('preview', () {
    test('price range and label', () {
      final s = PriceSetup(basePrice: '400', timeBased: true, weekdays: [_slot('18:00', '22:00', '650')]);
      expect(priceRangeLabel(s, _settings), '₹400 – ₹650 / hour');
      expect(priceRangeLabel(PriceSetup(basePrice: '2000'), _settings), '₹2,000 / hour');
      expect(priceRangeLabel(PriceSetup(), _settings), 'Not set');
      expect(priceRangeLabel(PriceSetup(basePrice: '500', unit: PriceUnit.perSession), _settings), '₹500 / session');
    });

    test('preview rows list slots then the base rate', () {
      final s = PriceSetup(basePrice: '400', timeBased: true, weekdays: [_slot('06:00', '17:00', '400')]);
      final rows = previewRows(s, _settings);
      expect(rows.first.day, 'Mon – Fri');
      expect(rows.first.time, '6:00 AM – 5:00 PM');
      expect(rows.last.day, 'Other times');
    });

    test('day labels', () {
      expect(dayGroupLabel(SlotGroup.specific, [5, 1, 0]), 'Mon, Fri, Sun');
      expect(dayGroupLabel(SlotGroup.specific), 'No days');
    });
  });

  test('autoTier follows the base price', () {
    expect(autoTier('500', '400'), 'PEAK');
    expect(autoTier('300', '400'), 'OFF_PEAK');
    expect(autoTier('400', '400'), '');
    expect(autoTier('', '400'), '');
  });

  test('openSpan covers the open days; nextSlot continues from the last slot', () {
    expect(openSpan(_openDays(start: '07:00', end: '22:00')).open, '07:00');
    expect(openSpan(null).close, '23:00');
    final next = nextSlot([_slot('06:00', '12:00', '300')], _span);
    expect(next.start, '12:00');
    expect(next.end, '23:00');
  });
}
