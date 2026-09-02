import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/membership.dart';
import '../../data/models/membership_session.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import 'batch_members_sheet.dart';
import '../../shared/widgets/app_dropdown.dart';

const List<({int value, String label})> _days = [
  (value: 1, label: 'Mon'),
  (value: 2, label: 'Tue'),
  (value: 3, label: 'Wed'),
  (value: 4, label: 'Thu'),
  (value: 5, label: 'Fri'),
  (value: 6, label: 'Sat'),
  (value: 0, label: 'Sun'),
];

String _daysLabel(List<int> daysOfWeek) {
  return _days.where((d) => daysOfWeek.contains(d.value)).map((d) => d.label).join('/');
}

/// Batch management: list existing batches (name, days, time, capacity,
/// active toggle), a create form, and a "Members" button per batch opening
/// batch-member management. Mirrors `membership-batches-dialog.tsx`.
class MembershipBatchesSheet extends ConsumerStatefulWidget {
  const MembershipBatchesSheet({super.key, required this.facilityId});

  final String facilityId;

  @override
  ConsumerState<MembershipBatchesSheet> createState() => _MembershipBatchesSheetState();
}

class _MembershipBatchesSheetState extends ConsumerState<MembershipBatchesSheet> {
  List<MembershipBatch>? _batches;
  List<MembershipPlan> _plans = [];
  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];
  List<PlayingArea> _areas = [];

  final _nameController = TextEditingController();
  final _capacityController = TextEditingController(text: '5');
  String? _planId;
  String? _facilitySportId;
  String? _courtId;
  final List<int> _selectedDays = [];
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 19, minute: 0);
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadOptions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final batches = await ref.read(membershipSessionRepositoryProvider).getFacilityBatches(widget.facilityId);
      if (mounted) setState(() => _batches = batches);
    } on AppException catch (_) {
      if (mounted) setState(() => _batches = []);
    }
  }

  Future<void> _loadOptions() async {
    try {
      final results = await Future.wait([
        ref.read(membershipRepositoryProvider).getFacilityPlans(widget.facilityId, activeOnly: true),
        ref.read(sportsRepositoryProvider).getFacilitySports(widget.facilityId),
        ref.read(sportsRepositoryProvider).getActiveSports(),
        ref.read(playingAreaRepositoryProvider).getPlayingAreas(widget.facilityId),
      ]);
      if (!mounted) return;
      setState(() {
        _plans = results[0] as List<MembershipPlan>;
        _facilitySports = results[1] as List<FacilitySport>;
        _sports = results[2] as List<Sport>;
        _areas = (results[3] as List<PlayingArea>)
            .where((a) => !a.archived && a.status == 'ACTIVE' && a.bookingEnabled)
            .toList();
      });
    } on AppException catch (_) {
      // Options failing to load just leaves the create form empty — the
      // batch list itself still renders.
    }
  }

  List<PlayingArea> get _courtsForSport =>
      _areas.where((a) => a.facilitySportId == _facilitySportId).toList();

  String _sportLabel(FacilitySport fs) {
    final sport = _sports.where((s) => s.id == fs.sportId).firstOrNull;
    return fs.customSportName ?? sport?.name ?? 'Sport';
  }

  void _toggleDay(int value) {
    setState(() {
      if (_selectedDays.contains(value)) {
        _selectedDays.remove(value);
      } else {
        _selectedDays.add(value);
      }
    });
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _endTime);
    if (picked != null) setState(() => _endTime = picked);
  }

  String _formatTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool _endAfterStart() {
    final start = _startTime.hour * 60 + _startTime.minute;
    final end = _endTime.hour * 60 + _endTime.minute;
    return end > start;
  }

  Future<void> _addBatch() async {
    final name = _nameController.text.trim();
    final capacity = int.tryParse(_capacityController.text.trim());
    if (name.length < 2) {
      setState(() => _error = 'Enter a batch name.');
      return;
    }
    if (_planId == null || _facilitySportId == null || _courtId == null) {
      setState(() => _error = 'Select a plan, sport, and court.');
      return;
    }
    if (_selectedDays.isEmpty) {
      setState(() => _error = 'Select at least one day.');
      return;
    }
    if (capacity == null || capacity <= 0) {
      setState(() => _error = 'Enter a valid capacity.');
      return;
    }
    if (!_endAfterStart()) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref.read(membershipSessionRepositoryProvider).createBatch(
        MembershipBatchInput(
          facilityId: widget.facilityId,
          planId: _planId!,
          facilitySportId: _facilitySportId!,
          courtId: _courtId!,
          name: name,
          daysOfWeek: List.of(_selectedDays),
          startTime: _formatTime(_startTime),
          endTime: _formatTime(_endTime),
          capacity: capacity,
        ),
      );
      _nameController.clear();
      _capacityController.text = '5';
      setState(() => _selectedDays.clear());
      await _reload();
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleActive(MembershipBatch batch) async {
    try {
      await ref.read(membershipSessionRepositoryProvider).updateBatch(batch.id, isActive: !batch.isActive);
      await _reload();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openMembers(MembershipBatch batch) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => BatchMembersSheet(facilityId: widget.facilityId, batch: batch),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Membership Batches', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Recurring sessions that reserve court capacity for a membership plan.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_batches == null)
                  const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
                else ...[
                  if (_batches!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text('No batches yet — add the first one below.'),
                    )
                  else
                    ..._batches!.map(
                      (batch) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(child: Text(batch.name, style: Theme.of(context).textTheme.titleSmall)),
                                        if (!batch.isActive) ...[
                                          const SizedBox(width: AppSpacing.xs),
                                          const Chip(label: Text('Inactive'), visualDensity: VisualDensity.compact),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      '${_daysLabel(batch.daysOfWeek)} · ${batch.startTime.substring(0, 5)}–${batch.endTime.substring(0, 5)} · Capacity ${batch.capacity}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Wrap(
                                spacing: AppSpacing.xs,
                                children: [
                                  OutlinedButton(onPressed: () => _openMembers(batch), child: const Text('Members')),
                                  OutlinedButton(
                                    onPressed: () => _toggleActive(batch),
                                    child: Text(batch.isActive ? 'Deactivate' : 'Activate'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Add a batch', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Batch name', hintText: 'e.g. Evening Badminton'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppDropdown<String>(
                    initialValue: _planId,
                    decoration: const InputDecoration(labelText: 'Plan'),
                    items: _plans.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                    onChanged: (v) => setState(() => _planId = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppDropdown<String>(
                    initialValue: _facilitySportId,
                    decoration: const InputDecoration(labelText: 'Sport'),
                    items: _facilitySports
                        .map((fs) => DropdownMenuItem(value: fs.id, child: Text(_sportLabel(fs))))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _facilitySportId = v;
                      _courtId = null;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppDropdown<String>(
                    initialValue: _courtId,
                    decoration: const InputDecoration(labelText: 'Court'),
                    items: _courtsForSport.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                    onChanged: _facilitySportId == null ? null : (v) => setState(() => _courtId = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: _days
                        .map(
                          (d) => ChoiceChip(
                            label: Text(d.label),
                            selected: _selectedDays.contains(d.value),
                            onSelected: (_) => _toggleDay(d.value),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(onPressed: _pickStart, child: Text('Start ${_formatTime(_startTime)}')),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: OutlinedButton(onPressed: _pickEnd, child: Text('End ${_formatTime(_endTime)}'))),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _capacityController,
                    decoration: const InputDecoration(labelText: 'Capacity'),
                    keyboardType: TextInputType.number,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: const TextStyle(color: AppColors.destructive)),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(label: 'Add Batch', loadingLabel: 'Saving…', isLoading: _isSaving, onPressed: _addBatch),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}