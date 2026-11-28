import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/coaching.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/utils/photo_picker.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/smooth_switcher.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import '../staff/staff_credentials_card.dart';
import 'add_coach_validation.dart';
import 'coach_onboarding_form.dart';

class _SportChoice {
  const _SportChoice(this.id, this.name);
  final String id;
  final String name;
}

const _stepSubtitles = [
  "Who the coach is and how students will see them.",
  "What they teach and the credentials behind it.",
  "How they coach and what they charge.",
  "Where their earnings are paid. You can finish this later.",
  "Check everything and confirm the agreements.",
];

/// Add Coach — the 5-step onboarding, one step per screen (mirrors src/features/coaching/components/coach-onboarding-page.tsx).
/// Step 1 saves a draft coach, steps 2-4 save as you go, step 5 activates the coach. Opening with [resumeCoachId] restores the saved
/// values and the step the owner stopped at.
class CoachOnboardingScreen extends ConsumerStatefulWidget {
  const CoachOnboardingScreen({super.key, this.resumeCoachId, this.initialStep});

  final String? resumeCoachId;

  /// 1..5 — overrides the saved step when resuming (e.g. "Add payout details" opens step 4).
  final int? initialStep;

  @override
  ConsumerState<CoachOnboardingScreen> createState() => _CoachOnboardingScreenState();
}

class _CoachOnboardingScreenState extends ConsumerState<CoachOnboardingScreen> {
  static const _avatarMaxBytes = 2 * 1024 * 1024;

  CoachOnboardingForm _f = CoachOnboardingForm();
  int _step = 1;
  String? _coachId;
  final int _rev = 0; // bumped when the form is changed from code, so text fields pick up the new value
  int _displayRev = 0; // same, for the display-name field alone (so typing a first name never steals focus)

  List<CoachCandidate> _candidates = const [];
  List<RoleRow> _roles = const [];
  List<_SportChoice> _sports = const [];

  List<int>? _avatarBytes;
  String _avatarName = 'photo.jpg';
  String _avatarType = 'image/jpeg';
  String? _avatarError;

  bool _loading = true;
  bool _busy = false;
  String _stage = '';
  String? _error;
  bool _canManagePayouts = true;
  String _payoutStatus = 'PENDING';
  CoachPayoutMasked? _savedPayout;
  ({String coachId, String name, StaffCredentials? credentials})? _completed;
  StaffCredentials? _credentials;
  final _tagInput = TextEditingController();

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;
  bool get _hasSavedPayout => _savedPayout != null;
  bool get _valid => _f.isStepValid(_step, hasSavedPayout: _hasSavedPayout);

