import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/booking.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../authentication/session_controller.dart';

/// Add a coaching enrollment — mirrors
/// src/features/coaching/components/enrollment-form-dialog.tsx. Enrols an
/// existing facility member; never creates an account.
class CoachingEnrollmentFormSheet extends ConsumerStatefulWidget {
  const CoachingEnrollmentFormSheet({super.key, required this.facilityId});

  final String facilityId;

  @override
  ConsumerState<CoachingEnrollmentFormSheet> createState() => _CoachingEnrollmentFormSheetState();
}

class _CoachingEnrollmentFormSheetState extends ConsumerState<CoachingEnrollmentFormSheet> {
  final _memberQuery = TextEditingController();
  final _sessionsTotal = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  Timer? _debounce;

  List<ProgramOption> _programs = const [];
  List<CoachOption> _coaches = const [];
  List<MemberSearchResult> _memberHits = const [];
  MemberSearchResult? _member;
  String? _programId;
  String? _coachId;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _saving = false;
  String? _error;

  ProgramOption? get _program => _programs.where((p) => p.id == _programId).firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRefs());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_memberQuery, _sessionsTotal, _price, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRefs() async {
    try {
      final repo = ref.read(coachingRepositoryProvider);
      final programs = await repo.listProgramOptions(widget.facilityId);
      final coaches = await repo.listCoachOptions(widget.facilityId);
      if (mounted) setState(() { _programs = programs; _coaches = coaches; });
    } on AppException {
      // form still usable
    }
  }

  void _onMemberQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (v.trim().length < 2) {
        setState(() => _memberHits = const []);
        return;
      }
      try {
        final hits = await ref.read(bookingRepositoryProvider).searchMembers(widget.facilityId, v);
        if (mounted) setState(() => _memberHits = hits);
      } on AppException {
        if (mounted) setState(() => _memberHits = const []);
      }
    });
  }

  void _onProgramChanged(String? id) {
    setState(() {
      _programId = id;
      final p = _program;
      if (p != null) {
        if (_sessionsTotal.text.isEmpty && p.sessionCount != null) _sessionsTotal.text = '${p.sessionCount}';
        if (!p.isMembershipIncluded && p.defaultPriceMinor != null && _price.text.isEmpty) {
          _price.text = (p.defaultPriceMinor! / 100).toString();
        }
      }
    });
  }

  Future<void> _save() async {
    final canPrice = ref.read(sessionControllerProvider).can('COACHING_MANAGE_PRICING');
    if (_member == null) {
      setState(() => _error = 'Select a member.');
      return;
    }
    if (_programId == null) {
      setState(() => _error = 'Select a program.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final p = _program;
    final priceRupees = num.tryParse(_price.text.trim());
    try {
      final id = await ref.read(coachingRepositoryProvider).createEnrollment(
            facilityId: widget.facilityId,
            memberId: _member!.id,
            programId: _programId!,
            coachId: _coachId,
            startDate: DateFormat('yyyy-MM-dd').format(_startDate),
            endDate: _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : null,
            sessionsTotal: int.tryParse(_sessionsTotal.text.trim()),
            priceMinor: (p?.isMembershipIncluded ?? false)
                ? 0
                : priceRupees != null
                    ? (priceRupees * 100).round()
                    : null,
            pricingType: (p?.isMembershipIncluded ?? false)
                ? 'MEMBERSHIP_INCLUDED'
                : canPrice && _price.text.trim().isNotEmpty
                    ? 'CUSTOM'
                    : 'STANDARD',
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(id);
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
    final p = _program;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add enrollment', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            if (_member != null)
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Member'),
                child: Row(
                  children: [
                    Expanded(child: Text(_member!.fullName)),
                    TextButton(onPressed: () => setState(() => _member = null), child: const Text('Change')),
                  ],
                ),
              )
            else ...[
              TextField(
                controller: _memberQuery,
                onChanged: _onMemberQuery,
                decoration: const InputDecoration(labelText: 'Member', hintText: 'Search by name or phone'),
              ),
              ..._memberHits.map((m) => ListTile(
                    dense: true,
                    title: Text(m.fullName),
                    subtitle: m.phone.isNotEmpty ? Text(m.phone) : null,
                    onTap: () => setState(() {
                      _member = m;
                      _memberHits = const [];
                    }),
                  )),
            ],
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _programId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Program'),
              items: _programs
                  .map((x) => DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _onProgramChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _coachId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Coach (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('No specific coach')),
                ..._coaches.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => setState(() => _coachId = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime(_startDate.year - 1),
                        lastDate: DateTime(_startDate.year + 2),
                      );
                      if (picked != null) setState(() => _startDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Start date'),
                      child: Text(DateFormat('d MMM yyyy').format(_startDate)),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? _startDate,
                        firstDate: _startDate,
                        lastDate: DateTime(_startDate.year + 3),
                      );
                      if (picked != null) setState(() => _endDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'End date (optional)'),
                      child: Text(_endDate != null ? DateFormat('d MMM yyyy').format(_endDate!) : 'Not set'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sessionsTotal,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Sessions in package'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: (p?.isMembershipIncluded ?? false)
                      ? const InputDecorator(
                          decoration: InputDecoration(labelText: 'Fee'),
                          child: Text('Included'),
                        )
                      : TextField(
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: const InputDecoration(labelText: 'Fee (₹)'),
                        ),
                ),
              ],
            ),
            if (p != null && !p.isMembershipIncluded) ...[
              const SizedBox(height: 4),
              Text(
                'The fee is an obligation — record a payment against it from Pending Payments.',
                style: TextStyle(fontSize: 11, color: context.tokens.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: context.tokens.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Create Enrollment', loadingLabel: 'Enrolling…', isLoading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
