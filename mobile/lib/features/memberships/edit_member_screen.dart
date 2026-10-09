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
import '../../shared/widgets/app_dropdown.dart';
import 'add_member_wizard.dart';
import 'plan_wizard.dart' show planDayAbbr;

/// Edit Member — the Memberships section's own edit page, the counterpart of the Add Member wizard
/// (and of the web's /memberships/v1/:id/edit). Personal details and the start date are editable;
/// the plan — and with it the court and timings — is fixed, so it is shown read-only. Pops `true`
/// once saved.
class EditMemberScreen extends ConsumerStatefulWidget {
  const EditMemberScreen({super.key, required this.membershipId});

  final String membershipId;

  @override
  ConsumerState<EditMemberScreen> createState() => _EditMemberScreenState();
}

class _EditMemberScreenState extends ConsumerState<EditMemberScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  String _countryCode = '+91';
  String _gender = '';
  DateTime? _dob;
  DateTime _startDate = DateTime.now();

  MembershipDetail? _detail;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  String? _error;
  final Set<String> _touched = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [_fullName, _phone, _email, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(membershipRepositoryProvider).getMembershipDetail(widget.membershipId);
      if (!mounted) return;
      final p = addMemberSplitPhone(d.member.phone);
      setState(() {
        _detail = d;
        _fullName.text = d.member.fullName;
        _countryCode = addMemberCountryCodes.contains(p.code) ? p.code : '+91';
        _phone.text = p.number;
        _email.text = d.member.email ?? '';
        _address.text = d.member.address ?? '';
        _notes.text = d.notes ?? '';
        _gender = addMemberGenders.any((g) => g.value == d.member.gender) ? d.member.gender! : '';
        _dob = d.member.dateOfBirth == null ? null : DateTime.tryParse(d.member.dateOfBirth!);
        _startDate = d.membership.startDate;
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

  /// The wizard's own personal-information rules, on the fields this page edits.
  Map<String, String> get _errors => addMemberFieldErrors(
        0,
        AddMemberDraft()
          ..fullName = _fullName.text
          ..countryCode = _countryCode
          ..phone = _phone.text
          ..email = _email.text
          ..dateOfBirth = _dob,
      );

  String? _show(String field) => _touched.contains(field) ? _errors[field] : null;

  DateTime? get _endDate {
    final days = _detail?.membership.durationDays;
    return days == null || days <= 0 ? null : DateTime(_startDate.year, _startDate.month, _startDate.day + days - 1);
  }

  Future<void> _save() async {
    final d = _detail;
    if (d == null || _saving) return;
    if (_errors.isNotEmpty) {
      setState(() => _touched.addAll(_errors.keys));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(membershipRepositoryProvider).updateMembershipFull(
            widget.membershipId,
            fullName: _fullName.text.trim(),
            phone: addMemberComposePhone(_countryCode, _phone.text),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            dateOfBirth: _dob == null ? null : _isoDate(_dob!),
            gender: _gender.isEmpty ? null : _gender,
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            name: d.membership.name,
            membershipType: membershipTypeFromDb(d.membership.membershipType),
            maxFamilyMembers: d.membership.maxFamilyMembers < 1 ? 1 : d.membership.maxFamilyMembers,
            startDate: _startDate,
            durationDays: d.membership.durationDays ?? 0,
            description: d.membership.description,
            membershipFeeInr: d.membership.membershipFeeInr,
            registrationFeeInr: d.membership.registrationFeeInr,
            gstPercent: d.membership.gstPercent,
            referralMemberId: d.referralMemberId,
            discoverySource: d.discoverySource,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            // Re-sent as-is: leaving both batch fields empty would clear the member's court slot.
            batchId: d.slot?.batchId,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('Edit member failed: $e\n$st');
      if (mounted) setState(() => _error = 'Unable to save this member.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Edit Member')), body: const Center(child: CircularProgressIndicator()));
    }
    final d = _detail;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Member')),
        body: Center(child: Text(_loadError ?? "We couldn't load this member.")),
      );
    }
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit Member')),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            decoration: BoxDecoration(color: tokens.surface0, border: Border(top: BorderSide(color: tokens.borderColor))),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text('Personal Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('Basic details', style: AppTypography.secondary(context)),
            const SizedBox(height: AppSpacing.md),
            _field(_fullName, 'Full Name *', 'fullName'),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: AppDropdown<String>(
                    initialValue: _countryCode,
                    decoration: const InputDecoration(labelText: 'Code'),
                    items: [for (final c in addMemberCountryCodes) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => _countryCode = v ?? _countryCode),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _field(
                    _phone,
                    'Phone Number *',
                    'phone',
                    keyboard: TextInputType.phone,
                    formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(_countryCode == '+91' ? 10 : 14)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _field(_email, 'Email', 'email', keyboard: TextInputType.emailAddress),
            const SizedBox(height: AppSpacing.md),
            _dateField('Date of Birth', _dob, (v) => _dob = v, first: DateTime(1900), last: DateTime.now(), error: _show('dateOfBirth')),
            const SizedBox(height: AppSpacing.md),
            AppDropdown<String>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: [for (final g in addMemberGenders) DropdownMenuItem(value: g.value, child: Text(g.label))],
              onChanged: (v) => setState(() => _gender = v ?? ''),
            ),
            const SizedBox(height: AppSpacing.md),
            _field(_address, 'Address', null),
            const SizedBox(height: AppSpacing.md),
            _field(_notes, 'Notes', null, maxLines: 2),
            const SizedBox(height: AppSpacing.xl),
            const Text('Membership Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text("The plan can't be changed here — its court and timings come with it.", style: AppTypography.secondary(context)),
            const SizedBox(height: AppSpacing.md),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Plan'),
              child: Text('${d.membership.name} · ${Formatters.currencyInr(d.membership.membershipFeeInr)}'),
            ),
            const SizedBox(height: AppSpacing.md),
            _dateField('Plan Start Date *', _startDate, (v) => _startDate = v, first: DateTime(DateTime.now().year - 3)),
            const SizedBox(height: AppSpacing.md),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Plan End Date'),
              child: Text(_endDate == null ? '—' : Formatters.dateShort(_endDate!)),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Court & Timing', style: AppTypography.rowTitle(context)),
            const SizedBox(height: AppSpacing.sm),
            _slot(d.slot),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(_error!, style: TextStyle(color: tokens.destructive, fontSize: 13)),
              ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String? field, {
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, errorText: field == null ? null : _show(field)),
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick, {DateTime? first, DateTime? last, String? error}) {
    return TextField(
      readOnly: true,
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

  Widget _slot(MembershipSlot? s) {
    final tokens = context.tokens;
    if (s == null) return Text('No court time reserved.', style: AppTypography.caption(context));
    final days = [...s.daysOfWeek]..sort();
    return Container(
      width: double.infinity,
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
            Expanded(child: Text(s.courtName ?? 'Court', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
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
                  decoration: BoxDecoration(color: days.contains(day) ? tokens.primary : tokens.surface2, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    planDayAbbr[day],
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: days.contains(day) ? tokens.onPrimary : tokens.textSecondary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
