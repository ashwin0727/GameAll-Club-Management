import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/facility.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../authentication/session_controller.dart';
import 'onboarding_progress_bar.dart';
import '../../shared/widgets/app_dropdown.dart';

class FacilityDetailsScreen extends ConsumerStatefulWidget {
  const FacilityDetailsScreen({super.key});

  @override
  ConsumerState<FacilityDetailsScreen> createState() => _FacilityDetailsScreenState();
}

class _FacilityDetailsScreenState extends ConsumerState<FacilityDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _customType = TextEditingController();
  final _phone = TextEditingController();
  final _addressLine = TextEditingController();
  final _area = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pinCode = TextEditingController();
  final _description = TextEditingController();

  FacilityType _type = FacilityType.multiSport;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _name.dispose();
    _customType.dispose();
    _phone.dispose();
    _addressLine.dispose();
    _area.dispose();
    _city.dispose();
    _state.dispose();
    _pinCode.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final user = ref.read(sessionControllerProvider).user;
    if (user == null) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Please sign in and try again.';
      });
      return;
    }

    try {
      final facility = await ref.read(facilityRepositoryProvider).createFacility(
        name: _name.text.trim(),
        type: _type,
        customType: _type == FacilityType.other ? _customType.text.trim() : null,
        businessEmail: user.email,
        businessPhone: _phone.text.trim(),
        address: FacilityAddress(
          line1: _addressLine.text.trim(),
          area: _area.text.trim(),
          city: _city.text.trim(),
          state: _state.text.trim(),
          country: 'India',
          pinCode: _pinCode.text.trim(),
        ),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      );
      await ref
          .read(facilityRepositoryProvider)
          .updateOnboardingStep(facility.id, OnboardingStep.sports);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.onboardingSports);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e, stack) {
      debugPrint('Onboarding facility save failed: $e\n$stack');
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const OnboardingProgressBar(currentStep: 1)),
      body: SafeArea(
        child: ResponsivePage(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tell us about your facility', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                const Text('This helps customers find and understand your facility.'),
                const SizedBox(height: AppSpacing.xl),
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: const TextStyle(color: AppColors.destructive)),
                  const SizedBox(height: AppSpacing.md),
                ],
                AppTextField(
                  label: 'Facility Name',
                  controller: _name,
                  validator: (v) => Validators.name(v),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppDropdown<FacilityType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Facility Type'),
                  items: FacilityType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (value) => setState(() => _type = value ?? _type),
                ),
                if (_type == FacilityType.other) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    label: 'Specify Facility Type',
                    controller: _customType,
                    validator: (v) => Validators.required(v, field: 'Facility type'),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Business Contact Number',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Location', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Address',
                  controller: _addressLine,
                  validator: (v) => Validators.required(v, field: 'Address'),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Area / Locality',
                  controller: _area,
                  validator: (v) => Validators.required(v, field: 'Area'),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'City',
                  controller: _city,
                  validator: (v) => Validators.required(v, field: 'City'),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'State',
                  controller: _state,
                  validator: (v) => Validators.required(v, field: 'State'),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'PIN Code',
                  controller: _pinCode,
                  keyboardType: TextInputType.number,
                  validator: Validators.pinCode,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Branding (optional)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Description',
                  controller: _description,
                  maxLines: 4,
                ),
                const SizedBox(height: AppSpacing.xl),
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
      ),
    );
  }
}