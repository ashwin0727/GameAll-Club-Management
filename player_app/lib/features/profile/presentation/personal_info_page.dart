
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/top_toast.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/player_profile.dart';
import '../../player_home/application/player_home_controller.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';
import '../domain/field_rules.dart';
import '../domain/profile_models.dart';
import 'profile_page.dart' show photoPickerProvider;
import 'profile_widgets.dart';

/// Picks an ID proof from the gallery: its bytes, file extension and name, or null when cancelled. Tests replace it.
typedef DocumentPicker = Future<(Uint8List, String, String)?> Function();

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => () async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 90,
    );
    if (file == null) return null;
    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last : 'jpg';
    return (await file.readAsBytes(), ext, name);
  },
);

enum _Tab {
  personal('Personal Details', Icons.person_outline_rounded),
  contact('Contact & Emergency', Icons.call_outlined),
  address('Address', Icons.location_on_outlined),
  documents('Documents', Icons.description_outlined);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Personal Information: a photo and the account facts on one side; four tabs (Personal Details, Contact & Emergency, Address,
/// Documents) on the other, with one Save for all of them. The mobile number is shown but cannot be changed: it is the number that
/// was verified at sign-in. On a phone the same content is one column and the tabs scroll sideways.
class PersonalInfoPage extends ConsumerStatefulWidget {
  const PersonalInfoPage({super.key});

  @override
  ConsumerState<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends ConsumerState<PersonalInfoPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _about = TextEditingController();
  final _altPhone = TextEditingController();
  final _emName = TextEditingController();
  final _emRelation = TextEditingController();
  final _emPhone = TextEditingController();
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _pincode = TextEditingController();

  DateTime? _dob;
  Gender? _gender;
  String? _city;
  String? _state;
  String? _blood;
  String? _tshirt;
  String? _level;
  String? _docType;
  Set<String> _sports = {};

  _Tab _tab = _Tab.personal;
  bool _loaded = false;
  bool _saving = false;
  bool _photoBusy = false;
  bool _docBusy = false;
  String? _error;
  final Map<String, String> _errors = {};
  ProfileDetails? _current;

  @override
  void dispose() {
    for (final c in [
      _name, _email, _about, _altPhone, _emName, _emRelation, _emPhone, _line1, _line2, _pincode,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(ProfileDetails d, {bool force = false}) {
    if (_loaded && !force) return;
    _loaded = true;
    _name.text = d.fullName;
    _email.text = d.email ?? '';
    _about.text = d.about ?? '';
    _altPhone.text = FieldRules.tenDigits(d.altPhone ?? '');
    _emName.text = d.emergencyName ?? '';
    _emRelation.text = d.emergencyRelation ?? '';
    _emPhone.text = FieldRules.tenDigits(d.emergencyPhone ?? '');
    _line1.text = d.addressLine1 ?? '';
    _line2.text = d.addressLine2 ?? '';
    _pincode.text = d.pincode ?? '';
    _dob = d.dob;
    _gender = d.gender;
    _city = d.city;
    _state = d.state;
    _blood = d.bloodGroup;
    _tshirt = d.tshirtSize;
    _level = d.playingLevel;
    _docType = d.idDocType;
    _sports = {...d.preferredSports};
    _errors.clear();
    _error = null;
  }

  void _say(String text) {
    if (!mounted) return;
    TopToast.of(context, text);
  }

  /// True when the form differs from what is saved: only then are Discard and Save offered.
  bool _isDirty(ProfileDetails d) {
    String s(String? v) => (v ?? '').trim();
    final sameSports = _sports.length == d.preferredSports.length && _sports.containsAll(d.preferredSports);
    return FieldRules.squash(_name.text) != FieldRules.squash(d.fullName) ||
        _email.text.trim().toLowerCase() != s(d.email).toLowerCase() ||
        _about.text.trim() != s(d.about) ||
        FieldRules.tenDigits(_altPhone.text) != FieldRules.tenDigits(d.altPhone ?? '') ||
        FieldRules.squash(_emName.text) != FieldRules.squash(d.emergencyName ?? '') ||
        FieldRules.squash(_emRelation.text) != FieldRules.squash(d.emergencyRelation ?? '') ||
        FieldRules.tenDigits(_emPhone.text) != FieldRules.tenDigits(d.emergencyPhone ?? '') ||
        FieldRules.squash(_line1.text) != FieldRules.squash(d.addressLine1 ?? '') ||
        FieldRules.squash(_line2.text) != FieldRules.squash(d.addressLine2 ?? '') ||
        _pincode.text.trim() != s(d.pincode) ||
        _dob != d.dob ||
        _gender != d.gender ||
        (_city ?? '') != s(d.city) ||
        (_state ?? '') != s(d.state) ||
        (_blood ?? '') != s(d.bloodGroup) ||
        (_tshirt ?? '') != s(d.tshirtSize) ||
        (_level ?? '') != s(d.playingLevel) ||
        (_docType ?? '') != s(d.idDocType) ||
        !sameSports;
  }

  String _dobLabel(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null && mounted) {
      setState(() {
        _dob = picked;
        _errors.remove('dob');
      });
    }
  }

  Future<void> _pickCity() async {
    final p = context.palette;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text('Your city', style: AppTextStyles.sectionHeading(p.primaryText)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in playerCities)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                        leading: Icon(Icons.location_city_rounded, color: c == _city ? p.highlight : p.secondaryText),
                        title: Text(c, style: AppTextStyles.body(p.primaryText)),
                        trailing: c == _city ? Icon(Icons.check_circle_rounded, color: p.highlight) : null,
                        onTap: () => Navigator.of(sheet).pop(c),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) setState(() => _city = chosen);
  }

  Future<void> _pickSports(List<SportOption> options) async {
    final p = context.palette;
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        final chosen = {..._sports};
        return StatefulBuilder(
          builder: (context, setSheet) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text('Preferred sports', style: AppTextStyles.sectionHeading(p.primaryText)),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final o in options)
                          CheckboxListTile(
                            key: ValueKey('pi-sport-opt-${o.key}'),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                            value: chosen.contains(o.key),
                            title: Text(o.name, style: AppTextStyles.body(p.primaryText)),
                            onChanged: (on) => setSheet(() {
                              if (on ?? false) {
                                chosen.add(o.key);
                              } else {
                                chosen.remove(o.key);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: GameAllButton.gradient(
                      key: const ValueKey('pi-sports-done'),
                      label: 'Done',
                      expand: true,
                      onPressed: () => Navigator.of(sheet).pop(chosen),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _sports = picked;
        _errors.remove('sports');
      });
    }
  }

  Future<void> _changePhoto() async {
    final picker = ref.read(photoPickerProvider);
    final repo = ref.read(profileRepositoryProvider);
    try {
      final picked = await picker();
      if (picked == null) return;
      final bad = FieldRules.imageFile(picked.$2);
      if (bad != null) {
        _say(bad);
        return;
      }
      setState(() => _photoBusy = true);
      await repo.uploadAvatar(picked.$1, picked.$2);
      ref.invalidate(profileDetailsProvider);
      _say('Photo updated.');
    } on ProfileFailure catch (e) {
      _say(e.message);
    } catch (_) {
      _say("We couldn't use that photo. Please try another.");
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _uploadDocument() async {
    if (_docType == null || _docType!.isEmpty) {
      setState(() => _errors['docType'] = 'Choose the type of ID first.');
      return;
    }
    final picker = ref.read(documentPickerProvider);
    final repo = ref.read(profileRepositoryProvider);
    try {
      final picked = await picker();
      if (picked == null) return;
      final bad = FieldRules.imageFile(picked.$2);
      if (bad != null) {
        _say(bad);
        return;
      }
      setState(() => _docBusy = true);
      final saved = await repo.uploadDocument(picked.$1, picked.$2, picked.$3, _docType!);
      if (!mounted) return;
      setState(() => _current = saved);
      ref.invalidate(profileDetailsProvider);
      _say('Document saved.');
    } on ProfileFailure catch (e) {
      _say(e.message);
    } catch (_) {
      _say("We couldn't use that file. Please try another.");
    } finally {
      if (mounted) setState(() => _docBusy = false);
    }
  }

  Future<void> _removeDocument(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove this document?'),
        content: const Text('The saved ID proof will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Keep')),
          TextButton(
            key: const ValueKey('pi-doc-remove-confirm'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _docBusy = true);
    try {
      final saved = await ref.read(profileRepositoryProvider).removeDocument(path);
      if (!mounted) return;
      setState(() {
        _current = saved;
        _docType = null;
      });
      ref.invalidate(profileDetailsProvider);
    } on ProfileFailure catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _docBusy = false);
    }
  }

  Future<void> _viewDocument(String path) async {
    final uri = await ref.read(profileRepositoryProvider).documentLink(path);
    if (uri == null) {
      _say("We couldn't open the document. Please try again.");
      return;
    }
    await ref.read(linkOpenerProvider)(uri);
  }

  /// Checks the whole form; returns the tab of the first problem (or null when it is fine).
  _Tab? _validate(bool sportsKnown, String own) {
    _errors.clear();
    final tabs = <String, _Tab>{};
    void fail(String key, String? message, _Tab tab) {
      if (message == null) return;
      _errors[key] = message;
      tabs[key] = tab;
    }

    // Personal Details
    fail('name', FieldRules.name(_name.text), _Tab.personal);
    fail('dob', FieldRules.dob(_dob), _Tab.personal);
    if (_gender == null) fail('gender', 'Please choose your gender.', _Tab.personal);
    if (sportsKnown && _sports.isEmpty) fail('sports', 'Choose at least one sport.', _Tab.personal);
    fail('about', FieldRules.about(_about.text), _Tab.personal);

    // Contact & Emergency
    fail('email', FieldRules.email(_email.text), _Tab.contact);
    fail('altPhone', FieldRules.mobile(_altPhone.text, own: own, what: 'alternate mobile number'), _Tab.contact);
    final anyEmergency = _emName.text.trim().isNotEmpty || _emRelation.text.trim().isNotEmpty || _emPhone.text.trim().isNotEmpty;
    fail('emName', FieldRules.name(_emName.text, what: 'contact name', required: anyEmergency), _Tab.contact);
    fail('emRelation', FieldRules.relationship(_emRelation.text), _Tab.contact);
    fail('emPhone', FieldRules.mobile(_emPhone.text, required: anyEmergency, own: own, what: 'contact mobile number'), _Tab.contact);

    // Address: the first line and the PIN code go together
    final anyAddress = _line1.text.trim().isNotEmpty || _line2.text.trim().isNotEmpty || _pincode.text.trim().isNotEmpty;
    fail('line1', FieldRules.addressLine(_line1.text, required: anyAddress, what: 'address'), _Tab.address);
    fail('line2', FieldRules.addressLine(_line2.text), _Tab.address);
    fail('pincode', FieldRules.pincode(_pincode.text, required: anyAddress), _Tab.address);

    if (_errors.isEmpty) return null;
    // the first tab (in tab order) that has a problem
    for (final t in _Tab.values) {
      if (tabs.values.contains(t)) return t;
    }
    return null;
  }

  Future<void> _save(bool sportsKnown) async {
    final own = ref.read(profileDetailsProvider).value?.phone ?? '';
    final firstBad = _validate(sportsKnown, own);
    if (firstBad != null) {
      setState(() {
        _tab = firstBad;
        _error = _errors.values.first;
      });
      return;
    }
    final repo = ref.read(profileRepositoryProvider);
    final auth = ref.read(authControllerProvider.notifier);
    final navigator = Navigator.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    final palette = context.palette;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await repo.update(
        ProfileEdit(
          full: true,
          fullName: FieldRules.squash(_name.text),
          email: _email.text.trim().toLowerCase(),
          dob: _dob,
          clearDob: false,
          gender: _gender,
          city: _city,
          bloodGroup: _blood ?? '',
          tshirtSize: _tshirt ?? '',
          preferredSports: _sports.toList()..sort(),
          playingLevel: _level ?? '',
          about: _about.text,
          altPhone: FieldRules.tenDigits(_altPhone.text),
          emergencyName: FieldRules.squash(_emName.text),
          emergencyRelation: FieldRules.squash(_emRelation.text),
          emergencyPhone: FieldRules.tenDigits(_emPhone.text),
          addressLine1: FieldRules.squash(_line1.text),
          addressLine2: FieldRules.squash(_line2.text),
          state: _state ?? '',
          pincode: _pincode.text.trim(),
          idDocType: _docType ?? '',
        ),
      );
      auth.updateProfile(saved.toBasic());
      ref.invalidate(profileDetailsProvider);
      TopToast.show(overlay, palette, 'Profile saved.', success: true);
      navigator.pop();
    } on ProfileFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard(ProfileDetails d) {
    setState(() => _fill(d, force: true));
    _say('Changes discarded.');
  }

  // ── building blocks ────────────────────────────────────────────────────

  InputDecoration _deco(AppPalette p, String label, {String? error, bool required = false, String? hint}) => InputDecoration(
    labelText: required ? '$label *' : label,
    hintText: hint,
    errorText: error,
    filled: true,
    fillColor: p.isDark ? const Color(0xFF0E1630) : p.elevated,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
  );

  Widget _field(
    AppPalette p,
    String key,
    TextEditingController c,
    String label, {
    bool required = false,
    TextInputType? keyboard,
    int? maxLength,
    String? hint,
    String? errorKey,
    TextCapitalization caps = TextCapitalization.none,
    List<TextInputFormatter>? formatters,
    String? prefix,
    int? maxLines,
  }) => TextField(
    key: ValueKey(key),
    controller: c,
    keyboardType: keyboard,
    textCapitalization: caps,
    inputFormatters: formatters,
    maxLength: maxLength,
    maxLines: maxLines ?? 1,
    onChanged: (_) => setState(() {
      if (errorKey != null) _errors.remove(errorKey);
    }),
    style: AppTextStyles.body(p.primaryText),
    decoration: _deco(p, label, required: required, hint: hint, error: errorKey == null ? null : _errors[errorKey]).copyWith(counterText: '', prefixText: prefix),
  );

  Widget _tapField(AppPalette p, String key, String label, String value, VoidCallback onTap, {bool required = false, String? error, IconData trailing = Icons.keyboard_arrow_down_rounded}) =>
      Pressable(
        key: ValueKey(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: _deco(p, label, required: required, error: error),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.isEmpty ? 'Select' : value,
                  style: AppTextStyles.body(value.isEmpty ? p.mutedText : p.primaryText),
                ),
              ),
              Icon(trailing, color: p.secondaryText, size: 20),
            ],
          ),
        ),
      );

  /// A choice field: it looks like the other fields and its menu opens right under it (same width), with compact rows and a tick on
  /// the chosen one. (The stock dropdown opens on top of the field with tall rows.)
  Widget _dropdown<T>(
    AppPalette p,
    String key,
    String label,
    T? value,
    List<(T, String)> items,
    ValueChanged<T?> onChanged, {
    bool required = false,
    String? error,
  }) {
    final current = items.where((e) => e.$1 == value).map((e) => e.$2).firstOrNull;
    return Builder(
      builder: (ctx) => Pressable(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final box = ctx.findRenderObject() as RenderBox;
          final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
          final topLeft = box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlay);
          final chosen = await showMenu<T>(
            context: ctx,
            position: RelativeRect.fromLTRB(
              topLeft.dx,
              topLeft.dy,
              overlay.size.width - topLeft.dx - box.size.width,
              0,
            ),
            constraints: BoxConstraints(minWidth: box.size.width, maxWidth: box.size.width, maxHeight: 300),
            color: p.isDark ? const Color(0xFF14213F) : p.surface,
            elevation: 10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: p.border),
            ),
            items: [
              for (final (v, text) in items)
                PopupMenuItem<T>(
                  value: v,
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          text,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(v == value ? p.highlight : p.primaryText)
                              .copyWith(fontWeight: v == value ? FontWeight.w700 : FontWeight.w500),
                        ),
                      ),
                      if (v == value) Icon(Icons.check_rounded, size: 18, color: p.highlight),
                    ],
                  ),
                ),
            ],
          );
          if (chosen != null) onChanged(chosen);
        },
        child: InputDecorator(
          isEmpty: current == null,
          decoration: _deco(p, label, required: required, error: error),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  current ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(p.primaryText),
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, color: p.secondaryText, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// [children] side by side on a wide window (equal widths), stacked on a phone.
  Widget _row(List<Widget> children) {
    if (!profileIsWide(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: children[i]),
        ],
      ],
    );
  }

  Widget _heading(AppPalette p, String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 14),
    child: Text(text, style: AppTextStyles.sectionHeading(p.primaryText)),
  );

  // ── the identity card (left) ──────────────────────────────────────────

  Widget _identityCard(AppPalette p, ProfileDetails d) {
    Widget pill(String text, {Key? key}) => Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text == 'Verified') ...[
            const Icon(Icons.verified_rounded, size: 13, color: AppColors.success),
            const SizedBox(width: 4),
          ],
          Text(text, style: AppTextStyles.meta(AppColors.success).copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );

    Widget infoRow(IconData icon, String label, Widget value, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.isDark ? const Color(0xFF1A2447) : p.secondaryBackground),
            child: Icon(icon, size: 19, color: p.highlight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.meta(p.secondaryText)),
                const SizedBox(height: 2),
                value,
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    final avatar = d.avatarUrl;
    return ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  key: const ValueKey('pi-avatar'),
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                    image: avatar == null ? null : DecorationImage(image: NetworkImage(avatar), fit: BoxFit.cover),
                  ),
                  foregroundDecoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.highlight.withValues(alpha: 0.7), width: 3)),
                  alignment: Alignment.center,
                  child: avatar == null
                      ? Text(d.initials, style: AppTextStyles.heroHeading(Colors.white))
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: 2,
                  child: Pressable(
                    key: const ValueKey('pi-photo-camera'),
                    onTap: _photoBusy ? null : _changePhoto,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.violet, border: Border.all(color: p.surface, width: 2)),
                      child: _photoBusy
                          ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.photo_camera_rounded, size: 17, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GameAllButton.secondary(
            key: const ValueKey('pi-change-photo'),
            label: 'Change Photo',
            icon: Icons.file_upload_outlined,
            expand: true,
            onPressed: _photoBusy ? null : _changePhoto,
          ),
          const SizedBox(height: 8),
          Text('JPG, PNG or WEBP (Max 3 MB)', textAlign: TextAlign.center, style: AppTextStyles.meta(p.mutedText)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: p.isDark ? const Color(0xFF0E1630) : p.secondaryBackground,
            ),
            child: Column(
              children: [
                infoRow(
                  Icons.person_outline_rounded,
                  'Player ID',
                  Text(d.playerCode ?? '-', key: const ValueKey('pi-player-id'), style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w700)),
                  trailing: IconButton(
                    key: const ValueKey('pi-copy-id'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy Player ID',
                    icon: Icon(Icons.copy_rounded, size: 18, color: p.secondaryText),
                    onPressed: d.playerCode == null
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: d.playerCode!));
                            _say('Player ID copied.');
                          },
                  ),
                ),
                infoRow(
                  Icons.mail_outline_rounded,
                  'Email',
                  Text(
                    (d.email ?? '').isEmpty ? 'Not added' : d.email!,
                    key: const ValueKey('pi-email-shown'),
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body((d.email ?? '').isEmpty ? p.mutedText : p.primaryText),
                  ),
                ),
                infoRow(
                  Icons.call_outlined,
                  'Mobile Number',
                  Text('+91 ${d.phone}', key: const ValueKey('pi-phone'), style: AppTextStyles.body(p.primaryText)),
                  trailing: pill('Verified', key: const ValueKey('pi-phone-verified')),
                ),
                infoRow(
                  Icons.shield_outlined,
                  'Account Status',
                  const SizedBox.shrink(),
                  trailing: pill('Active', key: const ValueKey('pi-status')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── the tabs (right) ──────────────────────────────────────────────────

  Widget _tabBar(AppPalette p) {
    Widget button(_Tab t) {
      final on = t == _tab;
      return Pressable(
        key: ValueKey('pi-tab-${t.name}'),
        onTap: () => setState(() => _tab = t),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: on ? AppColors.accentGradient : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(t.icon, size: 18, color: on ? Colors.white : p.secondaryText),
              const SizedBox(width: 8),
              Text(t.label, style: AppTextStyles.button(on ? Colors.white : p.secondaryText)),
            ],
          ),
        ),
      );
    }

    if (profileIsWide(context)) {
      return Row(
        children: [
          for (final t in _Tab.values) Expanded(child: Center(child: button(t))),
        ],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final t in _Tab.values) ...[button(t), const SizedBox(width: 6)],
        ],
      ),
    );
  }

  Widget _personalTab(AppPalette p, List<SportOption> sports) {
    final names = {for (final s in sports) s.key: s.name};
    final chips = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final k in _sports)
          InputChip(
            key: ValueKey('pi-sport-$k'),
            label: Text(names[k] ?? k),
            onDeleted: () => setState(() => _sports.remove(k)),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(p, 'Basic Information'),
        _row([
          _field(p, 'pi-name', _name, 'Full Name', required: true, errorKey: 'name', caps: TextCapitalization.words, formatters: FieldRules.nameFormatters(FieldRules.nameMax)),
          _tapField(
            p, 'pi-dob', 'Date of Birth', _dob == null ? '' : _dobLabel(_dob!), _pickDob,
            required: true, error: _errors['dob'], trailing: Icons.calendar_today_outlined,
          ),
        ]),
        const SizedBox(height: 14),
        _row([
          _dropdown<Gender>(
            p, 'pi-gender', 'Gender', _gender, [for (final g in Gender.values) (g, g.label)],
            (v) => setState(() {
              _gender = v;
              _errors.remove('gender');
            }),
            required: true, error: _errors['gender'],
          ),
          _dropdown<String>(p, 'pi-blood', 'Blood Group', _blood, [for (final b in bloodGroups) (b, b)], (v) => setState(() => _blood = v)),
          _dropdown<String>(p, 'pi-tshirt', 'T-Shirt Size', _tshirt, [for (final s in tshirtSizes) (s, s)], (v) => setState(() => _tshirt = v)),
        ]),
        const SizedBox(height: 18),
        _heading(p, 'Additional Information'),
        _row([
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tapField(
                p, 'pi-sports', 'Preferred Sport(s)',
                _sports.isEmpty ? '' : '${_sports.length} selected',
                sports.isEmpty ? () => _say('The sports list is not available right now.') : () => _pickSports(sports),
                required: true, error: _errors['sports'],
              ),
              if (_sports.isNotEmpty) ...[const SizedBox(height: 8), chips],
            ],
          ),
          _dropdown<String>(
            p, 'pi-level', 'Playing Level', _level,
            [for (final l in playingLevels) (l.wire, l.label)],
            (v) => setState(() => _level = v),
          ),
        ]),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('pi-about'),
          controller: _about,
          maxLength: 200,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          style: AppTextStyles.body(p.primaryText),
          decoration: _deco(p, 'About You (Optional)', hint: 'e.g., Player, amateur, looking for regular games...', error: _errors['about']).copyWith(
            counterText: '${_about.text.length} / 200',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _contactTab(AppPalette p, ProfileDetails d) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(p, 'Contact Details'),
      _row([
        _field(p, 'pi-email', _email, 'Email', keyboard: TextInputType.emailAddress, errorKey: 'email', formatters: FieldRules.emailFormatters()),
        InputDecorator(
          decoration: _deco(p, 'Mobile Number').copyWith(
            helperText: 'This is the number you signed in with.',
            suffixIcon: const Icon(Icons.verified_rounded, color: AppColors.success),
          ),
          child: Text('+91 ${d.phone}', style: AppTextStyles.body(p.secondaryText)),
        ),
      ]),
      const SizedBox(height: 14),
      _row([
        _field(p, 'pi-alt-phone', _altPhone, 'Alternate Mobile Number', keyboard: TextInputType.phone, errorKey: 'altPhone', formatters: FieldRules.mobileFormatters(), prefix: '+91 '),
        const SizedBox.shrink(),
      ]),
      const SizedBox(height: 18),
      _heading(p, 'Emergency Contact'),
      _row([
        _field(p, 'pi-em-name', _emName, 'Contact Name', caps: TextCapitalization.words, errorKey: 'emName', formatters: FieldRules.nameFormatters(FieldRules.nameMax)),
        _field(p, 'pi-em-relation', _emRelation, 'Relationship', hint: 'e.g., Father', caps: TextCapitalization.words, errorKey: 'emRelation', formatters: FieldRules.nameFormatters(FieldRules.relationMax)),
      ]),
      const SizedBox(height: 14),
      _row([
        _field(p, 'pi-em-phone', _emPhone, 'Contact Mobile Number', keyboard: TextInputType.phone, errorKey: 'emPhone', formatters: FieldRules.mobileFormatters(), prefix: '+91 '),
        const SizedBox.shrink(),
      ]),
    ],
  );

  Widget _addressTab(AppPalette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(p, 'Address'),
      _field(p, 'pi-line1', _line1, 'Address Line 1', caps: TextCapitalization.words, errorKey: 'line1', formatters: FieldRules.addressFormatters()),
      const SizedBox(height: 14),
      _field(p, 'pi-line2', _line2, 'Address Line 2 (Optional)', caps: TextCapitalization.words, errorKey: 'line2', formatters: FieldRules.addressFormatters()),
      const SizedBox(height: 14),
      _row([
        _tapField(p, 'pi-city', 'City', _city ?? '', _pickCity),
        _dropdown<String>(p, 'pi-state', 'State', _state, [for (final s in indianStates) (s, s)], (v) => setState(() => _state = v)),
        _field(p, 'pi-pincode', _pincode, 'PIN Code', keyboard: TextInputType.number, errorKey: 'pincode', formatters: FieldRules.pinFormatters()),
      ]),
    ],
  );

  Widget _documentsTab(AppPalette p, ProfileDetails d) {
    final path = d.idDocPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(p, 'ID Proof'),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: _dropdown<String>(
              p, 'pi-doc-type', 'Type of ID', _docType, [for (final t in idDocTypes) (t.wire, t.label)],
              (v) => setState(() {
                _docType = v;
                _errors.remove('docType');
              }),
              error: _errors['docType'],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          key: const ValueKey('pi-doc-card'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: p.isDark ? const Color(0xFF0E1630) : p.secondaryBackground,
            border: Border.all(color: p.border),
          ),
          child: path == null
              ? Column(
                  children: [
                    Icon(Icons.upload_file_rounded, size: 34, color: p.highlight),
                    const SizedBox(height: 8),
                    Text('Upload a photo of your ID', style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('JPG, PNG or WEBP (Max 5 MB)', style: AppTextStyles.meta(p.mutedText)),
                    const SizedBox(height: 12),
                    GameAllButton.secondary(
                      key: const ValueKey('pi-doc-upload'),
                      label: _docBusy ? 'Uploading…' : 'Choose File',
                      icon: Icons.file_upload_outlined,
                      onPressed: _docBusy ? null : _uploadDocument,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(Icons.insert_drive_file_outlined, color: p.highlight),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.idDocName ?? 'ID proof', key: const ValueKey('pi-doc-name'), overflow: TextOverflow.ellipsis, style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            idDocTypes.where((t) => t.wire == d.idDocType).map((t) => t.label).firstOrNull ?? 'ID proof',
                            style: AppTextStyles.meta(p.secondaryText),
                          ),
                        ],
                      ),
                    ),
                    TextButton(key: const ValueKey('pi-doc-view'), onPressed: () => _viewDocument(path), child: const Text('View')),
                    TextButton(
                      key: const ValueKey('pi-doc-replace'),
                      onPressed: _docBusy ? null : _uploadDocument,
                      child: const Text('Replace'),
                    ),
                    TextButton(
                      key: const ValueKey('pi-doc-remove'),
                      onPressed: _docBusy ? null : () => _removeDocument(path),
                      child: Text('Remove', style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: p.mutedText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your document is private. Only you can open it; it is not shared with clubs.',
                style: AppTextStyles.meta(p.mutedText),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final async = ref.watch(profileDetailsProvider);
    final fetched = async.value;
    final unreadable = fetched != null && fetched.isFallback;
    if (fetched != null && !unreadable) _fill(fetched);
    // a saved document or photo reloads the profile; show that copy, not the stale one
    final details = _current != null && fetched != null && _current!.idDocPath != fetched.idDocPath ? _current : fetched;
    final sports = ref.watch(platformSportsProvider).value ?? const <SportOption>[];
    final wide = profileIsWide(context);

    return ProfileSubPage(
      title: 'Personal Information',
      child: unreadable
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Column(
                children: [
                  Text(
                    "We couldn't load your details just now.",
                    key: const ValueKey('pi-load-failed'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(p.secondaryText),
                  ),
                  const SizedBox(height: 14),
                  GameAllButton.secondary(
                    key: const ValueKey('pi-retry'),
                    label: 'Try again',
                    onPressed: () => ref.invalidate(profileDetailsProvider),
                  ),
                ],
              ),
            )
          : details == null
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 4, bottom: wide ? 16 : 14),
                  child: Text('Manage your personal and contact details', style: AppTextStyles.body(p.secondaryText)),
                ),
                ProfileColumns(
                  leftFlex: 3,
                  rightFlex: 8,
                  gap: 20,
                  left: Padding(
                    padding: EdgeInsets.only(bottom: wide ? 0 : 16),
                    child: _identityCard(p, details),
                  ),
                  right: ProfilePanel(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _tabBar(p),
                        Divider(height: 24, color: p.border),
                        switch (_tab) {
                          _Tab.personal => _personalTab(p, sports),
                          _Tab.contact => _contactTab(p, details),
                          _Tab.address => _addressTab(p),
                          _Tab.documents => _documentsTab(p, details),
                        },
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, key: const ValueKey('pi-error'), style: AppTextStyles.support(AppColors.danger)),
                ],
                if (_isDirty(fetched ?? details)) ...[
                const SizedBox(height: 22),
                Align(
                  alignment: wide ? Alignment.centerRight : Alignment.center,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 460 : double.infinity),
                    child: Flex(
                      direction: wide ? Axis.horizontal : Axis.vertical,
                      mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
                      crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
                      children: [
                        if (wide)
                          Expanded(
                            child: GameAllButton.secondary(
                              key: const ValueKey('pi-discard'),
                              label: 'Discard Changes',
                              expand: true,
                              onPressed: _saving ? null : () => _discard(fetched ?? details),
                            ),
                          )
                        else
                          GameAllButton.secondary(
                            key: const ValueKey('pi-discard'),
                            label: 'Discard Changes',
                            expand: true,
                            onPressed: _saving ? null : () => _discard(fetched ?? details),
                          ),
                        SizedBox(width: 14, height: wide ? 0 : 12),
                        if (wide)
                          Expanded(
                            child: GameAllButton.gradient(
                              key: const ValueKey('pi-save'),
                              label: _saving ? 'Saving…' : 'Save Changes',
                              icon: Icons.check_rounded,
                              expand: true,
                              onPressed: _saving ? null : () => _save(sports.isNotEmpty),
                            ),
                          )
                        else
                          GameAllButton.gradient(
                            key: const ValueKey('pi-save'),
                            label: _saving ? 'Saving…' : 'Save Changes',
                            icon: Icons.check_rounded,
                            expand: true,
                            onPressed: _saving ? null : () => _save(sports.isNotEmpty),
                          ),
                      ],
                    ),
                  ),
                ),
                ],
              ],
            ),
    );
  }
}
