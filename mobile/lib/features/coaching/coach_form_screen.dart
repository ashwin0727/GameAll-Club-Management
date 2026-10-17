import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/coaching.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'add_coach_validation.dart';

/// Add Coach — mirrors src/features/coaching/components/add-coach-page.tsx: pick an existing staff member or
/// create a new person (photo, name, phone, email, date of birth, role), then the coaching details (sports,
/// expertise, experience, certification), then status / default session length / bio, and a success screen
/// with the next actions. A coach is always a staff member.
class CoachFormScreen extends ConsumerStatefulWidget {
  const CoachFormScreen({super.key});

  @override
  ConsumerState<CoachFormScreen> createState() => _CoachFormScreenState();
}

class _FacilitySportChoice {
  const _FacilitySportChoice(this.id, this.name);
  final String id;
  final String name;
}

class _CoachFormScreenState extends ConsumerState<CoachFormScreen> {
  static const _avatarMaxBytes = 2 * 1024 * 1024;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _experience = TextEditingController();
  final _certifications = TextEditingController();
  final _customDuration = TextEditingController();
  final _bio = TextEditingController();

  List<CoachCandidate> _candidates = const [];
  List<RoleRow> _roles = const [];
  List<_FacilitySportChoice> _sports = const [];

  bool _newPerson = false;
  String? _userId;
  String? _roleId;
  DateTime? _dob;
  List<int>? _avatarBytes;
  String _avatarName = 'photo.jpg';
  String _avatarType = 'image/jpeg';
  String? _avatarError;

  final Set<String> _sportIds = {};
  final Set<String> _levels = {};
  CoachStatus _status = CoachStatus.active;
  String _duration = '60';

