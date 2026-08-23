/// Mirrors `pricing_rules` (0005 migration) — money stored as amount_minor
/// (integer, never a float) with a currency code.
class PricingRule {
  const PricingRule({
    this.id,
    required this.facilitySportId,
    this.playingAreaId,
    required this.dayType,
    required this.coversFullDay,
    this.startTime,
    this.endTime,
    required this.amountMinor,
    required this.currency,
    required this.pricingUnit,
    required this.priority,
  });

  final String? id;
  final String facilitySportId;
  final String? playingAreaId;
  final String dayType; // ALL_DAYS | WEEKDAYS | WEEKENDS
  final bool coversFullDay;
  final String? startTime;
  final String? endTime;
  final int amountMinor;
  final String currency;
  final String pricingUnit; // PER_HOUR | PER_30_MINUTES | PER_SESSION | PER_MATCH
  final int priority;

  factory PricingRule.fromJson(Map<String, dynamic> json) {
    return PricingRule(
      id: json['id'] as String?,
      facilitySportId: json['facility_sport_id'] as String,
      playingAreaId: json['playing_area_id'] as String?,
      dayType: json['day_type'] as String? ?? 'ALL_DAYS',
      coversFullDay: json['covers_full_day'] as bool? ?? true,
      startTime: (json['start_time'] as String?)?.substring(0, 5),
      endTime: (json['end_time'] as String?)?.substring(0, 5),
      amountMinor: json['amount_minor'] as int,
      currency: json['currency'] as String? ?? 'INR',
      pricingUnit: json['pricing_unit'] as String? ?? 'PER_HOUR',
      priority: json['priority'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toPayload() => {
    'facilitySportId': facilitySportId,
    'playingAreaId': playingAreaId ?? '',
    'dayType': dayType,
    'coversFullDay': coversFullDay,
    'startTime': coversFullDay ? '' : startTime,
    'endTime': coversFullDay ? '' : endTime,
    'amountMinor': amountMinor,
    'currency': currency,
    'pricingUnit': pricingUnit,
    'priority': priority,
  };

  /// 40000 (paise) -> 400 (rupees, matching how the amount is entered/shown).
  int get amountRupees => (amountMinor / 100).round();
}

class PricingPlan {
  const PricingPlan({
    required this.id,
    required this.facilityId,
    required this.currency,
    required this.rules,
  });

  final String id;
  final String facilityId;
  final String currency;
  final List<PricingRule> rules;

  factory PricingPlan.fromJson(
    Map<String, dynamic> planJson,
    List<Map<String, dynamic>> ruleRows,
  ) {
    return PricingPlan(
      id: planJson['id'] as String,
      facilityId: planJson['facility_id'] as String,
      currency: planJson['currency'] as String? ?? 'INR',
      rules: ruleRows.map(PricingRule.fromJson).toList(),
    );
  }
}