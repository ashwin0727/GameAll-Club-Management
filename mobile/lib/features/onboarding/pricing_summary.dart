// The Pricing Summary shown at the end of the pricing step — same rules as the web's pricing-summary.tsx: a sport's
// own rate, each court/turf with its own pricing, and courts that charge exactly the same shown once.

/// One priced period, in rupees.
class SummaryPeriod {
  const SummaryPeriod({required this.dayType, required this.coversFullDay, this.startTime, this.endTime, required this.amountInr});

  final String dayType; // ALL_DAYS | WEEKDAYS | WEEKENDS
  final bool coversFullDay;
  final String? startTime;
  final String? endTime;
  final num amountInr;

  bool get isPriced => amountInr > 0;

  /// Two periods with the same signature charge the same.
  String get signature => '$dayType|${coversFullDay ? 'full' : '$startTime-$endTime'}|$amountInr';
}

class CustomizedArea {
  const CustomizedArea(this.name, this.periods);
  final String name;
  final List<SummaryPeriod> periods;
}

class CustomizedGroup {
  const CustomizedGroup(this.areaNames, this.periods);
  final List<String> areaNames;
  final List<SummaryPeriod> periods;
}

String _signatureOf(List<SummaryPeriod> periods) => (periods.where((p) => p.isPriced).map((p) => p.signature).toList()..sort()).join(';');

/// Courts / turfs that charge exactly the same become one group ("Court 1, Court 2"); first-appearance order is kept.
List<CustomizedGroup> groupCustomized(List<CustomizedArea> areas) {
  final groups = <String, CustomizedGroup>{};
  for (final a in areas) {
    final key = _signatureOf(a.periods);
    final existing = groups[key];
    if (existing != null) {
      existing.areaNames.add(a.name);
    } else {
      groups[key] = CustomizedGroup([a.name], a.periods);
    }
  }
  return groups.values.toList();
}

/// "6:00 AM" from "06:00".
String _hour12(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
  return '${h % 12 == 0 ? 12 : h % 12}:$m ${h < 12 ? 'AM' : 'PM'}';
}

String periodLabel(SummaryPeriod p) {
  const day = {'ALL_DAYS': 'All days', 'WEEKDAYS': 'Weekdays', 'WEEKENDS': 'Weekends'};
  final window = p.coversFullDay ? 'Full day' : '${_hour12(p.startTime ?? '06:00')} – ${_hour12(p.endTime ?? '23:00')}';
  return '${day[p.dayType] ?? p.dayType} · $window';
}

/// One line per distinct block to show for a sport: its default (unless every court is customized), then each
/// group of customized courts.
class SportSummaryBlock {
  const SportSummaryBlock({required this.title, required this.periods, this.indented = false});
  final String? title; // null = the sport's own default rate
  final List<SummaryPeriod> periods;
  final bool indented;
}

/// What to show under one sport. [areaLabel] is "Court" / "Turf" / "Playing Area".
List<SportSummaryBlock> sportSummaryBlocks({
  required List<SummaryPeriod> defaults,
  required List<CustomizedArea> customized,
  required int areaCount,
  required String areaLabel,
}) {
  final blocks = <SportSummaryBlock>[];
  final allCustomized = areaCount > 0 && customized.length >= areaCount;
  if (!allCustomized) {
    blocks.add(SportSummaryBlock(title: null, periods: defaults.where((p) => p.isPriced).toList()));
  }
  for (final g in groupCustomized(customized)) {
    final coversAll = allCustomized && g.areaNames.length == areaCount && areaCount > 1;
    blocks.add(SportSummaryBlock(
      title: coversAll ? 'All $areaCount ${areaLabel}s' : '${g.areaNames.join(', ')} · custom',
      periods: g.periods.where((p) => p.isPriced).toList(),
      indented: !coversAll,
    ));
  }
  return blocks;
}