  bool _loading = true;
  bool _saving = false;
  String _stage = '';
  String? _error;
  ({String coachId, String name})? _added;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _email, _experience, _certifications, _customDuration, _bio]) {
      c.addListener(_refresh);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _experience, _certifications, _customDuration, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final candidates = await ref.read(coachingRepositoryProvider).listCoachCandidates(fid);
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final facilitySports = await sportsRepo.getFacilitySports(fid);
      final sports = await sportsRepo.getActiveSports();
      final choices = [
        for (final fs in facilitySports.where((f) => f.enabled))
          _FacilitySportChoice(
            fs.id,
            fs.customSportName ?? sports.where((s) => s.id == fs.sportId).map((s) => s.name).firstOrNull ?? 'Sport',
          ),
      ];
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
        _roleId = roles.where((r) => RegExp('coach', caseSensitive: false).hasMatch(r.name)).map((r) => r.id).firstOrNull;
        _error = rolesError == null ? null : 'Could not load roles for the new-person form: $rolesError';
        _loading = false;
      });
    } on AppException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  CoachCandidate? get _selected => _candidates.where((c) => c.userId == _userId).firstOrNull;

  bool get _canSubmit {
    final person = _newPerson
        ? _name.text.trim().isNotEmpty &&
            _roleId != null &&
            isValidEmail(_email.text) &&
            isValidPhoneDigits(_phone.text) &&
            isValidDateOfBirth(_dob)
        : _userId != null;
    final custom = _duration != 'custom' || (int.tryParse(_customDuration.text.trim()) ?? 0) > 0;
    return person && _sportIds.isNotEmpty && _levels.isNotEmpty && custom;
  }

  Future<void> _pickPhoto() async {
    setState(() => _avatarError = null);
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    final lower = file.name.toLowerCase();
    final type = lower.endsWith('.png') ? 'image/png' : lower.endsWith('.webp') ? 'image/webp' : (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) ? 'image/jpeg' : null;
    if (type == null) {
      setState(() => _avatarError = 'Please choose a JPG, PNG or WEBP image.');
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > _avatarMaxBytes) {
      setState(() => _avatarError = 'That photo is larger than 2MB.');
      return;
    }
    setState(() {
      _avatarBytes = bytes;
      _avatarName = file.name;
      _avatarType = type;
    });
  }

  Future<void> _pickDob() async {
    final b = dateOfBirthBounds();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? b.max,
      firstDate: b.min,
      lastDate: b.max,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final fid = _facilityId;
    if (fid == null || !_canSubmit) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var coachUserId = _userId;
      var displayName = _selected?.fullName ?? '';
      if (_newPerson) {
        String? avatarUrl;
        if (_avatarBytes != null) {
          setState(() => _stage = 'Uploading photo…');
          avatarUrl = await ref.read(staffRepositoryProvider).uploadAvatar(_avatarBytes!, _avatarName, _avatarType);
        }
        setState(() => _stage = 'Creating staff account…');
        final result = await ref.read(staffRepositoryProvider).createStaff(
              facilityId: fid,
              fullName: _name.text.trim(),
              email: _email.text.trim(),
              phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              roleId: _roleId!,
              avatarUrl: avatarUrl,
            );
        coachUserId = result.userId;
        displayName = _name.text.trim();
      }
      setState(() => _stage = 'Adding coach…');
      final exp = _experience.text.trim();
      final id = await ref.read(coachingRepositoryProvider).addCoach(
            facilityId: fid,
            userId: coachUserId!,
            experienceYears: exp.isEmpty ? null : double.tryParse(exp),
            certifications: _certifications.text.trim().isEmpty ? null : _certifications.text.trim(),
            bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
            status: _status,
            sportIds: _sportIds.toList(),
            expertiseLevels: coachExpertiseLevels.where(_levels.contains).toList(),
            defaultSessionDurationMinutes: _duration == 'custom' ? int.parse(_customDuration.text.trim()) : int.parse(_duration),
            dateOfBirth: _newPerson && _dob != null ? _iso(_dob!) : null,
          );
      if (mounted) setState(() { _saving = false; _added = (coachId: id, name: displayName); });
    } on AppException catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_MANAGE_COACHES')) {
      return const StaffPermissionDenied(title: 'Add Coach', message: "You don't have permission to manage coaches.");
    }
    if (_added != null) return _success(context, _added!);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Coach')),
      body: SafeArea(
        child: _loading
            ? const _CoachFormSkeleton()
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _heading(context, 1, 'Basic Information', "Enter the coach's personal and contact details."),
                  Wrap(spacing: AppSpacing.sm, children: [
                    ChoiceChip(label: const Text('Existing Staff Member'), selected: !_newPerson, onSelected: (_) => setState(() => _newPerson = false)),
                    ChoiceChip(label: const Text('+ New person'), selected: _newPerson, onSelected: (_) => setState(() => _newPerson = true)),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  if (!_newPerson) ..._pickExisting(context) else ..._newPersonFields(context),
                  const SizedBox(height: AppSpacing.lg),
                  _heading(context, 2, 'Coaching Details', 'Select the sports, expertise and experience.'),
                  _label('Sports *'),
                  if (_sports.isEmpty)
                    Text('No sports are enabled for this facility yet.', style: TextStyle(color: context.tokens.textSecondary))
                  else
                    Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
                      for (final s in _sports)
                        FilterChip(
                          label: Text(s.name),
                          selected: _sportIds.contains(s.id),
                          onSelected: (v) => setState(() => v ? _sportIds.add(s.id) : _sportIds.remove(s.id)),
                        ),
                    ]),
                  const SizedBox(height: AppSpacing.md),
                  _label('Expertise Level *'),
                  Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
                    for (final l in coachExpertiseLevels)
                      FilterChip(
                        label: Text(l),
                        selected: _levels.contains(l),
                        onSelected: (v) => setState(() => v ? _levels.add(l) : _levels.remove(l)),
                      ),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _experience,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Years of Experience'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _certifications,
                    decoration: const InputDecoration(labelText: 'Certification (Optional)', hintText: 'e.g. BWF Level 1, Certified Coach'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _heading(context, 3, 'Availability & Settings', "Set the coach's status and defaults."),
                  Text(
                    "The weekly recurring schedule is set up next, from the coach's profile — this just covers status and defaults.",
                    style: TextStyle(fontSize: 12, color: context.tokens.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppDropdown<CoachStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: CoachStatus.active, child: Text('Active')),
                      DropdownMenuItem(value: CoachStatus.inactive, child: Text('Inactive')),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? CoachStatus.active),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppDropdown<String>(
                    initialValue: _duration,
                    decoration: const InputDecoration(labelText: 'Default Session Duration'),
                    items: [for (final d in coachDurationOptions) DropdownMenuItem(value: d.value, child: Text(d.label))],
                    onChanged: (v) => setState(() => _duration = v ?? '60'),
                  ),
                  if (_duration == 'custom') ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _customDuration,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Custom Duration (Minutes)', hintText: 'e.g. 75'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _bio,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Coach Bio (Optional)', hintText: 'A short bio — achievements and coaching style'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: TextStyle(color: context.tokens.destructive)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: 'Add Coach',
                    loadingLabel: _stage.isEmpty ? 'Adding…' : _stage,
                    isLoading: _saving,
                    onPressed: _canSubmit && !_saving ? _save : null,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );

  Widget _heading(BuildContext context, int n, String title, String subtitle) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.success.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Text('$n', style: TextStyle(color: t.success, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: t.textSecondary)),
            ]),
          ),
        ],
      ),
    );
  }

  List<Widget> _pickExisting(BuildContext context) {
    final t = context.tokens;
    final c = _selected;
    return [
      AppDropdown<String>(
        initialValue: _userId,
        decoration: const InputDecoration(labelText: 'Staff Member'),
        items: _candidates.isEmpty
            ? const [DropdownMenuItem(value: null, child: Text('Every staff member is already a coach'))]
            : _candidates
                .map((c) => DropdownMenuItem(value: c.userId, child: Text(c.title != null ? '${c.fullName} · ${c.title}' : c.fullName)))
                .toList(),
        onChanged: (v) => setState(() => _userId = v),
      ),
      const SizedBox(height: 4),
      Text('Not on the list yet? Use "+ New person" above to add them as staff first.', style: TextStyle(fontSize: 11, color: t.textSecondary)),
      if (c != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: t.surface1, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: t.borderColor)),
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: c.avatarUrl != null ? NetworkImage(c.avatarUrl!) : null,
              child: c.avatarUrl == null ? Text(c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase()) : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [c.phone, c.email].where((s) => s != null && s.isNotEmpty).join(' · ').isEmpty
                      ? 'No contact details on file'
                      : [c.phone, c.email].where((s) => s != null && s.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ]),
            ),
          ]),
        ),
      ],
    ];
  }

  List<Widget> _newPersonFields(BuildContext context) {
    final t = context.tokens;
    final phoneBad = !isValidPhoneDigits(_phone.text);
    final emailBad = _email.text.isNotEmpty && !isValidEmail(_email.text);
    final dobBad = !isValidDateOfBirth(_dob);
    return [
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
            OutlinedButton(onPressed: _pickPhoto, child: Text(_avatarBytes == null ? 'Upload Photo' : 'Change Photo')),
            Text('JPG, PNG (Max 2MB)', style: TextStyle(fontSize: 11, color: t.textSecondary)),
            if (_avatarError != null) Text(_avatarError!, style: TextStyle(fontSize: 11, color: t.destructive)),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpacing.md),
      TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full Name *')),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        decoration: InputDecoration(labelText: 'Phone Number', errorText: phoneBad ? 'Enter all 10 digits of the phone number.' : null),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(labelText: 'Email *', errorText: emailBad ? 'Enter a valid email address.' : null),
      ),
      const SizedBox(height: AppSpacing.sm),
      InkWell(
        onTap: _pickDob,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Date of Birth (Optional)',
            errorText: dobBad ? 'Must be 18–100 years ago.' : null,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(_dob == null ? 'Select date' : _iso(_dob!), style: TextStyle(color: _dob == null ? t.textSecondary : t.textPrimary)),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppDropdown<String>(
        initialValue: _roleId,
        decoration: const InputDecoration(labelText: 'Role *'),
        items: _roles.isEmpty
            ? const [DropdownMenuItem(value: null, child: Text('No Roles Available'))]
            : _roles.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
        onChanged: (v) => setState(() => _roleId = v),
      ),
      const SizedBox(height: 4),
      Text('This creates a new staff account for this person — coaches are always staff members.',
          style: TextStyle(fontSize: 11, color: t.textSecondary)),
    ];
  }

  Widget _success(BuildContext context, ({String coachId, String name}) added) {
    final t = context.tokens;
    final actions = <({String title, String desc, IconData icon, VoidCallback onTap})>[
      (
        title: 'Schedule a Session',
        desc: 'Create a new coaching session for ${added.name}.',
        icon: Icons.event_available_outlined,
        onTap: () => context.push(AppRoutes.coachingSessionNew),
      ),
      (
        title: 'Manage Availability',
        desc: 'Set working days, time slots and session duration.',
        icon: Icons.schedule_outlined,
        onTap: () => context.push(AppRoutes.coachingCoachDetail.replaceFirst(':coachId', added.coachId)),
      ),
      (
        title: 'Assign to Program',
        desc: 'Add ${added.name} to an existing or new coaching program.',
        icon: Icons.sports_outlined,
        onTap: () => context.push(AppRoutes.coachingPrograms),
      ),
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
            Text(
              '${added.name} has been added to your coaching team and can now take sessions and manage their schedule.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary),
            ),
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

/// Structure-shaped placeholder for the add-coach form while the staff list, roles and sports load.
class _CoachFormSkeleton extends StatelessWidget {
  const _CoachFormSkeleton();

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
        SizedBox(height: AppSpacing.sm),
        AppSkeleton(height: 72),
        SizedBox(height: AppSpacing.sm),
        AppSkeleton(height: 56),
        SizedBox(height: AppSpacing.lg),
        AppSkeleton(height: 48),
      ],
    );
  }
}
