/// Reports & Analytics — the hub (Phase 9.1).
///
/// The web reaches its six reports through a sidebar section; mobile has no
/// sidebar, so `/reports` is a hub of six cards. Each card carries the
/// current facility into its report (via RLS the report re-checks anyway).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/app_card.dart';

class _ReportLink {
  const _ReportLink(this.icon, this.title, this.subtitle, this.route, this.accent);
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  /// Each report gets its own accent so the hub scans quickly instead of
  /// six identical white-icon rows — same idea as the dashboard's quick
  /// action grid.
  final Color Function(AppColorTokens tokens) accent;
}

final _links = <_ReportLink>[
  _ReportLink(Icons.insights_outlined, 'Overview', 'Business performance at a glance',
      AppRoutes.reportsOverview, (t) => t.primary),
  _ReportLink(Icons.event_note_outlined, 'Bookings', 'Volume, status mix and demand by sport',
      AppRoutes.reportsBookings, (t) => t.electricBlue),
  _ReportLink(Icons.donut_small_outlined, 'Court Utilization', 'How hard each court is working',
      AppRoutes.reportsCourtUtilization, (t) => t.violet),
  _ReportLink(Icons.trending_up_outlined, 'Revenue', 'Trend, breakdown and payment methods',
      AppRoutes.reportsRevenue, (t) => t.success),
  _ReportLink(Icons.workspace_premium_outlined, 'Memberships', 'Members, sessions and released capacity',
      AppRoutes.reportsMemberships, (t) => t.warning),
  _ReportLink(Icons.event_available_outlined, 'Guest Bookings', 'Guest volume, value and collection',
      AppRoutes.reportsGuestBookings, (t) => t.destructive),
];

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _links.length,
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          final link = _links[i];
          final tokens = context.tokens;
          final color = link.accent(tokens);
          return AppCard(
            onTap: () => context.push(link.route),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentFill(color),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(link.icon, size: 26, color: color),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(link.title,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary)),
                      const SizedBox(height: 2),
                      Text(link.subtitle,
                          style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: tokens.textSecondary),
              ],
            ),
          );
        },
      ),
    );
  }
}
