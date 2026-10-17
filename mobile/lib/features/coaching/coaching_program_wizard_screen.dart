import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/coaching.dart';
import '../../data/models/playing_area.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'program_wizard.dart';

class _SportChoice {
  const _SportChoice(this.id, this.name);
  final String id;
  final String name;
}

/// Create Coaching Program — the web's 5-step wizard (Basic Information → Program Details → Schedule & Batches →
/// Pricing & Settings → Review & Create), step for step and field for field, submitted atomically through
/// `create_coaching_program_full`. Editing an existing program still uses [CoachingProgramFormScreen].
class CoachingProgramWizardScreen extends ConsumerStatefulWidget {
  const CoachingProgramWizardScreen({super.key});

  @override
  ConsumerState<CoachingProgramWizardScreen> createState() => _CoachingProgramWizardScreenState();
}

class _CoachingProgramWizardScreenState extends ConsumerState<CoachingProgramWizardScreen> {
  static const _imageMaxBytes = 5 * 1024 * 1024;

  int _step = 0;
  bool _busy = false;
  String _stage = '';
  String? _error;

  // Reference data
  List<_SportChoice> _sports = const [];
  List<PlayingArea> _areas = const [];
  List<CoachOption> _coaches = const [];
  bool _loadingRefs = true;

  // Step 1
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _highlightInput = TextEditingController();
  String? _sportId;
  String _programType = 'GROUP';
  String _ageGroup = '11-14';
  String _level = 'Beginner';
  final List<String> _highlights = [];
  List<int>? _imageBytes;
  String _imageName = 'program.jpg';
  String _imageType = 'image/jpeg';
  String? _imageError;

  // Step 2
  String _sessionDuration = '60';
  final _customMinutes = TextEditingController();
  int _sessionsPerWeek = 3;
  String _durationWeeks = '12';
  DateTime _startDate = DateTime.now();
  DateTime? _customEnd;
  final _maxCapacity = TextEditingController(text: '20');
  final _minCapacity = TextEditingController();
  final _sessionFormat = TextEditingController();

  // Step 3
  final Set<int> _days = {1, 3, 5};
  TimeOfDay _start = const TimeOfDay(hour: 16, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);
  String? _courtId;
  String? _coachId;
  final _batchName = TextEditingController();
  final List<DraftBatch> _batches = [];

  // Step 4
  String _feeType = 'ONE_TIME';
  bool _perSession = false;
  final _fee = TextEditingController();
  String _paymentMode = 'BOTH';
  final _earlyBird = TextEditingController();
  DateTime? _discountTill;
  bool _tax = false;
  final _taxPercent = TextEditingController(text: '18');
  final _paymentNotes = TextEditingController();
  bool _waitlist = true;
  bool _trial = true;
  bool _autoEnroll = false;
  bool _notify = true;
  bool _visibleInBooking = false;
  bool _deadlineOn = false;
  DateTime? _deadline;

  List<TextEditingController> get _controllers =>
      [_name, _description, _highlightInput, _customMinutes, _maxCapacity, _minCapacity, _sessionFormat, _batchName, _fee, _earlyBird, _taxPercent, _paymentNotes];