  @override
  void initState() {
    super.initState();
    _coachId = widget.resumeCoachId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tagInput.dispose();
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final facilitySports = await sportsRepo.getFacilitySports(fid);
      final sports = await sportsRepo.getActiveSports();
      final choices = [
        for (final fs in facilitySports.where((f) => f.enabled))
          _SportChoice(fs.id, fs.customSportName ?? sports.where((s) => s.id == fs.sportId).map((s) => s.name).firstOrNull ?? 'Sport'),
      ];
      if (widget.resumeCoachId != null) {
        final o = await ref.read(coachingRepositoryProvider).getCoachOnboarding(widget.resumeCoachId!);
        if (!mounted) return;
        setState(() {
          _sports = choices;
          _f = CoachOnboardingForm.fromOnboarding(o);
          _step = (widget.initialStep ?? o.resumeStep).clamp(1, 5);
          _canManagePayouts = o.canManagePayouts;
          _payoutStatus = o.payoutStatus;
          _savedPayout = o.payout;
          _coachId = o.coachId;
          _loading = false;
        });
        return;
      }
      final candidates = await ref.read(coachingRepositoryProvider).listCoachCandidates(fid);
      // Roles only matter for "+ New person"; a failure must not block picking an existing staff member.
      var roles = <RoleRow>[];
      String? rolesError;
      try {
        roles = (await ref.read(staffRepositoryProvider).listRoles(fid)).where((r) => r.isActive).toList();
      } on AppException catch (e) {
        rolesError = e.message;
      }
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _sports = choices;
        _roles = roles;
        _f.roleId = roles.where((r) => RegExp('coach', caseSensitive: false).hasMatch(r.name)).map((r) => r.id).firstOrNull ?? '';
        _error = rolesError == null ? null : 'Could not load roles for the new-person form: $rolesError';
        _loading = false;
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  // ── saving ───────────────────────────────────────────────────────────────

  /// Runs [work] under a busy lock, so a double tap on Save & continue can never create two coaches or two staff accounts.
  Future<bool> _run(String label, Future<void> Function() work) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _stage = label;
      _error = null;
    });
    try {
      await work();
      return true;
    } on AppException catch (e) {
      _set(() => _error = e.message);
      return false;
    } catch (_) {
      _set(() => _error = 'Could not save. Please try again.');
      return false;
    } finally {
      _set(() {
        _busy = false;
        _stage = '';
      });
    }
  }

  Future<void> _saveIdentity() async {
    final fid = _facilityId;
    if (fid == null) throw AppException(AppErrorCode.databaseError, "Finish step 1 first.");
    final repo = ref.read(coachingRepositoryProvider);
    if (_coachId != null) {
      await repo.saveCoachOnboardingStep(_coachId!, 1, _f.stepPayload(1));
      return;
    }
    var staffUserId = _f.userId;
    if (_f.newPerson) {
      String? avatarUrl;
      if (_avatarBytes != null) {
        _set(() => _stage = 'Uploading photo…');
        avatarUrl = await ref.read(staffRepositoryProvider).uploadAvatar(_avatarBytes!, _avatarName, _avatarType);
      }
      _set(() => _stage = 'Creating staff account…');
      final result = await ref.read(staffRepositoryProvider).createStaff(
            facilityId: fid,
            firstName: _f.firstName.trim(),
            lastName: _f.lastName.trim(),
            email: _f.email.trim(),
            phone: _f.phone.trim().isEmpty ? null : _f.phone.trim(),
            roleId: _f.roleId,
            avatarUrl: avatarUrl,
          );
      staffUserId = result.userId;
      final password = result.temporaryPassword;
      if (password != null) _credentials = StaffCredentials(userId: result.userId, loginEmail: result.loginEmail, password: password);
      // From here the person exists: a retry must not create the staff account again.
      _f.newPerson = false;
      _f.userId = result.userId;
    }
    _set(() => _stage = 'Saving draft…');
    _coachId = await repo.startCoachOnboarding(
      facilityId: fid,
      userId: staffUserId,
      displayName: _f.displayName.trim(),
      location: _f.location.trim(),
      timezone: _f.timezone,
      languages: _f.languages.toList(),
      shortBio: _f.shortBio.trim(),
      dateOfBirth: _f.dobIso,
    );
  }

  Future<void> _saveCurrentStep() async {
    if (_step == 1) return _saveIdentity();
    final id = _coachId;
    if (id == null) throw AppException(AppErrorCode.databaseError, "Finish step 1 first.");
    await ref.read(coachingRepositoryProvider).saveCoachOnboardingStep(id, _step, _f.stepPayload(_step));
    if (_step == 4) {
      _payoutStatus = 'COMPLETE';
      _savedPayout ??= CoachPayoutMasked(entityType: _f.entityType, payoutMethod: _f.payoutMethod, payoutFrequency: _f.payoutFrequency);
    }
  }

  Future<void> _continue() async {
    if (_step >= 5 || !_valid) return;
    final ok = await _run('Saving…', _saveCurrentStep);
    if (ok && mounted) setState(() => _step++);
  }

  Future<void> _saveDraftAndExit() async {
    if (_step >= 5) return;
    if (!_valid) {
      // Nothing valid to save on the very first step: say why instead of doing nothing.
      if (_step == 1 && _coachId == null) {
        setState(() => _error = 'Fill in the required fields to save a draft.');
        return;
      }
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final ok = await _run('Saving draft…', _saveCurrentStep);
    if (ok && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _complete() async {
    final id = _coachId;
    if (id == null || !_f.isStepValid(5)) return;
    await _run('Submitting…', () async {
      await ref.read(coachingRepositoryProvider).completeCoachOnboarding(
            id,
            terms: _f.agreeTerms,
            ethics: _f.agreeEthics,
            privacy: _f.agreePrivacy,
            commission: _f.agreeCommission,
          );
      _set(() => _completed = (coachId: id, name: _f.displayName.trim(), credentials: _credentials));
    });
  }

  /// The display name is the whole first name until the owner types their own: it follows the first name as it is typed.
  void _setName({String? first, String? last}) {
    final follow = _f.displayName.isEmpty || _f.displayName == _f.firstName;
    if (first != null) _f.firstName = first;
    if (last != null) _f.lastName = last;
    if (follow) {
      _f.displayName = _f.firstName;
      _displayRev++;
    }
  }

  // ── pickers ──────────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    setState(() => _avatarError = null);
    final file = await pickPhoto(context, maxWidth: 1600);
    if (!mounted || file == null) return;
    final lower = file.name.toLowerCase();
    final type = lower.endsWith('.png') ? 'image/png' : lower.endsWith('.webp') ? 'image/webp' : (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) ? 'image/jpeg' : null;
    if (type == null) return setState(() => _avatarError = 'Please choose a JPG, PNG or WEBP image.');
    final bytes = await file.readAsBytes();
    if (bytes.length > _avatarMaxBytes) return setState(() => _avatarError = 'That photo is larger than 2MB.');
    setState(() {
      _avatarBytes = bytes;
      _avatarName = file.name;
      _avatarType = type;
    });
  }

  Future<void> _pickDob() async {
    final b = dateOfBirthBounds();
    final picked = await showDatePicker(context: context, initialDate: _f.dob ?? b.max, firstDate: b.min, lastDate: b.max);
    if (picked != null) setState(() => _f.dob = picked);
  }

  Future<void> _uploadCertificate(CertForm c) async {
    final fid = _facilityId;
    final id = _coachId;
    if (fid == null || id == null) return;
    final file = await pickPhoto(context, maxWidth: 2400);
    if (!mounted || file == null) return;
    final bytes = await file.readAsBytes();
    final problem = validateCertificate(file.name, bytes.length);
    if (problem != null) return setState(() => _error = problem);
    final lower = file.name.toLowerCase();
    final type = lower.endsWith('.png') ? 'image/png' : lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    await _run('Uploading certificate…', () async {
      final path = await ref.read(coachingRepositoryProvider).uploadCoachCertificate(facilityId: fid, coachId: id, bytes: bytes, fileName: file.name, contentType: type);
      _set(() => c.path = path);
    });
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_MANAGE_COACHES')) {
      return const StaffPermissionDenied(title: 'Add Coach', message: "You don't have permission to manage coaches.");
    }
    if (_completed != null) return _success(context, _completed!);
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Coach')),
      body: SafeArea(
        child: Column(
          children: [
            _stepper(t),
            Expanded(
              child: SmoothSwitcher(
                child: _loading
                    ? const _OnboardingSkeleton()
                    : ListView(
                        // Keyed by step only: bumping _rev (to refresh fields changed from code) must not rebuild the list and jump it to the top.
                        key: ValueKey('step-$_step'),
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: [
                          Text(_stepSubtitles[_step - 1], style: TextStyle(fontSize: 12, color: t.textSecondary)),
                          const SizedBox(height: AppSpacing.md),
                          if (_step == 1) ..._identity(t),
                          if (_step == 2) ..._expertise(t),
                          if (_step == 3) ..._services(t),
                          if (_step == 4) ..._payout(t),
                          if (_step == 5) ..._review(t),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(_error!, style: TextStyle(color: t.destructive)),
                          ],
                        ],
                      ),
              ),
            ),
            _bottomBar(t),
          ],
        ),
      ),
    );
  }

  Widget _stepper(AppColorTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step $_step of 5 · ${coachOnboardingSteps[_step - 1]}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: i < _step && !_busy ? () => setState(() => _step = i) : null,
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(right: i == 5 ? 0 : 4),
                      decoration: BoxDecoration(color: i < _step ? t.success : i == _step ? t.primary : t.borderColor, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(AppColorTokens t) {
    final last = _step == 5;
    final lockedPayout = _step == 4 && !_canManagePayouts;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(color: t.surface0, border: Border(top: BorderSide(color: t.borderColor))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              OutlinedButton(
                onPressed: _busy || _loading ? null : () => _step == 1 ? Navigator.of(context).maybePop() : setState(() => _step--),
                child: Text(_step == 1 ? 'Cancel' : 'Back'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: PrimaryButton(
                  label: last ? 'Submit & Activate' : 'Save & continue',
                  loadingLabel: _stage.isEmpty ? 'Saving…' : _stage,
                  isLoading: _busy,
                  onPressed: _busy || _loading
                      ? null
                      : last
                          ? (_valid ? _complete : null)
                          : lockedPayout
                              ? () => setState(() => _step = 5)
                              : (_valid ? _continue : null),
                ),
              ),
            ],
          ),
          if (!last)
            // A Wrap, not a Row: on a 320 px phone the two text buttons together are wider than the screen, so the second drops below.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  TextButton(onPressed: _busy || _loading ? null : _saveDraftAndExit, child: const Text('Save draft & exit')),
                  if (_step == 4 && !lockedPayout) TextButton(onPressed: _busy ? null : () => setState(() => _step = 5), child: const Text('Finish later')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── small builders ───────────────────────────────────────────────────────
  Widget _gap([double h = AppSpacing.md]) => SizedBox(height: h);

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(required ? '$text *' : text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );

  Widget _hint(AppColorTokens t, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text, style: TextStyle(fontSize: 11, color: t.textSecondary)),
      );

  /// A text input that keeps its own state and reports every change into the form. [fieldKey] must be stable per field.
  Widget _field(
    String fieldKey,
    String label,
    String value,
    ValueChanged<String> onChanged, {
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? hint,
    String? errorText,
    bool obscure = false,
    int maxLines = 1,
    int? maxLength,
    TextCapitalization caps = TextCapitalization.none,
    bool enabled = true,
  }) {
    return TextFormField(
      key: ValueKey('$fieldKey-$_rev'),
      initialValue: value,
      enabled: enabled,
      keyboardType: keyboard,
      inputFormatters: formatters,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      maxLength: maxLength,
      textCapitalization: caps,
      autocorrect: !obscure,
      decoration: InputDecoration(labelText: label, hintText: hint, errorText: errorText, counterText: ''),
      onChanged: (v) => setState(() => onChanged(v)),
    );
  }

  Widget _chips<T>(Iterable<T> options, bool Function(T) selected, void Function(T) toggle, String Function(T) labelOf) {
    return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
      for (final o in options) FilterChip(label: Text(labelOf(o)), selected: selected(o), onSelected: (_) => setState(() => toggle(o))),
    ]);
  }

  static final _digits = [FilteringTextInputFormatter.digitsOnly];

  // ── step 1 ───────────────────────────────────────────────────────────────
  List<Widget> _identity(AppColorTokens t) {
    final chooseWho = _coachId == null;
    final c = _candidates.where((x) => x.userId == _f.userId).firstOrNull;
    final phoneBad = !isValidPhoneDigits(_f.phone);
    final emailBad = _f.email.isNotEmpty && !isValidEmail(_f.email);
    final dobBad = !isValidDateOfBirth(_f.dob);
    return [
      if (chooseWho) ...[
        Wrap(spacing: AppSpacing.sm, children: [
          ChoiceChip(label: const Text('Existing Staff Member'), selected: !_f.newPerson, onSelected: (_) => setState(() => _f.newPerson = false)),
          ChoiceChip(label: const Text('+ New person'), selected: _f.newPerson, onSelected: (_) => setState(() => _f.newPerson = true)),
        ]),
        _gap(),
        if (!_f.newPerson) ...[
          AppDropdown<String>(
            initialValue: _f.userId.isEmpty ? null : _f.userId,
            decoration: const InputDecoration(labelText: 'Staff Member *'),
            items: _candidates.isEmpty
                ? const [DropdownMenuItem(value: null, child: Text('Every staff member is already a coach'))]
                : _candidates.map((x) => DropdownMenuItem(value: x.userId, child: Text(x.title != null ? '${x.fullName} · ${x.title}' : x.fullName))).toList(),
            onChanged: (v) => setState(() {
              _f.userId = v ?? '';
              final picked = _candidates.where((x) => x.userId == v).firstOrNull;
              if (_f.displayName.isEmpty && picked != null) {
                _f.displayName = picked.fullName;
                _displayRev++;
              }
            }),
          ),
          _hint(t, 'Not on the list yet? Use "+ New person" above to add them as staff first.'),
          if (c != null) ...[
            _gap(AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: t.surface1, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: t.borderColor)),
              child: Row(children: [
                CircleAvatar(radius: 20, backgroundImage: c.avatarUrl != null ? NetworkImage(c.avatarUrl!) : null, child: c.avatarUrl == null ? Text(c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase()) : null),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      [c.phone, c.email].where((s) => s != null && s.isNotEmpty).join(' · ').isEmpty ? 'No contact details on file' : [c.phone, c.email].where((s) => s != null && s.isNotEmpty).join(' · '),
                      style: TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                  ]),
                ),
              ]),
            ),
          ],
        ] else ...[
          Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: t.surface2,
              backgroundImage: _avatarBytes != null ? MemoryImage(Uint8List.fromList(_avatarBytes!)) : null,
              child: _avatarBytes == null ? Icon(Icons.photo_camera_outlined, color: t.textSecondary) : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                OutlinedButton(onPressed: _pickAvatar, child: Text(_avatarBytes == null ? 'Upload Photo' : 'Change Photo')),
                Text('JPG, PNG or WEBP (max 2MB)', style: TextStyle(fontSize: 11, color: t.textSecondary)),
                if (_avatarError != null) Text(_avatarError!, style: TextStyle(fontSize: 11, color: t.destructive)),
              ]),
            ),
          ]),
          _gap(),
          _field('first', 'First Name *', _f.firstName, (v) => _setName(first: v), caps: TextCapitalization.words),
          _gap(AppSpacing.sm),
          _field('last', 'Last Name *', _f.lastName, (v) => _setName(last: v), caps: TextCapitalization.words),
          _gap(AppSpacing.sm),
          _field('phone', 'Phone Number *',_f.phone, (v) => _f.phone = sanitizePhoneDigits(v),
              keyboard: TextInputType.phone, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], errorText: phoneBad ? 'Enter all 10 digits of the phone number.' : null),
          _gap(AppSpacing.sm),
          _field('email', 'Email *', _f.email, (v) => _f.email = v, keyboard: TextInputType.emailAddress, errorText: emailBad ? 'Enter a valid email address.' : null),
          _gap(AppSpacing.sm),
          AppDropdown<String>(
            initialValue: _f.roleId.isEmpty ? null : _f.roleId,
            decoration: const InputDecoration(labelText: 'Role *'),
            items: _roles.isEmpty ? const [DropdownMenuItem(value: null, child: Text('No Roles Available'))] : _roles.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
            onChanged: (v) => setState(() => _f.roleId = v ?? ''),
          ),
          _hint(t, 'This creates a new staff account for this person, coaches are always staff members.'),
        ],
        _gap(AppSpacing.lg),
      ],
      _field('display' '$_displayRev', 'Display Name *', _f.displayName, (v) => _f.displayName = v, caps: TextCapitalization.words, hint: 'e.g. Coach Ravi'),
      _hint(t, 'Shown to students and on schedules.'),
      _gap(AppSpacing.sm),
      _field('location', 'Location', _f.location, (v) => _f.location = v, caps: TextCapitalization.words, hint: 'City the coach is based in'),
      _gap(AppSpacing.sm),
      AppDropdown<String>(
        initialValue: _f.timezone,
        decoration: const InputDecoration(labelText: 'Timezone *'),
        items: [for (final z in timezoneOptions) DropdownMenuItem(value: z.value, child: Text(z.label))],
        onChanged: (v) => setState(() => _f.timezone = v ?? 'Asia/Kolkata'),
      ),
      _gap(AppSpacing.sm),
      InkWell(
        onTap: _pickDob,
        child: InputDecorator(
          decoration: InputDecoration(labelText: 'Date of Birth (Optional)', errorText: dobBad ? 'Must be 18–100 years ago.' : null, suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
          child: Text(_f.dob == null ? 'Select date' : _f.dobIso!, style: TextStyle(color: _f.dob == null ? t.textSecondary : t.textPrimary)),
        ),
      ),
      _gap(),
      _label('Languages Spoken'),
      _chips<String>(languageOptions, _f.languages.contains, (v) => _f.languages.contains(v) ? _f.languages.remove(v) : _f.languages.add(v), (v) => v),
      _gap(),
      _field('bio', 'Short Bio (Optional)', _f.shortBio, (v) => _f.shortBio = v, maxLines: 3, maxLength: 500, hint: 'A short introduction students will see'),
    ];
  }

  // ── step 2 ───────────────────────────────────────────────────────────────
  void _addTag() {
    final v = _tagInput.text.trim();
    if (v.isEmpty || _f.subSpecialties.contains(v)) return;
    setState(() => _f.subSpecialties.add(v));
    _tagInput.clear();
  }

  List<Widget> _expertise(AppColorTokens t) {
    final expBad = _f.experience.trim().isNotEmpty && !_f.isStepValid(2) && !RegExp(r'^\d+(\.\d+)?$').hasMatch(_f.experience.trim());
    return [
      _field('niche', 'Coaching Niche *', _f.niche, (v) => _f.niche = v, caps: TextCapitalization.sentences, hint: 'e.g. Badminton – singles technique'),
      _gap(AppSpacing.sm),
      _field('exp', 'Years of Experience', _f.experience, (v) => _f.experience = v,
          keyboard: const TextInputType.numberWithOptions(decimal: true), formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], errorText: expBad ? 'Enter a valid number.' : null),
      _gap(),
      _label('Sports', required: true),
      if (_sports.isEmpty)
        Text('No sports are enabled for this facility yet.', style: TextStyle(color: t.textSecondary))
      else
        _chips<_SportChoice>(_sports, (s) => _f.sportIds.contains(s.id), (s) => _f.sportIds.contains(s.id) ? _f.sportIds.remove(s.id) : _f.sportIds.add(s.id), (s) => s.name),
      _gap(),
      _label('Expertise Level', required: true),
      _chips<String>(coachExpertiseLevels, _f.expertiseLevels.contains, (v) => _f.expertiseLevels.contains(v) ? _f.expertiseLevels.remove(v) : _f.expertiseLevels.add(v), (v) => v),
      _gap(),
      _label('Sub-specialties (Optional)'),
      Row(children: [
        Expanded(child: TextField(controller: _tagInput, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'e.g. Footwork, Smash'), onSubmitted: (_) => _addTag())),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(onPressed: _addTag, child: const Text('Add')),
      ]),
      if (_f.subSpecialties.isNotEmpty) ...[
        _gap(AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
          for (final s in _f.subSpecialties) InputChip(label: Text(s), onDeleted: () => setState(() => _f.subSpecialties.remove(s))),
        ]),
      ],
      _gap(),
      _label('Target Audience'),
      _chips<String>(audienceOptions, _f.targetAudience.contains, (v) => _f.targetAudience.contains(v) ? _f.targetAudience.remove(v) : _f.targetAudience.add(v), (v) => v),
      _gap(),
      _field('method', 'Coaching Methodology (Optional)', _f.methodology, (v) => _f.methodology = v, maxLines: 3, hint: 'How the coach structures sessions and tracks progress'),
      _gap(AppSpacing.lg),
      Row(children: [
        const Expanded(child: Text('Certifications & Credentials', style: TextStyle(fontWeight: FontWeight.w800))),
        TextButton.icon(onPressed: () => setState(() => _f.certificates.add(CertForm(id: _f.nextId()))), icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
      ]),
      _hint(t, 'Photos of the certificate (JPG, PNG or WEBP, up to 5MB). Stored privately. PDFs can be uploaded from the web app.'),
      if (_f.certificates.isEmpty) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text('No certificates added yet.', style: TextStyle(color: t.textSecondary))),
      for (final c in _f.certificates)
        Container(
          key: ValueKey('cert-${c.id}'),
          margin: const EdgeInsets.only(top: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(border: Border.all(color: t.borderColor), borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Column(children: [
            _field('cert-name-${c.id}', 'Certificate name *', c.name, (v) => c.name = v),
            _gap(AppSpacing.sm),
            Row(children: [
              Expanded(flex: 3, child: _field('cert-issuer-${c.id}', 'Issued by', c.issuer, (v) => c.issuer = v)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 2, child: _field('cert-year-${c.id}', 'Year', c.year, (v) => c.year = v, keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)])),
            ]),
            _gap(AppSpacing.xs),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _coachId == null || _busy ? null : () => _uploadCertificate(c),
                  icon: Icon(c.path.isEmpty ? Icons.upload_file_outlined : Icons.check_circle, size: 18, color: c.path.isEmpty ? null : t.success),
                  label: Text(c.path.isEmpty ? 'Upload photo' : 'Replace photo'),
                ),
              ),
              IconButton(tooltip: 'Remove certificate', onPressed: () => setState(() => _f.certificates.remove(c)), icon: const Icon(Icons.delete_outline)),
            ]),
          ]),
        ),
    ];
  }

  // ── step 3 ───────────────────────────────────────────────────────────────
  List<Widget> _services(AppColorTokens t) {
    // The three coaching amounts are optional; when one is filled in it has to be a whole number of rupees above zero.
    String? bad(String v) => v.isNotEmpty && !isValidRupees(v) ? 'Enter a whole number of rupees greater than 0.' : null;
    return [
      _label('Session Formats', required: true),
      for (final o in sessionFormatOptions)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: CheckboxListTile(
            value: _f.sessionFormats.contains(o.value),
            onChanged: (_) => setState(() => _f.sessionFormats.contains(o.value) ? _f.sessionFormats.remove(o.value) : _f.sessionFormats.add(o.value)),
            title: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(o.hint, style: TextStyle(fontSize: 12, color: t.textSecondary)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      _gap(),
      _label('Session Durations', required: true),
      _chips<int>(sessionDurationOptions, _f.sessionDurations.contains, (v) => _f.sessionDurations.contains(v) ? _f.sessionDurations.remove(v) : _f.sessionDurations.add(v), (v) => '$v min'),
      _gap(),
      _field('rate-session', 'Per Session Coaching Amount (₹)', _f.perSessionRate, (v) => _f.perSessionRate = v, keyboard: TextInputType.number, formatters: _digits, hint: 'e.g. 500', errorText: bad(_f.perSessionRate)),
      _gap(AppSpacing.sm),
      _field('rate-week', 'Weekly Session Coaching Amount (₹)', _f.weeklyRate, (v) => _f.weeklyRate = v, keyboard: TextInputType.number, formatters: _digits, hint: 'e.g. 2000', errorText: bad(_f.weeklyRate)),
      _gap(AppSpacing.sm),
      _field('rate-month', 'Monthly Session Coaching Amount (₹)', _f.monthlyRate, (v) => _f.monthlyRate = v, keyboard: TextInputType.number, formatters: _digits, hint: 'e.g. 7000', errorText: bad(_f.monthlyRate)),
    ];
  }


  // ── step 4 ───────────────────────────────────────────────────────────────
  List<Widget> _payout(AppColorTokens t) {
    if (!_canManagePayouts) {
      return [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: t.surface1, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: t.borderColor)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_outline, size: 18, color: t.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                "Payout & KYC details are restricted. You don't have permission to enter bank or tax details. You can finish this coach now — an owner can add them later, and the coach stays marked \"KYC pending\" until then.",
                style: TextStyle(fontSize: 13, color: t.textSecondary),
              ),
            ),
          ]),
        ),
      ];
    }
    final s = _savedPayout;
    final business = _f.entityType == 'BUSINESS';
    final taxNorm = business && isValidGstin(normalizeGstin(_f.taxId)) ? normalizeGstin(_f.taxId) : normalizePan(_f.taxId);
    final taxBad = _f.taxId.trim().isNotEmpty && !(isValidPan(taxNorm) || (business && isValidGstin(taxNorm)));
    final acctBad = _f.accountNumber.isNotEmpty && !isValidAccountNumber(_f.accountNumber);
    final confirmBad = _f.confirmAccountNumber.isNotEmpty && _f.confirmAccountNumber != _f.accountNumber;
    final ifscBad = _f.ifsc.trim().isNotEmpty && !isValidIfsc(normalizeIfsc(_f.ifsc));
    final upiBad = _f.upiId.trim().isNotEmpty && !isValidUpi(_f.upiId);
    final savedBits = [
      if (s?.taxIdMasked != null) 'Tax ID ${s!.taxIdMasked}',
      if (s?.accountNumberMasked != null) 'Account ${s!.accountNumberMasked}',
      if (s?.ifsc != null) 'IFSC ${s!.ifsc}',
      if (s?.upiId != null) 'UPI ${s!.upiId}',
    ].join(' · ');
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.verified_user_outlined, size: 16, color: t.primary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text('Bank and tax details are stored in a restricted area and shown masked (last 4 characters) after saving. You can finish this step later.', style: TextStyle(fontSize: 12, color: t.textSecondary))),
      ]),
      if (s != null) ...[
        _gap(AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: t.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: t.success.withValues(alpha: 0.4))),
          child: Text(
            'Payout details saved${savedBits.isEmpty ? '.' : ': $savedBits.'} Leave the secret fields blank to keep them, or type new values to replace them.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
      _gap(),
      AppDropdown<String>(
        initialValue: _f.entityType,
        decoration: const InputDecoration(labelText: 'Entity Type *'),
        items: const [DropdownMenuItem(value: 'INDIVIDUAL', child: Text('Individual')), DropdownMenuItem(value: 'BUSINESS', child: Text('Business'))],
        onChanged: (v) => setState(() => _f.entityType = v ?? 'INDIVIDUAL'),
      ),
      _gap(AppSpacing.sm),
      _field('tax', business ? 'PAN or GSTIN ${s == null ? '*' : ''}' : 'PAN ${s == null ? '*' : ''}', _f.taxId, (v) => _f.taxId = v.toUpperCase(),
          caps: TextCapitalization.characters, hint: s?.taxIdMasked ?? 'ABCDE1234F', maxLength: 20, errorText: taxBad ? (business ? 'Enter a valid PAN or GSTIN.' : 'Enter a valid PAN, e.g. ABCDE1234F.') : null),
      if (business) ...[
        _gap(AppSpacing.sm),
        _field('legal', 'Legal Business Name *', _f.legalName, (v) => _f.legalName = v),
        _gap(AppSpacing.sm),
        _field('addr', 'Business Address *', _f.businessAddress, (v) => _f.businessAddress = v, maxLines: 2),
      ],
      _gap(AppSpacing.sm),
      AppDropdown<String>(
        initialValue: _f.payoutMethod,
        decoration: const InputDecoration(labelText: 'Preferred Payout Method *'),
        items: const [DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('Bank transfer')), DropdownMenuItem(value: 'UPI', child: Text('UPI'))],
        onChanged: (v) => setState(() => _f.payoutMethod = v ?? 'BANK_TRANSFER'),
      ),
      _gap(AppSpacing.sm),
      if (_f.payoutMethod == 'BANK_TRANSFER') ...[
        _field('holder', 'Account Holder Name *', _f.accountHolderName, (v) => _f.accountHolderName = v, caps: TextCapitalization.words),
        _gap(AppSpacing.sm),
        _field('ifsc', 'IFSC Code ${s == null ? '*' : ''}', _f.ifsc, (v) => _f.ifsc = v.toUpperCase(),
            caps: TextCapitalization.characters, hint: s?.ifsc ?? 'SBIN0001234', maxLength: 14, errorText: ifscBad ? 'Enter a valid IFSC, e.g. SBIN0001234.' : null),
        _gap(AppSpacing.sm),
        _field('acct', 'Account Number ${s == null ? '*' : ''}', _f.accountNumber, (v) => _f.accountNumber = v,
            keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)], obscure: true, hint: s?.accountNumberMasked, errorText: acctBad ? 'Account numbers are 9 to 18 digits.' : null),
        _gap(AppSpacing.sm),
        _field('acct2', 'Confirm Account Number ${s == null ? '*' : ''}', _f.confirmAccountNumber, (v) => _f.confirmAccountNumber = v,
            keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)], errorText: confirmBad ? "The account numbers don't match." : null),
      ] else
        _field('upi', 'UPI ID ${s == null ? '*' : ''}', _f.upiId, (v) => _f.upiId = v, keyboard: TextInputType.emailAddress, hint: s?.upiId ?? 'name@okbank', errorText: upiBad ? 'Enter a valid UPI ID, e.g. name@okbank.' : null),
      _gap(AppSpacing.sm),
      AppDropdown<String>(
        initialValue: _f.payoutFrequency,
        decoration: const InputDecoration(labelText: 'Payout Frequency *'),
        items: [for (final o in payoutFrequencyOptions) DropdownMenuItem(value: o.value, child: Text(o.label))],
        onChanged: (v) => setState(() => _f.payoutFrequency = v ?? 'MONTHLY'),
      ),
      _hint(t, 'Payouts are in Indian rupees (INR).'),
      _gap(AppSpacing.sm),
      _field('policy', 'Cancellation & Refund Policy (Optional)', _f.cancellationPolicy, (v) => _f.cancellationPolicy = v, maxLines: 3, hint: 'e.g. Free cancellation up to 24 hours before a session'),
    ];
  }

  // ── step 5 ───────────────────────────────────────────────────────────────
  Widget _reviewCard(AppColorTokens t, int n, String title, List<(String, String)> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: t.surface1, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: t.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 11, backgroundColor: t.primary.withValues(alpha: 0.15), child: Text('$n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: t.primary))),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          TextButton(onPressed: () => setState(() => _step = n), child: const Text('Edit')),
        ]),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 104, child: Text(r.$1, style: TextStyle(fontSize: 12, color: t.textSecondary))),
              Expanded(child: Text(r.$2.isEmpty ? '—' : r.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
    );
  }

  List<Widget> _review(AppColorTokens t) {
    final sportName = {for (final s in _sports) s.id: s.name};
    final formats = [for (final o in sessionFormatOptions) if (_f.sessionFormats.contains(o.value)) o.label].join(', ');
    final durations = (_f.sessionDurations.toList()..sort()).map((m) => '$m min').join(', ');
    final kycDone = _payoutStatus == 'COMPLETE';
    Widget agree(String label, bool v, ValueChanged<bool> on) => CheckboxListTile(
          value: v,
          onChanged: (x) => setState(() => on(x ?? false)),
          title: Text(label, style: const TextStyle(fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        );
    return [
      _reviewCard(t, 1, coachOnboardingSteps[0], [('Display name', _f.displayName), ('Location', _f.location), ('Timezone', _f.timezone), ('Languages', _f.languages.join(', '))]),
      _reviewCard(t, 2, coachOnboardingSteps[1], [
        ('Niche', _f.niche),
        ('Sports', _f.sportIds.map((id) => sportName[id] ?? 'Sport').join(', ')),
        ('Levels', _f.expertiseLevels.join(', ')),
        ('Experience', _f.experience.isEmpty ? '' : '${_f.experience} years'),
        ('Audience', _f.targetAudience.join(', ')),
        ('Certificates', _f.certificates.map((c) => c.name).join(', ')),
      ]),
      _reviewCard(t, 3, coachOnboardingSteps[2], [
        ('Formats', formats),
        ('Durations', durations),
        ('Per session', _f.perSessionRate.isEmpty ? '' : '₹${_f.perSessionRate}'),
        ('Weekly', _f.weeklyRate.isEmpty ? '' : '₹${_f.weeklyRate}'),
        ('Monthly', _f.monthlyRate.isEmpty ? '' : '₹${_f.monthlyRate}'),
      ]),
      _reviewCard(t, 4, coachOnboardingSteps[3], [('Status', kycDone ? 'KYC complete (shown masked)' : 'KYC pending — add later from the coach profile')]),
      _gap(AppSpacing.sm),
      const Text('Agreements', style: TextStyle(fontWeight: FontWeight.w800)),
      agree("Terms of service — I confirm the coach has agreed to the platform's terms of service.", _f.agreeTerms, (v) => _f.agreeTerms = v),
      agree('Coach code of ethics — I confirm the coach has agreed to the code of ethics.', _f.agreeEthics, (v) => _f.agreeEthics = v),
      agree('Privacy & confidentiality — I confirm the coach has agreed to keep student information confidential.', _f.agreePrivacy, (v) => _f.agreePrivacy = v),
      agree('Platform commission — I confirm the coach has acknowledged the platform commission fee.', _f.agreeCommission, (v) => _f.agreeCommission = v),
    ];
  }

  // ── success ──────────────────────────────────────────────────────────────
  Widget _success(BuildContext context, ({String coachId, String name, StaffCredentials? credentials}) added) {
    final t = context.tokens;
    final actions = <({String title, String desc, IconData icon, VoidCallback onTap})>[
      (title: 'Schedule a Session', desc: 'Create a new coaching session for ${added.name}.', icon: Icons.event_available_outlined, onTap: () => context.push(AppRoutes.coachingSessionNew)),
      (
        title: 'Manage Availability',
        desc: 'Set working days, time slots and session duration.',
        icon: Icons.schedule_outlined,
        onTap: () => context.push(AppRoutes.coachingCoachDetail.replaceFirst(':coachId', added.coachId)),
      ),
      (title: 'Assign to Program', desc: 'Add ${added.name} to an existing or new coaching program.', icon: Icons.school_outlined, onTap: () => context.push(AppRoutes.coachingPrograms)),
      (
        title: 'View Coach Profile',
        desc: 'Go to the profile to manage details and settings.',
        icon: Icons.person_outline,
        onTap: () => context.push(AppRoutes.coachingCoachDetail.replaceFirst(':coachId', added.coachId)),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Add Coach'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SizedBox(height: AppSpacing.md),
            Icon(Icons.celebration_outlined, size: 48, color: t.success),
            const SizedBox(height: AppSpacing.sm),
            const Text('Coach Added Successfully!', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.xs),
            Text('${added.name} has been added to your coaching team and can now take sessions and manage their schedule.', textAlign: TextAlign.center, style: TextStyle(color: t.textSecondary)),
            if (added.credentials != null) ...[
              const SizedBox(height: AppSpacing.lg),
              const Text('Sign-in details', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              StaffCredentialsCard(loginEmail: added.credentials!.loginEmail, password: added.credentials!.password),
              const SizedBox(height: AppSpacing.xs),
              Text('They set their own password on first sign-in. Lost it? Open the person under Users & Roles > Staff and choose Reset Password.', style: TextStyle(fontSize: 12, color: t.textSecondary)),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Sign-in details are only shown when the account is created. Lost the password? Open the person under Staff and choose Reset Password.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: t.textSecondary)),
            ],
            const SizedBox(height: AppSpacing.lg),
            for (final a in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: InkWell(
                  onTap: a.onTap,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(color: t.surface1, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: t.borderColor)),
                    child: Row(children: [
                      Icon(a.icon, color: t.primary),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(a.desc, style: TextStyle(fontSize: 12, color: t.textSecondary)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop(true)),
          ],
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder while the staff list, roles, sports (or the saved draft) load.
class _OnboardingSkeleton extends StatelessWidget {
  const _OnboardingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [
        AppSkeleton(height: 32),
        SizedBox(height: AppSpacing.sm),
        AppSkeleton(height: 56),
        SizedBox(height: AppSpacing.sm),
        AppSkeleton(height: 56),
        SizedBox(height: AppSpacing.sm),
        AppSkeleton(height: 56),
        SizedBox(height: AppSpacing.lg),
        AppSkeleton(height: 48),
      ],
    );
  }
}
