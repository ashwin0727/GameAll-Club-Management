// GameAll's own plans (Basic / Advanced) — migration 0157. Mirrors src/features/plans on the web.
//
// The mobile app only READS the club's plan: it never sells one (Google Play billing rules). Plans are chosen and paid for on
// the web; a club created in the app is given the free trial directly (start_free_trial, migration 0163).

const autoPayFeature = 'AUTOPAY';

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
