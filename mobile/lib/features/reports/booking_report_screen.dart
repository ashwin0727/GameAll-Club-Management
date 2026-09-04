import 'package:flutter/material.dart';

import '../../data/models/analytics.dart';
import 'analytics_filter.dart';
import 'report_shell.dart';

/// Reports → Booking Report. Phase 9.1 ships the shell + filter; the report body
/// lands in a later phase.
class BookingReportScreen extends StatefulWidget {
  const BookingReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  State<BookingReportScreen> createState() => _BookingReportScreenState();
}

class _BookingReportScreenState extends State<BookingReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  @override
  Widget build(BuildContext context) {
    return ReportShell(
      title: 'Booking Report',
      status: ReportStatus.empty,
      filter: _filter,
      onFilterChanged: (f) => setState(() => _filter = f),
      onRetry: () => setState(() {}),
      emptyMessage: 'The Booking report lands in a later update.',
      body: const SizedBox.shrink(),
    );
  }
}
