import 'package:flutter/material.dart';

import '../../shared/utils/photo_picker.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/facility.dart';
import '../../data/models/facility_image.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/app_text_field.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import 'onboarding_scaffold.dart';

class FacilityDetailsScreen extends ConsumerStatefulWidget {
  const FacilityDetailsScreen({super.key});

  @override
  ConsumerState<FacilityDetailsScreen> createState() =>
      _FacilityDetailsScreenState();
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
  final _locationUrl = TextEditingController();

  Uint8List? _logoBytes;
  String? _logoUrl;
  bool _uploadingLogo = false;

  bool _showMore = false;

  // The venue profile GameAll's admin checks: indoor/outdoor, amenities and photos (at least one).
  VenueType? _venueType;
  FacilityAmenities _amenities = const FacilityAmenities();
  List<FacilityImage> _savedPhotos = [];
  final List<NewPhoto> _newPhotos = [];
  bool _addingPhoto = false;
  String? _venueTypeError;
  String? _photosError;

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
        _locationUrl.text = facility.locationUrl ?? '';
        _logoUrl = facility.logoUrl;
        _venueType = facility.venueType;
        _amenities = facility.amenities;
        _showMore =
            facility.address.area.isNotEmpty ||
            facility.address.state.isNotEmpty;
      });
      // Photos already saved on an earlier visit to this step.
      final photos = await ref
          .read(facilityRepositoryProvider)
          .listFacilityImages(facility.id);
      if (mounted) setState(() => _savedPhotos = photos);
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
    _locationUrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final picked = await pickPhoto(context);
      if (!mounted) return;
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
          IOSUiSettings(title: 'Adjust Logo', aspectRatioLockEnabled: true),
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

  Future<void> _addPhoto() async {
    if (_savedPhotos.length + _newPhotos.length >= maxFacilityPhotos) {
      setState(
        () => _photosError = 'You can add up to $maxFacilityPhotos photos.',
      );
      return;
    }
    setState(() => _addingPhoto = true);
    try {
      final picked = await pickPhoto(context, maxWidth: 1600);
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _newPhotos.add(NewPhoto(bytes, picked.name));
        _photosError = null;
      });
    } catch (e, stack) {
      debugPrint('Photo pick failed: $e\n$stack');
      if (mounted) {
        setState(
          () =>
              _photosError = 'We couldn’t use that photo. Please try another.',
        );
      }
    } finally {
      if (mounted) setState(() => _addingPhoto = false);
    }
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    // Indoor/outdoor and at least one photo are required too; show both messages together with the field errors.
    setState(() {
      _venueTypeError = _venueType == null ? 'Choose indoor or outdoor.' : null;
      _photosError = (_savedPhotos.isEmpty && _newPhotos.isEmpty)
          ? 'Add at least one photo of your facility.'
          : null;
    });
    if (!formOk || _venueTypeError != null || _photosError != null) return;
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
      final existingId = _existingFacilityId;

      final Facility facility;
      if (existingId != null) {
        facility = await repo.updateFacility(
          id: existingId,
          name: _name.text.trim(),
          type: _type,
          customType: _type == FacilityType.other
              ? _customType.text.trim()
              : null,
          businessPhone: _phone.text.trim(),
          address: address,
          logoUrl: _logoUrl,
          locationUrl: _locationUrl.text.trim(),
          venueType: _venueType,
          amenities: _amenities,
        );
      } else {
        facility = await repo.createFacility(
          name: _name.text.trim(),
          type: _type,
          customType: _type == FacilityType.other
              ? _customType.text.trim()
              : null,
          businessEmail: user.email,
          businessPhone: _phone.text.trim(),
          address: address,
          logoUrl: _logoUrl,
          locationUrl: _locationUrl.text.trim(),
          venueType: _venueType,
          amenities: _amenities,
        );
      }

      // The photos go up now that the facility exists; they start waiting for GameAll's check. Anything already uploaded on an
      // earlier try stays, so a retry never duplicates.
      final urls = <String>[];
      for (final photo in List.of(_newPhotos)) {
        urls.add(await repo.uploadFacilityPhoto(photo.bytes, photo.name));
        _newPhotos.remove(photo);
      }
      await repo.addFacilityImages(
        facility.id,
        urls,
        firstSortOrder: _savedPhotos.length,
      );
      _existingFacilityId = facility.id;

      // Only advance the step forward, never drag it back.
      final step = ref.read(sessionControllerProvider).facility?.onboardingStep;
      if (step == null || step == OnboardingStep.facilityDetails) {
        await repo.updateOnboardingStep(
          facility.id,
          OnboardingStep.sportsCourts,
        );
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
            const SnackBar(
              content: Text('Add your facility details to continue.'),
            ),
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
                  label: 'Facility Name',
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  validator: (v) => Validators.name(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg2),
          _Field(
            label: 'Street Address',
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
                  label: 'PIN Code',
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
            validator: Validators.mobile,
            // Digits only, capped at 10 — a pasted "+91 98765-43210" or a stray letter never lands in the field.
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              // Behaves like every other field: the name sits inside as a
              // hint and floats up as a label once you tap in — but "+91"
              // is a fixed prefix that's always on screen.
              labelText: 'Number Guests Can Call',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.sm,
                ),
                child: Text(
                  '+91',
                  style: TextStyle(
                    color: context.tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Field(
            label: 'Google Map Location Link',
            controller: _locationUrl,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            validator: Validators.googleMapsLink,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Open your facility in Google Maps, tap Share, copy the link and paste it here. GameAll checks it points at the right place.',
            style: TextStyle(
              fontSize: 12,
              color: context.tokens.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg2),
          VenueTypePicker(
            value: _venueType,
            error: _venueTypeError,
            onChanged: (v) => setState(() {
              _venueType = v;
              _venueTypeError = null;
            }),
          ),
          const SizedBox(height: AppSpacing.lg2),
          PhotosPicker(
            saved: _savedPhotos,
            added: _newPhotos,
            busy: _addingPhoto,
            error: _photosError,
            onAdd: _addPhoto,
            onRemoveNew: (p) => setState(() => _newPhotos.remove(p)),
          ),
          const SizedBox(height: AppSpacing.lg2),
          AmenitiesCard(
            value: _amenities,
            onChanged: (a) => setState(() => _amenities = a),
          ),
          const SizedBox(height: AppSpacing.lg2),
          _MoreDetails(
            open: _showMore,
            onToggle: () => setState(() => _showMore = !_showMore),
            child: Column(
              children: [
                AppDropdown<FacilityType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Facility Type'),
                  items: FacilityType.values
                      .map(
                        (t) => DropdownMenuItem(value: t, child: Text(t.label)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _type = value ?? _type),
                ),
                if (_type == FacilityType.other) ...[
                  const SizedBox(height: AppSpacing.md),
                  _Field(
                    label: 'Specify Facility Type',
                    controller: _customType,
                    validator: (v) =>
                        Validators.required(v, field: 'Facility type'),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _Field(label: 'Area / Locality', controller: _area),
                const SizedBox(height: AppSpacing.md),
                _Field(label: 'State', controller: _state),
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
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
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
                  Icon(
                    Icons.add_a_photo_outlined,
                    size: 20,
                    color: tokens.textSecondary,
                  ),
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

/// Indoor or Outdoor: exactly two choices.
class VenueTypePicker extends StatelessWidget {
  const VenueTypePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.error,
  });

  final VenueType? value;
  final String? error;
  final ValueChanged<VenueType> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Venue Type',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (final type in VenueType.values) ...[
              if (type != VenueType.values.first)
                const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: value == type,
                  label: type.label,
                  child: GestureDetector(
                    key: ValueKey('venue-type-${type.name}'),
                    onTap: () => onChanged(type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: value == type
                            ? tokens.primary.withValues(alpha: 0.10)
                            : tokens.surface1,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                          color: value == type
                              ? tokens.primary
                              : tokens.borderColor,
                          width: value == type ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                value == type
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 18,
                                color: value == type
                                    ? tokens.primary
                                    : tokens.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                type.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            type.hint,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: tokens.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            error!,
            key: const ValueKey('venue-type-error'),
            style: TextStyle(fontSize: 12, color: tokens.destructive),
          ),
        ],
      ],
    );
  }
}

/// A photo picked but not uploaded yet.
class NewPhoto {
  NewPhoto(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

/// Facility photos: at least one is required. Saved ones show GameAll's verdict; new ones are uploaded when the step is saved.
class PhotosPicker extends StatelessWidget {
  const PhotosPicker({
    super.key,
    required this.saved,
    required this.added,
    required this.busy,
    required this.onAdd,
    required this.onRemoveNew,
    this.onRemoveSaved,
    this.error,
  });

  final List<FacilityImage> saved;
  final List<NewPhoto> added;
  final bool busy;
  final String? error;
  final VoidCallback onAdd;
  final ValueChanged<NewPhoto> onRemoveNew;

  /// Given, saved photos get a remove button too (the profile editor); the first-time setup has none.
  final ValueChanged<FacilityImage>? onRemoveSaved;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final total = saved.length + added.length;
    Widget tile(
      Widget image, {
      String? caption,
      String? note,
      Color? captionColor,
      VoidCallback? onRemove,
      bool cover = false,
    }) => SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(width: 104, height: 78, child: image),
              ),
              if (onRemove != null)
                Positioned(
                  right: 4,
                  top: 4,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (cover)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Cover',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: captionColor ?? tokens.textSecondary,
              ),
            ),
            if (note != null && note.isNotEmpty)
              Text(note, style: TextStyle(fontSize: 10.5, color: tokens.destructive)),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Facility Photos',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Add at least one clear photo of your facility (up to $maxFacilityPhotos). GameAll checks each photo before players see it; the first one is the cover.',
          style: TextStyle(
            fontSize: 12,
            color: tokens.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (var i = 0; i < saved.length; i++)
              tile(
                Image.network(
                  saved[i].url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: tokens.surface2,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                caption: saved[i].status.label,
                note: saved[i].status == VerificationStatus.rejected ? saved[i].note : null,
                onRemove: onRemoveSaved == null
                    ? null
                    : () => onRemoveSaved!(saved[i]),
                captionColor: switch (saved[i].status) {
                  VerificationStatus.verified => tokens.success,
                  VerificationStatus.rejected => tokens.destructive,
                  VerificationStatus.pending => tokens.textSecondary,
                },
                cover: i == 0,
              ),
            for (var i = 0; i < added.length; i++)
              tile(
                Image.memory(added[i].bytes, fit: BoxFit.cover),
                caption: 'Not uploaded yet',
                onRemove: () => onRemoveNew(added[i]),
                cover: saved.isEmpty && i == 0,
              ),
            if (total < maxFacilityPhotos)
              GestureDetector(
                key: const ValueKey('add-photo'),
                onTap: busy ? null : onAdd,
                child: Container(
                  width: 104,
                  height: 78,
                  decoration: BoxDecoration(
                    color: tokens.surface1,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: tokens.borderColor),
                  ),
                  child: busy
                      ? const Center(
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              color: tokens.textSecondary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add photo',
                              style: TextStyle(
                                fontSize: 11,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            error!,
            key: const ValueKey('photos-error'),
            style: TextStyle(fontSize: 12, color: tokens.destructive),
          ),
        ],
      ],
    );
  }
}

/// The five amenities, each a plain on/off switch.
class AmenitiesCard extends StatelessWidget {
  const AmenitiesCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final FacilityAmenities value;
  final ValueChanged<FacilityAmenities> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget row(
      String label,
      bool on,
      FacilityAmenities Function(bool) change, {
      Key? key,
    }) => SwitchListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
      ),
      value: on,
      onChanged: (v) => onChanged(change(v)),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      // The switches' tap highlight paints on the nearest Material, which must sit inside this decorated box.
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Amenities',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            Text(
              'Switch on what your facility offers. Players can filter venues by these.',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            row(
              'Free Parking',
              value.parking,
              (v) => value.copyWith(parking: v),
              key: const ValueKey('amenity-parking'),
            ),
            row(
              'Changing Rooms',
              value.changingRooms,
              (v) => value.copyWith(changingRooms: v),
              key: const ValueKey('amenity-changing'),
            ),
            row(
              'Toilets / Rest Room',
              value.toilets,
              (v) => value.copyWith(toilets: v),
              key: const ValueKey('amenity-toilets'),
            ),
            row(
              'Cafeteria',
              value.cafeteria,
              (v) => value.copyWith(cafeteria: v),
              key: const ValueKey('amenity-cafeteria'),
            ),
            row(
              'Equipment Rental',
              value.equipmentRental,
              (v) => value.copyWith(equipmentRental: v),
              key: const ValueKey('amenity-rental'),
            ),
          ],
        ),
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
        if (open) ...[const SizedBox(height: AppSpacing.md), child],
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
