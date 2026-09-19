import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/maintenance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../reports/report_section_header.dart';
import '../reports/report_widgets.dart';
import '../../shared/widgets/skeleton.dart';
import 'maintenance_format.dart';
import 'maintenance_status_chips.dart';

/// Maintenance → Overview — mirrors
/// src/features/maintenance/components/maintenance-overview-page.tsx.
class MaintenanceOverviewScreen extends ConsumerStatefulWidget {
  const MaintenanceOverviewScreen({super.key});

  @override
  ConsumerState<MaintenanceOverviewScreen> createState() => _MaintenanceOverviewScreenState();
}

class _MaintenanceOverviewScreenState extends ConsumerState<MaintenanceOverviewScreen> {
  MaintenanceOverview? _overview;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await ref.read(maintenanceRepositoryProvider).getOverview(facility.id);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Court Maintenance', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: Material(
        color: tokens.primary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: () async {
            await context.push(AppRoutes.maintenanceTicketNew);
            if (mounted) _load();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: [
                BoxShadow(
                  color: tokens.primary.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: tokens.onAccent(tokens.primary)),
                const SizedBox(width: 6),
                Text('New Ticket',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: tokens.onAccent(tokens.primary))),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const _MaintenanceOverviewSkeleton()
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : _overview == null
                      ? const EmptyStateView(message: 'No maintenance data yet.')
                      : _buildBody(_overview!),
        ),
      ),
    );
  }

  Widget _buildBody(MaintenanceOverview o) {
    final tokens = context.tokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxxl),
      children: [
        // Each tile gets its own accent, same as the dashboard/reports —
        // six tiles, six distinct colours, scans at a glance.
        ReportKpiGrid(items: [
          ReportKpi(
              label: 'Open Issues',
              value: '${o.openIssues}',
              icon: Icons.error_outline_rounded,
              accent: tokens.destructive),
          ReportKpi(
              label: 'In Progress',
              value: '${o.inProgress}',
              icon: Icons.autorenew_rounded,
              accent: tokens.warning),
          ReportKpi(
              label: 'Scheduled',
              value: '${o.scheduled}',
              icon: Icons.event_available_outlined,
              accent: tokens.electricBlue),
          ReportKpi(
              label: 'Resolved This Month',
              value: '${o.resolvedThisMonth}',
              icon: Icons.check_circle_outline_rounded,
              accent: tokens.success),
          ReportKpi(
              label: 'Courts Blocked',
              value: '${o.courtsBlocked}',
              icon: Icons.block_rounded,
              accent: tokens.violet),
          ReportKpi(
              label: 'Repair Cost',
              value: maintenanceAmount(o.repairCostThisMonthMinor),
              icon: Icons.build_outlined,
              accent: tokens.primary),
        ]),
        const SizedBox(height: AppSpacing.xl),
        const ReportSectionHeader(title: 'Court Status'),
        const SizedBox(height: AppSpacing.sm),
        // Two tiles per row, each Expanded — a lone tile in the last row
        // then stretches to fill the width instead of leaving a bare gap
        // beside it (what a fixed-width Wrap did with an odd count).
        for (var i = 0; i < o.courtStatus.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: _courtStatusTile(o.courtStatus[i])),
                if (i + 1 < o.courtStatus.length) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _courtStatusTile(o.courtStatus[i + 1])),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        ReportSectionHeader(
          title: 'Maintenance Tickets',
          trailing: TextButton(
              onPressed: () async {
                await context.push(AppRoutes.maintenanceTickets);
                if (mounted) _load();
              },
              child: const Text('View all')),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (o.recentTickets.isEmpty)
          _EmptyRow(
            icon: Icons.build_circle_outlined,
            color: tokens.textSecondary,
            message: 'No maintenance tickets yet.',
          )
        else
          for (final t in o.recentTickets) _ticketRow(t),
      ],
    );
  }

  Color _courtStatusColor(AppColorTokens tokens, CourtMaintenanceStatus s) => switch (s) {
        CourtMaintenanceStatus.available => tokens.success,
        CourtMaintenanceStatus.inUse => tokens.info,
        CourtMaintenanceStatus.underMaintenance => tokens.destructive,
        CourtMaintenanceStatus.blocked => tokens.textSecondary,
      };

  IconData _courtStatusIcon(CourtMaintenanceStatus s) => switch (s) {
        CourtMaintenanceStatus.available => Icons.check_circle_outline_rounded,
        CourtMaintenanceStatus.inUse => Icons.sports_tennis_rounded,
        CourtMaintenanceStatus.underMaintenance => Icons.build_rounded,
        CourtMaintenanceStatus.blocked => Icons.block_rounded,
      };

  Widget _courtStatusTile(CourtMaintenanceStatusRow c) {
    final tokens = context.tokens;
    final color = _courtStatusColor(tokens, c.status);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accentFill(color),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(_courtStatusIcon(c.status), size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.courtName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                Text(c.sportName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
                const SizedBox(height: 6),
                courtStatusBadge(c.status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ticketRow(MaintenanceRecentTicket t) {
    final tokens = context.tokens;
    final tone = switch (t.status) {
      MaintenanceStatus.reported => StatusTone.danger,
      MaintenanceStatus.assigned => StatusTone.info,
      MaintenanceStatus.scheduled => StatusTone.warning,
      MaintenanceStatus.inProgress => StatusTone.info,
      MaintenanceStatus.resolved => StatusTone.success,
      MaintenanceStatus.closed => StatusTone.neutral,
    };
    final color = switch (tone) {
      StatusTone.success => tokens.success,
      StatusTone.warning => tokens.warning,
      StatusTone.danger => tokens.destructive,
      StatusTone.info => tokens.info,
      StatusTone.neutral => tokens.textSecondary,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await context.push('${AppRoutes.maintenanceTickets}/${t.ticketId}');
            if (mounted) _load();
          },
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: tokens.borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentFill(color),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.build_rounded, size: 17, color: color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      Text(t.courtName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: tokens.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusBadge(label: t.status.label, tone: tone),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder shown while the overview loads — mirrors the
/// real body's KPI grid + court status grid + recent tickets list.
class _MaintenanceOverviewSkeleton extends StatelessWidget {
  const _MaintenanceOverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxxl),
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: const [
            SkeletonStatTile(),
            SkeletonStatTile(),
            SkeletonStatTile(),
            SkeletonStatTile(),
            SkeletonStatTile(),
            SkeletonStatTile(),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSkeleton(width: 120, height: 16),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: const [
                Expanded(child: SkeletonCard(child: AppSkeleton(height: 56))),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: SkeletonCard(child: AppSkeleton(height: 56))),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        const AppSkeleton(width: 150, height: 16),
        const SizedBox(height: AppSpacing.sm),
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
          child: SkeletonListRow(),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
          child: SkeletonListRow(),
        ),
        const SkeletonListRow(),
      ],
    );
  }
}

/// A quiet "nothing here" row — an icon + message instead of a bare line of
/// grey text, matching the rest of the app's list screens.
class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.icon, required this.color, required this.message});

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
          ),
        ],
      ),
    );
  }
}
