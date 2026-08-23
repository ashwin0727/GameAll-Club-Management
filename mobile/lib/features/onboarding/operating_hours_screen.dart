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
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'onboarding_progress_bar.dart';

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
        if (mounted) context.go(AppRoutes.onboardingFacility);
        return;
      }
      final schedule = await ref.read(operatingHoursRepositoryProvider).getFacilitySchedule(facility.id);
      setState(() {
        _facilityId = facility.id;
        if (schedule != null && schedule.days.isNotEmpty) {
          _days = daysOfWeek
              .map((d) => schedule.days.where((day) => day.dayOfWeek == d).firstOrNull ?? OperatingDay.defaultOpen(d))
              .toList();
        }
        _isLoading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  void _updateDay(int dayOfWeek, OperatingDay Function(OperatingDay) update) {
    setState(() {
      _days = _days.map((d) => d.dayOfWeek == dayOfWeek ? update(d) : d).toList();
    });
  }

  Future<void> _pickTime(int dayOfWeek, bool isStart) async {
    final day = _days.firstWhere((d) => d.dayOfWeek == dayOfWeek);
    final slot = day.slots.isNotEmpty
        ? day.slots.first
        : const OperatingTimeSlot(startTime: '06:00', endTime: '23:00', crossesMidnight: false, displayOrder: 0);
    final current = isStart ? slot.startTime : slot.endTime;
    final parts = current.split(':');
    final initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 6, minute: int.tryParse(parts[1]) ?? 0);

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

    final newSlot = OperatingTimeSlot(
      startTime: isStart ? formatted : slot.startTime,
      endTime: isStart ? slot.endTime : formatted,
      crossesMidnight: false,
      displayOrder: 0,
    );
    _updateDay(dayOfWeek, (d) => d.copyWith(slots: [newSlot]));
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await ref.read(operatingHoursRepositoryProvider).saveFacilitySchedule(_facilityId!, _days);
      await ref
          .read(facilityRepositoryProvider)
          .updateOnboardingStep(_facilityId!, OnboardingStep.pricing);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.onboardingPricing);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _submitError = e.message);
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
                    const SizedBox(height: AppSpacing.xl),
                    if (_submitError != null) ...[
                      Text(_submitError!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    ...displayOrder.map((dow) {
                      final day = _days.firstWhere((d) => d.dayOfWeek == dow);
                      final isOpen = !day.isClosed;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(dayLabels[dow], style: Theme.of(context).textTheme.titleSmall),
                                  ),
                                  Switch(
                                    value: isOpen,
                                    onChanged: (value) => _updateDay(
                                      dow,
                                      (d) => d.copyWith(
                                        isClosed: !value,
                                        slots: value && d.slots.isEmpty
                                            ? OperatingDay.defaultOpen(dow).slots
                                            : d.slots,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (isOpen) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Wrap(
                                  spacing: AppSpacing.md,
                                  runSpacing: AppSpacing.sm,
                                  children: [
                                    _TimeChip(
                                      label: 'Opens',
                                      time: day.slots.isNotEmpty ? day.slots.first.startTime : '06:00',
                                      onTap: () => _pickTime(dow, true),
                                    ),
                                    _TimeChip(
                                      label: 'Closes',
                                      time: day.slots.isNotEmpty ? day.slots.first.endTime : '23:00',
                                      onTap: () => _pickTime(dow, false),
                                    ),
                                  ],
                                ),
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