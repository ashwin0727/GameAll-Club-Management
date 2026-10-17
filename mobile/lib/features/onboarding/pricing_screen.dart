import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/facility.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/pricing.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import 'onboarding_scaffold.dart';
import 'pricing_summary.dart';
import 'pricing_validation.dart';

const List<({String value, String label})> _dayTypeOptions = [
  (value: 'ALL_DAYS', label: 'All Days'),
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

  /// A period as the summary shows it — the amount comes from what is typed in the field right now, so the summary
  /// follows every keystroke.
  SummaryPeriod _summaryPeriod(_PeriodState p) => SummaryPeriod(
        dayType: p.draft.dayType,
        coversFullDay: p.draft.coversFullDay,
        startTime: p.draft.startTime,
        endTime: p.draft.endTime,
        amountInr: num.tryParse(p.amountController.text.trim()) ?? 0,
      );

  /// Pricing Summary — each sport's rate, courts/turfs with their own pricing, identical ones shown once.
  Widget _pricingSummary(BuildContext context) {
    var priced = 0;
    var custom = 0;
    final rows = <Widget>[];
    for (final fs in _facilitySports) {
      final sport = _sports.where((x) => x.id == fs.sportId).firstOrNull;
      final areas = _areas.where((a) => a.facilitySportId == fs.id).toList();
      final label = playingAreaLabelFor(sport?.code ?? 'OTHER');
      final defaults = (_defaultPeriods[fs.id] ?? const <_PeriodState>[]).map(_summaryPeriod).toList();
      final customized = [
        for (final a in areas)
          if (_overrides[a.id]?.active ?? false) CustomizedArea(a.name, _overrides[a.id]!.periods.map(_summaryPeriod).toList()),
      ];
      final blocks = sportSummaryBlocks(defaults: defaults, customized: customized, areaCount: areas.length, areaLabel: label);
      if (defaults.any((p) => p.isPriced) || customized.any((c) => c.periods.any((p) => p.isPriced))) priced++;
      custom += customized.length;

      Widget periodLines(List<SummaryPeriod> periods) => periods.isEmpty
          ? const Text('Not Set', style: TextStyle(fontSize: 12, color: AppColors.muted))
          : Column(
              children: [
                for (final p in periods)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Expanded(child: Text(periodLabel(p), style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                        Text('${Formatters.currencyInr(p.amountInr)} / hour', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            );

      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(fs.customSportName ?? sport?.name ?? 'Sport', style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${areas.length} ${areas.length == 1 ? label : '${label}s'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 2),
            for (final b in blocks)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: b.indented ? const EdgeInsets.only(left: AppSpacing.sm) : EdgeInsets.zero,
                decoration: b.indented ? const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border, width: 2))) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (b.title != null) Text(b.title!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    periodLines(b.periods),
                  ],
                ),
              ),
          ],
        ),
      ));
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pricing Summary', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          ...rows,
          const Divider(),
          Text(
            '${_facilitySports.length} Sports · ${_areas.length} Playing Areas · $priced priced${custom > 0 ? ' · $custom custom' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
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
        if (mounted) context.go(AppRoutes.onboardingSportsCourts);
        return;
      }
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id);
      final plan = await ref.read(pricingRepositoryProvider).getPricingPlan(facility.id);

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

  /// True when the sport's own rate isn't needed: it has courts, every one is customized with a real price, and the
  /// default itself was left blank. Mirrors the web, where a sport whose courts all have their own pricing doesn't
  /// also need a default rate.
  bool _defaultNotNeeded(String facilitySportId) {
    final areas = _areas.where((a) => a.facilitySportId == facilitySportId).toList();
    if (areas.isEmpty) return false;
    final everyCourtPriced = areas.every((a) {
      final o = _overrides[a.id];
      if (o == null || !o.active || o.periods.isEmpty) return false;
      return o.periods.every((p) => (num.tryParse(p.amountController.text.trim()) ?? 0) > 0);
    });
    final defaultBlank = (_defaultPeriods[facilitySportId] ?? const <_PeriodState>[]).every((p) => (num.tryParse(p.amountController.text.trim()) ?? 0) <= 0);
    return everyCourtPriced && defaultBlank;
  }

  bool _validateAll() {
    var isValid = true;
    setState(() {
      // Operating hours are set on the *next* step now, so there is nothing
      // to cross-check pricing periods against here.
      for (final entry in _defaultPeriods.entries) {
        final periods = entry.value;
        if (_defaultNotNeeded(entry.key)) {
          for (final p in periods) {
            p.error = null;
          }
          continue;
        }
        for (final p in periods) {
          _syncAmount(p);
          p.error = validatePricingPeriod(p.draft);
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
      setState(() => _submitError = 'Some pricing needs attention — fix the highlighted periods, then continue.');
      return;
    }

    final rules = <PricingRule>[];
    for (final fs in _facilitySports) {
      for (final p in _defaultPeriods[fs.id] ?? []) {
        if (_defaultNotNeeded(fs.id)) break;
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
      await ref
          .read(facilityRepositoryProvider)
          .updateOnboardingStep(_facilityId!, OnboardingStep.operatingHours);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.push(AppRoutes.onboardingOperatingHours);
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
    if (_isLoading || _loadError != null) {
      return OnboardingScaffold(
        stepIndex: 2,
        title: 'Set Your Pricing',
        onBack: () => context.go(AppRoutes.onboardingSportsCourts),
        footer: const SizedBox.shrink(),
        children: [
          SizedBox(
            height: 320,
            child: _isLoading
                ? const LoadingView(message: 'Loading pricing…')
                : ErrorView(message: _loadError!, onRetry: _load),
          ),
        ],
      );
    }
    return OnboardingScaffold(
      stepIndex: 2,
      title: 'Set Your Pricing',
      subtitle: 'Define how much guests pay to use your courts and turfs.',
      onBack: () => context.go(AppRoutes.onboardingSportsCourts),
      // The error sits beside the button: the field at fault is usually far above, off screen.
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_submitError != null) ...[
            Text(_submitError!, style: const TextStyle(color: AppColors.destructive, fontSize: 12)),
            const SizedBox(height: AppSpacing.sm),
          ],
          AuthGradientButton(
            label: 'Next · operating hours  ›',
            loadingLabel: 'Saving…',
            isLoading: _isSubmitting,
            onPressed: _submit,
          ),
        ],
      ),
      children: [
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
                                                  child: const Text('Use Default Rate'),
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
        _pricingSummary(context),
      ],
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
                    AppInlineDropdown<String>(
                      value: p.draft.dayType,
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
                        const Text('Full Day', style: TextStyle(fontSize: 11, color: AppColors.muted)),
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
                      labelText: 'Rate (₹ / Hour)',
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
          label: const Text('Add Another Period'),
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