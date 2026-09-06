/// Reports & Analytics — the filter model helpers (Phase 9.1).
///
/// Mirrors src/features/reports/url-state.ts + aggregation.ts. Nothing here
/// resolves a date boundary for the *server* (that is
/// resolve_finance_date_range's job) — these only decode a drill-down link's
/// query params, pick a readable chart granularity from a span, and name the
/// comparison window.
library;

import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/analytics.dart';

final _shortDate = DateFormat('d MMM');

/// "2026-09-01" -> "1 Sep". For trend/table date cells.
String reportDateShort(String iso) => _shortDate.format(DateTime.parse(iso));

/// Decode the query params a drill-down `context.push` carried (same keys as
/// the web: preset / from / to / sport / court). Unknown or half-formed
/// values fall back to the default.
AnalyticsFilter analyticsFilterFromQuery(Map<String, String> q) {
  AnalyticsPreset preset;
  try {
    preset = q['preset'] != null ? AnalyticsPreset.fromJson(q['preset']!) : AnalyticsPreset.thisMonth;
  } catch (_) {
    preset = AnalyticsPreset.thisMonth;
  }
  final from = q['from'];
  final to = q['to'];
  if (preset == AnalyticsPreset.custom && (from == null || to == null)) {
    preset = AnalyticsPreset.thisMonth;
  }
  return AnalyticsFilter(
    preset: preset,
    startDate: preset == AnalyticsPreset.custom ? from : null,
    endDate: preset == AnalyticsPreset.custom ? to : null,
    facilitySportId: q['sport'],
    courtId: q['court'],
  );
}

/// Encode a filter into query params for a drill-down link.
Map<String, String> analyticsFilterToQuery(AnalyticsFilter f) {
  return {
    'preset': f.preset.toJson(),
    if (f.preset == AnalyticsPreset.custom && f.startDate != null) 'from': f.startDate!,
    if (f.preset == AnalyticsPreset.custom && f.endDate != null) 'to': f.endDate!,
    if (f.facilitySportId != null) 'sport': f.facilitySportId!,
    if (f.courtId != null) 'court': f.courtId!,
  };
}

const _presetSpanDays = <AnalyticsPreset, int>{
  AnalyticsPreset.today: 1,
  AnalyticsPreset.yesterday: 1,
  AnalyticsPreset.thisWeek: 7,
  AnalyticsPreset.lastWeek: 7,
  AnalyticsPreset.thisMonth: 31,
  AnalyticsPreset.lastMonth: 31,
  AnalyticsPreset.thisQuarter: 92,
  AnalyticsPreset.thisYear: 365,
};

int analyticsFilterSpanDays(AnalyticsFilter f) {
  if (f.preset == AnalyticsPreset.custom) {
    final s = f.startDate, e = f.endDate;
    if (s == null || e == null) return 31;
    return DateTime.parse(e).difference(DateTime.parse(s)).inDays + 1;
  }
  return _presetSpanDays[f.preset]!;
}

/// Readable chart buckets: daily <=31d, weekly <=183d, monthly beyond
/// (web spec §31).
RevenueTrendGranularity pickAnalyticsGranularity(AnalyticsFilter f) {
  final days = analyticsFilterSpanDays(f);
  if (days <= 31) return RevenueTrendGranularity.daily;
  if (days <= 183) return RevenueTrendGranularity.weekly;
  return RevenueTrendGranularity.monthly;
}

const _priorPreset = <AnalyticsPreset, AnalyticsPreset>{
  AnalyticsPreset.today: AnalyticsPreset.yesterday,
  AnalyticsPreset.thisWeek: AnalyticsPreset.lastWeek,
  AnalyticsPreset.thisMonth: AnalyticsPreset.lastMonth,
};

/// The equal-length window immediately before this one, for "vs previous
/// period". Only the three rolling presets map cleanly; everything else
/// returns null and the delta is suppressed (web spec §27).
AnalyticsFilter? previousAnalyticsPeriod(AnalyticsFilter f) {
  final mapped = _priorPreset[f.preset];
  if (mapped != null) {
    return AnalyticsFilter(
      preset: mapped,
      facilitySportId: f.facilitySportId,
      courtId: f.courtId,
    );
  }
  if (f.preset == AnalyticsPreset.custom && f.startDate != null && f.endDate != null) {
    final start = DateTime.parse(f.startDate!);
    final end = DateTime.parse(f.endDate!);
    final days = end.difference(start).inDays + 1;
    final prevEnd = start.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: days - 1));
    return AnalyticsFilter(
      preset: AnalyticsPreset.custom,
      startDate: _iso(prevStart),
      endDate: _iso(prevEnd),
      facilitySportId: f.facilitySportId,
      courtId: f.courtId,
    );
  }
  return null;
}

double? analyticsChangePct({required num current, required num previous}) {
  if (previous == 0) return null;
  return ((current - previous) / previous.abs() * 1000).round() / 10;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 18 -> "6 PM".
String formatHourLabel(int hour) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12 ${hour < 12 ? 'AM' : 'PM'}';
}

/// Minutes -> "12.5 h".
String formatHours(int minutes) => '${(minutes / 60).toStringAsFixed(1)} h';

/// Minor units (paise) -> "₹1,234" via the app's whole-rupee formatter. The
/// /100 is a display unit conversion only — the value shown is still exactly
/// what the server returned. Mirrors financeAmount in finance_presentation.dart.
String analyticsAmount(int amountMinor) => Formatters.currencyInr((amountMinor / 100).round());
