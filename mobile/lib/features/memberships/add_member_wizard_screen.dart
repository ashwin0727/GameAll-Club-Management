import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../authentication/session_controller.dart';
import 'add_member_wizard.dart';
import 'duplicate_guards.dart';
import 'plan_presentation.dart';
import 'plan_wizard.dart' show planBillingIntervalLabel, planDayAbbr;

/// Memberships → New membership — mirrors the web's Add New Member wizard
/// (src/features/memberships/components/add-member-wizard-page.tsx), step for step:
///
///   1 Personal Information — who the member is
///   2 Select Plan          — pick a plan; its courts and timings come with it (read-only)
///   3 Review & Confirm     — check everything
///   4 Payment              — payment link, offline payment, or mark as paid
///
/// A plan's court and timings are configured when the plan is created, so the member cannot change
/// them here: saving simply joins the plan's own slots. Pops `true` once a member exists.
class AddMemberWizardScreen extends ConsumerStatefulWidget {
  const AddMemberWizardScreen({super.key});

  @override
  ConsumerState<AddMemberWizardScreen> createState() => _AddMemberWizardScreenState();
}

class _AddMemberWizardScreenState extends ConsumerState<AddMemberWizardScreen> {
  final _d = AddMemberDraft();

  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _registrationFee = TextEditingController();
  final _gst = TextEditingController();
  final _paymentAmount = TextEditingController();
  final _paymentRef = TextEditingController();
  final _receivedFrom = TextEditingController();
  final _collectedBy = TextEditingController();
  final _paymentNotes = TextEditingController();

  int _step = 0;
  final Set<String> _touched = {};

  String? _facilityId;
  bool _loading = true;
  String? _loadError;
  List<MembershipPlan> _plans = const [];
  List<AssignableBatch> _batches = const [];

  /// Every membership at the facility, so the same person can't be put on the same plan twice.
  List<MembershipListRow> _memberships = const [];

  bool _saving = false;
  String? _error;
  bool _receivedFromSeeded = false;

  /// Set once a payment link exists: the member is already created, so nothing earlier can change.
  ({String membershipId, String? shortUrl})? _link;

  bool get _locked => _link != null;
  bool get _planIsRecurring => _selectedPlan?.planType == 'RECURRING';

  MembershipPlan? get _selectedPlan {
    for (final p in _plans) {
      if (p.id == _d.planId) return p;
    }
    return null;
  }

