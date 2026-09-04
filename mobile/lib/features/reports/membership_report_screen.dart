import 'package:flutter/material.dart';

import '../../data/models/analytics.dart';
import 'analytics_filter.dart';
import 'report_shell.dart';

/// Reports → Membership Report. Phase 9.1 ships the shell + filter; the report body
/// lands in a later phase.
class MembershipReportScreen extends StatefulWidget {
  const MembershipReportScreen({super.key, this.initialQuery = const {}});

  final Map<String, String> initialQuery;

  @override
  State<MembershipReportScreen> createState() => _MembershipReportScreenState();
}

class _MembershipReportScreenState extends State<MembershipReportScreen> {
  late AnalyticsFilter _filter = analyticsFilterFromQuery(widget.initialQuery);

  @override
  Widget build(BuildContext context) {
    return ReportShell(
      title: 'Membership Report',
      status: ReportStatus.empty,
      filter: _filter,
      onFilterChanged: (f) => setState(() => _filter = f),
      onRetry: () => setState(() {}),
      emptyMessage: 'The Membership report lands in a later update.',
      body: const SizedBox.shrink(),
    );
  }
}
