import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/facility.dart';
import '../../data/models/pricing.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'onboarding_progress_bar.dart';

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
  final Map<String, TextEditingController> _rateControllers = {};
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _rateControllers.values) {
      c.dispose();
    }
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
      final facilitySports = await ref.read(sportsRepositoryProvider).getFacilitySports(facility.id);
      if (facilitySports.isEmpty) {
        if (mounted) context.go(AppRoutes.onboardingSports);
        return;
      }
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final plan = await ref.read(pricingRepositoryProvider).getPricingPlan(facility.id);

      for (final fs in facilitySports) {
        final existing = plan?.rules.where(
          (r) => r.facilitySportId == fs.id && r.playingAreaId == null,
        ).firstOrNull;
        _rateControllers[fs.id] = TextEditingController(
          text: existing != null ? existing.amountRupees.toString() : '',
        );
      }

      setState(() {
        _facilityId = facility.id;
        _facilitySports = facilitySports;
        _sports = sports;
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
    final rules = <PricingRule>[];
    for (final fs in _facilitySports) {
      final text = _rateControllers[fs.id]?.text.trim() ?? '';
      final error = Validators.positiveAmount(text);
      if (error != null) {
        setState(() => _submitError = 'Set a valid rate for every sport.');
        return;
      }
      rules.add(
        PricingRule(
          facilitySportId: fs.id,
          dayType: 'ALL_DAYS',
          coversFullDay: true,
          amountMinor: (num.parse(text) * 100).round(),
          currency: 'INR',
          pricingUnit: 'PER_HOUR',
          priority: 0,
        ),
      );
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await ref.read(pricingRepositoryProvider).savePricingRules(_facilityId!, rules);
      await ref
          .read(facilityRepositoryProvider)
          .updateOnboardingStep(_facilityId!, OnboardingStep.completed);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.onboardingComplete);
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
                      Text(_submitError!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    ..._facilitySports.map((fs) {
                      final sport = _sports.where((s) => s.id == fs.sportId).firstOrNull;
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
                              AppTextField(
                                label: 'Default Rate (₹ / hour)',
                                controller: _rateControllers[fs.id],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}