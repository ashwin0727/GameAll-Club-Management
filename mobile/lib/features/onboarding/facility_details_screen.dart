import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/facility.dart';
import '../../data/models/facility_image.dart';
import '../../data/repositories/facility_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/utils/photo_picker.dart';
import '../authentication/session_controller.dart';
import 'facility_setup_validation.dart';
import 'setup_ui.dart';

const String _draftKey = 'facility_setup_draft_v1';

/// Step 1 of the setup: Facility Information. Light page in the GameAll setup style — facility details and photos, the contact
/// person, booking policies and the amenities on offer.
class FacilityDetailsScreen extends ConsumerStatefulWidget {
  const FacilityDetailsScreen({super.key});

  @override
  ConsumerState<FacilityDetailsScreen> createState() => _FacilityDetailsScreenState();
}

class _FacilityDetailsScreenState extends ConsumerState<FacilityDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();

  final _name = TextEditingController();
  final _customType = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _description = TextEditingController();
  final _addressLine = TextEditingController();
  final _area = TextEditingController();
  final _city = TextEditingController();
  final _pinCode = TextEditingController();
  final _locationUrl = TextEditingController();
  final _contactName = TextEditingController();
  final _contactAlt = TextEditingController();

  // One key per field, in on-screen order, so a failed Next scrolls to the first problem.
  final _nameKey = GlobalKey<FormFieldState<String>>();
  final _customTypeKey = GlobalKey<FormFieldState<String>>();
  final _addressKey = GlobalKey<FormFieldState<String>>();
  final _areaKey = GlobalKey<FormFieldState<String>>();
  final _cityKey = GlobalKey<FormFieldState<String>>();
  final _stateKey = GlobalKey<FormFieldState<String>>();
  final _pinKey = GlobalKey<FormFieldState<String>>();
  final _locationKey = GlobalKey<FormFieldState<String>>();
  final _phoneKey = GlobalKey<FormFieldState<String>>();
  final _whatsappKey = GlobalKey<FormFieldState<String>>();
  final _descriptionKey = GlobalKey<FormFieldState<String>>();
  final _photosKey = GlobalKey();
  final _contactNameKey = GlobalKey<FormFieldState<String>>();
  final _contactAltKey = GlobalKey<FormFieldState<String>>();
  final _typeKey = GlobalKey<FormFieldState<FacilityType>>();
  final _roleKey = GlobalKey<FormFieldState<String>>();

  FacilityType _type = FacilityType.multiSport;
  OwnershipType _ownership = OwnershipType.owned;
  String? _state;
  String _role = 'Facility Owner';
  FacilityPolicies _policies = const FacilityPolicies();
  List<String> _amenityKeys = [];
  List<String> _customAmenities = [];

  List<FacilityImage> _savedPhotos = [];
  final List<NewPhoto> _newPhotos = [];
  bool _addingPhoto = false;
  String? _photosError;

  String? _logoUrl;
  bool _isSubmitting = false;
  String? _errorMessage;

  /// Set when the owner already created a facility and stepped back here — the form then prefills and saves as an update.
  String? _existingFacilityId;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [_name, _customType, _phone, _whatsapp, _description, _addressLine, _area, _city, _pinCode, _locationUrl, _contactName, _contactAlt]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── prefill / draft ──────────────────────────────────────────────────

  Future<void> _prefill() async {
    // A saved draft first (typed but never submitted), then the real facility on top if one exists.
    await _loadDraft();
    // The contact person defaults to the account holder (a saved draft or the facility, loaded next, wins).
    final account = ref.read(sessionControllerProvider).user;
    if (account != null && _contactName.text.trim().isEmpty) _contactName.text = account.fullName;
    try {
      final repo = ref.read(facilityRepositoryProvider);
      final facility = await repo.getFacility();
      if (facility == null || !mounted) return;
      setState(() {
        _existingFacilityId = facility.id;
        _name.text = facility.name;
        _type = facility.type;
        _typeKey.currentState?.didChange(_type);
        _customType.text = facility.customType ?? '';
        _ownership = facility.ownershipType;
        _phone.text = facility.businessPhone.replaceFirst(RegExp(r'^\+?91(?=\d{10}$)'), '');
        _whatsapp.text = facility.whatsappNumber ?? '';
        _description.text = facility.description ?? '';
        _addressLine.text = facility.address.line1;
        _area.text = facility.address.area;
        _city.text = facility.address.city;
        _state = kIndianStates.contains(facility.address.state) ? facility.address.state : null;
        _stateKey.currentState?.didChange(_state);
        _pinCode.text = facility.address.pinCode;
        _locationUrl.text = facility.locationUrl ?? '';
        _logoUrl = facility.logoUrl;
        final person = facility.contactPerson;
        if (person != null) {
          _contactName.text = person.name;
          _role = kContactRoles.contains(person.role) ? person.role : 'Other';
          _roleKey.currentState?.didChange(_role);
          _contactAlt.text = person.alternatePhone ?? '';
        }
        _policies = facility.policies;
        _amenityKeys = List.of(facility.amenityKeys);
        _customAmenities = List.of(facility.customAmenities);
      });
      final photos = await repo.listFacilityImages(facility.id);
      if (mounted) setState(() => _savedPhotos = photos);
    } catch (e, stack) {
      debugPrint('Facility prefill failed: $e\n$stack');
    }
  }

  Map<String, dynamic> _draftJson() => {
        'name': _name.text,
        'type': _type.toDb(),
        'customType': _customType.text,
        'ownership': _ownership.toDb(),
        'phone': _phone.text,
        'whatsapp': _whatsapp.text,
        'description': _description.text,
        'address': _addressLine.text,
        'area': _area.text,
        'city': _city.text,
        'state': _state,
        'pin': _pinCode.text,
        'location': _locationUrl.text,
        'contactName': _contactName.text,
        'role': _role,
        'contactAlt': _contactAlt.text,
        'policies': _policies.toDb(),
        'amenityKeys': _amenityKeys,
        'customAmenities': _customAmenities,
      };

  Future<void> _saveDraft({bool announce = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, jsonEncode(_draftJson()));
      if (announce && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Draft saved. You can pick up where you left off.')));
      }
    } catch (e) {
      debugPrint('Draft save failed: $e');
    }
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || !mounted) return;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      String s(String k) => (d[k] as String?) ?? '';
      setState(() {
        _name.text = s('name');
        _type = FacilityType.fromDb(s('type'));
        _typeKey.currentState?.didChange(_type);
        _customType.text = s('customType');
        _ownership = OwnershipType.fromDb(s('ownership'));
        _phone.text = s('phone');
        _whatsapp.text = s('whatsapp');
        _description.text = s('description');
        _addressLine.text = s('address');
        _area.text = s('area');
        _city.text = s('city');
        final st = d['state'] as String?;
        _state = st != null && kIndianStates.contains(st) ? st : null;
        _stateKey.currentState?.didChange(_state);
        _pinCode.text = s('pin');
        _locationUrl.text = s('location');
        _contactName.text = s('contactName');
        final role = s('role');
        _role = kContactRoles.contains(role) ? role : 'Facility Owner';
        _roleKey.currentState?.didChange(_role);
        _contactAlt.text = s('contactAlt');
        _policies = FacilityPolicies.fromJson((d['policies'] as Map?)?.cast<String, dynamic>() ?? const {});
        _amenityKeys = ((d['amenityKeys'] as List?) ?? const []).cast<String>().where((k) => kFacilityAmenities.any((a) => a.key == k)).toList();
        _customAmenities = ((d['customAmenities'] as List?) ?? const []).cast<String>();
      });
    } catch (e) {
      debugPrint('Draft load failed: $e');
    }
  }

  Future<void> _clearDraft() async {
    try {
      (await SharedPreferences.getInstance()).remove(_draftKey);
    } catch (_) {}
  }

  // ── photos ───────────────────────────────────────────────────────────

  Future<void> _addPhoto() async {
    if (_savedPhotos.length + _newPhotos.length >= FacilitySetupValidation.maxSetupPhotos) {
      setState(() => _photosError = 'You can add up to ${FacilitySetupValidation.maxSetupPhotos} photos.');
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
      if (mounted) setState(() => _photosError = 'We couldn’t use that photo. Please try another.');
    } finally {
      if (mounted) setState(() => _addingPhoto = false);
    }
  }

  // ── submit ───────────────────────────────────────────────────────────

  /// Scrolls to the first field (in on-screen order) that is showing an error.
  void _scrollToFirstProblem() {
    final ordered = <GlobalKey>[
      _nameKey, _typeKey, _customTypeKey, _addressKey, _areaKey, _cityKey, _stateKey, _pinKey, _locationKey, _phoneKey, _whatsappKey, _descriptionKey,
      _photosKey, _contactNameKey, _roleKey, _contactAltKey,
    ];
    for (final key in ordered) {
      final state = key.currentState;
      final hasError = state is FormFieldState ? state.hasError : _problemFor(key);
      final ctx = key.currentContext;
      if (hasError && ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.1, curve: Curves.easeOut);
        return;
      }
    }
  }

  bool _problemFor(GlobalKey key) => key == _photosKey && _photosError != null;

  Future<void> _submit() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() {
      _photosError = (_savedPhotos.isEmpty && _newPhotos.isEmpty) ? 'Add at least one photo of your facility.' : null;
      _errorMessage = null;
    });
    if (!formOk || _photosError != null) {
      setState(() => _errorMessage = 'Please fix the highlighted fields to continue.');
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFirstProblem());
      return;
    }

    setState(() => _isSubmitting = true);
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
        state: _state!,
        country: 'India',
        pinCode: _pinCode.text.trim(),
      );
      final extras = FacilitySetupExtras(
        ownership: _ownership,
        whatsappNumber: _whatsapp.text,
        description: _description.text,
        contactPerson: FacilityContactPerson(name: _contactName.text.trim(), role: _role, alternatePhone: _contactAlt.text.trim()),
        policies: _policies,
        amenityKeys: _amenityKeys,
        customAmenities: _customAmenities,
      );
      final customType = _type == FacilityType.other ? _customType.text.trim() : null;
      final existingId = _existingFacilityId;

      final Facility facility;
      if (existingId != null) {
        facility = await repo.updateFacility(
          id: existingId,
          name: _name.text.trim(),
          type: _type,
          customType: customType,
          businessPhone: _phone.text.trim(),
          address: address,
          logoUrl: _logoUrl,
          locationUrl: _locationUrl.text.trim(),
          extras: extras,
        );
      } else {
        facility = await repo.createFacility(
          name: _name.text.trim(),
          type: _type,
          customType: customType,
          businessEmail: user.email,
          businessPhone: _phone.text.trim(),
          address: address,
          logoUrl: _logoUrl,
          locationUrl: _locationUrl.text.trim(),
          extras: extras,
        );
      }

      // The photos go up now that the facility exists; they start waiting for GameAll's check. Anything already uploaded on an
      // earlier try stays, so a retry never duplicates.
      final urls = <String>[];
      for (final photo in List.of(_newPhotos)) {
        urls.add(await repo.uploadFacilityPhoto(photo.bytes, photo.name));
        _newPhotos.remove(photo);
      }
      await repo.addFacilityImages(facility.id, urls, firstSortOrder: _savedPhotos.length);
      _existingFacilityId = facility.id;

      // Only advance the step forward, never drag it back.
      final step = ref.read(sessionControllerProvider).facility?.onboardingStep;
      if (step == null || step == OnboardingStep.facilityDetails) {
        await repo.updateOnboardingStep(facility.id, OnboardingStep.sportsCourts);
      }
      await _clearDraft();
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

  // ── build ────────────────────────────────────────────────────────────

  List<TextInputFormatter> get _digits10 => [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)];

  Widget _phonePrefix() => Padding(
        padding: const EdgeInsets.only(left: 14, right: 8),
        child: Text('+91', style: setupText(size: 15, weight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(sessionControllerProvider).user;
    final email = account?.email ?? '';
    // The contact number is the mobile verified at signup: locked, with a Verified badge (older accounts without one type it).
    final verifiedMobile = account?.verifiedMobile;
    if (verifiedMobile != null && _phone.text != verifiedMobile) _phone.text = verifiedMobile;
    const gap = SizedBox(height: 16);

    return Form(
      key: _formKey,
      child: SetupPage(
        scrollController: _scroll,
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SetupButton(
                    label: 'Back',
                    icon: Icons.arrow_back,
                    onPressed: () async {
                      await _saveDraft(announce: false);
                      if (context.mounted) context.go(AppRoutes.onboardingWelcome);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SetupButton(label: 'Next', primary: true, trailingIcon: Icons.arrow_forward, loading: _isSubmitting, loadingLabel: 'Saving…', onPressed: _submit),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const ValueKey('save-draft'),
              onPressed: _isSubmitting ? null : _saveDraft,
              icon: const Icon(Icons.description_outlined, size: 18, color: SetupColors.secondary),
              label: Text('Save as Draft', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.secondary)),
            ),
          ],
        ),
        children: [
          const SetupStepper(current: 1),
          const SizedBox(height: 18),
          Text('Facility Information', style: setupText(size: 28, weight: FontWeight.w700, height: 1.1)),
          const SizedBox(height: 6),
          Text('Add the key details about your venue, amenities and owner contact.', style: setupText(size: 14, color: SetupColors.secondary, height: 1.4)),
          const SizedBox(height: 18),
          if (_errorMessage != null) SetupErrorBanner(_errorMessage!),

          // ── Facility information ────────────────────────────────────
          SetupCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SetupTextField(
                  label: 'Facility Name',
                  required: true,
                  controller: _name,
                  fieldKey: _nameKey,
                  hint: 'e.g. Champz Turf',
                  maxLength: 100,
                  validator: FacilitySetupValidation.facilityName,
                ),
                gap,
                SetupDropdown<FacilityType>(
                  label: 'Facility Type',
                  required: true,
                  value: _type,
                  fieldKey: _typeKey,
                  items: [for (final t in FacilityType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                if (_type == FacilityType.other) ...[
                  gap,
                  SetupTextField(
                    label: 'Specify Facility Type',
                    required: true,
                    controller: _customType,
                    fieldKey: _customTypeKey,
                    hint: 'e.g. Basketball Court',
                    maxLength: 50,
                    validator: (v) => FacilitySetupValidation.customType(v, required: true),
                  ),
                ],
                gap,
                SetupSegmented<OwnershipType>(
                  label: 'Ownership Type',
                  required: true,
                  keyPrefix: 'ownership',
                  value: _ownership,
                  options: [for (final o in OwnershipType.values) (value: o, label: o.label)],
                  onChanged: (v) => setState(() => _ownership = v),
                ),
                gap,
                SetupTextField(
                  label: 'Address',
                  required: true,
                  controller: _addressLine,
                  fieldKey: _addressKey,
                  hint: 'Building / street',
                  maxLength: 250,
                  validator: FacilitySetupValidation.address,
                ),
                gap,
                SetupTextField(label: 'Area / Locality', required: true, controller: _area, fieldKey: _areaKey, hint: 'e.g. Iyyapanthangal', maxLength: 100, validator: FacilitySetupValidation.area),
                gap,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: SetupTextField(label: 'City', required: true, controller: _city, fieldKey: _cityKey, hint: 'Chennai', validator: FacilitySetupValidation.city)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SetupTextField(
                        label: 'PIN Code',
                        required: true,
                        controller: _pinCode,
                        fieldKey: _pinKey,
                        hint: '600056',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        validator: Validators.pinCode,
                      ),
                    ),
                  ],
                ),
                gap,
                SetupDropdown<String>(
                  label: 'State',
                  required: true,
                  value: _state,
                  fieldKey: _stateKey,
                  hint: 'Select state',
                  items: [for (final s in kIndianStates) DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _state = v),
                  validator: FacilitySetupValidation.state,
                ),
                gap,
                SetupTextField(
                  label: 'Set Location on Map',
                  required: true,
                  controller: _locationUrl,
                  fieldKey: _locationKey,
                  hint: 'https://maps.app.goo.gl/...',
                  keyboardType: TextInputType.url,
                  prefix: const Padding(padding: EdgeInsets.only(left: 14, right: 8), child: Icon(Icons.location_on_outlined, size: 20, color: SetupColors.primary)),
                  validator: Validators.googleMapsLink,
                  helper: 'Open your facility in Google Maps, tap Share, copy the link and paste it here. GameAll checks it points at the right place.',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('open-maps'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.only(top: 4), minimumSize: const Size(0, 32), foregroundColor: SetupColors.primary),
                    onPressed: () {
                      final query = [_addressLine.text, _area.text, _city.text, _pinCode.text].where((p) => p.trim().isNotEmpty).join(', ');
                      launchUrl(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query.isEmpty ? 'sports facility' : query}), mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text('Open Google Maps', style: setupText(size: 13, weight: FontWeight.w600, color: SetupColors.primary)),
                  ),
                ),
                gap,
                if (verifiedMobile != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            Text.rich(TextSpan(style: setupText(size: 14, weight: FontWeight.w600), children: [
                              const TextSpan(text: 'Contact Number'),
                              TextSpan(text: ' *', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.error)),
                            ])),
                            const Icon(Icons.verified_outlined, size: 15, color: SetupColors.success),
                            Text('Verified', style: setupText(size: 12, weight: FontWeight.w600, color: SetupColors.success)),
                          ],
                        ),
                      ),
                      Container(
                        key: const ValueKey('verified-contact'),
                        height: 50,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(color: SetupColors.mutedFill, borderRadius: BorderRadius.circular(10), border: Border.all(color: SetupColors.border)),
                        child: Text('+91 $verifiedMobile', style: setupText(size: 15)),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('The mobile number you verified when you signed up. Shown to players.', style: setupText(size: 12, color: SetupColors.secondary, height: 1.35)),
                      ),
                    ],
                  )
                else
                SetupTextField(
                  label: 'Contact Number',
                  required: true,
                  controller: _phone,
                  fieldKey: _phoneKey,
                  hint: '98765 43210',
                  keyboardType: TextInputType.phone,
                  inputFormatters: _digits10,
                  prefix: _phonePrefix(),
                  validator: FacilitySetupValidation.contactNumber,
                  helper: 'Shown to players. It doesn’t have to match your personal number.',
                ),
                gap,
                SetupTextField(
                  label: 'WhatsApp Number',
                  optional: true,
                  controller: _whatsapp,
                  fieldKey: _whatsappKey,
                  hint: '98765 43210',
                  keyboardType: TextInputType.phone,
                  inputFormatters: _digits10,
                  prefix: _phonePrefix(),
                  validator: FacilitySetupValidation.optionalMobile,
                ),
                gap,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text.rich(TextSpan(style: setupText(size: 14, weight: FontWeight.w600), children: [
                            const TextSpan(text: 'Email Address'),
                            TextSpan(text: ' *', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.error)),
                          ])),
                          const Icon(Icons.verified_outlined, size: 15, color: SetupColors.success),
                          const SizedBox(width: 3),
                          Text('Verified', style: setupText(size: 12, weight: FontWeight.w600, color: SetupColors.success)),
                        ],
                      ),
                    ),
                    Container(
                      height: 50,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: SetupColors.mutedFill, borderRadius: BorderRadius.circular(10), border: Border.all(color: SetupColors.border)),
                      child: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: setupText(size: 15)),
                    ),
                  ],
                ),
                gap,
                SetupTextField(
                  label: 'Facility Description',
                  optional: true,
                  controller: _description,
                  fieldKey: _descriptionKey,
                  hint: 'Tell us about your facility (key features, location highlights, etc.)',
                  maxLines: 4,
                  maxLength: FacilitySetupValidation.descriptionMax,
                  onChanged: (_) => setState(() {}),
                  validator: FacilitySetupValidation.description,
                  counter: Text('${_description.text.length} / ${FacilitySetupValidation.descriptionMax}', style: setupText(size: 12, color: SetupColors.secondary)),
                ),
              ],
            ),
          ),
          gap,

          // ── Photos ──────────────────────────────────────────────────
          KeyedSubtree(
            key: _photosKey,
            child: SetupCard(
              child: _SetupPhotos(
                saved: _savedPhotos,
                added: _newPhotos,
                busy: _addingPhoto,
                error: _photosError,
                onAdd: _addPhoto,
                onRemoveNew: (p) => setState(() => _newPhotos.remove(p)),
              ),
            ),
          ),
          gap,

          // ── Contact person ──────────────────────────────────────────
          SetupCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SetupCardHeading(icon: Icons.person_outline, title: 'Facility Contact Person', description: 'Primary person to reach for bookings and operations.'),
                SetupTextField(label: 'Person Name', required: true, controller: _contactName, fieldKey: _contactNameKey, hint: 'Full name', maxLength: 80, validator: FacilitySetupValidation.personName),
                gap,
                SetupDropdown<String>(
                  label: 'Role / Designation',
                  required: true,
                  value: _role,
                  fieldKey: _roleKey,
                  items: [for (final r in kContactRoles) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                  validator: FacilitySetupValidation.role,
                ),
                gap,
                SetupTextField(
                  label: 'Alternate Number',
                  optional: true,
                  controller: _contactAlt,
                  fieldKey: _contactAltKey,
                  hint: '98765 11122',
                  keyboardType: TextInputType.phone,
                  inputFormatters: _digits10,
                  prefix: _phonePrefix(),
                  validator: (v) => FacilitySetupValidation.alternateNumber(v, _phone.text),
                ),
              ],
            ),
          ),
          gap,

          // ── Policies ────────────────────────────────────────────────
          SetupCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SetupCardHeading(icon: Icons.shield_outlined, title: 'Facility Policies', description: 'Set basic rules for players (shown on your facility page).'),
                SetupCheckRow(label: 'Allow Online Booking', hint: 'Players can book your courts from the GameAll Player app.', value: _policies.allowOnlineBooking, onChanged: (v) => setState(() => _policies = _policies.copyWith(allowOnlineBooking: v))),
                SetupCheckRow(label: 'Allow Walk-in / Offline Booking', hint: 'Your front desk can take bookings for players who walk in.', value: _policies.allowWalkIn, onChanged: (v) => setState(() => _policies = _policies.copyWith(allowWalkIn: v))),
                SetupCheckRow(label: 'Advance Payment Required', hint: 'Players must pay in advance to confirm a booking.', value: _policies.advancePaymentRequired, onChanged: (v) => setState(() => _policies = _policies.copyWith(advancePaymentRequired: v))),
                SetupCheckRow(label: 'Allow Cancellations', hint: 'Players can cancel a booking, subject to your refund rules.', value: _policies.allowCancellations, onChanged: (v) => setState(() => _policies = _policies.copyWith(allowCancellations: v))),
                SetupCheckRow(label: 'Require Player Details', hint: 'Ask for the player’s name and phone number when booking.', value: _policies.requirePlayerDetails, onChanged: (v) => setState(() => _policies = _policies.copyWith(requirePlayerDetails: v))),
              ],
            ),
          ),
          gap,

          // ── Amenities ───────────────────────────────────────────────
          SetupCard(
            child: _SetupAmenities(
              keys: _amenityKeys,
              custom: _customAmenities,
              onKeysChanged: (k) => setState(() => _amenityKeys = k),
              onCustomChanged: (c) => setState(() => _customAmenities = c),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

/// "Facility Photos": up to 5. Saved ones show GameAll's verdict; new ones are uploaded when the step is saved.
class _SetupPhotos extends StatelessWidget {
  const _SetupPhotos({required this.saved, required this.added, required this.busy, required this.onAdd, required this.onRemoveNew, this.error});

  final List<FacilityImage> saved;
  final List<NewPhoto> added;
  final bool busy;
  final String? error;
  final VoidCallback onAdd;
  final ValueChanged<NewPhoto> onRemoveNew;

  @override
  Widget build(BuildContext context) {
    final total = saved.length + added.length;
    const max = FacilitySetupValidation.maxSetupPhotos;

    Widget frame(Widget child, {bool cover = false, VoidCallback? onRemove, String? caption, Color captionColor = SetupColors.secondary}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
                if (cover)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                      child: Text('Cover', style: setupText(size: 10, weight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                if (onRemove != null)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: GestureDetector(
                      onTap: onRemove,
                      child: Container(
                        height: 26,
                        width: 26,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4)]),
                        child: const Icon(Icons.close, size: 16, color: SetupColors.text),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (caption != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(caption, style: setupText(size: 11, weight: FontWeight.w600, color: captionColor))),
        ],
      );
    }

    final tiles = <Widget>[
      for (var i = 0; i < saved.length; i++)
        frame(
          Image.network(saved[i].url, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: SetupColors.mutedFill, child: const Icon(Icons.broken_image_outlined, color: SetupColors.secondary))),
          cover: i == 0,
          caption: saved[i].status.label,
          captionColor: switch (saved[i].status) {
            VerificationStatus.verified => SetupColors.success,
            VerificationStatus.rejected => SetupColors.error,
            VerificationStatus.pending => SetupColors.secondary,
          },
        ),
      for (var i = 0; i < added.length; i++)
        frame(Image.memory(added[i].bytes, fit: BoxFit.cover), cover: saved.isEmpty && i == 0, onRemove: () => onRemoveNew(added[i])),
      if (total < max)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: GestureDetector(
                key: const ValueKey('add-photo'),
                onTap: busy ? null : onAdd,
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: SetupColors.primary.withValues(alpha: 0.45))),
                  child: busy
                      ? const Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_photo_alternate_outlined, color: SetupColors.primary, size: 26),
                            const SizedBox(height: 6),
                            Text(total == 0 ? 'Upload Photos' : 'Upload More', style: setupText(size: 13, weight: FontWeight.w600, color: SetupColors.primary)),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(style: setupText(size: 17, weight: FontWeight.w600), children: [
          const TextSpan(text: 'Facility Photos'),
          TextSpan(text: ' *', style: setupText(size: 17, weight: FontWeight.w600, color: SetupColors.error)),
        ])),
        const SizedBox(height: 2),
        Text('Add clear photos of your facility (up to $max). The first one is your cover.', style: setupText(size: 13, color: SetupColors.secondary, height: 1.35)),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 4 / 3.45,
          children: tiles,
        ),
        const SizedBox(height: 8),
        Text('$total of $max added · GameAll checks each photo before players see it.', style: setupText(size: 12, color: SetupColors.secondary)),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, key: const ValueKey('photos-error'), style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error))),
      ],
    );
  }
}

