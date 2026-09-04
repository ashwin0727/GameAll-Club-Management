import 'package:flutter/material.dart';

import '../../data/models/analytics.dart';
import 'analytics_filter.dart';
import 'report_shell.dart';

/// Reports → Court Utilization. Phase 9.1 ships the shell + filter; the report body
/// lands in a later phase.
class CourtUtilizationReportScreen extends StatefulWidget {
  const CourtUtilizationReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  State<CourtUtilizationReportScreen> createState() => _CourtUtilizationReportScreenState();
}

class _CourtUtilizationReportScreenState extends State<CourtUtilizationReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  @override
  Widget build(BuildContext context) {
    return ReportShell(
      title: 'Court Utilization',
      status: ReportStatus.empty,
      filter: _filter,
      onFilterChanged: (f) => setState(() => _filter = f),
      onRetry: () => setState(() {}),
      emptyMessage: 'The Court Utilization report lands in a later update.',
      body: const SizedBox.shrink(),
    );
  }
}
