/// Reports & Analytics — the hub (Phase 9.1).
///
/// The web reaches its six reports through a sidebar section; mobile has no
/// sidebar, so `/reports` is a hub of six cards. Each card carries the
/// current facility into its report (via RLS the report re-checks anyway).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/app_card.dart';

class _ReportLink {
  const _ReportLink(this.icon, this.title, this.subtitle, this.route);
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

const _links = <_ReportLink>[
  _ReportLink(Icons.insights_outlined, 'Overview', 'Business performance at a glance', AppRoutes.reportsOverview),
  _ReportLink(Icons.event_note_outlined, 'Bookings', 'Volume, status mix and demand by sport', AppRoutes.reportsBookings),
  _ReportLink(Icons.donut_small_outlined, 'Court Utilization', 'How hard each court is working', AppRoutes.reportsCourtUtilization),
  _ReportLink(Icons.trending_up_outlined, 'Revenue', 'Trend, breakdown and payment methods', AppRoutes.reportsRevenue),
  _ReportLink(Icons.workspace_premium_outlined, 'Memberships', 'Members, sessions and released capacity', AppRoutes.reportsMemberships),
  _ReportLink(Icons.event_available_outlined, 'Guest Bookings', 'Guest volume, value and collection', AppRoutes.reportsGuestBookings),
];

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Analytics')),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _links.length,
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          final link = _links[i];
          return AppCard(
            onTap: () => context.push(link.route),
            child: Row(
              children: [
                Icon(link.icon, size: 28),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(link.title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(link.subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          );
        },
      ),
    );
  }
}
