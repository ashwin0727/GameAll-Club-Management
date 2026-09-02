import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/facility.dart';
import '../../data/models/operating_hours.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'onboarding_progress_bar.dart';
import 'operating_hours_validation.dart';

class _OverrideEntry {
  _OverrideEntry({required this.active, required this.days, this.initiallyActive = false});

  bool active;
  List<OperatingDay> days;
  final bool initiallyActive;
}

class OperatingHoursScreen extends ConsumerStatefulWidget {
  const OperatingHoursScreen({super.key});

  @override
  ConsumerState<OperatingHoursScreen> createState() => _OperatingHoursScreenState();
}

class _OperatingHoursScreenState extends ConsumerState<OperatingHoursScreen> {
  bool _isLoading = true;
  String? _loadError;
  String? _facilityId;
  List<OperatingDay> _days = OperatingDay.defaultWeek();
  Map<int, String> _dayErrors = {};
  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];
  List<PlayingArea> _areas = [];
  final Map<String, _OverrideEntry> _overrides = {};
  final Map<String, Map<int, String>> _overrideErrors = {};
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        if (!mounted) return;
        // Clear the flag before navigating: if the route doesn't change for
        // any reason, the screen shows an actionable error rather than
        // spinning forever.
        setState(() {
          _isLoading = false;
          _loadError = 'Finish your facility details first.';
        });
        context.go(AppRoutes.onboardingFacility);
        return;
      }
      final hoursRepo = ref.read(operatingHoursRepositoryProvider);
      // Independent reads — fetch them together rather than one after another.
      final results = await Future.wait([
        hoursRepo.getFacilitySchedule(facility.id),
        ref.read(sportsRepositoryProvider).getFacilitySports(facility.id),
        ref.read(sportsRepositoryProvider).getActiveSports(),
        ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id),
      ]);
      final schedule = results[0] as OperatingSchedule?;
      final facilitySports = results[1] as List<FacilitySport>;
      final sports = results[2] as List<Sport>;
      final areas = results[3] as List<PlayingArea>;

      final days = schedule != null && schedule.days.isNotEmpty
          ? daysOfWeek
                .map((d) => schedule.days.where((day) => day.dayOfWeek == d).firstOrNull ?? OperatingDay.defaultOpen(d))
                .toList()
          : OperatingDay.defaultWeek();

      // One request per court, in parallel — a sequential await here meant a
      // facility with several courts sat on the loading spinner for as many
      // round-trips as it had courts.
      final areaSchedules = await Future.wait(areas.map((a) => hoursRepo.getPlayingAreaSchedule(a.id)));

      _overrides.clear();
      _overrideErrors.clear();
      for (var i = 0; i < areas.length; i++) {
        final area = areas[i];
        final areaSchedule = areaSchedules[i];
        final hasOverride = areaSchedule != null && areaSchedule.days.isNotEmpty;
        final overrideDays = hasOverride
            ? daysOfWeek
                  .map((d) => areaSchedule.days.where((day) => day.dayOfWeek == d).firstOrNull ?? OperatingDay.defaultOpen(d))
                  .toList()
            : days.map((d) => OperatingDay.defaultOpen(d.dayOfWeek)).toList();
        _overrides[area.id] = _OverrideEntry(active: hasOverride, days: overrideDays, initiallyActive: hasOverride);
        _overrideErrors[area.id] = {};
      }

      setState(() {
        _facilityId = facility.id;
        _days = days;
        _facilitySports = facilitySports;
        _sports = sports;
        _areas = areas;
        _isLoading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      // Anything that isn't an AppException — a cast failure, a dropped
      // socket, a raw Postgrest error — used to escape this method and
      // leave the screen dead: no spinner, no error, no retry. Surface it
      // instead, and keep the stack in the log for diagnosis.
      debugPrint('Operating hours load failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'We couldn’t load your operating hours. Please try again.';
      });
    }
  }

  void _updateDay(int dayOfWeek, OperatingDay Function(OperatingDay) update) {
    setState(() {
      _days = _days.map((d) => d.dayOfWeek == dayOfWeek ? withComputedOvernight(update(d)) : d).toList();
      _dayErrors = Map.of(_dayErrors)..remove(dayOfWeek);
    });
  }

  void _updateOverrideDay(String areaId, int dayOfWeek, OperatingDay Function(OperatingDay) update) {
    setState(() {
      final entry = _overrides[areaId]!;
      entry.days = entry.days.map((d) => d.dayOfWeek == dayOfWeek ? withComputedOvernight(update(d)) : d).toList();
      _overrideErrors[areaId] = Map.of(_overrideErrors[areaId] ?? {})..remove(dayOfWeek);
    });
  }

  Future<void> _pickTime(OperatingTimeSlot slot, bool isStart, ValueChanged<OperatingTimeSlot> onChanged) async {
    final current = isStart ? slot.startTime : slot.endTime;
    final parts = current.split(':');
    final initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 6, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    onChanged(
      OperatingTimeSlot(
        startTime: isStart ? formatted : slot.startTime,
        endTime: isStart ? slot.endTime : formatted,
        crossesMidnight: slot.crossesMidnight,
        displayOrder: slot.displayOrder,
      ),
    );
  }

  Future<void> _copyDayTo(int sourceDow) async {
    final source = _days.firstWhere((d) => d.dayOfWeek == sourceDow);
    final targets = await showDialog<Set<int>>(
      context: context,
      builder: (context) => _CopyHoursDialog(sourceDow: sourceDow),
    );
    if (targets == null || targets.isEmpty) return;
    setState(() {
      _days = _days
          .map((d) => targets.contains(d.dayOfWeek)
              ? withComputedOvernight(d.copyWith(isClosed: source.isClosed, is24Hours: source.is24Hours, slots: source.slots))
              : d)
          .toList();
      _dayErrors = Map.of(_dayErrors)..removeWhere((dow, _) => targets.contains(dow));
    });
  }

  void _applyQuickSetup(String preset) {
    setState(() {
      switch (preset) {
        case 'everyday':
          _days = _days
              .map((d) => d.copyWith(isClosed: false, is24Hours: false, slots: OperatingDay.defaultOpen(d.dayOfWeek).slots))
              .toList();
          break;
        case 'weekdays':
          _days = _days
              .map(
                (d) => d.dayOfWeek == 0 || d.dayOfWeek == 6
                    ? d.copyWith(isClosed: true, slots: const [])
                    : d.copyWith(isClosed: false, is24Hours: false, slots: OperatingDay.defaultOpen(d.dayOfWeek).slots),
              )
              .toList();
          break;
        case '24hours':
          _days = _days.map((d) => d.copyWith(isClosed: false, is24Hours: true)).toList();
          break;
      }
      _dayErrors = {};
    });
  }

  Future<void> _submit() async {
    final dayErrors = validateSchedule(_days);
    final overrideErrors = <String, Map<int, String>>{};
    for (final entry in _overrides.entries) {
      if (entry.value.active) {
        overrideErrors[entry.key] = validateSchedule(entry.value.days);
      }
    }
    final hasErrors = dayErrors.isNotEmpty || overrideErrors.values.any((e) => e.isNotEmpty);
    if (hasErrors) {
      setState(() {
        _dayErrors = dayErrors;
        _overrideErrors.addAll(overrideErrors);
        _submitError = 'Fix the highlighted days before continuing.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final hoursRepo = ref.read(operatingHoursRepositoryProvider);
      await hoursRepo.saveFacilitySchedule(_facilityId!, _days);
      for (final area in _areas) {
        final entry = _overrides[area.id];
        if (entry == null) continue;
        if (entry.active) {
          await hoursRepo.savePlayingAreaSchedule(area.id, _facilityId!, entry.days);
        } else if (entry.initiallyActive) {
          await hoursRepo.deletePlayingAreaOverride(area.id);
        }
      }
      await ref
          .read(facilityRepositoryProvider)
          .updateOnboardingStep(_facilityId!, OnboardingStep.pricing);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.onboardingPricing);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _submitError = e.message);
    } catch (e, stack) {
      debugPrint('Operating hours save failed: $e\n$stack');
      if (!mounted) return;
      setState(() => _submitError = 'We couldn’t save your hours. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const OnboardingProgressBar(currentStep: 4)),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading operating hours…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Set your operating hours', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    const Text('Choose when your facility is open for bookings and activities.'),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _QuickSetupChip(label: 'Everyday, same hours', onTap: () => _applyQuickSetup('everyday')),
                        _QuickSetupChip(label: 'Weekdays only', onTap: () => _applyQuickSetup('weekdays')),
                        _QuickSetupChip(label: 'Open 24 hours', onTap: () => _applyQuickSetup('24hours')),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_submitError != null) ...[
                      Text(_submitError!, style: const TextStyle(color: AppColors.destructive)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    ...displayOrder.map((dow) {
                      // A schedule row missing a day used to throw a
                      // StateError out of build and leave the body blank.
                      final day = _days.where((d) => d.dayOfWeek == dow).firstOrNull ??
                          OperatingDay.defaultOpen(dow);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _DayCard(
                          label: dayLabels[dow],
                          day: day,
                          error: _dayErrors[dow],
                          onChange: (update) => _updateDay(dow, update),
                          onPickTime: (slot, isStart, onChanged) => _pickTime(slot, isStart, onChanged),
                          onCopyRequest: () => _copyDayTo(dow),
                        ),
                      );
                    }),
                    if (_areas.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text('Customize individual court/turf hours', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        'By default, all courts and turfs use the facility hours above.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ..._facilitySports.map((fs) {
                        final sport = _sports.where((s) => s.id == fs.sportId).firstOrNull;
                        // Only courts we actually built an override entry for
                        // — a missing entry used to blow up the `!` below and
                        // take the whole page down with it.
                        final areasForSport = _areas
                            .where((a) => a.facilitySportId == fs.id && _overrides.containsKey(a.id))
                            .toList();
                        if (areasForSport.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fs.customSportName ?? sport?.name ?? 'Sport',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              ...areasForSport.map((area) => _PlayingAreaOverrideCard(
                                area: area,
                                entry: _overrides[area.id]!,
                                errors: _overrideErrors[area.id] ?? {},
                                onCustomize: () => setState(() => _overrides[area.id]!.active = true),
                                onUseFacilityHours: () => setState(() => _overrides[area.id]!.active = false),
                                onDayChange: (dow, update) => _updateOverrideDay(area.id, dow, update),
                                onPickTime: _pickTime,
                              )),
                            ],
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Continue →',
                      loadingLabel: 'Saving…',
                      isLoading: _isSubmitting,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _QuickSetupChip extends StatelessWidget {
  const _QuickSetupChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }
}

class _PlayingAreaOverrideCard extends StatelessWidget {
  const _PlayingAreaOverrideCard({
    required this.area,
    required this.entry,
    required this.errors,
    required this.onCustomize,
    required this.onUseFacilityHours,
    required this.onDayChange,
    required this.onPickTime,
  });

  final PlayingArea area;
  final _OverrideEntry entry;
  final Map<int, String> errors;
  final VoidCallback onCustomize;
  final VoidCallback onUseFacilityHours;
  final void Function(int dayOfWeek, OperatingDay Function(OperatingDay)) onDayChange;
  final Future<void> Function(OperatingTimeSlot, bool, ValueChanged<OperatingTimeSlot>) onPickTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(area.name, style: Theme.of(context).textTheme.titleSmall)),
                if (entry.active)
                  TextButton(onPressed: onUseFacilityHours, child: const Text('Use facility hours'))
                else
                  OutlinedButton(onPressed: onCustomize, child: const Text('Customize')),
              ],
            ),
            if (!entry.active)
              const Text('Uses facility hours ✓', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            if (entry.active) ...[
              const SizedBox(height: AppSpacing.sm),
              ...displayOrder.map((dow) {
                final day = entry.days.firstWhere((d) => d.dayOfWeek == dow);
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _DayCard(
                    label: dayLabels[dow],
                    day: day,
                    error: errors[dow],
                    onChange: (update) => onDayChange(dow, update),
                    onPickTime: onPickTime,
                    compact: true,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.label,
    required this.day,
    required this.error,
    required this.onChange,
    required this.onPickTime,
    this.onCopyRequest,
    this.compact = false,
  });

  final String label;
  final OperatingDay day;
  final String? error;
  final ValueChanged<OperatingDay Function(OperatingDay)> onChange;
  final Future<void> Function(OperatingTimeSlot, bool, ValueChanged<OperatingTimeSlot>) onPickTime;
  final VoidCallback? onCopyRequest;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isOpen = !day.isClosed;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
            if (onCopyRequest != null)
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                tooltip: 'Copy hours to other days',
                onPressed: onCopyRequest,
              ),
            const Text('Open', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            Switch(
              value: isOpen,
              onChanged: (value) => onChange(
                (d) => d.copyWith(
                  isClosed: !value,
                  slots: value && d.slots.isEmpty ? OperatingDay.defaultOpen(d.dayOfWeek).slots : d.slots,
                ),
              ),
            ),
          ],
        ),
        if (isOpen) ...[
          Row(
            children: [
              const Text('Open 24 hours', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              Switch(value: day.is24Hours, onChanged: (value) => onChange((d) => d.copyWith(is24Hours: value))),
            ],
          ),
          if (!day.is24Hours) ...[
            ...day.slots.map((slot) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _TimeChip(
                      label: 'Opens',
                      time: slot.startTime,
                      onTap: () => onPickTime(
                        slot,
                        true,
                        (newSlot) => onChange(
                          (d) => d.copyWith(slots: [for (final s in d.slots) s == slot ? newSlot : s]),
                        ),
                      ),
                    ),
                    _TimeChip(
                      label: 'Closes',
                      time: slot.endTime,
                      onTap: () => onPickTime(
                        slot,
                        false,
                        (newSlot) => onChange(
                          (d) => d.copyWith(slots: [for (final s in d.slots) s == slot ? newSlot : s]),
                        ),
                      ),
                    ),
                    if (slot.crossesMidnight)
                      const Text('(next day)', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    if (day.slots.length > 1)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Remove slot',
                        onPressed: () => onChange(
                          (d) => d.copyWith(slots: d.slots.where((s) => s != slot).toList()),
                        ),
                      ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add another time slot'),
              onPressed: () => onChange(
                (d) => d.copyWith(
                  slots: [
                    ...d.slots,
                    OperatingTimeSlot(
                      startTime: '06:00',
                      endTime: '23:00',
                      crossesMidnight: false,
                      displayOrder: d.slots.length,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(error!, style: const TextStyle(color: AppColors.destructive, fontSize: 12)),
        ],
      ],
    );

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: body,
      );
    }
    return AppCard(child: body);
  }
}

class _CopyHoursDialog extends StatefulWidget {
  const _CopyHoursDialog({required this.sourceDow});

  final int sourceDow;

  @override
  State<_CopyHoursDialog> createState() => _CopyHoursDialogState();
}

class _CopyHoursDialogState extends State<_CopyHoursDialog> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    final targets = displayOrder.where((d) => d != widget.sourceDow).toList();
    return AlertDialog(
      title: Text('Copy ${dayLabels[widget.sourceDow]}\'s hours to…'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: targets
              .map(
                (dow) => CheckboxListTile(
                  title: Text(dayLabels[dow]),
                  value: _selected.contains(dow),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _selected.add(dow);
                    } else {
                      _selected.remove(dow);
                    }
                  }),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.time, required this.onTap});

  final String label;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            Text(Formatters.time12h(time)),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}