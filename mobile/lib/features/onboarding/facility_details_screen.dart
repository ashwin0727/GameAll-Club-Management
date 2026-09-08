import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/facility.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/app_text_field.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import 'onboarding_scaffold.dart';

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
  final _locationUrl = TextEditingController();

  final _picker = ImagePicker();
  Uint8List? _logoBytes;
  String? _logoUrl;
  bool _uploadingLogo = false;

  bool _pinExpanded = false;
  bool _showMore = false;

  FacilityType _type = FacilityType.multiSport;
  bool _isSubmitting = false;
  String? _errorMessage;

  /// Set when the owner already created a facility and stepped back here —
  /// the form then prefills and saves as an update instead of a create.
  String? _existingFacilityId;

  @override
  void initState() {
    super.initState();
    _prefillFromExisting();
  }

  Future<void> _prefillFromExisting() async {
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null || !mounted) return;
      setState(() {
        _existingFacilityId = facility.id;
        _name.text = facility.name;
        _type = facility.type;
        _customType.text = facility.customType ?? '';
        _phone.text = facility.businessPhone;
        _addressLine.text = facility.address.line1;
        _area.text = facility.address.area;
        _city.text = facility.address.city;
        _state.text = facility.address.state;
        _pinCode.text = facility.address.pinCode;
        _description.text = facility.description ?? '';
        _locationUrl.text = facility.locationUrl ?? '';
        _logoUrl = facility.logoUrl;
        _showMore = (facility.description ?? '').isNotEmpty ||
            facility.address.area.isNotEmpty ||
            facility.address.state.isNotEmpty;
      });
    } catch (e, stack) {
      debugPrint('Facility prefill failed: $e\n$stack');
    }
  }

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
    _locationUrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      // Let the owner reframe / zoom / crop before it's saved.
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 512,
        maxHeight: 512,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Adjust logo',
            lockAspectRatio: true,
            hideBottomControls: false,
            toolbarColor: const Color(0xFF0C1628),
            toolbarWidgetColor: const Color(0xFFF8FAFC),
            backgroundColor: const Color(0xFF07101F),
            activeControlsWidgetColor: const Color(0xFF00F08A),
          ),
          IOSUiSettings(title: 'Adjust logo', aspectRatioLockEnabled: true),
        ],
      );
      if (cropped == null) return;
      final bytes = await cropped.readAsBytes();
      setState(() {
        _logoBytes = bytes;
        _uploadingLogo = true;
        _errorMessage = null;
      });
      final url = await ref
          .read(facilityRepositoryProvider)
          .uploadFacilityLogo(bytes, cropped.path);
      if (!mounted) return;
      setState(() {
        _logoUrl = url;
        _uploadingLogo = false;
      });
    } catch (e, stack) {
      debugPrint('Logo pick/upload failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _uploadingLogo = false;
        _logoBytes = null;
        _errorMessage = 'We couldn’t upload that image. Please try another.';
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_uploadingLogo) return;
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
      final repo = ref.read(facilityRepositoryProvider);
      final address = FacilityAddress(
        line1: _addressLine.text.trim(),
        area: _area.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim(),
        country: 'India',
        pinCode: _pinCode.text.trim(),
      );
      final description =
          _description.text.trim().isEmpty ? null : _description.text.trim();
      final existingId = _existingFacilityId;

      final Facility facility;
      if (existingId != null) {
        facility = await repo.updateFacility(
          id: existingId,
          name: _name.text.trim(),
          type: _type,
          customType: _type == FacilityType.other ? _customType.text.trim() : null,
          businessPhone: _phone.text.trim(),
          address: address,
          logoUrl: _logoUrl,
          locationUrl: _locationUrl.text.trim(),
          description: description,
        );
      } else {
        facility = await repo.createFacility(
          name: _name.text.trim(),
          type: _type,
          customType: _type == FacilityType.other ? _customType.text.trim() : null,
          businessEmail: user.email,
          businessPhone: _phone.text.trim(),
          address: address,
          logoUrl: _logoUrl,
          locationUrl: _locationUrl.text.trim(),
          description: description,
        );
      }

      // Only advance the step forward, never drag it back.
      final step = ref.read(sessionControllerProvider).facility?.onboardingStep;
      if (step == null || step == OnboardingStep.facilityDetails) {
        await repo.updateOnboardingStep(facility.id, OnboardingStep.sportsCourts);
      }
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.push(AppRoutes.onboardingSportsCourts);
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
    final locationLink = _locationUrl.text.trim();
    return Form(
      key: _formKey,
      child: OnboardingScaffold(
        stepIndex: 0,
        title: 'Where do you play?',
        subtitle: 'This is what guests see on your booking page and invoices.',
        onBack: () => context.go(AppRoutes.onboardingWelcome),
        onSkip: () => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Add your facility details to continue.')),
          ),
        footer: AuthGradientButton(
          label: 'Next · sports & courts  ›',
          loadingLabel: 'Saving…',
          isLoading: _isSubmitting,
          onPressed: _submit,
        ),
        children: [
          if (_errorMessage != null) ...[
            _ErrorText(_errorMessage!),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _LogoTile(
                bytes: _logoBytes,
                imageUrl: _logoUrl,
                uploading: _uploadingLogo,
                onTap: _pickLogo,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: _Field(
                  label: 'Facility name',
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  validator: (v) => Validators.name(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg2),
          _Field(
            label: 'Street address',
            controller: _addressLine,
            textInputAction: TextInputAction.next,
            validator: (v) => Validators.required(v, field: 'Address'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Field(
                  label: 'City',
                  controller: _city,
                  textInputAction: TextInputAction.next,
                  validator: (v) => Validators.required(v, field: 'City'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Field(
                  label: 'PIN code',
                  controller: _pinCode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: Validators.pinCode,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: Validators.phone,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              // Behaves like every other field: the name sits inside as a
              // hint and floats up as a label once you tap in — but "+91"
              // is a fixed prefix that's always on screen.
              labelText: 'Number guests can call',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
                child: Text(
                  '+91',
                  style: TextStyle(
                    color: context.tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _MapPinCard(
            controller: _locationUrl,
            expanded: _pinExpanded,
            savedLink: locationLink,
            onToggle: () => setState(() => _pinExpanded = !_pinExpanded),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg2),
          _MoreDetails(
            open: _showMore,
            onToggle: () => setState(() => _showMore = !_showMore),
            child: Column(
              children: [
                AppDropdown<FacilityType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Facility type'),
                  items: FacilityType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (value) => setState(() => _type = value ?? _type),
                ),
                if (_type == FacilityType.other) ...[
                  const SizedBox(height: AppSpacing.md),
                  _Field(
                    label: 'Specify facility type',
                    controller: _customType,
                    validator: (v) => Validators.required(v, field: 'Facility type'),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _Field(label: 'Area / locality', controller: _area),
                const SizedBox(height: AppSpacing.md),
                _Field(label: 'State', controller: _state),
                const SizedBox(height: AppSpacing.md),
                _Field(
                  label: 'Short description',
                  controller: _description,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

/// Thin adapter so this screen's fields render exactly like the sign-in /
/// create-account fields: the app's standard [AppTextField] with a floating
/// label and no example-value placeholder.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      maxLines: maxLines,
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({
    required this.bytes,
    required this.imageUrl,
    required this.uploading,
    required this.onTap,
  });

  final Uint8List? bytes;
  final String? imageUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: Container(
        height: 76,
        width: 76,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tokens.borderColor),
        ),
        child: uploading
            ? const Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : bytes != null
                ? Image.memory(bytes!, fit: BoxFit.cover)
                : (imageUrl != null && imageUrl!.isNotEmpty)
                ? Image.network(imageUrl!, fit: BoxFit.cover)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined,
                          size: 20, color: tokens.textSecondary),
                      const SizedBox(height: 4),
                      Text(
                        'Logo',
                        style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _MapPinCard extends StatelessWidget {
  const _MapPinCard({
    required this.controller,
    required this.expanded,
    required this.savedLink,
    required this.onToggle,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool expanded;
  final String savedLink;
  final VoidCallback onToggle;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasLink = savedLink.isNotEmpty;
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
            children: [
              Icon(Icons.location_on_outlined, size: 20, color: tokens.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasLink ? 'Map location added' : 'Drop a map pin',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasLink
                          ? savedLink
                          : 'Paste a Google Maps link — helps guests find the entrance.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  expanded ? 'Done' : (hasLink ? 'Change' : 'Add'),
                  style: TextStyle(
                    color: tokens.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Google Maps link',
              controller: controller,
              keyboardType: TextInputType.url,
              onChanged: (_) => onChanged(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoreDetails extends StatelessWidget {
  const _MoreDetails({
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Text(
                'More details (optional)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: tokens.textSecondary,
              ),
            ],
          ),
        ),
        if (open) ...[
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.tokens.destructive.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        message,
        style: TextStyle(color: context.tokens.destructive, fontSize: 13),
      ),
    );
  }
}
