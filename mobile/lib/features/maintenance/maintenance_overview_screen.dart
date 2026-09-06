import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/maintenance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../reports/report_widgets.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Court Maintenance')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.maintenanceTicketNew),
        icon: const Icon(Icons.add),
        label: const Text('New Ticket'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const LoadingView()
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
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        ReportKpiGrid(items: [
          ReportKpi(label: 'Open Issues', value: '${o.openIssues}'),
          ReportKpi(label: 'In Progress', value: '${o.inProgress}'),
          ReportKpi(label: 'Scheduled', value: '${o.scheduled}'),
          ReportKpi(label: 'Resolved This Month', value: '${o.resolvedThisMonth}'),
          ReportKpi(label: 'Courts Blocked', value: '${o.courtsBlocked}'),
          ReportKpi(label: 'Repair Cost', value: maintenanceAmount(o.repairCostThisMonthMinor)),
        ]),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(title: 'Court Status'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final c in o.courtStatus)
                SizedBox(
                  width: 150,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.courtName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(c.sportName ?? '', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        courtStatusBadge(c.status),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(title: 'Maintenance Tickets', trailing: TextButton(onPressed: () => context.push(AppRoutes.maintenanceTickets), child: const Text('View All'))),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: o.recentTickets.isEmpty
              ? Text('No maintenance tickets yet.', style: Theme.of(context).textTheme.bodyMedium)
              : ReportDataTable(
                  caption: 'Recent maintenance tickets',
                  columns: const [
                    ReportColumn(label: 'Court'),
                    ReportColumn(label: 'Issue'),
                    ReportColumn(label: 'Status'),
                  ],
                  rows: [for (final t in o.recentTickets) [t.courtName, t.title, t.status.label]],
                  onTapRow: (i) => context.push('${AppRoutes.maintenanceTickets}/${o.recentTickets[i].ticketId}'),
                ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
