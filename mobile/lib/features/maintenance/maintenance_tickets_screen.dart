import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/maintenance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'maintenance_format.dart';
import 'maintenance_status_chips.dart';

/// Maintenance → Maintenance Tickets — mirrors
/// src/features/maintenance/components/maintenance-tickets-page.tsx.
class MaintenanceTicketsScreen extends ConsumerStatefulWidget {
  const MaintenanceTicketsScreen({super.key});

  @override
  ConsumerState<MaintenanceTicketsScreen> createState() => _MaintenanceTicketsScreenState();
}

class _MaintenanceTicketsScreenState extends ConsumerState<MaintenanceTicketsScreen> {
  List<MaintenanceTicketListRow>? _tickets;
  String? _error;
  bool _loading = true;
  String _search = '';
  String? _statusFilter;

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
      final result = await ref.read(maintenanceRepositoryProvider).listTickets(
            facility.id,
            search: _search,
            status: _statusFilter,
            limit: 50,
          );
      if (!mounted) return;
      setState(() {
        _tickets = result.tickets;
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
      appBar: AppBar(title: const Text('Maintenance Tickets')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await context.push(AppRoutes.maintenanceTicketNew);
          if (mounted) _load();
        },
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(hintText: 'Search tickets, court…', prefixIcon: Icon(Icons.search), isDense: true),
                    onSubmitted: (v) {
                      _search = v;
                      _load();
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _FilterChip(label: 'All', selected: _statusFilter == null, onTap: () => _applyStatus(null)),
                        for (final s in MaintenanceStatus.values)
                          Padding(
                            padding: const EdgeInsets.only(left: AppSpacing.xs),
                            child: _FilterChip(label: s.label, selected: _statusFilter == s.toJson(), onTap: () => _applyStatus(s.toJson())),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? const _MaintenanceTicketsSkeleton()
                    : _error != null
                        ? ErrorView(message: _error!, onRetry: _load)
                        : (_tickets == null || _tickets!.isEmpty)
                            ? const EmptyStateView(message: 'No maintenance tickets match this filter.')
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                                itemCount: _tickets!.length,
                                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (context, i) => _TicketCard(
                                  ticket: _tickets![i],
                                  onReturn: _load,
                                ),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyStatus(String? status) {
    setState(() => _statusFilter = status);
    _load();
  }
}

/// Structure-shaped placeholder shown while tickets load — mirrors the real
/// body's status filter-chip strip + ticket list.
class _MaintenanceTicketsSkeleton extends StatelessWidget {
  const _MaintenanceTicketsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      children: const [
        SkeletonChipRow(count: 5),
        SizedBox(height: AppSpacing.sm),
        Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: SkeletonListRow()),
        Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: SkeletonListRow()),
        Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: SkeletonListRow()),
        Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: SkeletonListRow()),
        SkeletonListRow(),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onReturn});
  final MaintenanceTicketListRow ticket;
  final Future<void> Function() onReturn;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () async {
        await context.push('${AppRoutes.maintenanceTickets}/${ticket.ticketId}');
        onReturn();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${ticket.code} · ${ticket.courtName}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              priorityBadge(ticket.priority),
            ],
          ),
          const SizedBox(height: 4),
          Text(ticket.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(
            children: [
              maintenanceStatusBadge(ticket.status),
              const Spacer(),
              Text(ticket.assignedToName ?? 'Unassigned', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (ticket.actualCostMinor != null || ticket.estimatedCostMinor != null) ...[
            const SizedBox(height: 4),
            Text(maintenanceAmount(ticket.actualCostMinor ?? ticket.estimatedCostMinor), style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