  @override
  void initState() {
    super.initState();
    for (final c in _controllers) {
      c.addListener(_refresh);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRefs());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _loadRefs() async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final facilitySports = (await sportsRepo.getFacilitySports(fid)).where((f) => f.enabled).toList();
      final sports = await sportsRepo.getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(fid);
      final coaches = await ref.read(coachingRepositoryProvider).listCoachOptions(fid);
      if (!mounted) return;
      setState(() {
        _sports = [
          for (final fs in facilitySports)
            _SportChoice(fs.id, fs.customSportName ?? sports.where((s) => s.id == fs.sportId).map((s) => s.name).firstOrNull ?? 'Sport'),
        ];
        _areas = areas.where((a) => !a.archived && a.status == 'ACTIVE').toList();
        _coaches = coaches;
        _loadingRefs = false;
      });
    } on AppException catch (e) {
      if (mounted) setState(() { _error = e.message; _loadingRefs = false; });
    }
  }

  // ── derived values ──────────────────────────────────────────────────────
  String? get _sportName => _sports.where((s) => s.id == _sportId).map((s) => s.name).firstOrNull;
  List<PlayingArea> get _courts => _areas.where((a) => a.facilitySportId == _sportId).toList();
  int get _effectiveDuration => _sessionDuration == 'custom' ? (int.tryParse(_customMinutes.text.trim()) ?? 0) : int.parse(_sessionDuration);
  int get _weeks => weeksInProgram(durationWeeks: _durationWeeks, start: _startDate, customEnd: _customEnd);
  String get _endIso => _durationWeeks == 'custom' ? (_customEnd == null ? '' : _iso(_customEnd!)) : addWeeksIso(_startDate, int.parse(_durationWeeks));
  num get _price => num.tryParse(_fee.text.trim()) ?? 0;
  num get _discount => num.tryParse(_earlyBird.text.trim()) ?? 0;
  ProgramFee get _feeCalc => computeProgramFee(
        priceInr: _price,
        perSession: _perSession,
        sessionsPerWeek: _sessionsPerWeek,
        weeks: _weeks,
        discountInr: _discount,
        taxApplicable: _tax,
        taxPercent: num.tryParse(_taxPercent.text.trim()) ?? 0,
      );

  bool get _step1Valid => _name.text.trim().isNotEmpty && _description.text.trim().isNotEmpty && _sportId != null;
  bool get _step2Valid {
    final max = int.tryParse(_maxCapacity.text.trim()) ?? 0;
    final min = int.tryParse(_minCapacity.text.trim());
    return _effectiveDuration > 0 &&
        max > 0 &&
        (min == null || min <= max) &&
        (_durationWeeks != 'custom' || (_customEnd != null && !_customEnd!.isBefore(_startDate)));
  }

  bool get _step3Valid => _batches.length == 1;
  bool get _step4Valid {
    final monthly = _feeType == 'MONTHLY';
    return _price >= 0 && (!monthly || _price > 0) && _discount <= _feeCalc.baseInr && (!_deadlineOn || _deadline != null);
  }

  bool get _stepValid => switch (_step) {
        0 => _step1Valid,
        1 => _step2Valid,
        2 => _step3Valid,
        3 => _step4Valid,
        _ => _step1Valid && _step2Valid && _step3Valid && _step4Valid,
      };

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _date(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);
  String _inr(num v) => Formatters.currencyInr(v.round());

  String? get _batchDuplicate => _batchName.text.trim().isEmpty || _courtId == null
      ? null
      : findDuplicateBatch(_batches, name: _batchName.text, courtId: _courtId!, startTime: _hhmm(_start), endTime: _hhmm(_end), days: _days.toList());

  bool get _canAddBatch =>
      _batchName.text.trim().isNotEmpty && _days.isNotEmpty && _courtId != null && _batchDuplicate == null && (_start.hour * 60 + _start.minute) < (_end.hour * 60 + _end.minute);

  void _addBatch() {
    if (!_canAddBatch) return;
    setState(() {
      _batches.add(DraftBatch(
        name: _batchName.text.trim(),
        daysOfWeek: ([..._days]..sort()),
        startTime: _hhmm(_start),
        endTime: _hhmm(_end),
        capacity: int.tryParse(_maxCapacity.text.trim()) ?? 1,
        courtId: _courtId!,
        coachId: _coachId,
      ));
      _batchName.clear();
    });
  }

  Future<void> _pickImage() async {
    setState(() => _imageError = null);
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 85);
    if (file == null) return;
    final lower = file.name.toLowerCase();
    final type = lower.endsWith('.png') ? 'image/png' : lower.endsWith('.webp') ? 'image/webp' : (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) ? 'image/jpeg' : null;
    if (type == null) {
      setState(() => _imageError = 'Please choose a JPG, PNG or WEBP image.');
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > _imageMaxBytes) {
      setState(() => _imageError = 'That image is larger than 5MB.');
      return;
    }
    setState(() {
      _imageBytes = bytes;
      _imageName = file.name;
      _imageType = type;
    });
  }

  void _addHighlight() {
    final v = _highlightInput.text.trim();
    if (v.isEmpty || _highlights.contains(v)) return;
    setState(() {
      _highlights.add(v);
      _highlightInput.clear();
    });
  }

  Future<DateTime?> _pickDate(DateTime? initial, {DateTime? first, DateTime? last}) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? first ?? now,
      firstDate: first ?? DateTime(now.year - 1),
      lastDate: last ?? DateTime(now.year + 6),
    );
  }

  Future<void> _submit(String status) async {
    final fid = _facilityId;
    if (fid == null) return;
    if (status == 'ACTIVE' && !_stepValid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? imageUrl;
      if (_imageBytes != null) {
        setState(() => _stage = 'Uploading image…');
        imageUrl = await ref.read(coachingRepositoryProvider).uploadProgramImage(_imageBytes!, _imageName, _imageType);
      }
      setState(() => _stage = 'Creating…');
      final f = _feeCalc;
      final max = int.parse(_maxCapacity.text.trim());
      await ref.read(coachingRepositoryProvider).createProgramFull(
            facilityId: fid,
            name: _name.text.trim(),
            level: _level,
            ageGroup: _ageGroup,
            description: _description.text.trim(),
            facilitySportId: _sportId,
            defaultDurationMinutes: _effectiveDuration,
            defaultCapacity: max,
            minCapacity: _minCapacity.text.trim().isEmpty ? null : int.parse(_minCapacity.text.trim()),
            sessionsPerWeek: _sessionsPerWeek,
            startDate: _iso(_startDate),
            endDate: _endIso.isEmpty ? null : _endIso,
            programType: _programType,
            programStructure: _highlights,
            sessionFormat: _sessionFormat.text.trim().isEmpty ? null : _sessionFormat.text.trim(),
            imageUrl: imageUrl,
            // Stored as the base per-student fee (before discount / tax), a per-session fee already multiplied out.
            defaultPriceMinor: f.baseInr > 0 ? (f.baseInr * 100).round() : null,
            paymentMode: _paymentMode,
            feeType: _feeType,
            earlyBirdDiscountMinor: _discount > 0 ? (_discount * 100).round() : null,
            discountValidTill: _discountTill == null ? null : _iso(_discountTill!),
            taxPercent: _tax ? double.tryParse(_taxPercent.text.trim()) : null,
            paymentNotes: _paymentNotes.text.trim().isEmpty ? null : _paymentNotes.text.trim(),
            allowWaitlist: _waitlist,
            allowTrialSession: _trial,
            autoEnrollNextBatch: _autoEnroll,
            sendNotifications: _notify,
            visibleInBooking: _visibleInBooking,
            enrollmentDeadline: _deadlineOn && _deadline != null ? _iso(_deadline!) : null,
            status: status,
            batches: _batches.map((b) => b.toPayload()).toList(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; });
    }
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_MANAGE_PROGRAMS')) {
      return const StaffPermissionDenied(title: 'Create Program', message: "You don't have permission to manage programs.");
    }
    final t = context.tokens;
    final last = _step == programSteps.length - 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Coaching Program')),
      body: SafeArea(
        child: _loadingRefs
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _stepper(t),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        if (_step == 0) ..._basic(t),
                        if (_step == 1) ..._details(t),
                        if (_step == 2) ..._schedule(t),
                        if (_step == 3) ..._pricing(t),
                        if (_step == 4) ..._review(t),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(_error!, style: TextStyle(color: t.destructive)),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                    decoration: BoxDecoration(color: t.surface0, border: Border(top: BorderSide(color: t.borderColor))),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: _busy ? null : () => _step == 0 ? Navigator.of(context).maybePop() : setState(() => _step--),
                          child: Text(_step == 0 ? 'Cancel' : 'Back'),
                        ),
                        const Spacer(),
                        if (last) ...[
                          OutlinedButton(onPressed: _busy ? null : () => _submit('DRAFT'), child: const Text('Save as Draft')),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        SizedBox(
                          width: 150,
                          child: PrimaryButton(
                            label: last ? 'Create Program' : 'Next',
                            loadingLabel: _stage.isEmpty ? 'Creating…' : _stage,
                            isLoading: _busy,
                            onPressed: _busy || !_stepValid ? null : (last ? () => _submit('ACTIVE') : () => setState(() => _step++)),
                          ),
                        ),
                      ],
                    ),
                  ),
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
          Text('Step ${_step + 1} of ${programSteps.length} · ${programSteps[_step]}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < programSteps.length; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: i <= _step && !_busy ? () => setState(() => _step = i) : null,
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(right: i == programSteps.length - 1 ? 0 : 4),
                      decoration: BoxDecoration(
                        color: i < _step ? t.success : i == _step ? t.primary : t.borderColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
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

  Widget _choice(AppColorTokens t, String label, bool selected, VoidCallback onTap) => ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());

  Widget _num(TextEditingController c, String label, {bool decimal = false, String? hint}) => TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [decimal ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')) : FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, hintText: hint),
      );

  Widget _dateField(String label, DateTime? value, VoidCallback onTap, {bool enabled = true}) => InkWell(
        onTap: enabled ? onTap : null,
        child: AppSelectField(
          decoration: InputDecoration(labelText: label),
          child: Text(value == null ? 'Select date' : DateFormat('d MMM yyyy').format(value)),
        ),
      );

  Widget _timeField(String label, TimeOfDay value, ValueChanged<TimeOfDay> onPicked) => InkWell(
        onTap: () async {
          final picked = await showTimePicker(context: context, initialTime: value);
          if (picked != null) onPicked(picked);
        },
        child: AppSelectField(decoration: InputDecoration(labelText: label), child: Text(value.format(context))),
      );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(border: Border.all(color: context.tokens.borderColor), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(label), value: value, onChanged: onChanged),
      );

  Widget _optionCard(AppColorTokens t, String title, String? hint, bool selected, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Opacity(
            opacity: onTap == null ? 0.45 : 1,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: selected ? t.success.withValues(alpha: 0.10) : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: selected ? t.success : t.borderColor, width: selected ? 1.5 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? t.success : null)),
                if (hint != null) Text(hint, style: TextStyle(fontSize: 12, color: t.textSecondary)),
              ]),
            ),
          ),
        ),
      );

  // ── step 1 ───────────────────────────────────────────────────────────────
  List<Widget> _basic(AppColorTokens t) => [
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Program Name *', hintText: 'e.g. Junior Badminton Academy')),
        _gap(AppSpacing.sm),
        AppDropdown<String>(
          initialValue: _sportId,
          decoration: const InputDecoration(labelText: 'Sport *'),
          items: [for (final s in _sports) DropdownMenuItem(value: s.id, child: Text(s.name))],
          onChanged: (v) => setState(() {
            _sportId = v;
            _courtId = null;
            _batches.clear();
          }),
        ),
        _gap(AppSpacing.sm),
        TextField(
          controller: _description,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Description *', hintText: 'Describe the program, what students will learn…'),
        ),
        _label('Program Image'),
        InkWell(
          onTap: _pickImage,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(border: Border.all(color: t.borderColor), borderRadius: BorderRadius.circular(AppRadius.md)),
            clipBehavior: Clip.antiAlias,
            child: _imageBytes != null
                ? Image.memory(Uint8List.fromList(_imageBytes!), fit: BoxFit.cover)
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate_outlined, color: t.textSecondary),
                    Text('Tap to upload an image', style: TextStyle(fontSize: 12, color: t.textSecondary)),
                  ]),
          ),
        ),
        _hint(t, 'JPG, PNG or WEBP, up to 5MB.'),
        if (_imageError != null) Text(_imageError!, style: TextStyle(fontSize: 12, color: t.destructive)),
        _gap(),
        _label('Program Type', required: true),
        for (final p in programTypes) _optionCard(t, p.label, p.hint, _programType == p.value, () => setState(() => _programType = p.value)),
        _gap(AppSpacing.sm),
        _label('Target Audience — Age Group', required: true),
        Wrap(spacing: AppSpacing.sm, children: [for (final a in programAgeGroups) _choice(t, a, _ageGroup == a, () => setState(() => _ageGroup = a))]),
        _gap(),
        _label('Target Audience — Skill Level', required: true),
        Wrap(spacing: AppSpacing.sm, children: [for (final l in programSkillLevels) _choice(t, l, _level == l, () => setState(() => _level = l))]),
        _gap(),
        _label('Key Highlights'),
        Row(children: [
          Expanded(child: TextField(controller: _highlightInput, onSubmitted: (_) => _addHighlight(), decoration: const InputDecoration(hintText: 'e.g. Certified coaches'))),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(onPressed: _addHighlight, child: const Text('Add')),
        ]),
        _hint(t, "Short highlights shown on the program's card."),
        if (_highlights.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(spacing: AppSpacing.sm, children: [
              for (final h in _highlights) InputChip(label: Text(h), onDeleted: () => setState(() => _highlights.remove(h))),
            ]),
          ),
      ];

  // ── step 2 ───────────────────────────────────────────────────────────────
  List<Widget> _details(AppColorTokens t) {
    final presets = programStructurePresetsForSport(_sportName);
    return [
      _label('Session Duration', required: true),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
        for (final d in sessionDurations) _choice(t, d.label, _sessionDuration == d.value, () => setState(() => _sessionDuration = d.value)),
      ]),
      if (_sessionDuration == 'custom') ...[_gap(AppSpacing.sm), _num(_customMinutes, 'Minutes')],
      _gap(),
      _label('Sessions Per Week', required: true),
      Wrap(spacing: AppSpacing.sm, children: [for (final n in sessionsPerWeekChoices) _choice(t, '$n', _sessionsPerWeek == n, () => setState(() => _sessionsPerWeek = n))]),
      _gap(),
      _label('Program Duration', required: true),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
        for (final d in programDurations) _choice(t, d.label, _durationWeeks == d.value, () => setState(() => _durationWeeks = d.value)),
      ]),
      _gap(),
      Row(children: [
        Expanded(
          child: _dateField('Start Date *', _startDate, () async {
            final d = await _pickDate(_startDate, first: DateTime.now().subtract(const Duration(days: 1)));
            if (d != null) setState(() => _startDate = d);
          }),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _durationWeeks == 'custom'
              ? _dateField('End Date *', _customEnd, () async {
                  final d = await _pickDate(_customEnd, first: _startDate);
                  if (d != null) setState(() => _customEnd = d);
                })
              : _dateField('End Date (computed)', DateTime.tryParse(_endIso), () {}, enabled: false),
        ),
      ]),
      _gap(),
      Row(children: [
        Expanded(child: _num(_maxCapacity, 'Max Capacity *')),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _num(_minCapacity, 'Minimum Students')),
      ]),
      _gap(),
      _label('Program Structure'),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
        for (final p in presets)
          FilterChip(
            label: Text(p),
            selected: _highlights.contains(p),
            onSelected: (v) => setState(() => v ? _highlights.add(p) : _highlights.remove(p)),
          ),
      ]),
      _hint(t, _sportName == null ? 'What this program covers, shown to students.' : 'What this $_sportName program covers, shown to students.'),
      _gap(),
      TextField(controller: _sessionFormat, decoration: const InputDecoration(labelText: 'Session Format (optional)', hintText: 'e.g. On-court group drills')),
    ];
  }

  // ── step 3 ───────────────────────────────────────────────────────────────
  List<Widget> _schedule(AppColorTokens t) {
    final courts = _courts;
    return [
      if (_batches.isEmpty) ...[
        _label('Weekly Schedule', required: true),
        _hint(t, "A program has exactly one batch — its day / time / court / coach schedule."),
        _gap(AppSpacing.sm),
        Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
          for (var d = 0; d < 7; d++)
            FilterChip(
              label: Text(dayLabelsShort[d]),
              selected: _days.contains(d),
              showCheckmark: false,
              onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
            ),
        ]),
        _gap(),
        Row(children: [
          Expanded(child: _timeField('Start Time *', _start, (v) => setState(() => _start = v))),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _timeField('End Time *', _end, (v) => setState(() => _end = v))),
        ]),
        _gap(AppSpacing.sm),
        AppDropdown<String>(
          initialValue: _courtId,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Court *', helperText: courts.isEmpty ? 'No active courts for ${_sportName ?? 'this sport'}.' : null),
          items: [for (final c in courts) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _courtId = v),
        ),
        _gap(AppSpacing.sm),
        AppDropdown<String>(
          initialValue: _coachId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Coach'),
          items: [
            const DropdownMenuItem(value: null, child: Text('No specific coach')),
            for (final c in _coaches) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _coachId = v),
        ),
        _gap(AppSpacing.sm),
        Row(children: [
          Expanded(child: TextField(controller: _batchName, decoration: const InputDecoration(labelText: 'Batch name', hintText: 'e.g. Morning Batch'))),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(onPressed: _canAddBatch ? _addBatch : null, child: const Text('Add Batch')),
        ]),
        if (_batchDuplicate != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_batchDuplicate!, style: TextStyle(fontSize: 12, color: t.destructive))),
        _gap(),
      ],
      _label('Batches', required: true),
      if (_batches.isEmpty)
        Text('No batch added yet — a batch is required before you can continue.', style: TextStyle(color: t.textSecondary))
      else
        for (var i = 0; i < _batches.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(border: Border.all(color: t.borderColor), borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_batches[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '${_batches[i].daysOfWeek.map((d) => dayLabelsShort[d]).join(', ')} · ${_batches[i].startTime}–${_batches[i].endTime} · '
                    '${_areas.where((a) => a.id == _batches[i].courtId).map((a) => a.name).firstOrNull ?? '—'}'
                    '${_coaches.where((c) => c.id == _batches[i].coachId).map((c) => ' · ${c.name}').firstOrNull ?? ''} · Capacity ${_batches[i].capacity}',
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                  ),
                ]),
              ),
              IconButton(onPressed: () => setState(() => _batches.removeAt(i)), icon: Icon(Icons.delete_outline, color: t.destructive)),
            ]),
          ),
    ];
  }

  // ── step 4 ───────────────────────────────────────────────────────────────
  List<Widget> _pricing(AppColorTokens t) {
    final monthly = _feeType == 'MONTHLY';
    final f = _feeCalc;
    return [
      _label('Fee Type'),
      _optionCard(t, 'One-time Payment', 'Student pays the full fee once, via a payment link.', !monthly, () => setState(() => _feeType = 'ONE_TIME')),
      _optionCard(t, 'Monthly Payment', 'Auto-charged every month until the program ends.', monthly, () => setState(() {
            _feeType = 'MONTHLY';
            _perSession = false; // a monthly fee is one flat amount per month
          })),
      _label('Fee Structure'),
      _optionCard(t, 'Single Program Fee', null, !_perSession, () => setState(() => _perSession = false)),
      _optionCard(t, 'Per Session Fee', null, _perSession, monthly ? null : () => setState(() => _perSession = true)),
      _gap(AppSpacing.sm),
      _num(_fee, monthly ? 'Fee per Month (₹)' : (_perSession ? 'Fee per Session (₹)' : 'Total Program Fee (₹)'), decimal: true),
      _gap(AppSpacing.sm),
      AppDropdown<String>(
        initialValue: _paymentMode,
        decoration: const InputDecoration(labelText: 'Payment Mode'),
        items: const [
          DropdownMenuItem(value: 'OFFLINE', child: Text('Offline')),
          DropdownMenuItem(value: 'ONLINE', child: Text('Online')),
          DropdownMenuItem(value: 'BOTH', child: Text('Offline & Online')),
        ],
        onChanged: (v) => setState(() => _paymentMode = v ?? 'BOTH'),
      ),
      _gap(AppSpacing.sm),
      Row(children: [
        Expanded(child: _num(_earlyBird, 'Early Bird Discount (₹)', decimal: true)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _dateField('Discount Valid Till', _discountTill, () async {
            final d = await _pickDate(_discountTill, first: DateTime.now());
            if (d != null) setState(() => _discountTill = d);
          }),
        ),
      ]),
      if (_discount > f.baseInr) Padding(padding: const EdgeInsets.only(top: 4), child: Text('The discount cannot be more than the fee.', style: TextStyle(fontSize: 12, color: t.destructive))),
      _gap(AppSpacing.sm),
      _switchRow('Apply Tax (GST)', _tax, (v) => setState(() => _tax = v)),
      if (_tax) _num(_taxPercent, 'Tax Percent', decimal: true),
      _gap(AppSpacing.sm),
      TextField(controller: _paymentNotes, maxLines: 2, decoration: const InputDecoration(labelText: 'Payment Notes (optional)')),
      _gap(),
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: t.primary.withValues(alpha: 0.25))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(monthly ? 'Per Month' : 'Total Fee per Student', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                _perSession ? '${_inr(_price)} × ${f.totalSessions} sessions${_discount > 0 ? ' − discount' : ''}${_tax ? ' + tax' : ''}' : 'Program fee${_discount > 0 ? ' − discount' : ''}${_tax ? ' + tax' : ''}',
                style: TextStyle(fontSize: 12, color: t.textSecondary),
              ),
            ]),
          ),
          Text(_inr(f.totalInr), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.primary)),
        ]),
      ),
      _gap(),
      const Text('Additional Settings', style: TextStyle(fontWeight: FontWeight.w800)),
      _gap(AppSpacing.sm),
      _switchRow('Allow Waitlist', _waitlist, (v) => setState(() => _waitlist = v)),
      _switchRow('Allow Trial Session', _trial, (v) => setState(() => _trial = v)),
      _switchRow('Auto Enroll to Next Batch', _autoEnroll, (v) => setState(() => _autoEnroll = v)),
      _switchRow('Send Notifications', _notify, (v) => setState(() => _notify = v)),
      _switchRow('Visible in Online Booking', _visibleInBooking, (v) => setState(() => _visibleInBooking = v)),
      _switchRow('Enrollment Deadline', _deadlineOn, (v) => setState(() => _deadlineOn = v)),
      if (_deadlineOn)
        _dateField('Deadline (on or before the start date)', _deadline, () async {
          final d = await _pickDate(_deadline, first: DateTime.now(), last: _startDate);
          if (d != null) setState(() => _deadline = d);
        }),
    ];
  }

  // ── step 5 ───────────────────────────────────────────────────────────────
  Widget _reviewSection(AppColorTokens t, int n, String title, int editStep, List<Widget> rows) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: t.surface1, border: Border.all(color: t.borderColor), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Text('$n', style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            OutlinedButton.icon(onPressed: () => setState(() => _step = editStep), icon: const Icon(Icons.edit_outlined, size: 14), label: const Text('Edit')),
          ]),
          const SizedBox(height: AppSpacing.sm),
          ...rows,
        ]),
      );

  Widget _row(AppColorTokens t, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 12, color: t.textSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      );

  List<Widget> _review(AppColorTokens t) {
    final f = _feeCalc;
    final monthly = _feeType == 'MONTHLY';
    final typeLabel = programTypes.firstWhere((p) => p.value == _programType).label;
    return [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(color: t.surface1, border: Border.all(color: t.borderColor), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 80,
              height: 64,
              child: _imageBytes != null ? Image.memory(Uint8List.fromList(_imageBytes!), fit: BoxFit.cover) : Container(color: t.surface2, child: Icon(Icons.menu_book_outlined, color: t.textSecondary)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name.text.trim().isEmpty ? 'Untitled Program' : _name.text.trim(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(_description.text.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.textSecondary)),
              const SizedBox(height: 4),
              Text('${_sportName ?? '—'} · $_level · Ages $_ageGroup · ${_maxCapacity.text} students', style: TextStyle(fontSize: 11, color: t.textSecondary)),
            ]),
          ),
        ]),
      ),
      _reviewSection(t, 1, 'Basic Information', 0, [
        _row(t, 'Program Name', _name.text.trim()),
        _row(t, 'Description', _description.text.trim()),
        _row(t, 'Sport', _sportName ?? '—'),
        _row(t, 'Program Type', typeLabel),
        if (_highlights.isNotEmpty) _row(t, 'Key Highlights', _highlights.join(', ')),
      ]),
      _reviewSection(t, 2, 'Program Details', 1, [
        _row(t, 'Age Group', _ageGroup),
        _row(t, 'Skill Level', _level),
        _row(t, 'Session Duration', '$_effectiveDuration minutes'),
        _row(t, 'Sessions per Week', '$_sessionsPerWeek'),
        _row(t, 'Program Duration', _weeks > 0 ? '$_weeks Weeks' : '—'),
        _row(t, 'Start Date', _date(_startDate)),
        _row(t, 'End Date', _date(DateTime.tryParse(_endIso))),
        _row(t, 'Max Capacity', '${_maxCapacity.text} Students'),
        if (_minCapacity.text.trim().isNotEmpty) _row(t, 'Minimum Students', '${_minCapacity.text} Students'),
        if (_sessionFormat.text.trim().isNotEmpty) _row(t, 'Session Format', _sessionFormat.text.trim()),
      ]),
      _reviewSection(t, 3, 'Schedule & Batches', 2, [
        if (_batches.isEmpty) Text('No batches added yet.', style: TextStyle(color: t.textSecondary)),
        for (final b in _batches) ...[
          _row(t, 'Batch', b.name),
          _row(t, 'Days', b.daysOfWeek.map((d) => dayLabelsShort[d]).join(', ')),
          _row(t, 'Time', '${b.startTime}–${b.endTime}'),
          _row(t, 'Court', _areas.where((a) => a.id == b.courtId).map((a) => a.name).firstOrNull ?? '—'),
          _row(t, 'Coach', _coaches.where((c) => c.id == b.coachId).map((c) => c.name).firstOrNull ?? '—'),
        ],
      ]),
      _reviewSection(t, 4, 'Pricing & Settings', 3, [
        _row(t, 'Fee Type', monthly ? 'Monthly (auto-charged until program ends)' : 'One-time'),
        _row(t, 'Fee Structure', _perSession ? 'Per Session Fee' : 'Single Program Fee'),
        if (_perSession) ...[_row(t, 'Per Session Fee', _inr(_price)), _row(t, 'Total Sessions', '${f.totalSessions}')] else _row(t, monthly ? 'Fee per Month' : 'Program Fee', _inr(_price)),
        if (_discount > 0) _row(t, 'Early Bird Discount', '${_inr(_discount)}${_discountTill != null ? ' (till ${_date(_discountTill)})' : ''}'),
        _row(t, 'Tax Applicable', _tax ? 'Yes (${_taxPercent.text}% GST)' : 'No'),
        _row(t, 'Payment Mode', const {'OFFLINE': 'Offline', 'ONLINE': 'Online', 'BOTH': 'Offline & Online'}[_paymentMode]!),
        _row(t, 'Allow Waitlist', _waitlist ? 'Yes' : 'No'),
        _row(t, 'Allow Trial Session', _trial ? 'Yes' : 'No'),
        _row(t, 'Auto Enroll Next Batch', _autoEnroll ? 'Yes' : 'No'),
        _row(t, 'Send Notifications', _notify ? 'Yes' : 'No'),
        _row(t, 'Visible in Booking', _visibleInBooking ? 'Yes' : 'No'),
        _row(t, 'Enrollment Deadline', _deadlineOn ? _date(_deadline) : 'None'),
        const Divider(),
        Row(children: [
          Expanded(child: Text(monthly ? 'Per Month' : 'Total Fee per Student', style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(_inr(f.totalInr), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.primary)),
        ]),
        if (_batches.isNotEmpty)
          Text('Estimated total across ${_maxCapacity.text} students: ${_inr(f.totalInr * (int.tryParse(_maxCapacity.text) ?? 0))}', style: TextStyle(fontSize: 11, color: t.textSecondary)),
      ]),
    ];
  }
}
