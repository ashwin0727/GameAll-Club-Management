import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'coaching_common.dart';

/// Coaching → Coach detail — mirrors
/// src/features/coaching/components/coach-details-page.tsx.
class CoachDetailScreen extends ConsumerStatefulWidget {
  const CoachDetailScreen({super.key, required this.coachId});

  final String coachId;

  @override
  ConsumerState<CoachDetailScreen> createState() => _CoachDetailScreenState();
}

class _CoachDetailScreenState extends ConsumerState<CoachDetailScreen> {
  static const _tabs = ['Overview', 'Today', 'Students', 'Availability'];

  CoachDetail? _coach;
  String? _error;
  int _tab = 0;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final c = await ref.read(coachingRepositoryProvider).getCoach(widget.coachId);
      if (mounted) setState(() => _coach = c);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditCoachSheet(coach: _coach!),
    );
    if (ok == true) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Coach', message: "You don't have permission to view coaching.");
    }
    final canManage = session.can('COACHING_MANAGE_COACHES');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_coach?.fullName ?? 'Coach'),
          actions: [
            if (_coach != null && canManage)
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _edit),
          ],
        ),
        body: SafeArea(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _coach == null
                  ? const _CoachDetailSkeleton()
                  : _content(_coach!, canManage),
        ),
      ),
    );
  }

  Widget _content(CoachDetail c, bool canManage) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              StaffAvatar(name: c.fullName, photoUrl: c.avatarUrl, size: 56),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(c.fullName, style: Theme.of(context).textTheme.titleMedium)),
                        const SizedBox(width: AppSpacing.sm),
                        StatusBadge(label: c.status.label, tone: coachTone(c.status)),
                      ],
                    ),
                    Text(c.title ?? 'Coach', style: AppTypography.caption(context)),
                    if (c.email != null) Text(c.email!, style: AppTypography.caption(context)),
                  ],
                ),
              ),
            ],
          ),
          if (c.bio != null && c.bio!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(c.bio!, style: AppTypography.secondary(context)),
          ],
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.5,
            children: [
              CoachingKpi(label: 'Sessions', value: '${c.sessionsThisMonth}', hint: 'this month'),
              CoachingKpi(label: 'Students', value: '${c.activeStudents}'),
              CoachingKpi(label: 'Programs', value: '${c.programsCount}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: AppSpacing.md),
          if (_tab == 0) ..._overview(c),
          if (_tab == 1) ..._today(c),
          if (_tab == 2) ..._students(c),
          if (_tab == 3) _availability(c, canManage),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  List<Widget> _overview(CoachDetail c) => [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Specialization', c.specialization ?? '—'),
              _kv('Experience', c.experienceYears != null ? '${c.experienceYears} years' : '—'),
              _kv('Certifications', c.certifications ?? '—'),
              _kv('Hourly rate', c.hourlyRateMinor != null ? '${coachMoney(c.hourlyRateMinor)} / hour' : '—'),
              _kv('Joined', coachDate(c.joinedOn)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Programs', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              if (c.programs.isEmpty)
                Text('No programs yet.', style: AppTypography.secondary(context))
              else
                ...c.programs.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text(p.name)),
                          Text(p.level, style: AppTypography.caption(context)),
                        ],
                      ),
                    )),
            ],
          ),
        ),
      ];

  List<Widget> _today(CoachDetail c) {
    if (c.todaySchedule.isEmpty) {
      return [Text('No sessions today.', style: AppTypography.secondary(context))];
    }
    return c.todaySchedule
        .map((s) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              onTap: () async {
                await context.push('/coaching/sessions/${s.id}');
                if (mounted) _load();
              },
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.programName, style: AppTypography.rowTitle(context)),
                        Text('${coachDateTime(s.startAt)} · ${s.courtName}', style: AppTypography.caption(context)),
                      ],
                    ),
                  ),
                  StatusBadge(label: s.status.label, tone: sessionTone(s.status)),
                ],
              ),
            ))
        .toList();
  }

  List<Widget> _students(CoachDetail c) {
    if (c.students.isEmpty) {
      return [Text('No active students.', style: AppTypography.secondary(context))];
    }
    return c.students
        .map((s) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              onTap: () async {
                await context.push('/coaching/enrollments/${s.enrollmentId}');
                if (mounted) _load();
              },
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: AppTypography.rowTitle(context)),
                        Text(s.programName, style: AppTypography.caption(context)),
                      ],
                    ),
                  ),
                  StatusBadge(label: s.status.label, tone: enrollmentTone(s.status)),
                ],
              ),
            ))
        .toList();
  }

  Widget _availability(CoachDetail c, bool canManage) {
    return _AvailabilityEditor(
      coachId: c.id,
      initial: c.availability,
      canManage: canManage,
      onSaved: () {
        _changed = true;
        _load();
      },
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: AppTypography.caption(context))),
            Expanded(child: Text(v, style: AppTypography.body(context))),
          ],
        ),
      );
}

class _AvailabilityEditor extends ConsumerStatefulWidget {
  const _AvailabilityEditor({
    required this.coachId,
    required this.initial,
    required this.canManage,
    required this.onSaved,
  });

  final String coachId;
  final List<AvailabilityWindow> initial;
  final bool canManage;
  final VoidCallback onSaved;

  @override
  ConsumerState<_AvailabilityEditor> createState() => _AvailabilityEditorState();
}