/// The 12 amenities as checkable tiles, plus owner-typed custom ones ("Add Custom Amenity").
class _SetupAmenities extends StatefulWidget {
  const _SetupAmenities({required this.keys, required this.custom, required this.onKeysChanged, required this.onCustomChanged});

  final List<String> keys;
  final List<String> custom;
  final ValueChanged<List<String>> onKeysChanged;
  final ValueChanged<List<String>> onCustomChanged;

  @override
  State<_SetupAmenities> createState() => _SetupAmenitiesState();
}

class _SetupAmenitiesState extends State<_SetupAmenities> {
  final _input = TextEditingController();
  bool _adding = false;
  String? _problem;

  static const _icons = <String, IconData>{
    'car_parking': Icons.directions_car_outlined,
    'two_wheeler_parking': Icons.two_wheeler,
    'restroom': Icons.wc,
    'changing_room': Icons.checkroom_outlined,
    'shower': Icons.shower_outlined,
    'drinking_water': Icons.water_drop_outlined,
    'seating_area': Icons.event_seat_outlined,
    'cafeteria': Icons.local_cafe_outlined,
    'wifi': Icons.wifi,
    'lockers': Icons.lock_outline,
    'equipment_rental': Icons.sports_tennis,
    'first_aid': Icons.medical_services_outlined,
  };

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _toggle(String key) {
    final next = List.of(widget.keys);
    next.contains(key) ? next.remove(key) : next.add(key);
    widget.onKeysChanged(next);
  }

