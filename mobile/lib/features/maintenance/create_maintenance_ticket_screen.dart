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
import 'maintenance_court_options.dart';

/// Maintenance → Create Ticket. Mobile uses one grouped, scrollable form
/// (spec §"structured form" alternative to a multi-step wizard) with the
/// same four sections as the web wizard: Issue Details, Schedule,
/// Assignment, Review.
class CreateMaintenanceTicketScreen extends ConsumerStatefulWidget {
  const CreateMaintenanceTicketScreen({super.key});

  @override
  ConsumerState<CreateMaintenanceTicketScreen> createState() => _CreateMaintenanceTicketScreenState();
}

class _CreateMaintenanceTicketScreenState extends ConsumerState<CreateMaintenanceTicketScreen> {
  bool _loading = true;
  String? _loadError;
  List<MaintenanceCourtOption> _courts = const [];
  List<MaintenanceIssueCategory> _categories = const [];
  List<FacilityStaffOption> _staff = const [];

  String? _courtId;
  String? _categoryId;
  MaintenancePriority _priority = MaintenancePriority.medium;
  final _title = TextEditingController();
  final _description = TextEditingController();

  bool _schedule = false;
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime _end = DateTime.now().add(const Duration(hours: 4));
  int _affectedCount = 0;

  String? _assignedTo;
  final _estimatedCost = TextEditingController();
  final _notes = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _estimatedCost.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    try {
      final courts = await loadMaintenanceCourtOptions(ref, facility.id);
      final cats = await ref.read(maintenanceRepositoryProvider).listIssueCategories(facility.id, includeInactive: false);
      final staff = await ref.read(maintenanceRepositoryProvider).listAssignableStaff(facility.id);
      if (!mounted) return;
      setState(() {
        _courts = courts;
        _categories = cats;
        _staff = staff;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _checkConflicts() async {
    if (!_schedule || _courtId == null || !_end.isAfter(_start)) {
      setState(() => _affectedCount = 0);
      return;
    }
    try {
      final rows = await ref.read(maintenanceRepositoryProvider).detectAffectedBookings(_courtId!, _start, _end);
      if (mounted) setState(() => _affectedCount = rows.length);
    } catch (_) {
      if (mounted) setState(() => _affectedCount = 0);
    }
  }

  bool get _valid =>
      _courtId != null &&
      _categoryId != null &&
      _title.text.trim().length >= 3 &&
      _description.text.trim().length >= 5 &&
      (!_schedule || _end.isAfter(_start));

  Future<void> _submit() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null || !_valid) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final id = await ref.read(maintenanceRepositoryProvider).createTicket(
            facilityId: facility.id,
            courtId: _courtId!,
            issueCategoryId: _categoryId!,
            priority: _priority,
            title: _title.text.trim(),
            description: _description.text.trim(),
            scheduledStart: _schedule ? _start : null,
            scheduledEnd: _schedule ? _end : null,
            assignedTo: _assignedTo,
            estimatedCostMinor: _estimatedCost.text.isEmpty ? null : ((double.tryParse(_estimatedCost.text) ?? 0) * 100).round(),
            notes: _notes.text.isEmpty ? null : _notes.text,
          );
      if (!mounted) return;
      context.pushReplacement('${AppRoutes.maintenanceTickets}/$id');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
  }

  Future<void> _pickDateTime(bool isStart) async {
    final current = isStart ? _start : _end;
    final date = await showDatePicker(context: context, initialDate: current, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null || !mounted) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = picked;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 2));
      } else {
        _end = picked;
      }
    });
    _checkConflicts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Maintenance Ticket')),
      body: SafeArea(
        child: _loading
            ? const LoadingView()
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      SectionHeader(title: 'Issue Details'),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _courtId,
                              decoration: const InputDecoration(labelText: 'Court'),
                              isExpanded: true,
                              items: [for (final c in _courts) DropdownMenuItem(value: c.id, child: Text('${c.name} — ${c.sportName}'))],
                              onChanged: (v) {
                                setState(() => _courtId = v);
                                _checkConflicts();
                              },
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            DropdownButtonFormField<String>(
                              initialValue: _categoryId,
                              decoration: const InputDecoration(labelText: 'Issue Category'),
                              isExpanded: true,
                              items: [for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                              onChanged: (v) => setState(() => _categoryId = v),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.xs,
                              children: [
                                for (final p in MaintenancePriority.values)
                                  ChoiceChip(label: Text(p.label), selected: _priority == p, onSelected: (_) => setState(() => _priority = p)),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title'), maxLength: 100, onChanged: (_) => setState(() {})),
                            TextField(
                              controller: _description,
                              decoration: const InputDecoration(labelText: 'Description'),
                              maxLines: 4,
                              maxLength: 500,
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Schedule'),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Schedule maintenance now'),
                              value: _schedule,
                              onChanged: (v) {
                                setState(() => _schedule = v);
                                _checkConflicts();
                              },
                            ),
                            if (_schedule) ...[
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Start'),
                                subtitle: Text(_start.toLocal().toString().substring(0, 16)),
                                trailing: const Icon(Icons.edit_calendar_outlined),
                                onTap: () => _pickDateTime(true),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('End'),
                                subtitle: Text(_end.toLocal().toString().substring(0, 16)),
                                trailing: const Icon(Icons.edit_calendar_outlined),
                                onTap: () => _pickDateTime(false),
                              ),
                              if (_affectedCount > 0)
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.warning_amber, size: 18),
                                      const SizedBox(width: AppSpacing.xs),
                                      Expanded(child: Text('$_affectedCount existing booking(s) overlap this window. They will not be cancelled automatically.')),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Assignment'),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _assignedTo,
                              decoration: const InputDecoration(labelText: 'Assign Staff (optional)'),
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Unassigned')),
                                for (final s in _staff) DropdownMenuItem(value: s.userId, child: Text('${s.fullName} (${s.role})')),
                              ],
                              onChanged: (v) => setState(() => _assignedTo = v),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(controller: _estimatedCost, decoration: const InputDecoration(labelText: 'Estimated Repair Cost (₹)'), keyboardType: TextInputType.number),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (_error != null) ...[
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      FilledButton(
                        onPressed: _valid && !_submitting ? _submit : null,
                        child: Text(_submitting ? 'Creating…' : 'Create Maintenance Ticket'),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
      ),
    );
  }
}
