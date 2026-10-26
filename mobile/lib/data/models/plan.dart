// GameAll's own plans (Basic / Advanced) — migration 0157. Mirrors src/features/plans on the web.

const autoPayFeature = 'AUTOPAY';

/// One plan on offer (list_plans).
class PlanOption {
  const PlanOption({
    required this.code,
    required this.name,
    required this.description,
    required this.monthlyMinor,
    required this.yearlyMinor,
    required this.features,
    required this.isPopular,
    required this.trialDays,
  });

  final String code;
  final String name;
  final String? description;
  final int monthlyMinor;
  final int yearlyMinor;
  final List<String> features;
  final bool isPopular;
  final int trialDays;

  int priceFor(bool yearly) => yearly ? yearlyMinor : monthlyMinor;

  /// What paying yearly saves compared with twelve months.
  int get yearlySavingMinor => (monthlyMinor * 12 - yearlyMinor).clamp(0, 1 << 30);

  factory PlanOption.fromJson(Map<String, dynamic> j) => PlanOption(
        code: j['code'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        monthlyMinor: (j['monthly_minor'] as num).toInt(),
        yearlyMinor: (j['yearly_minor'] as num).toInt(),
        features: ((j['features'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
        isPopular: j['is_popular'] == true,
        trialDays: (j['trial_days'] as num?)?.toInt() ?? 0,
      );
}

/// What the club's plan grants right now (my_facility_plan). A club with no plan has none — and is unrestricted.
class PlanSnapshot {
  const PlanSnapshot({
    required this.planCode,
    required this.effectiveCode,
    required this.name,
    required this.status,
    required this.interval,
    required this.priceMinor,
    required this.validTill,
    required this.onTrial,
    required this.lapsed,
    required this.daysLeft,
    required this.features,
    required this.pageKeys,
  });

  final String planCode;

  /// The plan whose rules apply today — Basic once a chosen plan has lapsed.
  final String effectiveCode;
  final String name;
  final String status;
  final String interval;
  final int priceMinor;
  final String validTill;
  final bool onTrial;
  final bool lapsed;
  final int daysLeft;
  final Set<String> features;
  final Set<String> pageKeys;

  bool includesPage(String page) => pageKeys.contains(page);
  bool hasFeature(String feature) => features.contains(feature);

  factory PlanSnapshot.fromJson(Map<String, dynamic> j) => PlanSnapshot(
        planCode: j['planCode'] as String,
        effectiveCode: j['effectiveCode'] as String,
        name: (j['name'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'active',
        interval: (j['interval'] as String?) ?? 'month',
        priceMinor: (j['priceMinor'] as num?)?.toInt() ?? 0,
        validTill: j['validTill'] as String,
        onTrial: j['onTrial'] == true,
        lapsed: j['lapsed'] == true,
        daysLeft: (j['daysLeft'] as num?)?.toInt() ?? 0,
        features: ((j['features'] as List<dynamic>?) ?? const []).map((e) => '$e').toSet(),
        pageKeys: ((j['pageKeys'] as List<dynamic>?) ?? const []).map((e) => '$e').toSet(),
      );
}

/// The server's answer to "start this plan" (create-plan-subscription, action "start").
class PlanCheckoutInfo {
  const PlanCheckoutInfo({
    required this.subscriptionId,
    required this.keyId,
    required this.planName,
    required this.interval,
    required this.firstChargeOn,
    required this.trial,
  });

  final String subscriptionId;
  final String keyId;
  final String planName;
  final String interval;
  final String? firstChargeOn;
  final bool trial;

  factory PlanCheckoutInfo.fromJson(Map<String, dynamic> j) => PlanCheckoutInfo(
        subscriptionId: j['subscriptionId'] as String,
        keyId: j['keyId'] as String,
        planName: (j['planName'] as String?) ?? '',
        interval: (j['interval'] as String?) ?? 'month',
        firstChargeOn: j['firstChargeOn'] as String?,
        trial: j['trial'] == true,
      );
}
