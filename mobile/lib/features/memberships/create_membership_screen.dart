import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/booking.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import 'access_days.dart';
import 'membership_charges.dart';
import 'membership_slot.dart';
import 'membership_slot_section.dart';
import 'membership_status.dart';
import '../../shared/widgets/app_dropdown.dart';

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
  String? _memberId; // edit mode — for delete
  bool _loading = true;
  bool _deleting = false;
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
  List<AssignableBatch> _batches = const [];
  String? _planId;
  final _name = TextEditingController();
  final _description = TextEditingController();
  MembershipType _type = MembershipType.individual;
  DateTime _startDate = DateTime.now();
  int _durationDays = 0;
  int _maxFamily = 1;

  /// The reserved court time slot (parity gap G3). Seeded from the membership's
  /// current batch in edit mode; day chips for a new slot seed from
  /// [_accessDays].
  MembershipSlotSelection _slot = const SlotNone();
  List<int> _accessDays = allDays;

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

  /// Edit mode: the form serialised right after prefill. "Save Changes" is
  /// enabled only while [_snapshot] differs from this.
  String? _initialSnapshot;

  @override
  void initState() {
    super.initState();
    for (final c in [_fullName, _phone, _email, _address, _name, _description, _fee, _regFee, _gst, _notes]) {
      c.addListener(_onChargesChanged);
    }
    _referralQuery.addListener(_onReferralQueryChanged);
    _load();
  }

  String _slotKey() => switch (_slot) {
        SlotNone() => 'none',
        SlotExisting(:final batchId) => 'batch:$batchId',
        SlotNew(:final draft) =>
          'new:${draft.courtId}:${(draft.daysOfWeek.toList()..sort()).join(',')}:${draft.startTime}:${draft.endTime}:${draft.capacity}',
      };

  String _snapshot() => [
        _fullName.text.trim(),
        _phone.text.trim(),
        _email.text.trim(),
        _address.text.trim(),
        _dob?.toIso8601String() ?? '',
        _gender ?? '',
        _name.text.trim(),
        _type.name,
        _startDate.toIso8601String(),
        _durationDays,
        _type == MembershipType.family ? _maxFamily : 1,
        _description.text.trim(),
        num.tryParse(_fee.text.trim()) ?? 0,
        num.tryParse(_regFee.text.trim()) ?? 0,
        num.tryParse(_gst.text.trim()) ?? 0,
        _slotKey(),
        _referral?.id ?? '',
        _discovery ?? '',
        _notes.text.trim(),
      ].join('|');

  bool get _dirty => !_isEdit || (_initialSnapshot != null && _snapshot() != _initialSnapshot);

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
      final facility = ref.read(sessionControllerProvider).facility ??
          await ref.read(facilityRepositoryProvider).getFacility();
      if (!mounted) return;
      setState(() {
        _facilityId = facility?.id;
        _accessDays = facility?.membershipAccessDays ?? allDays;
        _loading = false;
        _loadError = facility == null ? 'Complete your facility setup before creating a membership.' : null;
      });
      if (facility != null) {
        final repo = ref.read(membershipRepositoryProvider);
        final plans = await repo.getFacilityPlans(facility.id, activeOnly: true);
        if (mounted) setState(() => _plans = plans);
        try {
          final batches = await repo.listAssignableBatches(facility.id);
          if (mounted) setState(() => _batches = batches);
        } on AppException catch (_) {
          // Batch names are only used to label the success summary.
        }
      }
      if (widget.membershipId != null) {
        final d = await ref.read(membershipRepositoryProvider).getMembershipDetail(widget.membershipId!);
        if (!mounted) return;
        setState(() {
          _memberId = d.member.id;
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
          // The reserved court slot, so an edit re-sends it rather than the
          // RPC's "both null = clear the slot" branch stripping it.
          final batchId = d.slot?.batchId;
          _slot = batchId != null ? SlotExisting(batchId) : const SlotNone();
          // The membership is self-contained (no plan_id) — surface the plan
          // it was created from by matching on name, for display only.
          for (final p in _plans) {
            if (p.name.trim().toLowerCase() == d.membership.name.trim().toLowerCase()) {
              _planId = p.id;
              break;
            }
          }
          _initialSnapshot = _snapshot();
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

    final slotError = validateSlotSelection(_slot);
    if (slotError != null) return setState(() => _error = slotError);
    final slotArgs = slotRpcArgs(_slot);
    final batchId = slotArgs['p_batch_id'] as String?;
    final newBatch = slotArgs['p_new_batch'] as Map<String, dynamic>?;

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
              batchId: batchId,
              newBatch: newBatch,
            );
        if (mounted) await _showSummaryAndExit();
      } on AppException catch (e) {
        if (mounted) setState(() => _error = e.message);
      } catch (e, st) {
        debugPrint('Update membership failed after RPC: $e\n$st');
        if (mounted) {
          setState(() => _error = 'Something went wrong. Please try again.');
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
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
          batchId: batchId,
          newBatch: newBatch,
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
        String? url;
        var failed = false;
        try {
          final sub = await repo.createMembershipSubscription(membership.id);
          url = sub.shortUrl ?? '';
        } on AppException catch (_) {
          failed = true;
        }
        if (mounted) await _showSummaryAndExit(mandateUrl: url, mandateFailed: failed);
        return;
      }
      if (mounted) await _showSummaryAndExit();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('Create membership failed after RPC: $e\n$st');
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  AssignableBatch? _selectedBatch() {
    final s = _slot;
    if (s is! SlotExisting) return null;
    for (final b in _batches) {
      if (b.batchId == s.batchId) return b;
    }
    return null;
  }

  /// A compact bottom sheet summarising what was just created, then pops the
  /// screen so the members list refreshes.
  Future<void> _showSummaryAndExit({
    String? mandateUrl,
    bool mandateFailed = false,
  }) async {
    if (!mounted) return;
    setState(() => _saving = false);
    final charges = _charges;
    final batch = _selectedBatch();
    String? planName;
    for (final p in _plans) {
      if (p.id == _planId) planName = p.name;
    }
    final membershipName = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : (planName ?? 'Membership');
    final amountPaid = !_isEdit && _mode == MembershipPaymentMode.paid
        ? charges.total
        : 0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.tokens.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _MembershipSummarySheet(
        isEdit: _isEdit,
        memberName: _fullName.text.trim(),
        membershipName: membershipName,
        batchName: batch?.name ?? (_slot is SlotNew ? 'New session' : null),
        sportName: batch?.sportName,
        showPayment: !_isEdit && _mode != MembershipPaymentMode.free,
        amountPaidInr: amountPaid,
        totalInr: charges.total,
        mandateUrl:
            (mandateUrl != null && mandateUrl.isNotEmpty) ? mandateUrl : null,
        mandateFailed: mandateFailed,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final id = _memberId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this member?'),
        content: Text(
          "${_fullName.text.trim()} and this membership will be removed. "
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: context.tokens.destructive),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting = true);
    try {
      await ref.read(membershipRepositoryProvider).deleteMember(id);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Member deleted')));
        Navigator.of(context).pop(true);
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_loading && _loadError == null && _facilityId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit membership' : 'New membership',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_isEdit && _memberId != null)
            IconButton(
              tooltip: 'Delete member',
              icon: _deleting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.delete_outline,
                      color: context.tokens.destructive),
              onPressed: _deleting ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : _form(context),
      ),
      bottomNavigationBar: !ready
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.tokens.surface0,
                  border: Border(
                      top: BorderSide(color: context.tokens.borderColor)),
                ),
                child: AuthGradientButton(
                  label: _isEdit ? 'Save changes' : 'Create membership',
                  loadingLabel: _isEdit ? 'Saving…' : 'Creating…',
                  isLoading: _saving,
                  onPressed: (_isEdit && !_dirty) ? null : _submit,
                ),
              ),
            ),
    );
  }

  Widget _form(BuildContext context) {
    final tokens = context.tokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        Text(
          _isEdit
              ? "Update this member's details"
              : 'Add a member and set up their membership.',
          style: TextStyle(fontSize: 13, color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── 1 · Member ────────────────────────────────────────────────
        _Section(
          n: 1,
          title: 'Member',
          children: [
            _text('Full name', _fullName, required: true),
            _phoneField(),
            _text('Email address', _email,
                kb: TextInputType.emailAddress),
            _labeled(
              'Date of birth',
              child: _PickerField(
                text: _dob == null
                    ? 'Select date'
                    : Formatters.dateShort(_dob!),
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
            _text('Address', _address, maxLines: 2),
          ],
        ),

        // ── 2 · Membership ───────────────────────────────────────────
        _Section(
          n: 2,
          title: 'Membership',
          children: [
            if (_plans.isNotEmpty)
              _labeled(
                'Plan',
                hint: _planId != null
                    ? 'Fee and duration come from the plan.'
                    : 'Or keep it custom and set the fee below.',
                child: AppDropdown<String>(
                  initialValue: _planId ?? '',
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('Custom (no plan)')),
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
            _text('Membership name', _name, required: true),
            _labeled(
              'Type',
              required: true,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: MembershipType.values
                    .map((t) => _pill(
                          membershipTypeLabel(t),
                          selected: _type == t,
                          onTap: () => setState(() => _type = t),
                        ))
                    .toList(),
              ),
            ),
            _labeled(
              'Start date',
              required: true,
              child: _PickerField(
                text: Formatters.dateShort(_startDate),
                icon: Icons.calendar_today_outlined,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _startDate = picked);
                },
              ),
            ),
            _labeled(
              'Duration',
              required: true,
              hint: _planId != null && !_isEdit
                  ? 'Set by the plan'
                  : _endDate == null
                      ? '1 month · 3 months · 6 months · 1 year'
                      : 'Ends ${Formatters.dateShort(_endDate!)}',
              child: _planId != null && !_isEdit
                  ? _PickerField(
                      text: _durationDays > 0 ? '$_durationDays days' : '—',
                      placeholder: _durationDays == 0,
                      onTap: () {},
                    )
                  : _Dropdown<int>(
                      value: _durationDays == 0 ? null : _durationDays,
                      hint: 'Select duration',
                      // Always include the current value — a plan can carry a
                      // non-preset duration (e.g. 31 days) that would otherwise
                      // crash the DropdownButton.
                      items: <int>{
                        ..._durations.map((d) => d.days),
                        if (_durationDays > 0) _durationDays,
                      }.toList()
                        ..sort(),
                      labelOf: (days) {
                        for (final d in _durations) {
                          if (d.days == days) return d.label;
                        }
                        return '$days days';
                      },
                      onChanged: (d) => setState(() => _durationDays = d ?? 0),
                    ),
            ),
            if (_facilityId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              MembershipSlotSection(
                facilityId: _facilityId!,
                accessDays: _accessDays,
                value: _slot,
                planId: _planId,
                currentBatchId: _slot is SlotExisting
                    ? (_slot as SlotExisting).batchId
                    : null,
                onChanged: (s) => setState(() => _slot = s),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (_type == MembershipType.family)
              _labeled(
                'Family members',
                child: Row(
                  children: [
                    _StepBtn(
                        icon: Icons.remove,
                        onTap: () => setState(() =>
                            _maxFamily = (_maxFamily - 1).clamp(1, 99))),
                    SizedBox(
                        width: 44,
                        child: Text('$_maxFamily',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16))),
                    _StepBtn(
                        icon: Icons.add,
                        onTap: () => setState(() =>
                            _maxFamily = (_maxFamily + 1).clamp(1, 99))),
                  ],
                ),
              ),
            _text('Description', _description, maxLines: 3),
          ],
        ),

        // ── 3 · Charges ──────────────────────────────────────────────
        _Section(
          n: 3,
          title: 'Charges',
          children: [
            _text('Membership fee', _fee,
                required: true,
                kb: TextInputType.number,
                enabled: _planId == null || _isEdit,
                prefix: '₹',
                helper: _planId != null && !_isEdit
                    ? 'Set by the selected plan'
                    : null),
            _text('Registration fee', _regFee,
                kb: TextInputType.number,
                prefix: '₹',
                helper: 'One-time, if applicable'),
            _text('GST %', _gst,
                kb: TextInputType.number, helper: 'Applicable tax percentage'),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: tokens.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: tokens.borderColor),
              ),
              child: Column(
                children: [
                  _chargeRow('Subtotal',
                      Formatters.currencyInr(_charges.subTotal)),
                  _chargeRow('GST',
                      Formatters.currencyInr(_charges.gstAmount)),
                  _chargeRow('Registration',
                      Formatters.currencyInr(_charges.registration)),
                  Divider(color: tokens.borderColor, height: 18),
                  _chargeRow('Total',
                      Formatters.currencyInr(_charges.total),
                      strong: true),
                ],
              ),
            ),
          ],
        ),

        // ── 4 · Payment ──────────────────────────────────────────────
        if (!_isEdit)
          _Section(
            n: 4,
            title: 'Payment',
            children: [
              for (final m in const [
                (MembershipPaymentMode.paid, 'Paid', 'Collect payment now'),
                (
                  MembershipPaymentMode.pending,
                  'Pending',
                  'Collect payment later'
                ),
                (MembershipPaymentMode.free, 'Free', 'No payment required'),
              ])
                _OptionRow(
                  selected: _mode == m.$1,
                  title: m.$2,
                  subtitle: m.$3,
                  onTap: () => setState(() => _mode = m.$1),
                ),
              if (_mode != MembershipPaymentMode.free) ...[
                const SizedBox(height: AppSpacing.sm),
                _labeled(
                  'Accepted methods',
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _paymentMethods
                        .map((pm) => _pill(
                              pm,
                              selected: _methods.contains(pm),
                              onTap: () => setState(() => _methods.contains(pm)
                                  ? _methods.remove(pm)
                                  : _methods.add(pm)),
                            ))
                        .toList(),
                  ),
                ),
                _text('Payment reference', _paymentRef,
                    helper: 'Transaction / reference number (optional)'),
                _OptionRow(
                  selected: _recurring,
                  isCheckbox: true,
                  title: 'Recurring UPI AutoPay',
                  subtitle:
                      'Generates a Razorpay mandate link; the total is charged each cycle.',
                  onTap: () => setState(() => _recurring = !_recurring),
                ),
              ],
            ],
          ),

        // ── 5 · Extra ────────────────────────────────────────────────
        _Section(
          n: _isEdit ? 4 : 5,
          title: 'Extra',
          children: [
            _labeled(
              'Referred by',
              child: _referral != null
                  ? _PickerField(
                      text: _referral!.fullName,
                      onTap: () {},
                      trailing: TextButton(
                        onPressed: () => setState(() => _referral = null),
                        child: const Text('Change'),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextField(
                            label: 'Search member (optional)',
                            controller: _referralQuery),
                        for (final r in _referralResults)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(r.fullName),
                            trailing: Text(r.phone,
                                style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 11)),
                            onTap: () => setState(() {
                              _referral = r;
                              _referralQuery.clear();
                              _referralResults = [];
                            }),
                          ),
                      ],
                    ),
            ),
            _labeled(
              'How did they find you?',
              child: _Dropdown<String>(
                value: _discovery,
                hint: 'Select an option',
                items: _discoverySources,
                labelOf: (d) => d,
                onChanged: (d) => setState(() => _discovery = d),
              ),
            ),
            _text('Notes', _notes, maxLines: 2),
          ],
        ),

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.destructive.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(_error!,
                style: TextStyle(color: tokens.destructive, fontSize: 13)),
          ),
        ],
        if (!_isEdit) ...[
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text('You can edit any of this later.',
                style:
                    TextStyle(color: tokens.textSecondary, fontSize: 12)),
          ),
        ],
      ],
    );
  }

  // ── field helpers ───────────────────────────────────────────────────────

  Widget _text(
    String label,
    TextEditingController c, {
    bool required = false,
    bool enabled = true,
    TextInputType? kb,
    int maxLines = 1,
    String? prefix,
    String? helper,
  }) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: c,
            enabled: enabled,
            keyboardType: kb,
            maxLines: maxLines,
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              prefixText: prefix == null ? null : '$prefix ',
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(helper,
                  style: TextStyle(fontSize: 11, color: tokens.textSecondary)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _phoneField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Phone number *',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text('+91',
                style: TextStyle(
                    color: context.tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16)),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
        ),
      ),
    );
  }

  Widget _pill(String label,
      {required bool selected, required VoidCallback onTap}) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? tokens.violet.withValues(alpha: 0.16) : tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? tokens.violet : tokens.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? tokens.violet : tokens.textPrimary,
            )),
      ),
    );
  }

  Widget _chargeRow(String label, String value, {bool strong = false}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                  fontSize: strong ? 14 : 13,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                  color: strong ? tokens.textPrimary : tokens.textSecondary,
                )),
          ),
          Text(value,
              style: TextStyle(
                fontSize: strong ? 15 : 13,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: strong ? tokens.primary : tokens.textPrimary,
              )),
        ],
      ),
    );
  }

  Widget _labeled(String label,
      {bool required = false, String? hint, required Widget child}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(
            text: label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary),
            children: required
                ? [
                    TextSpan(
                        text: ' *',
                        style: TextStyle(color: tokens.destructive))
                  ]
                : null,
          )),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[
            const SizedBox(height: 5),
            Text(hint,
                style: TextStyle(fontSize: 11, color: tokens.textSecondary)),
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
      child: Container(
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
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        tokens.violet,
                        tokens.violet.withValues(alpha: 0.6)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$n',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: tokens.onPrimary)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tokens.borderColor),
          color: tokens.surface2,
        ),
        child: Icon(icon, size: 18, color: tokens.textPrimary),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isCheckbox = false,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isCheckbox;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color:
            selected ? tokens.violet.withValues(alpha: 0.10) : tokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? tokens.violet : tokens.borderColor,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isCheckbox
                      ? (selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank)
                      : (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                  size: 18,
                  color: selected ? tokens.violet : tokens.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 1),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 11.5, color: tokens.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.text,
    required this.onTap,
    this.icon,
    this.placeholder = false,
    this.trailing,
  });

  final String text;
  final VoidCallback onTap;
  final IconData? icon;
  final bool placeholder;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: 14),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tokens.borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: placeholder
                          ? tokens.textSecondary
                          : tokens.textPrimary)),
            ),
            if (trailing != null)
              trailing!
            else if (icon != null)
              Icon(icon, size: 18, color: tokens.textSecondary),
          ],
        ),
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
    return AppDropdown<T>(
      initialValue: value,
      isExpanded: true,
      hint: Text(hint),
      items: items.map((i) => DropdownMenuItem<T>(value: i, child: Text(labelOf(i)))).toList(),
      onChanged: onChanged,
    );
  }
}

