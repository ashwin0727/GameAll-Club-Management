import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/operating_hours.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/pricing.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'onboarding_progress_bar.dart';
import 'pricing_validation.dart';

const List<({String value, String label})> _dayTypeOptions = [
  (value: 'ALL_DAYS', label: 'All days'),
  (value: 'WEEKDAYS', label: 'Weekdays'),
  (value: 'WEEKENDS', label: 'Weekends'),
];

class _PeriodState {
  _PeriodState({required this.draft, required this.amountController});

  final PricingPeriodDraft draft;
  final TextEditingController amountController;
  String? error;

  void dispose() => amountController.dispose();
}

class _AreaOverrideState {
  _AreaOverrideState({required this.active, required this.periods, this.initiallyActive = false});

  bool active;
  List<_PeriodState> periods;
  final bool initiallyActive;
}

class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key});

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  bool _isLoading = true;
  String? _loadError;
  String? _facilityId;
  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];
  List<PlayingArea> _areas = [];
  List<OperatingDay>? _operatingDays;
  final Map<String, List<_PeriodState>> _defaultPeriods = {};
  final Map<String, _AreaOverrideState> _overrides = {};
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final periods in _defaultPeriods.values) {
      for (final p in periods) {
        p.dispose();
      }
    }
    for (final o in _overrides.values) {
      for (final p in o.periods) {
        p.dispose();
      }
    }
    super.dispose();
  }

  _PeriodState _newPeriod({
    String dayType = 'ALL_DAYS',
    bool coversFullDay = true,
    String? startTime,
    String? endTime,
    int amountMinor = 0,
  }) {
    final draft = PricingPeriodDraft(
      dayType: dayType,
      coversFullDay: coversFullDay,
      startTime: startTime,
      endTime: endTime,
      amountMinor: amountMinor,
    );
    return _PeriodState(
      draft: draft,
      amountController: TextEditingController(text: amountMinor > 0 ? (amountMinor / 100).round().toString() : ''),
    );
  }

  List<_PeriodState> _periodsFromRules(List<PricingRule> rules) {
    if (rules.isEmpty) return [_newPeriod()];
    return rules
        .map(
          (r) => _newPeriod(
            dayType: r.dayType,
            coversFullDay: r.coversFullDay,
            startTime: r.startTime,
            endTime: r.endTime,
            amountMinor: r.amountMinor,
          ),
        )
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        if (mounted) context.go(AppRoutes.onboardingFacility);
        return;
      }
      final facilitySports = await ref.read(sportsRepositoryProvider).getFacilitySports(facility.id);
      if (facilitySports.isEmpty) {
        if (mounted) context.go(AppRoutes.onboardingSports);
        return;
      }
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id);
      final plan = await ref.read(pricingRepositoryProvider).getPricingPlan(facility.id);
      final schedule = await ref.read(operatingHoursRepositoryProvider).getFacilitySchedule(facility.id);

      _defaultPeriods.clear();
      _overrides.clear();
      for (final fs in facilitySports) {
        final defaultRules = plan?.rules.where((r) => r.facilitySportId == fs.id && r.playingAreaId == null).toList() ?? [];
        _defaultPeriods[fs.id] = _periodsFromRules(defaultRules);
      }
      for (final area in areas) {
        final areaRules = plan?.rules.where((r) => r.playingAreaId == area.id).toList() ?? [];
        final hasOverride = areaRules.isNotEmpty;
        _overrides[area.id] = _AreaOverrideState(
          active: hasOverride,
          periods: hasOverride ? _periodsFromRules(areaRules) : [_newPeriod()],
          initiallyActive: hasOverride,
        );
      }

      setState(() {
        _facilityId = facility.id;
        _facilitySports = facilitySports;
        _sports = sports;
        _areas = areas;
        _operatingDays = schedule?.days;
        _isLoading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      // Anything that isn't an AppException used to escape this method
      // and leave the screen dead: no spinner, no error, no retry.
      debugPrint('Onboarding pricing load failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'We couldn’t load this step. Please try again.';
      });
    }
  }

  void _syncAmount(_PeriodState period) {
    final rupees = num.tryParse(period.amountController.text.trim());
    period.draft.amountMinor = rupees == null ? 0 : (rupees * 100).round();
  }

  bool _validateAll() {
    var isValid = true;
    setState(() {
      final operatingDays = _operatingDays;
      for (final periods in _defaultPeriods.values) {
        for (final p in periods) {
          _syncAmount(p);
          p.error = validatePricingPeriod(p.draft);
          if (p.error == null && operatingDays != null) {
            p.error = validatePricingAgainstOperatingHours(p.draft, operatingDays);
          }
          if (p.error != null) isValid = false;
        }
        if (hasOverlappingPricingPeriods(periods.map((p) => p.draft).toList())) {
          for (final p in periods) {
            p.error ??= 'Pricing periods cannot overlap.';
          }
          isValid = false;
        }
      }
      for (final o in _overrides.values) {
        if (!o.active) continue;
        for (final p in o.periods) {
          _syncAmount(p);
          p.error = validatePricingPeriod(p.draft);
          if (p.error == null && operatingDays != null) {
            p.error = validatePricingAgainstOperatingHours(p.draft, operatingDays);
          }
          if (p.error != null) isValid = false;
        }
        if (hasOverlappingPricingPeriods(o.periods.map((p) => p.draft).toList())) {
          for (final p in o.periods) {
            p.error ??= 'Pricing periods cannot overlap.';
          }
          isValid = false;
        }
      }
    });
    return isValid;
  }

  Future<void> _submit() async {
    if (!_validateAll()) {
      setState(() => _submitError = 'Fix the highlighted pricing periods before continuing.');
      return;
    }

    final rules = <PricingRule>[];
    for (final fs in _facilitySports) {
      for (final p in _defaultPeriods[fs.id] ?? []) {
        rules.add(
          PricingRule(
            facilitySportId: fs.id,
            dayType: p.draft.dayType,
            coversFullDay: p.draft.coversFullDay,
            startTime: p.draft.startTime,
            endTime: p.draft.endTime,
            amountMinor: p.draft.amountMinor,
            currency: 'INR',
            pricingUnit: 'PER_HOUR',
            priority: 0,
          ),
        );
      }
    }
    for (final area in _areas) {
      final o = _overrides[area.id]!;
      if (!o.active) continue;
      for (final p in o.periods) {
        rules.add(
          PricingRule(
            facilitySportId: area.facilitySportId,
            playingAreaId: area.id,
            dayType: p.draft.dayType,
            coversFullDay: p.draft.coversFullDay,
            startTime: p.draft.startTime,
            endTime: p.draft.endTime,
            amountMinor: p.draft.amountMinor,
            currency: 'INR',
            pricingUnit: 'PER_HOUR',
            priority: 1,
          ),
        );
      }
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await ref.read(pricingRepositoryProvider).savePricingRules(_facilityId!, rules);
      // Goes through the complete_facility_setup RPC (not a raw onboarding_step
      // write) so profiles.onboarding_completed is flipped in the same
      // transaction — otherwise a client that reads that column instead of
      // facility.onboardingStep would send the owner back into onboarding.
      await ref.read(onboardingRepositoryProvider).completeSetup(_facilityId!);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.onboardingComplete);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _submitError = e.message);
    } catch (e, stack) {
      debugPrint('Onboarding pricing save failed: $e\n$stack');
      if (!mounted) return;
      setState(() => _submitError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickTime(String? current, ValueChanged<String> onPicked) async {
    final parts = (current ?? '06:00').split(':');
    final initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 6, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    onPicked('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const OnboardingProgressBar(currentStep: 5)),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading pricing…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Set your pricing', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    const Text('Define how much customers pay to use your courts and turfs.'),
                    const SizedBox(height: AppSpacing.xl),
                    if (_submitError != null) ...[
                      Text(_submitError!, style: const TextStyle(color: AppColors.destructive)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    ..._facilitySports.map((fs) {
                      final sport = _sports.where((s) => s.id == fs.sportId).firstOrNull;
                      final areasForSport = _areas.where((a) => a.facilitySportId == fs.id).toList();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fs.customSportName ?? sport?.name ?? 'Sport',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _PeriodsEditor(
                                periods: _defaultPeriods[fs.id] ?? [],
                                onAdd: () => setState(() => _defaultPeriods[fs.id]!.add(_newPeriod())),
                                onRemove: (p) => setState(() {
                                  _defaultPeriods[fs.id]!.remove(p);
                                  p.dispose();
                                }),
                                onPickTime: _pickTime,
                                onChanged: () => setState(() {}),
                              ),
                              if (areasForSport.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.md),
                                const Divider(),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Customize individual court/turf pricing',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                ...areasForSport.map((area) {
                                  final o = _overrides[area.id]!;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                    child: Container(
                                      padding: const EdgeInsets.all(AppSpacing.sm),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: AppColors.border),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(child: Text(area.name)),
                                              if (o.active)
                                                TextButton(
                                                  onPressed: () => setState(() => o.active = false),
                                                  child: const Text('Use default rate'),
                                                )
                                              else
                                                OutlinedButton(
                                                  onPressed: () => setState(() => o.active = true),
                                                  child: const Text('Customize'),
                                                ),
                                            ],
                                          ),
                                          if (!o.active)
                                            const Text('Uses default rate ✓', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                                          if (o.active)
                                            _PeriodsEditor(
                                              periods: o.periods,
                                              onAdd: () => setState(() => o.periods.add(_newPeriod())),
                                              onRemove: (p) => setState(() {
                                                o.periods.remove(p);
                                                p.dispose();
                                              }),
                                              onPickTime: _pickTime,
                                              onChanged: () => setState(() {}),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
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

class _PeriodsEditor extends StatelessWidget {
  const _PeriodsEditor({
    required this.periods,
    required this.onAdd,
    required this.onRemove,
    required this.onPickTime,
    required this.onChanged,
  });

  final List<_PeriodState> periods;
  final VoidCallback onAdd;
  final ValueChanged<_PeriodState> onRemove;
  final Future<void> Function(String? current, ValueChanged<String> onPicked) onPickTime;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...periods.map((p) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    DropdownButton<String>(
                      value: p.draft.dayType,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: _dayTypeOptions
                          .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          p.draft.dayType = v;
                          onChanged();
                        }
                      },
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Full day', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        Switch(
                          value: p.draft.coversFullDay,
                          onChanged: (v) {
                            p.draft.coversFullDay = v;
                            onChanged();
                          },
                        ),
                      ],
                    ),
                    if (periods.length > 1)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Remove period',
                        onPressed: () => onRemove(p),
                      ),
                  ],
                ),
                if (!p.draft.coversFullDay)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _TimeChip(
                          label: 'From',
                          time: p.draft.startTime,
                          onTap: () => onPickTime(p.draft.startTime, (t) {
                            p.draft.startTime = t;
                            onChanged();
                          }),
                        ),
                        _TimeChip(
                          label: 'To',
                          time: p.draft.endTime,
                          onTap: () => onPickTime(p.draft.endTime, (t) {
                            p.draft.endTime = t;
                            onChanged();
                          }),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: p.amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Rate (₹ / hour)',
                      isDense: true,
                    ),
                  ),
                ),
                if (p.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(p.error!, style: const TextStyle(color: AppColors.destructive, fontSize: 11)),
                  ),
              ],
            ),
          );
        }),
        TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add another period'),
          onPressed: onAdd,
        ),
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.time, required this.onTap});

  final String label;
  final String? time;
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
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            Text(time != null ? Formatters.time12h(time!) : '--:--'),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}