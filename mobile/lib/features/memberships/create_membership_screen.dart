import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/booking.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import 'membership_charges.dart';
import 'membership_status.dart';

/// The full Create Membership page — mirrors
/// src/features/memberships/components/create-membership-page.tsx: a
/// self-contained membership (its own name / type / duration / fee / GST /
/// time slot) written through the `create_membership_full` RPC, not a plan
/// assignment. Pops `true` when a membership was created so the list can
/// refresh.
class CreateMembershipScreen extends ConsumerStatefulWidget {
  const CreateMembershipScreen({super.key, this.membershipId});

  /// When set, the screen edits this membership instead of creating one:
  /// every field is prefilled, the Payment Mode section is hidden, and Save
  /// calls `update_membership_full` (no payment side-effects).
  final String? membershipId;

  @override
  ConsumerState<CreateMembershipScreen> createState() => _CreateMembershipScreenState();
}

const _durations = <({String label, int days})>[
  (label: '1 Month', days: 30),
  (label: '3 Months', days: 90),
  (label: '6 Months', days: 180),
  (label: '1 Year', days: 365),
];
const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];
const _paymentMethods = ['Cash', 'UPI', 'Card', 'Bank Transfer', 'Other'];
const _discoverySources = [
  'Walk-in',
  'Referral',
  'Social Media',
  'Google Search',
  'Advertisement',
  'Friend / Family',
  'Other',
];

class _CreateMembershipScreenState extends ConsumerState<CreateMembershipScreen> {
  bool get _isEdit => widget.membershipId != null;
  String? _facilityId;
  bool _loading = true;
  String? _loadError;

  // Member
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  DateTime? _dob;
  String? _gender;

  // Membership
  List<MembershipPlan> _plans = [];
  String? _planId;
  final _name = TextEditingController();
  final _description = TextEditingController();
  MembershipType _type = MembershipType.individual;
  DateTime _startDate = DateTime.now();
  int _durationDays = 0;
  int _maxFamily = 1;
  TimeOfDay? _slotStart;
  TimeOfDay? _slotEnd;

  // Charges
  final _fee = TextEditingController();
  final _regFee = TextEditingController();
  final _gst = TextEditingController();

  // Payment
  MembershipPaymentMode _mode = MembershipPaymentMode.paid;
  final Set<String> _methods = {'Cash', 'UPI'};
  final _paymentRef = TextEditingController();
  bool _recurring = false;

  // Extras
  final _referralQuery = TextEditingController();
  List<MemberSearchResult> _referralResults = [];
  MemberSearchResult? _referral;
  Timer? _referralDebounce;
  String? _discovery;
  final _notes = TextEditingController();

  bool _saving = false;
  String? _error;
  String? _mandateUrl; // non-null (possibly empty) once the success panel shows