/// Compact confirmation that slides up from the bottom after a membership is
/// created or updated — just the essentials: who, which batch/sport, which
/// membership, and what was paid vs. the total.
class _MembershipSummarySheet extends StatelessWidget {
  const _MembershipSummarySheet({
    required this.isEdit,
    required this.memberName,
    required this.membershipName,
    required this.showPayment,
    required this.amountPaidInr,
    required this.totalInr,
    this.batchName,
    this.sportName,
    this.mandateUrl,
    this.mandateFailed = false,
  });

  final bool isEdit;
  final String memberName;
  final String membershipName;
  final String? batchName;
  final String? sportName;
  final bool showPayment;
  final num amountPaidInr;
  final num totalInr;
  final String? mandateUrl;
  final bool mandateFailed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: tokens.primary,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.primary.withValues(alpha: 0.45),
                        blurRadius: 22,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: Icon(Icons.check_rounded,
                      color: tokens.onPrimary, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    isEdit ? 'Membership updated' : 'Membership created',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: tokens.surface1,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: tokens.borderColor),
              ),
              child: Column(
                children: [
                  _row(context, 'Member', memberName),
                  if (batchName != null) _row(context, 'Batch', batchName!),
                  if (sportName != null && sportName!.isNotEmpty)
                    _row(context, 'Sport', sportName!),
                  _row(context, 'Membership', membershipName),
                  if (showPayment) ...[
                    Divider(color: tokens.borderColor, height: 18),
                    _row(context, 'Amount paid',
                        Formatters.currencyInr(amountPaidInr.toInt())),
                  ],
                  Divider(color: tokens.borderColor, height: 18),
                  _row(context, 'Total',
                      Formatters.currencyInr(totalInr.toInt()),
                      strong: true),
                ],
              ),
            ),
            if (mandateUrl != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text('UPI AutoPay link — send this to the member:',
                  style: TextStyle(
                      fontSize: 12, color: tokens.textSecondary)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: tokens.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: tokens.borderColor),
                ),
                child: SelectableText(mandateUrl!,
                    style: const TextStyle(fontSize: 12)),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: mandateUrl!));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy link'),
                ),
              ),
            ] else if (mandateFailed) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'The recurring AutoPay link couldn’t be generated — retry it from the members list.',
                style:
                    TextStyle(fontSize: 12, color: tokens.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AuthGradientButton(
              label: 'Back to members',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool strong = false}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: strong ? 14 : 13,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                color: strong ? tokens.textPrimary : tokens.textSecondary,
              )),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: strong ? 15 : 13,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                  color: strong ? tokens.primary : tokens.textPrimary,
                )),
          ),
        ],
      ),
    );
  }
}