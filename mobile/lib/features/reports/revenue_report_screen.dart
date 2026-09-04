import 'package:flutter/material.dart';

import '../../data/models/analytics.dart';
import 'analytics_filter.dart';
import 'report_shell.dart';

/// Reports → Revenue Report. Phase 9.1 ships the shell + filter; the report body
/// lands in a later phase.
class RevenueReportScreen extends StatefulWidget {
  const RevenueReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  State<RevenueReportScreen> createState() => _RevenueReportScreenState();
}

class _RevenueReportScreenState extends State<RevenueReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  @override
  Widget build(BuildContext context) {
    return ReportShell(
      title: 'Revenue Report',
      status: ReportStatus.empty,
      filter: _filter,
      onFilterChanged: (f) => setState(() => _filter = f),
      onRetry: () => setState(() {}),
      emptyMessage: 'The Revenue report lands in a later update.',
      body: const SizedBox.shrink(),
    );
  }
}