  @override
  void initState() {
    super.initState();
    _fee.addListener(_onChargesChanged);
    _regFee.addListener(_onChargesChanged);
    _gst.addListener(_onChargesChanged);
    _referralQuery.addListener(_onReferralQueryChanged);
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _phone,
      _email,
      _address,
      _name,
      _description,
      _fee,
      _regFee,
      _gst,
      _paymentRef,
      _referralQuery,
      _notes,
    ]) {
      c.dispose();
    }
    _referralDebounce?.cancel();
    super.dispose();
  }

  void _onChargesChanged() => setState(() {});

  void _applyPlan(String? id) {
    setState(() {
      _planId = (id == null || id.isEmpty) ? null : id;
      MembershipPlan? plan;
      for (final p in _plans) {
        if (p.id == _planId) plan = p;
      }
      if (plan != null) {
        _name.text = plan.name;
        _durationDays = plan.durationDays;
        _fee.text = plan.priceInr.toString();
      }
    });
  }

  Future<void> _load() async {
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (!mounted) return;
      setState(() {
        _facilityId = facility?.id;
        _loading = false;
        _loadError = facility == null ? 'Complete your facility setup before creating a membership.' : null;
      });
      if (facility != null) {
        final plans = await ref.read(membershipRepositoryProvider).getFacilityPlans(facility.id, activeOnly: true);
        if (mounted) setState(() => _plans = plans);
      }
      if (widget.membershipId != null) {
        final d = await ref.read(membershipRepositoryProvider).getMembershipDetail(widget.membershipId!);
        if (!mounted) return;
        setState(() {
          _fullName.text = d.member.fullName;
          _phone.text = d.member.phone;
          _email.text = d.member.email ?? '';
          _address.text = d.member.address ?? '';
          _dob = d.member.dateOfBirth == null ? null : DateTime.tryParse(d.member.dateOfBirth!);
          _gender = _genders.contains(d.member.gender) ? d.member.gender : null;
          _name.text = d.membership.name;
          _type = membershipTypeFromDb(d.membership.membershipType);
          _startDate = d.membership.startDate;
          _durationDays = d.membership.durationDays ?? 0;
          _maxFamily = d.membership.maxFamilyMembers < 1 ? 1 : d.membership.maxFamilyMembers;
          _description.text = d.membership.description ?? '';
          _fee.text = d.membership.membershipFeeInr == 0 ? '' : d.membership.membershipFeeInr.toString();
          _regFee.text = d.membership.registrationFeeInr == 0 ? '' : d.membership.registrationFeeInr.toString();
          _gst.text = d.membership.gstPercent == 0 ? '' : d.membership.gstPercent.toString();
          if (d.referralMemberId != null && d.referralName != null) {
            _referral = MemberSearchResult(id: d.referralMemberId!, fullName: d.referralName!, phone: '');
          }
          _discovery = _discoverySources.contains(d.discoverySource) ? d.discoverySource : null;
          _notes.text = d.notes ?? '';
        });
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  void _onReferralQueryChanged() {
    final q = _referralQuery.text.trim();
    _referralDebounce?.cancel();
    if (q.length < 2 || _facilityId == null || _referral != null) {
      if (_referralResults.isNotEmpty) {
        setState(() => _referralResults = []);
      }
      return;
    }
    _referralDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await ref.read(membershipRepositoryProvider).searchMembers(_facilityId!, q);
        if (mounted) setState(() => _referralResults = results);
      } on AppException catch (_) {
        // Referral search is optional — a failure here just shows no matches.
      }
    });
  }

  MembershipCharges get _charges => computeMembershipCharges(
        feeInr: num.tryParse(_fee.text.trim()),
        gstPercent: num.tryParse(_gst.text.trim()),
        registrationInr: num.tryParse(_regFee.text.trim()),
      );

  DateTime? get _endDate => _durationDays > 0 ? computeMembershipEndDate(_startDate, _durationDays) : null;

  String? _time24(TimeOfDay? t) =>
      t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_facilityId == null) return;
    final nameError = Validators.name(_fullName.text);
    if (nameError != null) return setState(() => _error = nameError);
    final phoneError = Validators.phone(_phone.text);
    if (phoneError != null) return setState(() => _error = phoneError);
    if (_email.text.trim().isNotEmpty) {
      final emailError = Validators.email(_email.text);
      if (emailError != null) return setState(() => _error = emailError);
    }
    if (_durationDays <= 0) return setState(() => _error = 'Select a membership duration.');
    if (!_isEdit && _mode != MembershipPaymentMode.free && _charges.subTotal <= 0) {
      return setState(() => _error = 'Enter a membership fee.');
    }

    if (_isEdit) {
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        await ref.read(membershipRepositoryProvider).updateMembershipFull(
              widget.membershipId!,
              fullName: _fullName.text.trim(),
              phone: _phone.text.trim(),
              email: _email.text.trim().isEmpty ? null : _email.text.trim(),
              dateOfBirth: _dob == null ? null : _dateOnly(_dob!),
              gender: _gender,
              address: _address.text.trim().isEmpty ? null : _address.text.trim(),
              name: _name.text.trim().isEmpty ? null : _name.text.trim(),
              membershipType: _type,
              maxFamilyMembers: _type == MembershipType.family ? _maxFamily : 1,
              startDate: _startDate,
              durationDays: _durationDays,
              description: _description.text.trim().isEmpty ? null : _description.text.trim(),
              membershipFeeInr: _charges.subTotal,
              registrationFeeInr: _charges.registration,
              gstPercent: num.tryParse(_gst.text.trim())?.toDouble().clamp(0, double.infinity) ?? 0,
              referralMemberId: _referral?.id,
              discoverySource: _discovery,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            );
        if (mounted) Navigator.of(context).pop(true);
      } on AppException catch (e) {
        if (mounted) setState(() => _error = e.message);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    final start = _time24(_slotStart);
    final end = _time24(_slotEnd);
    if (start != null && end != null && end.compareTo(start) <= 0) {
      return setState(() => _error = 'Time slot end must be after the start.');
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(membershipRepositoryProvider);
      final membership = await repo.createMembershipFull(
        CreateMembershipFullInput(
          facilityId: _facilityId!,
          fullName: _fullName.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          dateOfBirth: _dob == null ? null : _dateOnly(_dob!),
          gender: _gender,
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          name: _name.text.trim().isEmpty ? null : _name.text.trim(),
          membershipType: _type,
          maxFamilyMembers: _type == MembershipType.family ? _maxFamily : 1,
          startDate: _startDate,
          durationDays: _durationDays,
          timeSlotStart: start,
          timeSlotEnd: end,
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          membershipFeeInr: _charges.subTotal,
          registrationFeeInr: _charges.registration,
          gstPercent: num.tryParse(_gst.text.trim())?.toDouble().clamp(0, double.infinity) ?? 0,
          paymentMode: _mode,
          paymentMethods: _mode == MembershipPaymentMode.free ? const [] : _methods.toList(),
          paymentReference: _paymentRef.text.trim().isEmpty ? null : _paymentRef.text.trim(),
          recurring: _recurring,
          referralMemberId: _referral?.id,
          discoverySource: _discovery,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ),
      );

      if (_recurring && _mode != MembershipPaymentMode.free && _charges.total > 0) {
        try {
          final sub = await repo.createMembershipSubscription(membership.id);
          if (mounted) setState(() => _mandateUrl = sub.shortUrl ?? '');
        } on AppException catch (_) {
          if (mounted) setState(() => _mandateUrl = '');
        }
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Membership' : 'Create Membership')),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : _mandateUrl != null
                    ? _MandateSuccessPanel(
                        shortUrl: _mandateUrl!.isEmpty ? null : _mandateUrl!,
                        onDone: () => Navigator.of(context).pop(true),
                      )
                    : _form(context),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final tokens = context.tokens;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(_isEdit ? "Update this member's details" : 'Register a new member', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary)),
        const SizedBox(height: AppSpacing.lg),

        // ── 1 · Member Information ──────────────────────────────────────
        _Section(
          n: 1,
          title: 'Member Information',
          children: [
            _labeled('Full Name', required: true, child: TextField(controller: _fullName, decoration: const InputDecoration(hintText: 'Enter full name'))),
            _labeled(
              'Phone Number',
              required: true,
              child: Row(
                children: [
                  Container(
                    height: 48,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: tokens.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tokens.borderColor),
                    ),
                    child: Text('+91', style: TextStyle(color: tokens.textSecondary)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(hintText: 'Enter phone number'),
                    ),
                  ),
                ],
              ),
            ),
            _labeled('Email Address', child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'Enter email address'))),
            _labeled(
              'Date of Birth',
              child: _PickerField(
                text: _dob == null ? 'Select date' : Formatters.dateShort(_dob!),
                placeholder: _dob == null,
                icon: Icons.calendar_today_outlined,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dob ?? DateTime(DateTime.now().year - 20),
                    firstDate: DateTime(1920),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _dob = picked);
                },
              ),
            ),
            _labeled(
              'Gender',
              child: _Dropdown<String>(
                value: _gender,
                hint: 'Select gender',
                items: _genders,
                labelOf: (g) => g,
                onChanged: (g) => setState(() => _gender = g),
              ),
            ),
            _labeled('Address', child: TextField(controller: _address, decoration: const InputDecoration(hintText: 'Enter complete address'))),
          ],
        ),

        // ── 2 · Membership Details ─────────────────────────────────────
        _Section(
          n: 2,
          title: 'Membership Details',
          children: [
            if (_plans.isNotEmpty)
              _labeled(
                'Plan',
                hint: _planId != null
                    ? 'Fee and duration are set by the plan'
                    : 'Or leave as Custom and enter the fee below',
                child: DropdownButtonFormField<String>(
                  initialValue: _planId ?? '',
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Custom (no plan)')),
                    ..._plans.map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${p.name} — ${Formatters.currencyInr(p.priceInr)} · ${p.durationDays} days',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: _applyPlan,
                ),
              ),
            _labeled('Membership Name', required: true, hint: 'e.g., Premium Membership', child: TextField(controller: _name, decoration: const InputDecoration(hintText: 'Enter membership name'))),
            _labeled(
              'Membership Type',
              required: true,
              child: Wrap(
                spacing: AppSpacing.sm,
                children: MembershipType.values
                    .map((t) => ChoiceChip(
                          label: Text(membershipTypeLabel(t)),
                          selected: _type == t,
                          onSelected: (_) => setState(() => _type = t),
                        ))
                    .toList(),
              ),
            ),
            _labeled(
              'Start Date',
              required: true,
              child: _PickerField(
                text: Formatters.dateShort(_startDate),
                icon: Icons.calendar_today_outlined,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _startDate = picked);
                },
              ),
            ),
            _labeled(
              'Duration',
              required: true,
              hint: _planId != null
                  ? 'Set by the plan'
                  : _endDate == null
                      ? 'e.g., 3 Months, 6 Months, 1 Year'
                      : 'Ends ${Formatters.dateShort(_endDate!)}',
              child: _planId != null
                  ? InputDecorator(
                      decoration: const InputDecoration(enabled: false),
                      child: Text(
                        _durationDays > 0 ? '$_durationDays days' : '—',
                        style: TextStyle(color: context.tokens.textSecondary),
                      ),
                    )
                  : _Dropdown<int>(
                      value: _durationDays == 0 ? null : _durationDays,
                      hint: 'Select duration',
                      items: _durations.map((d) => d.days).toList(),
                      labelOf: (days) {
                        for (final d in _durations) {
                          if (d.days == days) return d.label;
                        }
                        return '$days days';
                      },
                      onChanged: (d) => setState(() => _durationDays = d ?? 0),
                    ),
            ),
            if (!_isEdit)
            _labeled(
              'Time Slot',
              hint: 'The hour the member plays each visit',
              child: Row(
                children: [
                  Expanded(
                    child: _PickerField(
                      text: _slotStart == null ? 'Start' : _slotStart!.format(context),
                      placeholder: _slotStart == null,
                      icon: Icons.schedule,
                      onTap: () async {
                        final picked = await showTimePicker(context: context, initialTime: _slotStart ?? const TimeOfDay(hour: 6, minute: 0));
                        if (picked != null) setState(() => _slotStart = picked);
                      },
                    ),
                  ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm), child: Text('to')),
                  Expanded(
                    child: _PickerField(
                      text: _slotEnd == null ? 'End' : _slotEnd!.format(context),
                      placeholder: _slotEnd == null,
                      icon: Icons.schedule,
                      onTap: () async {
                        final picked = await showTimePicker(context: context, initialTime: _slotEnd ?? const TimeOfDay(hour: 7, minute: 0));
                        if (picked != null) setState(() => _slotEnd = picked);
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_type == MembershipType.family)
              _labeled(
                'Max. Members (Family)',
                child: Row(
                  children: [
                    IconButton.outlined(onPressed: () => setState(() => _maxFamily = (_maxFamily - 1).clamp(1, 99)), icon: const Icon(Icons.remove)),
                    SizedBox(width: 40, child: Text('$_maxFamily', textAlign: TextAlign.center)),
                    IconButton.outlined(onPressed: () => setState(() => _maxFamily = (_maxFamily + 1).clamp(1, 99)), icon: const Icon(Icons.add)),
                  ],
                ),
              ),
            _labeled(
              'Description',
              child: TextField(
                controller: _description,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(hintText: 'Enter membership description and benefits…'),
              ),
            ),
          ],
        ),

        // ── 3 · Membership Charges ─────────────────────────────────────
        _Section(
          n: 3,
          title: 'Membership Charges',
          children: [
            _labeled(
              'Membership Fee',
              required: true,
              hint: _planId != null ? 'Set by the selected plan' : null,
              child: TextField(
                controller: _fee,
                enabled: _planId == null,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Enter amount', prefixText: '₹ '),
              ),
            ),
            _labeled('Registration Fee', hint: 'One-time, if applicable', child: TextField(controller: _regFee, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Enter amount', prefixText: '₹ '))),
            _labeled('GST (%)', hint: 'Applicable tax percentage', child: TextField(controller: _gst, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Enter GST percentage'))),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: tokens.surface2, borderRadius: BorderRadius.circular(8)),
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Sub Total ${Formatters.currencyInr(_charges.subTotal)}'),
                  const Text('+'),
                  Text('GST ${Formatters.currencyInr(_charges.gstAmount)}'),
                  const Text('+'),
                  Text('Registration ${Formatters.currencyInr(_charges.registration)}'),
                  const Text('='),
                  Text('Total ${Formatters.currencyInr(_charges.total)}', style: TextStyle(fontWeight: FontWeight.w700, color: tokens.success)),
                ],
              ),
            ),
          ],
        ),

        // ── 4 · Payment Mode (create only — payment is not edited here) ─
        if (!_isEdit)
        _Section(
          n: 4,
          title: 'Payment Mode',
          children: [
            ...[
              (MembershipPaymentMode.paid, 'Paid', 'Collect payment now'),
              (MembershipPaymentMode.pending, 'Pending', 'Collect payment later'),
              (MembershipPaymentMode.free, 'Free', 'No payment required'),
            ].map((m) {
              final selected = _mode == m.$1;
              return InkWell(
                onTap: () => setState(() => _mode = m.$1),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          size: 20, color: selected ? tokens.primary : tokens.textSecondary),
                      const SizedBox(width: AppSpacing.sm),
                      Text(m.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(m.$3, style: TextStyle(color: tokens.textSecondary, fontSize: 12))),
                    ],
                  ),
                ),
              );
            }),
            if (_mode != MembershipPaymentMode.free) ...[
              const SizedBox(height: AppSpacing.sm),
              _labeled(
                'Accepted Payment Methods',
                child: Wrap(
                  spacing: AppSpacing.sm,
                  children: _paymentMethods
                      .map((pm) => FilterChip(
                            label: Text(pm),
                            selected: _methods.contains(pm),
                            onSelected: (on) => setState(() => on ? _methods.add(pm) : _methods.remove(pm)),
                          ))
                      .toList(),
                ),
              ),
              _labeled('Payment Reference (Optional)', child: TextField(controller: _paymentRef, decoration: const InputDecoration(hintText: 'Enter transaction / reference number'))),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v ?? false),
                title: const Text('Recurring UPI AutoPay'),
                subtitle: const Text('Generates a Razorpay mandate link — the total is charged automatically each cycle.'),
              ),
            ],
          ],
        ),

        // ── 5 · Additional Information ────────────────────────────────
        _Section(
          n: 5,
          title: 'Additional Information',
          children: [
            _labeled(
              'Referral By',
              child: _referral != null
                  ? InputDecorator(
                      decoration: const InputDecoration(),
                      child: Row(
                        children: [
                          Expanded(child: Text(_referral!.fullName)),
                          TextButton(onPressed: () => setState(() => _referral = null), child: const Text('Change')),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(controller: _referralQuery, decoration: const InputDecoration(hintText: 'Select member (optional)')),
                        ..._referralResults.map((r) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(r.fullName),
                              trailing: Text(r.phone, style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
                              onTap: () => setState(() {
                                _referral = r;
                                _referralQuery.clear();
                                _referralResults = [];
                              }),
                            )),
                      ],
                    ),
            ),
            _labeled(
              'How did you find us?',
              child: _Dropdown<String>(
                value: _discovery,
                hint: 'Select an option',
                items: _discoverySources,
                labelOf: (d) => d,
                onChanged: (d) => setState(() => _discovery = d),
              ),
            ),
            _labeled('Notes', child: TextField(controller: _notes, maxLines: 2, maxLength: 200, decoration: const InputDecoration(hintText: 'Add any notes or special requests…'))),
          ],
        ),

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: const TextStyle(color: AppColors.destructive)),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: _isEdit ? 'Save Changes' : 'Create Membership',
          loadingLabel: _isEdit ? 'Saving…' : 'Creating…',
          isLoading: _saving,
          onPressed: _facilityId == null ? null : _submit,
        ),
        if (!_isEdit) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text('Secure registration · You can edit details later', style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _labeled(String label, {bool required = false, String? hint, required Widget child}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(
            text: label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.textSecondary),
            children: required ? const [TextSpan(text: ' *', style: TextStyle(color: AppColors.destructive))] : null,
          )),
          const SizedBox(height: AppSpacing.xs),
          child,
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint, style: TextStyle(fontSize: 11, color: tokens.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.n, required this.title, required this.children});

  final int n;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: tokens.primary.withValues(alpha: 0.15),
                  child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.primary)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.text, required this.onTap, this.icon, this.placeholder = false});

  final String text;
  final VoidCallback onTap;
  final IconData? icon;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(suffixIcon: icon == null ? null : Icon(icon, size: 18)),
        child: Text(text, style: TextStyle(color: placeholder ? tokens.textSecondary : tokens.textPrimary)),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.value, required this.hint, required this.items, required this.labelOf, required this.onChanged});

  final T? value;
  final String hint;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      hint: Text(hint),
      items: items.map((i) => DropdownMenuItem<T>(value: i, child: Text(labelOf(i)))).toList(),
      onChanged: onChanged,
    );
  }
}

class _MandateSuccessPanel extends StatelessWidget {
  const _MandateSuccessPanel({required this.shortUrl, required this.onDone});

  final String? shortUrl;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 48, color: tokens.success),
            const SizedBox(height: AppSpacing.md),
            Text('Membership created', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (shortUrl != null) ...[
              Text('Send this UPI AutoPay link to the member:', textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary)),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(color: tokens.surface2, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(shortUrl!, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Copy link',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: shortUrl!));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
                },
              ),
            ] else
              Text(
                'Recurring link could not be generated — you can retry from the list.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textSecondary),
              ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Back to Memberships', onPressed: onDone),
          ],
        ),
      ),
    );
  }
}