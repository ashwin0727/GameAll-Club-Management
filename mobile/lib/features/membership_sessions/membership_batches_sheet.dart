import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/models/membership_session.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../authentication/auth_widgets.dart';

const List<({int value, String label})> _days = [
  (value: 1, label: 'Mon'),
  (value: 2, label: 'Tue'),
  (value: 3, label: 'Wed'),
  (value: 4, label: 'Thu'),
  (value: 5, label: 'Fri'),
  (value: 6, label: 'Sat'),
  (value: 0, label: 'Sun'),
];

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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Membership batches',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Recurring sessions that reserve court capacity for a plan.',
                  style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (_batches == null)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_batches!.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: tokens.surface1,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: tokens.borderColor),
                    ),
                    child: Text('No batches yet — add the first one below.',
                        style: TextStyle(color: tokens.textSecondary)),
                  )
                else
                  for (final batch in _batches!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _batchCard(context, batch),
                    ),
                const SizedBox(height: AppSpacing.xl),
                _sectionLabel(context, 'ADD A BATCH'),
                const SizedBox(height: AppSpacing.md),
                _labeled(context, 'Batch name',
                    TextField(controller: _nameController)),
                const SizedBox(height: AppSpacing.md),
                AppDropdown<String>(
                  initialValue: _planId,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: _plans
                      .map((p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _planId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                AppDropdown<String>(
                  initialValue: _facilitySportId,
                  decoration: const InputDecoration(labelText: 'Sport'),
                  items: _facilitySports
                      .map((fs) => DropdownMenuItem(
                          value: fs.id, child: Text(_sportLabel(fs))))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _facilitySportId = v;
                    _courtId = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                AppDropdown<String>(
                  initialValue: _courtId,
                  decoration: const InputDecoration(labelText: 'Court'),
                  items: _courtsForSport
                      .map((a) =>
                          DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: _facilitySportId == null
                      ? null
                      : (v) => setState(() => _courtId = v),
                ),
                const SizedBox(height: AppSpacing.lg),
                _labeled(
                  context,
                  'Runs on',
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _days
                        .map((d) => _DayChip(
                              label: d.label,
                              selected: _selectedDays.contains(d.value),
                              onTap: () => _toggleDay(d.value),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: _TimeBox(
                        label: 'Starts',
                        value: Formatters.time12h(_formatTime(_startTime)),
                        onTap: _pickStart,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _TimeBox(
                        label: 'Ends',
                        value: Formatters.time12h(_formatTime(_endTime)),
                        onTap: _pickEnd,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _labeled(
                  context,
                  'Capacity',
                  TextField(
                    controller: _capacityController,
                    keyboardType: TextInputType.number,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!,
                      style: TextStyle(color: tokens.destructive, fontSize: 13)),
                ],
                const SizedBox(height: AppSpacing.lg),
                AuthGradientButton(
                  label: 'Add batch',
                  loadingLabel: 'Saving…',
                  isLoading: _isSaving,
                  onPressed: _addBatch,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: context.tokens.textSecondary,
        ),
      );

  Widget _labeled(BuildContext context, String label, Widget field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.tokens.textSecondary)),
          const SizedBox(height: 6),
          field,
        ],
      );

  Widget _batchCard(BuildContext context, MembershipBatch batch) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.violet.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.event_repeat_rounded,
                    size: 20, color: tokens.violet),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(batch.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                        if (!batch.isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: tokens.textSecondary.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Inactive',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textSecondary)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Formatters.time12h(batch.startTime.substring(0, 5))}–${Formatters.time12h(batch.endTime.substring(0, 5))}',
                      style: TextStyle(
                          fontSize: 12, color: tokens.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _planName(batch.planId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tokens.violet),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _SmallBtn(
                label: batch.isActive ? 'Deactivate' : 'Activate',
                danger: batch.isActive,
                onTap: () => _toggleActive(batch),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _planName(String planId) => _plans
      .where((p) => p.id == planId)
      .map((p) => p.name)
      .firstOrNull ??
      'Membership';
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = danger ? tokens.destructive : tokens.violet;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(
          side: BorderSide(color: color.withValues(alpha: 0.5))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              )),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? tokens.violet.withValues(alpha: 0.18)
              : tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? tokens.violet : tokens.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? tokens.violet : tokens.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tokens.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: tokens.textSecondary)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary)),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}