  void _add() {
    final name = _input.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final why = FacilitySetupValidation.customAmenity(name, widget.custom);
    if (why != null) {
      setState(() => _problem = why);
      return;
    }
    widget.onCustomChanged([...widget.custom, name]);
    setState(() {
      _input.clear();
      _problem = null;
      _adding = false;
    });
  }

  Widget _tile({required Key key, required bool on, required IconData icon, required String label, required VoidCallback onTap, VoidCallback? onRemove}) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on ? SetupColors.activeBg : SetupColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? SetupColors.primary.withValues(alpha: 0.4) : SetupColors.border),
        ),
        child: Row(
          children: [
            Container(
              height: 20,
              width: 20,
              decoration: BoxDecoration(color: on ? SetupColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(5), border: Border.all(color: on ? SetupColors.primary : SetupColors.border, width: 1.6)),
              child: on ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 18, color: SetupColors.text),
            const SizedBox(width: 6),
            Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: setupText(size: 12.5, weight: FontWeight.w500, height: 1.15))),
            if (onRemove != null)
              GestureDetector(onTap: onRemove, child: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.close, size: 16, color: SetupColors.secondary))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final atLimit = widget.custom.length >= kMaxCustomAmenities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupCardHeading(icon: Icons.weekend_outlined, title: 'Amenities & Facilities', description: 'Select the amenities available at your facility.'),
        Row(
          children: [
            Expanded(child: Text('Can’t find an amenity?', style: setupText(size: 12, color: SetupColors.secondary))),
            OutlinedButton.icon(
              key: const ValueKey('add-custom-amenity'),
              onPressed: atLimit ? null : () => setState(() => _adding = !_adding),
              style: OutlinedButton.styleFrom(
                foregroundColor: SetupColors.primary,
                backgroundColor: const Color(0xFFF8F4FF),
                side: BorderSide(color: SetupColors.primary.withValues(alpha: 0.4)),
                minimumSize: const Size(0, 38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text('Add Custom Amenity', style: setupText(size: 13, weight: FontWeight.w600, color: SetupColors.primary)),
            ),
          ],
        ),
        if (_adding) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: SetupColors.mutedFill, borderRadius: BorderRadius.circular(10), border: Border.all(color: SetupColors.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('custom-amenity-input'),
                  controller: _input,
                  autofocus: true,
                  maxLength: 30,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  onChanged: (_) => setState(() => _problem = null),
                  style: setupText(size: 15),
                  decoration: setupDecoration(hint: 'e.g. Physiotherapy room', counterText: ''),
                ),
                if (_problem != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_problem!, key: const ValueKey('custom-amenity-error'), style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error))),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: SetupButton(label: 'Cancel', onPressed: () => setState(() { _adding = false; _problem = null; _input.clear(); }))),
                    const SizedBox(width: 10),
                    Expanded(child: SetupButton(label: 'Add', primary: true, onPressed: _add)),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final a in kFacilityAmenities)
                  SizedBox(
                    width: w,
                    child: _tile(key: ValueKey('amenity-${a.key}'), on: widget.keys.contains(a.key), icon: _icons[a.key] ?? Icons.check, label: a.label, onTap: () => _toggle(a.key)),
                  ),
                for (final name in widget.custom)
                  SizedBox(
                    width: w,
                    child: _tile(
                      key: ValueKey('custom-$name'),
                      on: true,
                      icon: Icons.star_outline,
                      label: name,
                      onTap: () {},
                      onRemove: () => widget.onCustomChanged(widget.custom.where((n) => n != name).toList()),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
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

