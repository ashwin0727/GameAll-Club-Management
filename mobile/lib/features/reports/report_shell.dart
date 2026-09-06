/// Reports & Analytics — the shared screen scaffold (Phase 9.1).
///
/// Mirrors src/features/reports/components/report-shell.tsx: an AppBar, the
/// filter controls, and a body that switches between loading (skeleton),
/// error (retry), empty and ready so the three states are always distinct
/// and a figure never flashes as 0 mid-load (web spec §43/§44/§45).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/analytics.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'analytics_filter_controls.dart';

enum ReportStatus { loading, error, empty, ready }

/// A report screen built on this: it owns [filter] state, calls [onReload]
/// when the filter changes, and hands back a [status] + the ready body.
class ReportShell extends ConsumerWidget {
  const ReportShell({
    super.key,
    required this.title,
    required this.status,
    required this.filter,
    required this.onFilterChanged,
    required this.onRetry,
    required this.body,
    this.emptyMessage = 'No data for this period.',
    this.errorMessage = 'Unable to load this report. Please try again.',
  });

  final String title;
  final ReportStatus status;
  final AnalyticsFilter filter;
  final ValueChanged<AnalyticsFilter> onFilterChanged;
  final VoidCallback onRetry;
  final Widget body;
  final String emptyMessage;
  final String errorMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facility = ref.watch(sessionControllerProvider).facility;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: facility == null
          ? const EmptyStateView(message: 'No facility found for this account yet.')
          : RefreshIndicator(
              onRefresh: () async => onRetry(),
              child: ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnalyticsFilterControls(
                      facilityId: facility.id,
                      filter: filter,
                      onChanged: onFilterChanged,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    switch (status) {
                      ReportStatus.loading => const Padding(
                          padding: EdgeInsets.only(top: AppSpacing.xl),
                          child: LoadingView(),
                        ),
                      ReportStatus.error => Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xxl),
                          child: ErrorView(message: errorMessage, onRetry: onRetry),
                        ),
                      ReportStatus.empty => Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xxl),
                          child: EmptyStateView(message: emptyMessage),
                        ),
                      ReportStatus.ready => body,
                    },
                  ],
                ),
              ),
            ),
    );
  }
}
