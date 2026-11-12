enum SettlementFrequency { daily, weekly, monthly }

/// How and when a facility is paid out (`facility_payout_settings`, migration 0200).
class PayoutSettings {
  const PayoutSettings({
    this.frequency = SettlementFrequency.daily,
    this.minimumPayoutInr = 500,
    this.includeBookings = true,
    this.includeMemberships = true,
    this.includeCoaching = true,
    this.autoPayout = true,
    this.holdForReview = false,
  });

  static const int maxMinimumPayout = 1000000;

  final SettlementFrequency frequency;

  /// Whole rupees.
  final int minimumPayoutInr;
  final bool includeBookings;
  final bool includeMemberships;
  final bool includeCoaching;
  final bool autoPayout;
  final bool holdForReview;

  PayoutSettings copyWith({
    SettlementFrequency? frequency,
    int? minimumPayoutInr,
    bool? includeBookings,
    bool? includeMemberships,
    bool? includeCoaching,
    bool? autoPayout,
    bool? holdForReview,
  }) =>
      PayoutSettings(
        frequency: frequency ?? this.frequency,
        minimumPayoutInr: minimumPayoutInr ?? this.minimumPayoutInr,
        includeBookings: includeBookings ?? this.includeBookings,
        includeMemberships: includeMemberships ?? this.includeMemberships,
        includeCoaching: includeCoaching ?? this.includeCoaching,
        autoPayout: autoPayout ?? this.autoPayout,
        holdForReview: holdForReview ?? this.holdForReview,
      );

  /// What is wrong with these settings, or null when they can be saved. Same rules as the web.
  String? validate() {
    if (minimumPayoutInr < 0 || minimumPayoutInr > maxMinimumPayout) {
      return 'Enter a minimum payout between ₹0 and ₹10,00,000.';
    }
    if (!includeBookings && !includeMemberships && !includeCoaching) {
      return 'Choose at least one earning to include in your payouts.';
    }
    return null;
  }

  factory PayoutSettings.fromJson(Map<String, dynamic> j) => PayoutSettings(
        frequency: switch (j['settlement_frequency']) {
          'WEEKLY' => SettlementFrequency.weekly,
          'MONTHLY' => SettlementFrequency.monthly,
          _ => SettlementFrequency.daily,
        },
        minimumPayoutInr: (j['minimum_payout_inr'] as num?)?.toInt() ?? 500,
        includeBookings: j['include_bookings'] != false,
        includeMemberships: j['include_memberships'] != false,
        includeCoaching: j['include_coaching'] != false,
        autoPayout: j['auto_payout'] != false,
        holdForReview: j['hold_for_review'] == true,
      );

  Map<String, dynamic> toRow(String facilityId) => {
        'facility_id': facilityId,
        'settlement_frequency': switch (frequency) {
          SettlementFrequency.daily => 'DAILY',
          SettlementFrequency.weekly => 'WEEKLY',
          SettlementFrequency.monthly => 'MONTHLY',
        },
        'minimum_payout_inr': minimumPayoutInr,
        'include_bookings': includeBookings,
        'include_memberships': includeMemberships,
        'include_coaching': includeCoaching,
        'auto_payout': autoPayout,
        'hold_for_review': holdForReview,
      };
}

String frequencyLabel(SettlementFrequency f) => switch (f) {
      SettlementFrequency.daily => 'Daily (T+1)',
      SettlementFrequency.weekly => 'Weekly',
      SettlementFrequency.monthly => 'Monthly',
    };

String frequencyNote(SettlementFrequency f) => switch (f) {
      SettlementFrequency.daily => 'T+1 means the amount will be settled the next working day after a successful booking.',
      SettlementFrequency.weekly => 'Earnings are settled once a week, on the first working day, for the week before.',
      SettlementFrequency.monthly => 'Earnings are settled once a month, on the first working day, for the month before.',
    };
