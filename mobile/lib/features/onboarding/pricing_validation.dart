/// Port of src/features/pricing/validation.ts — amount + time-window +
/// same-scope overlap checks, plus the operating-hours compatibility
/// cross-check (the backend RPC does not enforce this itself; web only
/// validates it client-side, so mobile mirrors that exactly).
library;
import '../../data/models/operating_hours.dart';

final RegExp _timeRe = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

int _toMinutes(String time) {
  final parts = time.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
  return h * 60 + m;
}

String? validatePriceAmount(int amountMinor) {
  if (amountMinor <= 0) return 'Amount must be greater than 0.';
  return null;
}

/// A single pricing period as edited in the UI, before conversion to a
/// PricingRule payload.
class PricingPeriodDraft {
  PricingPeriodDraft({
    required this.dayType,
    required this.coversFullDay,
    this.startTime,
    this.endTime,
    required this.amountMinor,
  });

  String dayType; // ALL_DAYS | WEEKDAYS | WEEKENDS
  bool coversFullDay;
  String? startTime;
  String? endTime;
  int amountMinor;
}

String? validatePricingPeriod(PricingPeriodDraft period) {
  final amountError = validatePriceAmount(period.amountMinor);
  if (amountError != null) return amountError;
  if (period.coversFullDay) return null;
  final start = period.startTime;
  final end = period.endTime;
  if (start == null || !_timeRe.hasMatch(start)) return 'Start time is required.';
  if (end == null || !_timeRe.hasMatch(end)) return 'End time is required.';
  if (start == end) return 'Start and end time cannot be the same.';
  return null;
}

/// Returns true if any two time-windowed periods sharing the same day-type
/// overlap within the given list (a single sport-or-area scope's periods).
bool hasOverlappingPricingPeriods(List<PricingPeriodDraft> periods) {
  final byDayType = <String, List<({int start, int end})>>{};
  for (final period in periods) {
    if (period.coversFullDay || period.startTime == null || period.endTime == null) continue;
    var start = _toMinutes(period.startTime!);
    var end = _toMinutes(period.endTime!);
    if (end <= start) end += 24 * 60;
    (byDayType[period.dayType] ??= []).add((start: start, end: end));
  }
  for (final intervals in byDayType.values) {
    for (var i = 0; i < intervals.length; i++) {
      for (var j = i + 1; j < intervals.length; j++) {
        final a = intervals[i];
        final b = intervals[j];
        if (a.start < b.end && b.start < a.end) return true;
      }
    }
  }
  return false;
}

/// Which days of week a pricing day-type covers, for the operating-hours
/// compatibility check.
List<int> _dayNumbersFor(String dayType) {
  if (dayType == 'WEEKDAYS') return [1, 2, 3, 4, 5];
  if (dayType == 'WEEKENDS') return [0, 6];
  return [0, 1, 2, 3, 4, 5, 6];
}

bool _windowFitsSlot(PricingPeriodDraft period, OperatingTimeSlot slot) {
  final ruleStart = _toMinutes(period.startTime!);
  var ruleEnd = _toMinutes(period.endTime!);
  if (ruleEnd <= ruleStart) ruleEnd += 24 * 60;

  final slotStart = _toMinutes(slot.startTime);
  var slotEnd = _toMinutes(slot.endTime);
  if (slotEnd <= slotStart) slotEnd += 24 * 60;

  return ruleStart >= slotStart && ruleEnd <= slotEnd;
}

/// A pricing window must fall within at least one operating-hours slot on
/// every day it applies to (a full-day period just needs the facility to be
/// open at all that day). Returns a friendly message, or null if compatible.
String? validatePricingAgainstOperatingHours(PricingPeriodDraft period, List<OperatingDay> operatingDays) {
  for (final dow in _dayNumbersFor(period.dayType)) {
    final day = operatingDays.where((d) => d.dayOfWeek == dow).firstOrNull;
    if (day == null || day.isClosed) {
      return 'This pricing period falls on a day the facility is closed.';
    }
    if (day.is24Hours) continue;
    if (period.coversFullDay) {
      if (day.slots.isEmpty) return 'This pricing period falls on a day the facility is closed.';
      continue;
    }
    final fits = day.slots.any((slot) => _windowFitsSlot(period, slot));
    if (!fits) return "Pricing hours must fall within your facility's operating hours.";
  }
  return null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}