import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/booking.dart';
import '../../data/models/coaching.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/membership_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'coaching_common.dart';

/// Coaching → Manage Students → Add Student — mirrors
/// src/features/coaching/components/add-student-wizard-page.tsx.
///
/// The web runs five steps (Student Details → Program & Enrollment → Review & Confirm → Payment →
/// Success). On mobile the first three are sections of one scrolling page, and the payment step is
/// the enrollment's own Payments tab, which this screen hands off to the moment the student is
/// enrolled — Record Payment, and for an online program a Razorpay payment link (one-time) or
/// monthly auto-pay. The fee, batch, coach and end date are decided exactly as on the web.
class CoachingAddStudentScreen extends ConsumerStatefulWidget {
  const CoachingAddStudentScreen({super.key});

  @override
  ConsumerState<CoachingAddStudentScreen> createState() => _CoachingAddStudentScreenState();
}

class _CoachingAddStudentScreenState extends ConsumerState<CoachingAddStudentScreen> {
  // ── Student ────────────────────────────────────────────────────────────
  final _memberQuery = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _dateOfBirth;
  Timer? _debounce;
  List<MemberSearchResult> _memberHits = const [];
  MemberSearchResult? _member;

  // ── Program & batch ────────────────────────────────────────────────────
  List<ProgramOption> _programs = const [];
  bool _loadingPrograms = true;
  String? _programId;
  List<ProgramBatch> _batches = const [];
  bool _loadingBatches = false;
  String? _batchId;
  DateTime _startDate = _today();

  // Monthly programs: how many monthly charges until the program ends (counted by the database).
  int? _cycles;