  List<PlanSlot> get _slots => planSlotsFor(_batches, _d.planId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _phone,
      _email,
      _address,
      _city,
      _pincode,
      _emergencyName,
      _emergencyPhone,
      _registrationFee,
      _gst,
      _paymentAmount,
      _paymentRef,
      _receivedFrom,
      _collectedBy,
      _paymentNotes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final facility = ref.read(sessionControllerProvider).facility ?? await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadError = 'Complete your facility setup before adding members.';
          });
        }
        return;
      }
      final repo = ref.read(membershipRepositoryProvider);
      final plans = await repo.getFacilityPlans(facility.id, activeOnly: true);
      var batches = const <AssignableBatch>[];
      try {
        batches = await repo.listAssignableBatches(facility.id);
      } on AppException catch (_) {
        // Without slots the plan simply reserves no court time.
      }
      final rows = <MembershipListRow>[];
      try {
        for (var page = 1; page <= 10; page++) {
          final result = await repo.listMemberships(facility.id, MembershipListParams(page: page, perPage: 100));
          rows.addAll(result.rows);
          if (rows.length >= result.totalCount || result.rows.isEmpty) break;
        }
      } on AppException catch (_) {
        // Without the list the check is skipped; the database still gets the save.
      }
      if (!mounted) return;
      setState(() {
        _memberships = rows;
        _facilityId = facility.id;
        _plans = plans;
        _batches = batches;
        _loading = false;
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.message;
        });
      }
    }
  }

  // ── navigation ─────────────────────────────────────────────────────────

  /// The membership that already puts this person (same phone) on the chosen plan, if any.
  MembershipListRow? get _duplicateMember {
    final plan = _selectedPlan;
    if (plan == null || _d.phone.trim().isEmpty) return null;
    return findDuplicateMember(_memberships, plan, addMemberComposePhone(_d.countryCode, _d.phone));
  }

  Map<String, String> get _errors {
    final errors = addMemberFieldErrors(_step, _d);
    if (_step == 1 && _duplicateMember != null) errors['planId'] = duplicateMemberMessage;
    return errors;
  }
  String? _show(String field) => _touched.contains(field) ? _errors[field] : null;

  void _syncText() {
    _d
      ..fullName = _fullName.text
      ..phone = _phone.text
      ..email = _email.text
      ..address = _address.text
      ..city = _city.text
      ..pincode = _pincode.text
      ..emergencyName = _emergencyName.text
      ..emergencyPhone = _emergencyPhone.text
      ..paymentReference = _paymentRef.text
      ..receivedFrom = _receivedFrom.text
      ..collectedBy = _collectedBy.text
      ..paymentNotes = _paymentNotes.text;
    _d.registrationFeeInr = int.tryParse(_registrationFee.text.trim()) ?? 0;
    final gst = double.tryParse(_gst.text.trim()) ?? 0;
    _d.gstPercent = gst > 28 ? 28 : gst;
    _d.paymentAmount = int.tryParse(_paymentAmount.text.trim()) ?? 0;
  }

  void _next() {
    _syncText();
    final errors = _errors;
    if (errors.isNotEmpty) {
      setState(() => _touched.addAll(errors.keys));
      return;
    }
    setState(() {
      _touched.clear();
      _step = (_step + 1).clamp(0, addMemberLastStep);
      if (_step == addMemberLastStep) _enterPayment();
    });
  }

  /// "Amount to Collect" follows the plan's total until edited; "Received From" defaults to the
  /// member's own name the first time Payment is reached; a recurring plan can only use the link.
  void _enterPayment() {
    final total = addMemberCharges(_d).total;
    if (_d.paymentAmount == 0 && total > 0) {
      _d.paymentAmount = total;
      _paymentAmount.text = '$total';
    }
    if (!_receivedFromSeeded) {
      _receivedFromSeeded = true;
      if (_receivedFrom.text.isEmpty) {
        _receivedFrom.text = _fullName.text.trim();
        _d.receivedFrom = _receivedFrom.text;
      }
    }
    if (_planIsRecurring) _d.paymentTab = AddMemberPaymentTab.link;
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _touched.clear();
      _step -= 1;
    });
  }

  void _goTo(int step) {
    if (_locked) return;
    _syncText();
    if (step > _step && step > addMemberFurthestStep(_d)) return;
    setState(() {
      _touched.clear();
      _step = step;
      if (_step == addMemberLastStep) _enterPayment();
    });
  }

  void _choosePlan(MembershipPlan plan) {
    setState(() {
      _d
        ..planId = plan.id
        ..planName = plan.name
        ..durationDays = plan.durationDays
        ..membershipFeeInr = plan.priceInr;
      // The plan's own joining fee is a starting point for the registration fee, still editable.
      final joining = plan.joiningFeeInr;
      if (joining != null) {
        _d.registrationFeeInr = joining;
        _registrationFee.text = joining == 0 ? '' : '$joining';
      }
      // The amount to collect follows the plan again until it is edited by hand.
      _d.paymentAmount = 0;
      _paymentAmount.clear();
      _touched.remove('planId');
    });
  }

  DateTime? get _endDate =>
      _d.durationDays > 0 ? DateTime(_d.startDate.year, _d.startDate.month, _d.startDate.day + _d.durationDays - 1) : null;

  // ── saving ─────────────────────────────────────────────────────────────

  /// Creates the membership — shared by the three Payment tabs. The plan's first slot rides along
  /// with the membership itself; any further ones are joined afterwards.
  Future<Membership> _createTheMember({required MembershipPaymentMode mode, required List<String> methods, required bool recurring}) async {
    final facilityId = _facilityId!;
    final slots = _slots;
    final repo = ref.read(membershipRepositoryProvider);
    final charges = addMemberCharges(_d);
    final membership = await repo.createMembershipFull(
      CreateMembershipFullInput(
        facilityId: facilityId,
        fullName: _d.fullName.trim(),
        phone: addMemberComposePhone(_d.countryCode, _d.phone),
        email: _d.email.trim().isEmpty ? null : _d.email.trim(),
        dateOfBirth: _d.dateOfBirth == null ? null : _isoDate(_d.dateOfBirth!),
        gender: _d.gender.isEmpty ? null : _d.gender,
        address: addMemberComposeAddress(_d),
        name: _d.planName.isEmpty ? null : _d.planName,
        membershipType: MembershipType.individual,
        maxFamilyMembers: 1,
        startDate: _d.startDate,
        durationDays: _d.durationDays,
        batchId: slots.isEmpty ? null : slots.first.batchId,
        membershipFeeInr: _d.paymentAmount > 0 ? _d.paymentAmount : charges.subTotal,
        registrationFeeInr: charges.registration,
        gstPercent: _d.gstPercent,
        paymentMode: mode,
        paymentMethods: methods,
        paymentReference: _d.paymentReference.trim().isEmpty ? null : _d.paymentReference.trim(),
        recurring: recurring,
        notes: addMemberNotes(_d),
      ),
    );
    for (final slot in slots.skip(1)) {
      await ref.read(membershipSessionRepositoryProvider).assignBatchMember(slot.batchId, membership.memberId, membershipId: membership.id);
    }
    return membership;
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// "Create Member" (Record Offline Payment) / "Mark as Paid & Cancel Link".
  Future<void> _submit() async {
    if (_saving || _facilityId == null) return;
    _syncText();
    final errors = _errors;
    if (errors.isNotEmpty) {
      setState(() => _touched.addAll(errors.keys));
      return;
    }
    if (_duplicateMember != null) {
      setState(() => _error = duplicateMemberMessage);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(membershipRepositoryProvider);
      final link = _link;
      if (link != null) {
        // The member and their mandate already exist: mark that membership paid and cancel the
        // now-unwanted mandate — never create a second member.
        await repo.recordMembershipPayment(link.membershipId, method: _d.paymentMethod);
        await repo.cancelMembershipSubscription(link.membershipId);
      } else {
        await _createTheMember(mode: MembershipPaymentMode.paid, methods: [_d.paymentMethod], recurring: false);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('Add member failed: $e\n$st');
      if (mounted) setState(() => _error = 'Unable to create this member.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "Generate Payment Link" — the member is created right away (payment incomplete) together with
  /// the Razorpay mandate; the same amount then auto-collects every cycle.
  Future<void> _generateLink() async {
    if (_saving || _facilityId == null) return;
    _syncText();
    final errors = _errors;
    if (errors.isNotEmpty) {
      setState(() => _touched.addAll(errors.keys));
      return;
    }
    if (_duplicateMember != null) {
      setState(() => _error = duplicateMemberMessage);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final membership = await _createTheMember(mode: MembershipPaymentMode.pending, methods: const [], recurring: true);
      // The member exists from here on; lock the earlier steps even if the link itself fails.
      setState(() => _link = (membershipId: membership.id, shortUrl: null));
      final sub = await ref.read(membershipRepositoryProvider).createMembershipSubscription(membership.id);
      if (mounted) setState(() => _link = (membershipId: membership.id, shortUrl: sub.shortUrl));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('Generate payment link failed: $e\n$st');
      if (mounted) setState(() => _error = 'Unable to generate the payment link.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Add New Member')), body: const Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add New Member')),
        body: Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(_loadError!, textAlign: TextAlign.center))),
      );
    }
    final last = _step == addMemberLastStep;
    final linkTab = _d.paymentTab == AddMemberPaymentTab.link;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Add New Member')),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            decoration: BoxDecoration(color: tokens.surface0, border: Border(top: BorderSide(color: tokens.borderColor))),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || (_locked && last) ? null : _back,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(_step == 0 ? 'Cancel' : 'Back'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: _primaryAction(last, linkTab)),
              ],
            ),
          ),
        ),
        body: ListView(
          // One list per step, so each opens at its top.
          key: ValueKey(_step),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _Stepper(current: _step, furthest: addMemberFurthestStep(_d), locked: _locked, onSelect: _goTo),
            const SizedBox(height: AppSpacing.lg),
            _heading(addMemberSteps[_step].title, addMemberSteps[_step].hint),
            if (_step == 0) ..._stepPersonal(),
            if (_step == 1) ..._stepPlan(),
            if (_step == 2) ..._stepReview(),
            if (_step == 3) ..._stepPayment(),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: Text(_error!, style: TextStyle(color: tokens.destructive, fontSize: 13))),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _primaryAction(bool last, bool linkTab) {
    Widget spinner() => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
    if (!last) {
      return FilledButton(
        onPressed: _saving ? null : _next,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text('Next: ${addMemberSteps[_step + 1].title}', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      );
    }
    if (linkTab) {
      // Generating the link is what creates the member; this button only offers the way out after.
      if (_link?.shortUrl != null) {
        return FilledButton.icon(onPressed: () => Navigator.of(context).pop(true), icon: const Icon(Icons.check, size: 18), label: const Text('Done'));
      }
      return FilledButton.icon(
        onPressed: _saving ? null : _generateLink,
        icon: _saving ? spinner() : const Icon(Icons.link, size: 18),
        label: Text(_saving ? 'Generating…' : (_link != null ? 'Retry link' : 'Generate Payment Link')),
      );
    }
    return FilledButton.icon(
      onPressed: _saving ? null : _submit,
      icon: _saving ? spinner() : const Icon(Icons.check, size: 18),
      label: Text(_saving ? 'Saving…' : (_locked ? 'Mark as Paid & Cancel Link' : 'Create Member')),
    );
  }

  // ── shared bits ────────────────────────────────────────────────────────

  Widget _heading(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle, style: AppTypography.secondary(context)),
          const SizedBox(height: AppSpacing.md),
        ],
      );

  Widget _gap([double h = AppSpacing.md]) => SizedBox(height: h);

  Widget _banner(String text, {IconData icon = Icons.info_outline, Color? color}) {
    final tokens = context.tokens;
    final c = color ?? tokens.electricBlue;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController c,
    String label, {
    String? field,
    String? hint,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int? maxLength,
    int maxLines = 1,
    String? prefix,
    bool enabled = true,
  }) {
    return TextField(
      controller: c,
      enabled: enabled && !_locked,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLength: maxLength,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        counterText: '',
        errorText: field == null ? null : _show(field),
      ),
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick, {DateTime? first, DateTime? last, String? error, bool enabled = true}) {
    return TextField(
      readOnly: true,
      enabled: enabled && !_locked,
      controller: TextEditingController(text: value == null ? '' : Formatters.dateShort(value)),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: first ?? DateTime(now.year - 5),
          lastDate: last ?? DateTime(now.year + 5),
        );
        if (picked != null) setState(() => onPick(picked));
      },
      decoration: InputDecoration(labelText: label, hintText: 'Select date', suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18), errorText: error),
    );
  }

  Widget _phoneRow({
    required String code,
    required ValueChanged<String> onCode,
    required TextEditingController controller,
    required String label,
    required String field,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: AppDropdown<String>(
            initialValue: code,
            decoration: const InputDecoration(labelText: 'Code'),
            items: [for (final c in addMemberCountryCodes) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: _locked ? null : (v) => setState(() => onCode(v ?? code)),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _textField(
            controller,
            label,
            field: field,
            keyboard: TextInputType.phone,
            formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(code == '+91' ? 10 : 14)],
          ),
        ),
      ],
    );
  }

  // ── step 1: personal information ───────────────────────────────────────

  List<Widget> _stepPersonal() {
    return [
      _textField(_fullName, 'Full Name *', field: 'fullName', hint: "Member's name"),
      _gap(),
      _phoneRow(code: _d.countryCode, onCode: (v) => _d.countryCode = v, controller: _phone, label: 'Phone Number *', field: 'phone'),
      _gap(),
      _textField(_email, 'Email', field: 'email', hint: 'name@example.com', keyboard: TextInputType.emailAddress),
      _gap(),
      _dateField('Date of Birth', _d.dateOfBirth, (v) => _d.dateOfBirth = v, last: DateTime.now(), first: DateTime(1900), error: _show('dateOfBirth')),
      _gap(),
      AppDropdown<String>(
        initialValue: _d.gender,
        decoration: const InputDecoration(labelText: 'Gender'),
        items: [for (final g in addMemberGenders) DropdownMenuItem(value: g.value, child: Text(g.label))],
        onChanged: _locked ? null : (v) => setState(() => _d.gender = v ?? ''),
      ),
      _gap(),
      _textField(_address, 'Address', hint: 'Optional'),
      _gap(),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _textField(_city, 'City', field: 'city', hint: 'Optional')),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _textField(
              _pincode,
              'Pincode',
              field: 'pincode',
              hint: '600040',
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            ),
          ),
        ],
      ),
      _gap(AppSpacing.lg),
      Text('Emergency Contact (Optional)', style: AppTypography.rowTitle(context)),
      _gap(AppSpacing.sm),
      _textField(_emergencyName, 'Name', field: 'emergencyName', hint: "Contact's name"),
      _gap(),
      _phoneRow(
        code: _d.emergencyCountryCode,
        onCode: (v) => _d.emergencyCountryCode = v,
        controller: _emergencyPhone,
        label: 'Phone Number',
        field: 'emergencyPhone',
      ),
      _gap(AppSpacing.lg),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _d.sendWelcome,
        onChanged: _locked ? null : (v) => setState(() => _d.sendWelcome = v ?? true),
        title: const Text('Send welcome message to member', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text('Member will receive an SMS/Email with membership details.', style: AppTypography.caption(context)),
      ),
    ];
  }

  // ── step 2: select plan ────────────────────────────────────────────────

  List<Widget> _stepPlan() {
    final tokens = context.tokens;
    final themes = _planThemes(tokens);
    final plan = _selectedPlan;
    return [
      if (_plans.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(child: Text('No active plans yet. Create a plan first.', style: AppTypography.secondary(context))),
        )
      else
        for (var i = 0; i < _plans.length; i++) ...[
          _planCard(_plans[i], themes[i % themes.length], chosen: _plans[i].id == _d.planId),
          _gap(AppSpacing.sm),
        ],
      if (_show('planId') != null) Text(_show('planId')!, style: TextStyle(color: tokens.destructive, fontSize: 12)),
      _gap(),
      _dateField(
        'Plan Start Date *',
        _d.startDate,
        (v) => _d.startDate = v,
        first: DateTime(DateTime.now().year - 1),
      ),
      _gap(),
      InputDecorator(
        decoration: const InputDecoration(labelText: 'Plan End Date'),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 16),
            const SizedBox(width: 8),
            Text(_endDate == null ? '—' : Formatters.dateShort(_endDate!)),
          ],
        ),
      ),
      if (plan != null) ...[
        _gap(AppSpacing.lg),
        Text('Court & Timing', style: AppTypography.rowTitle(context)),
        const SizedBox(height: 2),
        Text('Set by this plan — the member plays on these courts and timings. To change them, edit the plan.', style: AppTypography.caption(context)),
        _gap(AppSpacing.sm),
        _slotsList(_slots),
      ],
      _gap(),
      _banner('The membership will be active from the selected start date.'),
      _gap(),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _textField(
              _registrationFee,
              'Registration Fee (₹)',
              field: 'registrationFeeInr',
              hint: '0',
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _textField(
              _gst,
              'GST (%)',
              field: 'gstPercent',
              hint: '0',
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
            ),
          ),
        ],
      ),
    ];
  }

  /// The four card palettes the web's plan list cycles through: green, blue, amber, purple.
  List<({Color surface, Color accent})> _planThemes(AppColorTokens tokens) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color surf(Color base, Color light) => dark ? base.withValues(alpha: 0.10) : light;
    return [
      (surface: surf(tokens.success, const Color(0xFFEFFBF4)), accent: tokens.success),
      (surface: surf(tokens.electricBlue, const Color(0xFFEFF5FE)), accent: tokens.electricBlue),
      (surface: surf(tokens.warning, const Color(0xFFFFF8EC)), accent: tokens.warning),
      (surface: surf(tokens.violet, const Color(0xFFF7F2FE)), accent: tokens.violet),
    ];
  }

  Widget _planCard(MembershipPlan plan, ({Color surface, Color accent}) theme, {required bool chosen}) {
    final tokens = context.tokens;
    final name = splitPlanName(plan.name);
    final perMonth = planMonthlyEquivalentInr(plan.priceInr, plan.durationDays);
    final features = addMemberPlanFeatures(plan, planBillingIntervalLabel(plan.durationDays));
    final badge = plan.badgeText?.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      onTap: _locked ? null : () => _choosePlan(plan),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: chosen ? tokens.primary : tokens.borderColor, width: chosen ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: theme.accent.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(planIcon(plan), color: theme.accent),
                ),
                const Spacer(),
                if (badge != null && badge.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: theme.accent.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(999)),
                    child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.accent)),
                  ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: chosen ? tokens.primary : tokens.surface0,
                    border: Border.all(color: chosen ? tokens.primary : tokens.borderColor, width: 2),
                  ),
                  child: chosen ? Icon(Icons.check, size: 14, color: tokens.onPrimary) : null,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(name.main, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (name.detail != null) Text(name.detail!, style: AppTypography.caption(context)),
            Text('Valid for ${planDurationLabel(plan.durationDays)}', style: AppTypography.caption(context)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(Formatters.currencyInr(plan.priceInr), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text(planPeriodLabel(plan.durationDays), style: AppTypography.caption(context)),
              ],
            ),
            if (perMonth != null) Text('(${Formatters.currencyInr(perMonth)} / month)', style: AppTypography.caption(context)),
            const SizedBox(height: AppSpacing.sm),
            for (final f in features)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.accent),
                      child: const Icon(Icons.check, size: 9, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The plan's courts and timings, read-only.
  Widget _slotsList(List<PlanSlot> slots) {
    final tokens = context.tokens;
    if (slots.isEmpty) {
      return Text("This plan doesn't reserve any court time.", style: AppTypography.caption(context));
    }
    return Column(
      children: [
        for (final s in slots)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: tokens.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.place_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.courtName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.schedule, size: 16),
                  const SizedBox(width: 6),
                  Text('${Formatters.time12h(s.startTime)} - ${Formatters.time12h(s.endTime)}', style: const TextStyle(fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final day in const [1, 2, 3, 4, 5, 6, 0])
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: s.daysOfWeek.contains(day) ? tokens.primary : tokens.surface2,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          planDayAbbr[day],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: s.daysOfWeek.contains(day) ? tokens.onPrimary : tokens.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── step 3: review & confirm ───────────────────────────────────────────

  Widget _reviewSection(int n, String title, int? editStep, List<Widget> children) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: tokens.electricBlue.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.electricBlue)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                if (editStep != null && !_locked)
                  TextButton.icon(onPressed: () => _goTo(editStep), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: AppTypography.caption(context))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  String _genderLabel() => addMemberGenders.where((g) => g.value == _d.gender).map((g) => g.label).firstOrNull ?? '';

  List<Widget> _stepReview() {
    _syncText();
    final plan = _selectedPlan;
    final charges = addMemberCharges(_d);
    final emergency = [_d.emergencyName.trim(), if (_d.emergencyPhone.trim().isNotEmpty) '${_d.emergencyCountryCode} ${_d.emergencyPhone.trim()}']
        .where((p) => p.isNotEmpty)
        .join(' — ');
    return [
      _reviewSection(1, 'Member Details', 0, [
        _kv('Name', _d.fullName.trim()),
        _kv('Phone', '${_d.countryCode} ${_d.phone}'.trim()),
        if (_d.email.trim().isNotEmpty) _kv('Email', _d.email.trim()),
        if (_d.dateOfBirth != null) _kv('Date of Birth', Formatters.dateShort(_d.dateOfBirth!)),
        if (_genderLabel().isNotEmpty && _d.gender.isNotEmpty) _kv('Gender', _genderLabel()),
        if (addMemberComposeAddress(_d) != null) _kv('Address', addMemberComposeAddress(_d)!),
        if (emergency.isNotEmpty) _kv('Emergency', emergency),
      ]),
      _reviewSection(2, 'Membership Plan', 1, [
        _kv('Plan', plan == null ? _d.planName : splitPlanName(plan.name).main),
        _kv('Duration', planDurationLabel(_d.durationDays)),
        _kv('Start Date', Formatters.dateShort(_d.startDate)),
        if (_endDate != null) _kv('End Date', Formatters.dateShort(_endDate!)),
        _kv('Plan Fee', Formatters.currencyInr(charges.subTotal)),
      ]),
      _reviewSection(3, 'Court & Timing', 1, [
        _slotsList(_slots),
        if (_slots.isNotEmpty)
          _banner(
            'These time slots will be reserved for this member throughout the membership period. Guest bookings will not be allowed during these times.',
            icon: Icons.shield_outlined,
          ),
      ]),
      _reviewSection(4, 'Communication Preferences', null, [
        _kv('Welcome message', _d.sendWelcome ? 'Will be sent' : "Won't be sent"),
      ]),
      _reviewSection(5, 'Summary', null, [
        _kv('Membership fee', Formatters.currencyInr(charges.subTotal)),
        if (charges.gstAmount > 0) _kv('GST (${_d.gstPercent.toStringAsFixed(_d.gstPercent % 1 == 0 ? 0 : 1)}%)', Formatters.currencyInr(charges.gstAmount)),
        if (charges.registration > 0) _kv('Registration fee', Formatters.currencyInr(charges.registration)),
        _kv('Total Payable', Formatters.currencyInr(charges.total)),
      ]),
    ];
  }

  // ── step 4: payment ────────────────────────────────────────────────────

  List<Widget> _stepPayment() {
    final tokens = context.tokens;
    final tab = _d.paymentTab;
    final referenceRequired = _d.paymentMethod == 'UPI' || _d.paymentMethod == 'Bank Transfer';
    return [
      for (final t in AddMemberPaymentTab.values) ...[
        _paymentTabTile(t),
        _gap(AppSpacing.sm),
      ],
      _gap(),
      _textField(
        _paymentAmount,
        'Payment Amount *',
        field: 'paymentAmount',
        keyboard: TextInputType.number,
        formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
        prefix: '₹ ',
        enabled: !_locked,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('${_d.planName} (${planDurationLabel(_d.durationDays)})', style: AppTypography.caption(context)),
      ),
      _gap(),
      if (tab == AddMemberPaymentTab.link) ...[
        _banner(
          'A secure Razorpay payment link will be generated for this month, and the same amount will auto-collect on this day every month after — the member only has to approve it once. You can share this link via WhatsApp, SMS, or Email.',
        ),
        if (_link != null) ...[
          _gap(),
          _linkResult(tokens),
        ],
      ] else ...[
        if (tab == AddMemberPaymentTab.paid) ...[
          _banner('This will mark the payment as completed and you can create the member immediately.', icon: Icons.check_circle_outline, color: tokens.success),
          _gap(),
        ],
        _dateField('Payment Date *', _d.paymentDate, (v) => _d.paymentDate = v, enabled: !_locked),
        _gap(),
        Text('Payment Mode *', style: AppTypography.rowTitle(context)),
        _gap(AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final m in addMemberPaymentMethods)
              ChoiceChip(
                label: Text(m),
                selected: _d.paymentMethod == m,
                onSelected: (_) => setState(() => _d.paymentMethod = m),
              ),
          ],
        ),
        _gap(),
        _textField(
          _paymentRef,
          referenceRequired ? 'Reference / Transaction ID *' : 'Reference / Transaction ID (Optional)',
          field: 'paymentReference',
          hint: 'UTR, Receipt No.',
        ),
        _gap(),
        _textField(_receivedFrom, 'Received From *', field: 'receivedFrom'),
        _gap(),
        _textField(_collectedBy, 'Collected By *', field: 'collectedBy', hint: "Staff member's name"),
        _gap(),
        _textField(_paymentNotes, 'Notes (Optional)', hint: 'Add any additional notes...', maxLength: 500, maxLines: 2),
      ],
    ];
  }

  Widget _paymentTabTile(AddMemberPaymentTab t) {
    final tokens = context.tokens;
    final selected = _d.paymentTab == t;
    // A recurring plan must go through a verified subscription; and once a link exists, recording
    // a separate offline payment on top of a live mandate would double up.
    final disabled = (_planIsRecurring && t != AddMemberPaymentTab.link) || (_locked && t == AddMemberPaymentTab.offline);
    final icon = switch (t) {
      AddMemberPaymentTab.link => Icons.link,
      AddMemberPaymentTab.offline => Icons.credit_card,
      AddMemberPaymentTab.paid => Icons.fact_check_outlined,
    };
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: disabled || _saving ? null : () => setState(() => _d.paymentTab = t),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? tokens.primary.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: selected ? tokens.primary : tokens.borderColor, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? tokens.primary : tokens.electricBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: 19, color: selected ? tokens.onPrimary : tokens.electricBlue),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      _planIsRecurring && t != AddMemberPaymentTab.link ? 'Not available for a recurring plan' : t.subtitle,
                      style: AppTypography.caption(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkResult(AppColorTokens tokens) {
    final url = _link?.shortUrl;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.check_circle, size: 18, color: tokens.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                url == null ? 'Member created — the payment link could not be generated' : 'Member created — payment link ready',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tokens.success),
              ),
            ),
          ]),
          if (url != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SelectableText(url, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy link'),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The member is already created (Payment Incomplete) — share this link and their status updates once they pay.',
            style: AppTypography.caption(context),
          ),
        ],
      ),
    );
  }
}

/// The four circles across the top: filled for the current step, ticked once done, and only the
/// steps already unlocked can be tapped.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.current, required this.furthest, required this.locked, required this.onSelect});

  final int current;
  final int furthest;
  final bool locked;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < addMemberSteps.length; i++)
          Expanded(
            child: InkWell(
              onTap: !locked && (i <= furthest || i <= current) ? () => onSelect(i) : null,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : (i <= current ? tokens.primary : tokens.borderColor))),
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == current
                              ? tokens.primary
                              : i < current
                                  ? tokens.primary.withValues(alpha: 0.18)
                                  : tokens.surface2,
                        ),
                        child: i < current
                            ? Icon(Icons.check, size: 16, color: tokens.primary)
                            : Text('${i + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: i == current ? tokens.onPrimary : tokens.textSecondary,
                                )),
                      ),
                      Expanded(
                          child: Container(
                              height: 2,
                              color: i == addMemberSteps.length - 1 ? Colors.transparent : (i < current ? tokens.primary : tokens.borderColor))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    addMemberSteps[i].label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                      color: i == current ? tokens.primary : tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
