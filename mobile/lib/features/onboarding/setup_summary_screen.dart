import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/facility.dart';
import '../../data/models/setup_summary.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'onboarding_progress_bar.dart';

class SetupSummaryScreen extends ConsumerStatefulWidget {
  const SetupSummaryScreen({super.key});

  @override
  ConsumerState<SetupSummaryScreen> createState() => _SetupSummaryScreenState();
}

class _SetupSummaryScreenState extends ConsumerState<SetupSummaryScreen> {
  bool _isLoading = true;
  String? _loadError;
  SetupSummary? _summary;
  bool _isCompleting = false;
  String? _completeError;

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
      final summary = await ref.read(onboardingRepositoryProvider).getSetupSummary(facility.id);
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
      // Landing here with a facility already COMPLETED means nothing left to
      // validate — but re-running the (idempotent) RPC is still worth doing
      // as a self-heal for any account whose profiles.onboarding_completed
      // never got flipped by an older client bug. Best-effort.
      if (summary.facility.onboardingStep == OnboardingStep.completed) {
        unawaited(ref.read(onboardingRepositoryProvider).completeSetup(facility.id).catchError((_) => facility));
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      // Anything that isn't an AppException used to escape this method
      // and leave the screen dead: no spinner, no error, no retry.
      debugPrint('Onboarding setup summary load failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'We couldn’t load this step. Please try again.';
      });
    }
  }

  Future<void> _complete() async {
    final summary = _summary;
    if (summary == null) return;

    setState(() {
      _isCompleting = true;
      _completeError = null;
    });
    try {
      await ref.read(onboardingRepositoryProvider).completeSetup(summary.facility.id);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _completeError = e.message);
    } catch (e, stack) {
      debugPrint('Onboarding setup summary save failed: $e\n$stack');
      if (!mounted) return;
      setState(() => _completeError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const OnboardingProgressBar(currentStep: 6)),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading your setup…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : _buildBody(context, _summary!),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SetupSummary summary) {
    if (summary.facility.onboardingStep == OnboardingStep.completed) {
      return ResponsivePage(
        scrollable: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 56),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Your facility setup is already complete.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(label: 'Go to Dashboard', onPressed: () => context.go(AppRoutes.dashboard)),
          ],
        ),
      );
    }

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your facility is ready', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          const Text('Review your setup before you start managing your facility.'),
          const SizedBox(height: AppSpacing.xl),
          if (_completeError != null) ...[
            Text(_completeError!, style: const TextStyle(color: AppColors.destructive)),
            const SizedBox(height: AppSpacing.md),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Facility', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.onboardingFacility),
                      child: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(summary.facility.name),
                Text(summary.facility.address.city, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${summary.facilitySports.length} Sports · ${summary.playingAreas.length} Playing Areas',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Sports & Courts', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.onboardingSports),
                      child: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ...summary.facilitySports.map((fs) {
                  final sport = summary.sports.where((s) => s.id == fs.sportId).firstOrNull;
                  final areas = summary.playingAreas.where((a) => a.facilitySportId == fs.id).toList();
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '${fs.customSportName ?? sport?.name ?? 'Sport'} — ${areas.length} playing area${areas.length == 1 ? '' : 's'}',
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Operating Hours', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.onboardingOperatingHours),
                      child: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  summary.missingOperatingHours
                      ? 'Not configured yet.'
                      : 'Configured.',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Pricing', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.onboardingPricing),
                      child: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  summary.sportsMissingPricing.isEmpty
                      ? 'Configured for every sport.'
                      : 'Missing pricing for ${summary.sportsMissingPricing.join(', ')}.',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: summary.isReady
                ? const Row(
                    children: [
                      Icon(Icons.check_circle, color: AppColors.success, size: 20),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text('Ready to manage your facility')),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                          SizedBox(width: AppSpacing.sm),
                          Text('Setup needs attention'),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...summary.missingRequirements.map(
                        (req) => Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text('⚠ ${req.message}'),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Complete Setup →',
            loadingLabel: 'Completing Setup…',
            isLoading: _isCompleting,
            onPressed: summary.isReady ? _complete : null,
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}