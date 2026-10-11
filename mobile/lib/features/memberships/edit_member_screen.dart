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
import 'form_section.dart';
import 'plan_wizard.dart' show planDayAbbr;

/// Edit Member — the Memberships section's own edit page, the counterpart of the Add Member wizard
/// (and of the web's /memberships/v1/:id/edit). Personal details and the start date are editable;
/// the plan — and with it the court, timings and fees — is fixed, so it is shown read-only. Pops
/// `true` once saved.
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

  String _errorSig = '';

  /// Typing only rebuilds the page when it changes which errors are showing — not on every keystroke.
  void _typed() {
    if (_touched.isEmpty) return;
    final sig = _errors.toString();
    if (sig == _errorSig) return;
    setState(() => _errorSig = sig);
  }

  DateTime? get _endDate {
    final days = _detail?.membership.durationDays;
    return days == null || days <= 0 ? null : DateTime(_startDate.year, _startDate.month, _startDate.day + days - 1);
  }

  Future<void> _save() async {
    final d = _detail;
    if (d == null || _saving) return;
    if (_errors.isNotEmpty) {
      setState(() {
        _touched.addAll(_errors.keys);
        _errorSig = _errors.toString();
      });
      return;
    }
    FocusScope.of(context).unfocus();
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

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    return parts.map((p) => p[0].toUpperCase()).join();
  }

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
        body: Center(child: Text(_loadError ?? "We couldn't load this member.", style: AppTypography.secondary(context))),
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
                  child: OutlinedButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _summary(tokens, d),
            FormSection(
              title: 'Personal Information',
              icon: Icons.person_outline_rounded,
              children: [
                TextField(
                  controller: _fullName,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => _typed(),
                  decoration: InputDecoration(labelText: 'Full name *', errorText: _show('fullName')),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: AppDropdown<String>(
                        initialValue: _countryCode,
                        decoration: const InputDecoration(labelText: 'Code'),
                        items: [for (final c in addMemberCountryCodes) DropdownMenuItem(value: c, child: Text(c))],
                        onChanged: (v) => setState(() => _countryCode = v ?? _countryCode),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(_countryCode == '+91' ? 10 : 14)],
                        onChanged: (_) => _typed(),
                        decoration: InputDecoration(labelText: 'Phone number *', errorText: _show('phone')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => _typed(),
                  decoration: InputDecoration(labelText: 'Email', errorText: _show('email')),
                ),
                const SizedBox(height: AppSpacing.sm),
                DateField(
                  label: 'Date of birth',
                  value: _dob,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  format: Formatters.dateShort,
                  errorText: _show('dateOfBirth'),
                  onPick: (v) => setState(() => _dob = v),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppDropdown<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Gender'),
                  items: [for (final g in addMemberGenders) DropdownMenuItem(value: g.value, child: Text(g.label))],
                  onChanged: (v) => setState(() => _gender = v ?? ''),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
                const SizedBox(height: AppSpacing.sm),
                TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
              ],
            ),
            FormSection(
              title: 'Membership',
              subtitle: "The plan and its fees can't be changed here — only the start date.",
              icon: Icons.card_membership_outlined,
              children: [
                InfoRow('Plan', d.membership.name),
                InfoRow('Type', _titleCase(d.membership.membershipType)),
                InfoRow('Duration', d.membership.durationDays == null ? '—' : _duration(d.membership.durationDays!)),
                const SizedBox(height: AppSpacing.sm),
                DateField(
                  label: 'Plan start date *',
                  value: _startDate,
                  firstDate: DateTime(DateTime.now().year - 3),
                  lastDate: DateTime(DateTime.now().year + 3),
                  format: Formatters.dateShort,
                  onPick: (v) => setState(() => _startDate = v),
                ),
                InfoRow('Plan end date', _endDate == null ? '—' : Formatters.dateShort(_endDate!)),
                const Divider(height: AppSpacing.lg),
                InfoRow('Membership fee', Formatters.currencyInr(d.membership.membershipFeeInr)),
                if (d.membership.registrationFeeInr > 0) InfoRow('Registration fee', Formatters.currencyInr(d.membership.registrationFeeInr)),
                if (d.membership.gstPercent > 0) InfoRow('GST (${d.membership.gstPercent}%)', Formatters.currencyInr(d.membership.gstAmountInr)),
                InfoRow('Total', Formatters.currencyInr(d.membership.totalAmountInr)),
                if (d.payment != null) ...[
                  const Divider(height: AppSpacing.lg),
                  InfoRow(
                    'Payment',
                    d.payment!.settled ? 'Paid' : 'Pending',
                    valueColor: d.payment!.settled ? tokens.success : tokens.warning,
                  ),
                  if (d.payment!.method != null && d.payment!.method!.isNotEmpty) InfoRow('Method', d.payment!.method!),
                  if (d.payment!.paidAt != null) InfoRow('Paid on', Formatters.dateShort(d.payment!.paidAt!.toLocal())),
                ],
                if (d.referralName != null || d.discoverySource != null || d.createdByName != null) const Divider(height: AppSpacing.lg),
                if (d.referralName != null) InfoRow('Referred by', d.referralName!),
                if (d.discoverySource != null && d.discoverySource!.isNotEmpty) InfoRow('Found us via', d.discoverySource!),
                if (d.createdByName != null) InfoRow('Added by', d.createdByName!),
              ],
            ),
            FormSection(
              title: 'Court & Timing',
              subtitle: 'Set by the plan.',
              icon: Icons.schedule_outlined,
              children: [_slot(d.slot)],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(_error!, style: TextStyle(color: tokens.destructive, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  /// Who this is, at a glance — the gap at the top of the page, filled with what the app knows.
  Widget _summary(AppColorTokens tokens, MembershipDetail d) {
    final (label, color) = switch (d.displayStatus) {
      MembershipListStatus.active => ('Active', tokens.success),
      MembershipListStatus.paymentIncomplete => ('Payment pending', tokens.warning),
      MembershipListStatus.inactive => ('Inactive', tokens.destructive),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surface1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tokens.borderColor),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: tokens.primary.withValues(alpha: 0.14),
              child: Text(_initials(d.member.fullName), style: TextStyle(fontWeight: FontWeight.w700, color: tokens.primary)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.member.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.sectionTitle(context)),
                  Text(d.member.phone, style: AppTypography.secondary(context)),
                  const SizedBox(height: 4),
                  Text('Member since ${Formatters.dateShort(d.member.memberSince.toLocal())}', style: AppTypography.caption(context)),
                ],
              ),
            ),
            TintPill(label, color),
          ],
        ),
      ),
    );
  }

  static String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';

  static String _duration(int days) {
    final months = (days / 30).round();
    if (days < 30) return '$days ${days == 1 ? 'day' : 'days'}';
    return months == 1 ? '1 month' : '$months months';
  }

  Widget _slot(MembershipSlot? s) {
    final tokens = context.tokens;
    if (s == null) return Text('No court time reserved.', style: AppTypography.secondary(context));
    final days = [...s.daysOfWeek]..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow('Court', s.courtName ?? '—'),
        InfoRow('Time', '${Formatters.time12h(s.startTime)} - ${Formatters.time12h(s.endTime)}'),
        const SizedBox(height: AppSpacing.sm),
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
    );
  }
}
