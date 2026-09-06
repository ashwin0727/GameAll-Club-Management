import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/maintenance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'maintenance_format.dart';
import 'maintenance_status_chips.dart';

/// Maintenance → Ticket Details — mirrors
/// src/features/maintenance/components/ticket-detail-page.tsx. Actions are
/// context-aware: only transitions valid for the current status are shown.
class MaintenanceTicketDetailScreen extends ConsumerStatefulWidget {
  const MaintenanceTicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<MaintenanceTicketDetailScreen> createState() => _MaintenanceTicketDetailScreenState();
}

class _MaintenanceTicketDetailScreenState extends ConsumerState<MaintenanceTicketDetailScreen> {
  MaintenanceTicketDetail? _ticket;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(maintenanceRepositoryProvider).getTicketDetail(widget.ticketId);
      if (mounted) setState(() => _ticket = t);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      await _load();
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return Scaffold(
      appBar: AppBar(title: Text(t?.code ?? 'Maintenance Ticket')),
      body: SafeArea(
        child: _error != null && t == null
            ? ErrorView(message: _error!, onRetry: _load)
            : t == null
                ? const LoadingView()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(t.title, style: Theme.of(context).textTheme.titleMedium)),
                            priorityBadge(t.priority),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${t.courtName} · ${t.sportName ?? '—'} · ${t.categoryName}', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: AppSpacing.sm),
                        maintenanceStatusBadge(t.status),
                        const SizedBox(height: AppSpacing.lg),

                        SectionHeader(title: 'Issue Information'),
                        const SizedBox(height: AppSpacing.sm),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row('Reported By', t.reportedByName),
                              _row('Reported On', maintenanceDateTime(t.reportedAt)),
                              _row('Assigned To', t.assignedToName ?? 'Unassigned'),
                              const SizedBox(height: AppSpacing.sm),
                              Text('Description', style: Theme.of(context).textTheme.bodySmall),
                              Text(t.description),
                              if (t.notes != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Text('Notes', style: Theme.of(context).textTheme.bodySmall),
                                Text(t.notes!),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        SectionHeader(title: 'Schedule'),
                        const SizedBox(height: AppSpacing.sm),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row('Scheduled Start', maintenanceDateTime(t.scheduledStart)),
                              _row('Scheduled End', maintenanceDateTime(t.scheduledEnd)),
                              _row('Actual Start', maintenanceDateTime(t.actualStart)),
                              _row('Actual End', maintenanceDateTime(t.actualEnd)),
                            ],
                          ),
                        ),

                        if (t.affectedBookings.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          SectionHeader(title: 'Affected Bookings'),
                          const SizedBox(height: AppSpacing.sm),
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final b in t.affectedBookings)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Text(
                                      '${b.customerType == 'GUEST' ? (b.guestName ?? 'Guest') : 'Member'} · ${maintenanceDateTime(b.startTime)} · ${b.status} / ${b.paymentStatus}',
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'Reschedule, cancel or refund these from the Bookings page — Maintenance never changes a booking automatically.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: AppSpacing.lg),
                        SectionHeader(title: 'Cost'),
                        const SizedBox(height: AppSpacing.sm),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row('Estimated', maintenanceAmount(t.estimatedCostMinor)),
                              _row('Actual', maintenanceAmount(t.actualCostMinor)),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppSpacing.lg),
                        SectionHeader(title: 'Activity'),
                        const SizedBox(height: AppSpacing.sm),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final e in t.activity)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_activityLabel(e.eventType), style: const TextStyle(fontWeight: FontWeight.w600)),
                                      if (e.note != null) Text(e.note!),
                                      Text(
                                        '${maintenanceDateTime(e.createdAt)}${e.actorName != null ? ' · ${e.actorName}' : ''}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 96),
                      ],
                    ),
                  ),
      ),
      bottomNavigationBar: t == null ? null : _actionBar(t),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );

  Widget _actionBar(MaintenanceTicketDetail t) {
    final repo = ref.read(maintenanceRepositoryProvider);
    final actions = <({String label, VoidCallback onTap})>[];

    if (t.status == MaintenanceStatus.reported || t.status == MaintenanceStatus.assigned) {
      actions.add((label: 'Assign', onTap: () => _assignSheet(t)));
      actions.add((label: 'Schedule', onTap: () => _scheduleSheet(t)));
    }
    if (t.status == MaintenanceStatus.scheduled || t.status == MaintenanceStatus.assigned) {
      actions.add((label: 'Start', onTap: () => _run(() => repo.startMaintenance(t.id))));
    }
    if (t.status == MaintenanceStatus.inProgress) {
      actions.add((label: 'Add Cost', onTap: () => _costSheet(t)));
      actions.add((label: 'Resolve', onTap: () => _run(() => repo.resolveTicket(t.id))));
    }
    if (t.status == MaintenanceStatus.resolved) {
      actions.add((label: 'Reopen', onTap: () => _run(() => repo.reopenTicket(t.id))));
      actions.add((label: 'Close', onTap: () => _run(() => repo.closeTicket(t.id))));
    }
    if (t.status != MaintenanceStatus.closed && t.status != MaintenanceStatus.resolved) {
      actions.add((label: 'Close', onTap: () => _run(() => repo.closeTicket(t.id))));
    }
    if (actions.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final a in actions)
              OutlinedButton(onPressed: _busy ? null : a.onTap, child: Text(a.label)),
          ],
        ),
      ),
    );
  }

  Future<void> _assignSheet(MaintenanceTicketDetail t) async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    final staff = await ref.read(maintenanceRepositoryProvider).listAssignableStaff(facility.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in staff)
              ListTile(
                title: Text(s.fullName),
                subtitle: Text(s.role),
                onTap: () {
                  Navigator.pop(ctx);
                  _run(() => ref.read(maintenanceRepositoryProvider).assignTicket(t.id, s.userId));
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _scheduleSheet(MaintenanceTicketDetail t) async {
    var start = t.scheduledStart ?? DateTime.now().add(const Duration(hours: 1));
    var end = t.scheduledEnd ?? DateTime.now().add(const Duration(hours: 4));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Schedule Maintenance', style: Theme.of(ctx).textTheme.titleMedium),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start'),
                subtitle: Text(start.toLocal().toString().substring(0, 16)),
                onTap: () async {
                  final d = await _pick(ctx, start);
                  if (d != null) setSheet(() => start = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End'),
                subtitle: Text(end.toLocal().toString().substring(0, 16)),
                onTap: () async {
                  final d = await _pick(ctx, end);
                  if (d != null) setSheet(() => end = d);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Block Court')),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      await _run(() => ref.read(maintenanceRepositoryProvider).scheduleMaintenance(t.id, start, end));
    }
  }

  Future<void> _costSheet(MaintenanceTicketDetail t) async {
    final actual = TextEditingController();
    var post = true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Repair Cost', style: Theme.of(ctx).textTheme.titleMedium),
              TextField(controller: actual, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Actual Cost (₹)')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Post to Finance → Expenses'),
                value: post,
                onChanged: (v) => setSheet(() => post = v),
              ),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
    if (ok == true && actual.text.isNotEmpty) {
      await _run(() => ref.read(maintenanceRepositoryProvider).updateCost(
            ticketId: t.id,
            actualCostMinor: ((double.tryParse(actual.text) ?? 0) * 100).round(),
            postToExpenses: post,
          ));
    }
    actual.dispose();
  }

  Future<DateTime?> _pick(BuildContext ctx, DateTime current) async {
    final date = await showDatePicker(context: ctx, initialDate: current, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null || !ctx.mounted) return null;
    final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _activityLabel(String eventType) =>
      eventType.toLowerCase().split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}
