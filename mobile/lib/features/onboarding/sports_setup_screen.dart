import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/facility.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'onboarding_progress_bar.dart';

class SportsSetupScreen extends ConsumerStatefulWidget {
  const SportsSetupScreen({super.key});

  @override
  ConsumerState<SportsSetupScreen> createState() => _SportsSetupScreenState();
}

class _SportsSetupScreenState extends ConsumerState<SportsSetupScreen> {
  bool _isLoading = true;
  String? _loadError;
  String? _facilityId;
  List<Sport> _sports = [];
  final Set<String> _selectedIds = {};
  final _customName = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customName.dispose();
    super.dispose();
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
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final existing = await ref.read(sportsRepositoryProvider).getFacilitySports(facility.id);

      setState(() {
        _facilityId = facility.id;
        _sports = sports;
        _selectedIds
          ..clear()
          ..addAll(existing.map((e) => e.sportId));
        final otherRow = existing.where((e) => e.customSportName != null).firstOrNull;
        if (otherRow != null) _customName.text = otherRow.customSportName!;
        _isLoading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedIds.isEmpty || _facilityId == null) return;
    final otherSport = _sports.where((s) => s.code == otherSportCode).firstOrNull;
    if (otherSport != null && _selectedIds.contains(otherSport.id) && _customName.text.trim().length < 2) {
      setState(() => _submitError = 'Enter a sport name (at least 2 characters).');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await ref.read(sportsRepositoryProvider).saveFacilitySports(
        _facilityId!,
        _selectedIds.toList(),
        customSportName: otherSport != null && _selectedIds.contains(otherSport.id)
            ? _customName.text.trim()
            : null,
      );
      await ref
          .read(facilityRepositoryProvider)
          .updateOnboardingStep(_facilityId!, OnboardingStep.courts);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.onboardingCourts);
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
      appBar: AppBar(title: const OnboardingProgressBar(currentStep: 2)),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading sports…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Which sports do you offer?', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    const Text('Select every sport this facility offers.'),
                    const SizedBox(height: AppSpacing.xl),
                    if (_submitError != null) ...[
                      Text(_submitError!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: _sports.map((sport) {
                        final selected = _selectedIds.contains(sport.id);
                        return _SportChip(
                          sport: sport,
                          selected: selected,
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedIds.remove(sport.id);
                            } else {
                              _selectedIds.add(sport.id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    if (_sports.any((s) => s.code == otherSportCode && _selectedIds.contains(s.id))) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(label: 'Sport Name', controller: _customName),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    PrimaryButton(
                      label: 'Continue →',
                      loadingLabel: 'Saving…',
                      isLoading: _isSubmitting,
                      onPressed: _selectedIds.isEmpty ? null : _submit,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SportChip extends StatelessWidget {
  const _SportChip({required this.sport, required this.selected, required this.onTap});

  final Sport sport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget, minWidth: 140),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sport.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: Text(sport.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}