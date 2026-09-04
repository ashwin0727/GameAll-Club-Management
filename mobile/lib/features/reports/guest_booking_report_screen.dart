import 'package:flutter/material.dart';

import '../../data/models/analytics.dart';
import 'analytics_filter.dart';
import 'report_shell.dart';

/// Reports → Guest Booking Report. Phase 9.1 ships the shell + filter; the report body
/// lands in a later phase.
class GuestBookingReportScreen extends StatefulWidget {
  const GuestBookingReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  State<GuestBookingReportScreen> createState() => _GuestBookingReportScreenState();
}

class _GuestBookingReportScreenState extends State<GuestBookingReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  @override
  Widget build(BuildContext context) {
    return ReportShell(
      title: 'Guest Booking Report',
      status: ReportStatus.empty,
      filter: _filter,
      onFilterChanged: (f) => setState(() => _filter = f),
      onRetry: () => setState(() {}),
      emptyMessage: 'The Guest Booking report lands in a later update.',
      body: const SizedBox.shrink(),
    );
  }
}