class _AvailabilityEditorState extends ConsumerState<_AvailabilityEditor> {
  late final List<AvailabilityWindow> _windows = List.of(widget.initial);
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    for (final w in _windows) {
      if (w.endTime.compareTo(w.startTime) <= 0) {
        setState(() => _error = "Every window's end time must be after its start time.");
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(coachingRepositoryProvider).setCoachAvailability(widget.coachId, _windows);
      setState(() => _dirty = false);
      widget.onSaved();
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(int i, bool isStart) async {
    final w = _windows[i];
    final parts = (isStart ? w.startTime : w.endTime).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _windows[i] = isStart ? w.copyWith(startTime: v) : w.copyWith(endTime: v);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recurring Weekly Availability', style: Theme.of(context).textTheme.titleSmall),
          Text('Sessions can only be scheduled inside these windows, in the facility timezone.',
              style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.sm),
          if (_windows.isEmpty) Text('No availability set.', style: AppTypography.secondary(context)),
          ..._windows.asMap().entries.map((e) {
            final i = e.key;
            final w = e.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: DropdownButtonFormField<int>(
                      initialValue: w.dayOfWeek,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true),
                      items: List.generate(
                        7,
                        (d) => DropdownMenuItem(value: d, child: Text(dayLabels[d])),
                      ),
                      onChanged: widget.canManage
                          ? (v) => setState(() {
                                _windows[i] = w.copyWith(dayOfWeek: v ?? w.dayOfWeek);
                                _dirty = true;
                              })
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.canManage ? () => _pickTime(i, true) : null,
                      child: Text(w.startTime),
                    ),
                  ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('–')),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.canManage ? () => _pickTime(i, false) : null,
                      child: Text(w.endTime),
                    ),
                  ),
                  if (widget.canManage)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _windows.removeAt(i);
                        _dirty = true;
                      }),
                    ),
                ],
              ),
            );
          }),
          if (widget.canManage) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _windows.add(const AvailabilityWindow(dayOfWeek: 1, startTime: '16:00', endTime: '20:00'));
                    _dirty = true;
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add window'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: 'Save availability',
              loadingLabel: 'Saving…',
              isLoading: _saving,
              onPressed: _dirty ? _save : null,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: TextStyle(color: context.tokens.destructive)),
          ],
        ],
      ),
    );
  }
}

class _EditCoachSheet extends ConsumerStatefulWidget {
  const _EditCoachSheet({required this.coach});
  final CoachDetail coach;

  @override
  ConsumerState<_EditCoachSheet> createState() => _EditCoachSheetState();
}

class _EditCoachSheetState extends ConsumerState<_EditCoachSheet> {
  late final _specialization = TextEditingController(text: widget.coach.specialization ?? '');
  late final _experience =
      TextEditingController(text: widget.coach.experienceYears != null ? '${widget.coach.experienceYears}' : '');
  late final _certifications = TextEditingController(text: widget.coach.certifications ?? '');
  late final _bio = TextEditingController(text: widget.coach.bio ?? '');
  late final _hourlyRate = TextEditingController(
      text: widget.coach.hourlyRateMinor != null ? (widget.coach.hourlyRateMinor! / 100).toString() : '');
  late CoachStatus _status = widget.coach.status;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_specialization, _experience, _certifications, _bio, _hourlyRate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rate = num.tryParse(_hourlyRate.text.trim());
      await ref.read(coachingRepositoryProvider).updateCoach(
            coachId: widget.coach.id,
            specialization: _specialization.text.trim().isEmpty ? null : _specialization.text.trim(),
            experienceYears: num.tryParse(_experience.text.trim())?.toDouble(),
            certifications: _certifications.text.trim().isEmpty ? null : _certifications.text.trim(),
            bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
            hourlyRateMinor: (rate != null && rate > 0) ? (rate * 100).round() : null,
            status: _status,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit coach', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _specialization, decoration: const InputDecoration(labelText: 'Specialization')),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _experience,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Experience (yrs)'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _hourlyRate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Hourly rate (₹)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _certifications, decoration: const InputDecoration(labelText: 'Certifications')),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _bio, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio')),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<CoachStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: CoachStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
              onChanged: (v) => setState(() => _status = v ?? CoachStatus.active),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: context.tokens.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save', loadingLabel: 'Saving…', isLoading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder for the coach detail page: avatar header
/// row, the 3-tile KPI grid, then the overview cards below the tabs.
class _CoachDetailSkeleton extends StatelessWidget {
  const _CoachDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: const [
            AppSkeleton(width: 56, height: 56, radius: 28),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(width: 160, height: 16),
                  SizedBox(height: 6),
                  AppSkeleton(width: 100, height: 12),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.5,
          children: const [
            SkeletonStatTile(),
            SkeletonStatTile(),
            SkeletonStatTile(),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const SkeletonChipRow(count: 4),
        const SizedBox(height: AppSpacing.md),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SkelKv(),
              SizedBox(height: AppSpacing.sm),
              _SkelKv(),
              SizedBox(height: AppSpacing.sm),
              _SkelKv(),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              AppSkeleton(width: 100, height: 14),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 11),
              SizedBox(height: 6),
              AppSkeleton(width: 160, height: 11),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkelKv extends StatelessWidget {
  const _SkelKv();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        AppSkeleton(width: 120, height: 11),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: AppSkeleton(height: 11)),
      ],
    );
  }
}
