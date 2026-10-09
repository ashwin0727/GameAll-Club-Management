import 'package:flutter/material.dart';

import '../../data/models/membership.dart';

// How a membership plan reads in the Plans list and on Plan Details — labels, the sport shown, filter
// and sort. Pure so the rules are tested rather than eyeballed.

int _months(int durationDays) => (durationDays / 30).round();

/// The unit after a plan's price: "/ month", "/ 3 months", "/ year", "/ 15 days".
String planPeriodLabel(int durationDays) {
  if (durationDays < 30) return '/ $durationDays ${durationDays == 1 ? 'day' : 'days'}';
  final months = _months(durationDays);
  if (months == 1) return '/ month';
  if (months == 12) return '/ year';
  if (months % 12 == 0) return '/ ${months ~/ 12} years';
  return '/ $months months';
}

/// "1 Month", "3 Months", "1 Year", "15 Days" — the plan's length on the Overview.
String planDurationLabel(int durationDays) {
  if (durationDays < 30) return '$durationDays ${durationDays == 1 ? 'Day' : 'Days'}';
  final months = _months(durationDays);
  if (months % 12 == 0) {
    final years = months ~/ 12;
    return '$years ${years == 1 ? 'Year' : 'Years'}';
  }
  return '$months ${months == 1 ? 'Month' : 'Months'}';
}

/// What a longer plan works out to per month, or null for a plan of a month or less.
int? planMonthlyEquivalentInr(int priceInr, int durationDays) {
  final months = _months(durationDays);
  if (months <= 1) return null;
  return (priceInr / months).round();
}

/// The sport / kind shown under a plan's name: its own category, else the sport of the session slots
/// attached to it, else null.
String? planSportLabel(MembershipPlan plan, List<AssignableBatch> planBatches) {
  final category = plan.category?.trim();
  if (category != null && category.isNotEmpty) return category;
  final sports = <String>{
    for (final b in planBatches)
      if (b.sportName.isNotEmpty) b.sportName,
  };
  if (sports.isEmpty) return null;
  return sports.length == 1 ? sports.first : 'Multi Sport';
}

/// A stand-in for the plan photo (plans don't store one): a sport icon where the name or category
/// names one, else a generic membership card.
IconData planIcon(MembershipPlan plan) {
  final text = '${plan.category ?? ''} ${plan.name}'.toLowerCase();
  if (text.contains('badminton') || text.contains('tennis') || text.contains('squash') || text.contains('table')) {
    return Icons.sports_tennis_rounded;
  }
  if (text.contains('football') || text.contains('futsal') || text.contains('soccer')) return Icons.sports_soccer_rounded;
  if (text.contains('cricket')) return Icons.sports_cricket_rounded;
  if (text.contains('basket')) return Icons.sports_basketball_rounded;
  if (text.contains('swim') || text.contains('pool')) return Icons.pool_rounded;
  if (text.contains('fitness') || text.contains('gym')) return Icons.fitness_center_rounded;
  if (text.contains('multi')) return Icons.sports_handball_rounded;
  return Icons.card_membership_rounded;
}

enum PlanFilter { all, active, inactive }

enum PlanSort {
  priceLow('Price: Low to High'),
  priceHigh('Price: High to Low'),
  name('Name (A–Z)'),
  mostMembers('Most members');

  const PlanSort(this.label);
  final String label;
}

/// How many plans each filter chip would show.
({int all, int active, int inactive}) planFilterCounts(List<MembershipPlan> plans) => (
      all: plans.length,
      active: plans.where((p) => p.isActive).length,
      inactive: plans.where((p) => !p.isActive).length,
    );

/// Plans narrowed by status and by a search over name and sport.
List<MembershipPlan> filterPlans(List<MembershipPlan> plans, {PlanFilter filter = PlanFilter.all, String query = ''}) {
  final q = query.trim().toLowerCase();
  return plans.where((p) {
    if (filter == PlanFilter.active && !p.isActive) return false;
    if (filter == PlanFilter.inactive && p.isActive) return false;
    if (q.isEmpty) return true;
    return p.name.toLowerCase().contains(q) || (p.category ?? '').toLowerCase().contains(q);
  }).toList();
}

List<MembershipPlan> sortPlans(List<MembershipPlan> plans, PlanSort sort, {int Function(MembershipPlan)? memberCount}) {
  final out = [...plans];
  switch (sort) {
    case PlanSort.priceLow:
      out.sort((a, b) => a.priceInr.compareTo(b.priceInr));
    case PlanSort.priceHigh:
      out.sort((a, b) => b.priceInr.compareTo(a.priceInr));
    case PlanSort.name:
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case PlanSort.mostMembers:
      final count = memberCount ?? (_) => 0;
      out.sort((a, b) => count(b).compareTo(count(a)));
  }
  return out;
}