  bool _saving = false;
  String? _error;
  bool _showErrors = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  ProgramOption? get _program => _programs.where((p) => p.id == _programId).firstOrNull;

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrograms());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_memberQuery, _fullName, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPrograms() async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final programs = await ref.read(coachingRepositoryProvider).listProgramOptions(fid);
      if (mounted) setState(() => _programs = programs);
    } on AppException {
      // the dropdown just stays empty
    } finally {
      if (mounted) setState(() => _loadingPrograms = false);
    }
  }

  void _onMemberQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final fid = _facilityId;
      if (fid == null || v.trim().length < 2) {
        if (mounted) setState(() => _memberHits = const []);
        return;
      }
      try {
        final hits = await ref.read(bookingRepositoryProvider).searchMembers(fid, v);
        if (mounted) setState(() => _memberHits = hits);
      } on AppException {
        if (mounted) setState(() => _memberHits = const []);
      }
    });
  }

  Future<void> _onProgramChanged(String? id) async {
    setState(() {
      _programId = id;
      _batches = const [];
      _batchId = null;
      _cycles = null;
      _error = null;
      // A program that has not started yet enrolls the student from its own start date, not from
      // today; one already running (or with no start date) starts them today.
      final start = _program?.startDate != null ? DateTime.tryParse(_program!.startDate!) : null;
      _startDate = (start != null && start.isAfter(_today())) ? start : _today();
      _loadingBatches = id != null;
    });
    if (id == null) return;
    try {
      final batches = await ref.read(coachingRepositoryProvider).listProgramBatches(id);
      if (!mounted || _programId != id) return;
      final active = batches.where((b) => b.status == 'ACTIVE').toList();
      setState(() {
        _batches = active;
        _batchId = active.where((b) => !b.isFull).firstOrNull?.id;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted && _programId == id) setState(() => _loadingBatches = false);
    }
    await _refreshCycles();
  }

  /// Monthly programs only — the months between the start date and the program end, by the database.
  Future<void> _refreshCycles() async {
    final p = _program;
    if (p == null || !p.isMonthly || p.endDate == null) {
      if (mounted) setState(() => _cycles = null);
      return;
    }
    try {
      final c = await ref.read(coachingRepositoryProvider).getBillingCycles(_iso(_startDate), p.endDate);
      if (mounted && _program?.id == p.id) setState(() => _cycles = c);
    } on AppException {
      if (mounted) setState(() => _cycles = null);
    }
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  // ── Validation (one set of rules for the live errors and the submit gate) ──
  String? get _nameError => _fullName.text.trim().isEmpty ? 'Full name is required.' : null;

  String? get _phoneError {
    final d = _phone.text.trim();
    if (d.isEmpty) return 'Phone number is required.';
    if (d.length != 10) return 'Enter a valid 10-digit phone number.';
    if (!RegExp(r'^[6-9]').hasMatch(d)) return 'Phone number must start with 6, 7, 8 or 9.';
    return null;
  }

  String? get _emailError {
    final e = _email.text.trim();
    if (e.isEmpty) return null;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(e) ? null : 'Enter a valid email address.';
  }

  bool get _studentValid => _member != null || (_nameError == null && _phoneError == null && _emailError == null);

  Future<void> _submit() async {
    final fid = _facilityId;
    final program = _program;
    if (fid == null) return;
    setState(() => _showErrors = true);
    if (!_studentValid) return;
    if (program == null) {
      setState(() => _error = 'Choose a program.');
      return;
    }
    if (_batches.isNotEmpty && _batchId == null) {
      setState(() => _error = 'Choose a batch.');
      return;
    }
    if (_batches.isEmpty && !_loadingBatches) {
      setState(() => _error = 'This program has no active batches available for enrollment.');
      return;
    }
    if (program.isMonthly && (program.endDate == null || _cycles == null)) {
      setState(() => _error = "This monthly program's total cannot be worked out — it needs an end date.");
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 1 — the student: an existing member, or a new one created now.
      var member = _member;
      if (member == null) {
        try {
          final created = await ref.read(membershipRepositoryProvider).createMember(MemberInput(
                facilityId: fid,
                fullName: _fullName.text.trim(),
                phone: _phone.text.trim(),
                email: _email.text.trim().isEmpty ? null : _email.text.trim(),
                dateOfBirth: _dateOfBirth != null ? _iso(_dateOfBirth!) : null,
                notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              ));
          member = MemberSearchResult(id: created.id, fullName: created.fullName, phone: created.phone, email: created.email);
          // Remember them: if the enrollment below fails, a retry must reuse this student rather
          // than trip over "phone already exists".
          if (mounted) setState(() => _member = member);
        } on MemberAlreadyExistsException {
          if (mounted) {
            setState(() {
              _saving = false;
              _error = 'A student with this phone number already exists. Search for them above and select them instead.';
            });
          }
          return;
        }
      }

      // 2 — the enrollment. The total obligation is one charge, or every month's charge until the
      // program ends; the batch's coach and the program's end date are filled in by the database.
      final included = program.isMembershipIncluded;
      final cycles = program.isMonthly ? (_cycles ?? 1) : 1;
      final id = await ref.read(coachingRepositoryProvider).createEnrollment(
            facilityId: fid,
            memberId: member.id,
            programId: program.id,
            batchId: _batchId,
            startDate: _iso(_startDate),
            priceMinor: included ? 0 : program.chargeMinor * cycles,
            pricingType: included ? 'MEMBERSHIP_INCLUDED' : 'STANDARD',
          );

      // 3 — payment happens on the enrollment's Payments tab.
      if (mounted) context.pushReplacement('${AppRoutes.coachingEnrollments}/$id?tab=payments');
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_MANAGE_ENROLLMENTS')) {
      return const StaffPermissionDenied(title: 'Add Student', message: "You don't have permission to manage coaching enrollments.");
    }
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Student')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Enroll a student into an existing coaching program.', style: AppTypography.secondary(context)),
            const SizedBox(height: AppSpacing.md),
            _heading('Student'),
            ..._studentSection(t),
            const SizedBox(height: AppSpacing.lg),
            _heading('Program & Enrollment'),
            ..._programSection(),
            ..._summary(),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: t.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Enroll & Continue to Payment',
              loadingLabel: 'Enrolling…',
              isLoading: _saving,
              onPressed: _submit,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _heading(String label) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      );

  List<Widget> _studentSection(AppColorTokens t) {
    if (_member != null) {
      return [
        AppCard(
          child: Row(
            children: [
              Icon(Icons.check_circle, color: t.primary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_member!.fullName, style: AppTypography.rowTitle(context)),
                    Text(
                      [_member!.phone, _member!.email].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                      style: AppTypography.caption(context),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: _saving ? null : () => setState(() => _member = null), child: const Text('Change')),
            ],
          ),
        ),
      ];
    }
    return [
      TextField(
        controller: _memberQuery,
        onChanged: _onMemberQuery,
        decoration: const InputDecoration(
          labelText: 'Search existing student',
          hintText: 'Name, phone or email',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      ..._memberHits.map((m) => ListTile(
            dense: true,
            title: Text(m.fullName),
            subtitle: m.phone.isNotEmpty ? Text(m.phone) : null,
            onTap: () => setState(() {
              _member = m;
              _memberHits = const [];
              _memberQuery.clear();
            }),
          )),
      const SizedBox(height: AppSpacing.sm),
      Text("No match? Enter the student's details to create a new one.", style: AppTypography.caption(context)),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _fullName,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: 'Full name *', errorText: _showErrors ? _nameError : null),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: 'Phone number *', errorText: _showErrors ? _phoneError : null),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: 'Email', errorText: _showErrors ? _emailError : null),
      ),
      const SizedBox(height: AppSpacing.sm),
      InkWell(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _dateOfBirth ?? DateTime(now.year - 12),
            firstDate: DateTime(now.year - 100),
            lastDate: now,
          );
          if (picked != null) setState(() => _dateOfBirth = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Date of birth'),
          child: Text(_dateOfBirth == null ? '—' : DateFormat('d MMM yyyy').format(_dateOfBirth!)),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(controller: _notes, maxLines: 2, maxLength: 500, decoration: const InputDecoration(labelText: 'Notes (optional)')),
    ];
  }

  List<Widget> _programSection() {
    final p = _program;
    return [
      DropdownButtonFormField<String>(
        initialValue: _programId,
        isExpanded: true,
        decoration: InputDecoration(labelText: _loadingPrograms ? 'Loading programs…' : 'Coaching program *'),
        items: _programs.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: _saving ? null : _onProgramChanged,
      ),
      if (!_loadingPrograms && _programs.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text('No active coaching programs available.', style: AppTypography.caption(context)),
        ),
      if (p != null) ...[
        const SizedBox(height: AppSpacing.sm),
        if (_loadingBatches)
          const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator()))
        else if (_batches.isEmpty)
          Text('This program has no active batches available for enrollment.', style: AppTypography.caption(context))
        else ...[
          Text('Select batch *', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          for (final b in _batches) _batchTile(b),
        ],
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: _saving
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate: DateTime(_startDate.year - 1),
                    lastDate: DateTime(_startDate.year + 3),
                  );
                  if (picked != null) {
                    setState(() => _startDate = picked);
                    _refreshCycles();
                  }
                },
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Enrollment start date *'),
            child: Text(DateFormat('d MMM yyyy').format(_startDate)),
          ),
        ),
        if (p.endDate != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text('Ends with the program on ${coachDate(p.endDate)}.', style: AppTypography.caption(context)),
          ),
      ],
    ];
  }

  Widget _batchTile(ProgramBatch b) {
    final selected = b.id == _batchId;
    final t = context.tokens;
    final full = b.isFull;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: (full && !selected) || _saving ? null : () => setState(() => _batchId = b.id),
        child: Opacity(
          opacity: full && !selected ? 0.5 : 1,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? t.primary : t.borderColor, width: selected ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.name, style: AppTypography.rowTitle(context)),
                      Text(
                        [b.scheduleLabel, if (b.coachName != null) b.coachName!].join(' · '),
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
                Text(full ? 'Full' : '${b.enrolledCount ?? 0} / ${b.capacity}', style: AppTypography.caption(context)),
                if (selected) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.check_circle, color: t.primary, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Review — the same payment summary the web shows before "Continue to Payment".
  List<Widget> _summary() {
    final p = _program;
    if (p == null) return const [];
    final cycles = p.isMonthly ? (_cycles ?? 1) : 1;
    final base = p.defaultPriceMinor ?? 0;
    final discount = p.earlyBirdDiscountMinor ?? 0;
    final tax = p.chargeMinor - (base - discount).clamp(0, base);
    return [
      const SizedBox(height: AppSpacing.lg),
      _heading('Payment Summary'),
      AppCard(
        child: p.isMembershipIncluded
            ? Text('Included — no fee', style: AppTypography.rowTitle(context))
            : Column(
                children: [
                  _sumRow(p.isMonthly ? 'Program fee (per month)' : 'Program fee', coachMoney(base)),
                  if (discount > 0) _sumRow('Discount', '-${coachMoney(discount)}'),
                  if (p.taxPercent != null) _sumRow('Tax', coachMoney(tax)),
                  const Divider(height: AppSpacing.lg),
                  if (p.isMonthly) ...[
                    _sumRow('Amount per month', coachMoney(p.chargeMinor), bold: true),
                    _sumRow('Monthly charges (until ${coachDate(p.endDate)})', '× $cycles'),
                    _sumRow('Total payable', coachMoney(p.chargeMinor * cycles), bold: true),
                  ] else
                    _sumRow('Amount payable', coachMoney(p.chargeMinor), bold: true),
                ],
              ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        p.isMembershipIncluded
            ? 'Nothing to collect for this program.'
            : 'You will collect this on the next screen — record a payment, or send a payment link.',
        style: AppTypography.caption(context),
      ),
    ];
  }

  Widget _sumRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: bold ? AppTypography.rowTitle(context) : AppTypography.secondary(context))),
            Text(value, style: bold ? AppTypography.rowTitle(context) : AppTypography.body(context)),
          ],
        ),
      );
}
