/// Reports & Analytics — the shared date filter.
///
/// The mobile twin of the web `DayRangeFilter`: **From** and **To** dates with
/// an **Apply** button. Reports are facility-wide (the app has no sport
/// selector), so dates are the only scope. Controlled: it holds no filter
/// state beyond the dates being edited and calls [onChanged] on Apply.
library;

import 'package:flutter/material.dart';

import '../../data/models/analytics.dart';
import '../../data/models/finance.dart';
import '../finance/finance_date_range_picker.dart';

class AnalyticsFilterControls extends StatelessWidget {
  const AnalyticsFilterControls({
    super.key,
    required this.filter,
    required this.onChanged,
    this.trailing,
  });

  final AnalyticsFilter filter;
  final ValueChanged<AnalyticsFilter> onChanged;

  /// Sits beside Apply — e.g. an Export button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return FinanceDateRangePicker(
      value: FinanceDateRange(
        preset: FinanceDateRangePreset.custom,
        startDate: filter.startDate,
        endDate: filter.endDate,
      ),
      onChanged: (r) => onChanged(
        filter.copyWith(preset: AnalyticsPreset.custom, startDate: r.startDate, endDate: r.endDate),
      ),
      trailing: trailing,
    );
  }
}
