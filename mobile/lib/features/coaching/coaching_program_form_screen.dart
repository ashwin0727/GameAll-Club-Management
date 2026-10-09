import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../authentication/session_controller.dart';
import '../maintenance/maintenance_court_options.dart';
import '../staff/staff_common.dart';
import '../../shared/widgets/app_dropdown.dart';

/// Create a coaching program — mirrors the web's Create Program wizard as a
/// single scrolling form on mobile. Edit reuses via [existing].
///
/// Covers the same decisions as the web wizard: the program basics, its
/// dates, ONE batch (the weekly day / time / court / coach students are
/// enrolled into — the web requires exactly one), and pricing — including
/// the Fee Type (one-time link vs. monthly auto-pay), discount, tax and
/// which payment methods the program accepts. Batches of an existing program
/// are managed on the web.
class CoachingProgramFormScreen extends ConsumerStatefulWidget {
  const CoachingProgramFormScreen({super.key, this.existing});

  final ProgramDetail? existing;

  @override
  ConsumerState<CoachingProgramFormScreen> createState() => _CoachingProgramFormScreenState();
}

class _CoachingProgramFormScreenState extends ConsumerState<CoachingProgramFormScreen> {
  static const _levels = ['Beginner', 'Intermediate', 'Advanced', 'All Levels', 'Custom'];
  static const _ageGroups = ['All Ages', 'Under 12', 'Teens', 'Adults', 'Seniors'];
  static const _categories = ['General', 'Group', 'Private', 'Kids', 'Ladies', 'Competitive'];
  static const _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description = TextEditingController(text: widget.existing?.description ?? '');
  late final _duration =
      TextEditingController(text: '${widget.existing?.defaultDurationMinutes ?? 60}');
  late final _capacity = TextEditingController(text: '${widget.existing?.defaultCapacity ?? 10}');
  late final _sessionCount =
      TextEditingController(text: widget.existing?.sessionCount != null ? '${widget.existing!.sessionCount}' : '');
  late final _sessionsPerWeek =
      TextEditingController(text: widget.existing?.sessionsPerWeek != null ? '${widget.existing!.sessionsPerWeek}' : '');
  late final _price = TextEditingController(
      text: widget.existing?.defaultPriceMinor != null ? (widget.existing!.defaultPriceMinor! / 100).toString() : '');
  late final _discount = TextEditingController(
      text: widget.existing?.earlyBirdDiscountMinor != null ? (widget.existing!.earlyBirdDiscountMinor! / 100).toString() : '');
  late final _tax = TextEditingController(text: widget.existing?.taxPercent != null ? '${widget.existing!.taxPercent}' : '');
  final _batchName = TextEditingController(text: 'Batch 1');

  late String _level = widget.existing?.level ?? 'Beginner';
  late String _ageGroup = widget.existing?.ageGroup ?? 'All Ages';
  late String _category = widget.existing?.category ?? 'General';
  // PAID | INCLUDED | PER_ENROLLMENT
  String _pricingMode = 'PAID';
  // ONE_TIME | MONTHLY — for MONTHLY the fee above is charged every month until the end date.
  late String _feeType = widget.existing?.feeType ?? 'ONE_TIME';
  // OFFLINE | ONLINE | BOTH
  late String _paymentMode = widget.existing?.paymentMode ?? 'BOTH';
  DateTime? _startDate;
  DateTime? _endDate;

  // First batch (create only).
  final Set<int> _days = {};
  TimeOfDay _batchStart = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _batchEnd = const TimeOfDay(hour: 18, minute: 0);
  String? _courtId;
  String? _coachId;
  List<MaintenanceCourtOption> _courts = const [];
  List<CoachOption> _coaches = const [];

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _pricingMode = e.isMembershipIncluded
          ? 'INCLUDED'
          : e.defaultPriceMinor != null
              ? 'PAID'
              : 'PER_ENROLLMENT';
      _startDate = e.startDate != null ? DateTime.tryParse(e.startDate!) : null;
      _endDate = e.endDate != null ? DateTime.tryParse(e.endDate!) : null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRefs());
  }

  Future<void> _loadRefs() async {
    if (_isEdit) return; // batches are not edited here
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    try {
      final coaches = await ref.read(coachingRepositoryProvider).listCoachOptions(fid);
      final courts = await loadMaintenanceCourtOptions(ref, fid);
      if (mounted) {
        setState(() {
          _coaches = coaches;
          _courts = courts;
        });
      }
    } on AppException {
      // the form stays usable; batch court is then reported as missing on save
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _duration, _capacity, _sessionCount, _sessionsPerWeek, _price, _discount, _tax, _batchName]) {
      c.dispose();
    }
    super.dispose();
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  int _mins(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _save() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a program name.');
      return;
    }
    final dur = int.tryParse(_duration.text.trim()) ?? 60;
    final cap = int.tryParse(_capacity.text.trim()) ?? 1;
    if (dur < 15 || dur > 480) {
      setState(() => _error = 'Duration must be between 15 and 480 minutes.');
      return;
    }
    if (cap < 1) {
      setState(() => _error = 'Capacity must be at least 1.');
      return;
    }
    final priceRupees = num.tryParse(_price.text.trim());
    if (_pricingMode == 'PAID' && (priceRupees == null || priceRupees < 0)) {
      setState(() => _error = 'Enter a program fee, or choose another pricing option.');
      return;
    }
    final isMonthly = _feeType == 'MONTHLY' && _pricingMode == 'PAID';
    if (isMonthly) {
      if ((priceRupees ?? 0) <= 0) {
        setState(() => _error = 'Enter the fee per month.');
        return;
      }
      if (_startDate == null || _endDate == null) {
        setState(() => _error = 'A monthly program needs a start and end date.');
        return;
      }
    }
    if (_startDate != null && _endDate != null && _endDate!.isBefore(_startDate!)) {
      setState(() => _error = 'The end date cannot be before the start date.');
      return;
    }
    final discountRupees = num.tryParse(_discount.text.trim());
    if (discountRupees != null && priceRupees != null && discountRupees > priceRupees) {
      setState(() => _error = 'The discount cannot be more than the fee.');
      return;
    }
    final taxPercent = double.tryParse(_tax.text.trim());
    if (taxPercent != null && (taxPercent < 0 || taxPercent > 100)) {
      setState(() => _error = 'Tax must be between 0 and 100%.');
      return;
    }
    if (!_isEdit) {
      if (_startDate == null) {
        setState(() => _error = 'Choose the program start date.');
        return;
      }
      if (_days.isEmpty) {
        setState(() => _error = 'Choose at least one batch day.');
        return;
      }
      if (_mins(_batchEnd) <= _mins(_batchStart)) {
        setState(() => _error = 'The batch must end after it starts.');
        return;
      }
      if (_courtId == null) {
        setState(() => _error = 'Choose a court for the batch.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final priceMinor = switch (_pricingMode) {
      'PAID' => ((priceRupees ?? 0) * 100).round(),
      'INCLUDED' => 0,
      _ => null,
    };
    final discountMinor = discountRupees != null && discountRupees > 0 ? (discountRupees * 100).round() : null;
    final feeType = _pricingMode == 'PAID' ? _feeType : 'ONE_TIME';
    try {
      final repo = ref.read(coachingRepositoryProvider);
      if (_isEdit) {
        await repo.updateProgram(
          programId: widget.existing!.id,
          name: _name.text.trim(),
          level: _level,
          ageGroup: _ageGroup,
          category: _category,
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          defaultDurationMinutes: dur,
          defaultCapacity: cap,
          sessionCount: int.tryParse(_sessionCount.text.trim()),
          defaultPriceMinor: widget.existing!.isMembershipIncluded ? null : priceMinor,
          sessionsPerWeek: int.tryParse(_sessionsPerWeek.text.trim()),
          startDate: _startDate != null ? _iso(_startDate!) : null,
          endDate: _endDate != null ? _iso(_endDate!) : null,
          paymentMode: _paymentMode,
          earlyBirdDiscountMinor: discountMinor,
          taxPercent: taxPercent,
          feeType: feeType,
        );
      } else {
        await repo.createProgramFull(
          facilityId: fid,
          name: _name.text.trim(),
          level: _level,
          ageGroup: _ageGroup,
          category: _category,
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          defaultDurationMinutes: dur,
          defaultCapacity: cap,
          sessionCount: int.tryParse(_sessionCount.text.trim()),
          defaultPriceMinor: priceMinor,
          isMembershipIncluded: _pricingMode == 'INCLUDED',
          sessionsPerWeek: int.tryParse(_sessionsPerWeek.text.trim()),
          startDate: _iso(_startDate!),
          endDate: _endDate != null ? _iso(_endDate!) : null,
          paymentMode: _paymentMode,
          earlyBirdDiscountMinor: discountMinor,
          taxPercent: taxPercent,
          feeType: feeType,
          batches: [
            {
              'courtId': _courtId,
              'coachId': _coachId,
              'name': _batchName.text.trim().isEmpty ? 'Batch 1' : _batchName.text.trim(),
              'daysOfWeek': ([..._days]..sort()),
              'startTime': _hhmm(_batchStart),
              'endTime': _hhmm(_batchEnd),
              'capacity': cap,
            },
          ],
        );
      }
      if (mounted) Navigator.of(context).pop(true);
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
    if (!session.can('COACHING_MANAGE_PROGRAMS')) {
      return StaffPermissionDenied(
        title: _isEdit ? 'Edit Program' : 'Create Program',
        message: "You don't have permission to manage programs.",
      );
    }
    final canPrice = session.can('COACHING_MANAGE_PRICING');
    final monthly = _pricingMode == 'PAID' && _feeType == 'MONTHLY';

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Program' : 'Create Program')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Program name')),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: _dropdown('Level', _level, _levels, (v) => setState(() => _level = v))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _dropdown('Age group', _ageGroup, _ageGroups, (v) => setState(() => _ageGroup = v))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _dropdown('Category', _category, _categories, (v) => setState(() => _category = v)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: _num(_duration, 'Duration (min)')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _num(_capacity, 'Capacity')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: _num(_sessionsPerWeek, 'Sessions / week')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _num(_sessionCount, 'Sessions in package')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Schedule', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(child: _dateField('Start date', _startDate, (d) => setState(() => _startDate = d))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _dateField(
                    monthly ? 'End date (required)' : 'End date',
                    _endDate,
                    (d) => setState(() => _endDate = d),
                    first: _startDate,
                  ),
                ),
              ],
            ),
            if (!_isEdit) ..._batchSection(),
            const SizedBox(height: AppSpacing.md),
            Text('Pricing', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _pricingChip('PAID', 'Fixed fee', true),
                _pricingChip('INCLUDED', 'Membership-included', canPrice),
                _pricingChip('PER_ENROLLMENT', 'Per enrollment', canPrice),
              ],
            ),
            if (_pricingMode == 'PAID') ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Fee type', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('One-time payment'),
                    selected: _feeType == 'ONE_TIME',
                    onSelected: (_) => setState(() => _feeType = 'ONE_TIME'),
                  ),
                  ChoiceChip(
                    label: const Text('Monthly payment'),
                    selected: _feeType == 'MONTHLY',
                    onSelected: (_) => setState(() => _feeType = 'MONTHLY'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                monthly
                    ? 'Auto-charged every month until the program ends. The fee below is per month.'
                    : 'The student pays the full fee once, through a payment link.',
                style: TextStyle(fontSize: 11, color: context.tokens.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              _num(_price, monthly ? 'Fee per month (₹)' : 'Program fee (₹)', decimal: true),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _num(_discount, 'Early-bird discount (₹)', decimal: true)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _num(_tax, 'Tax / GST (%)', decimal: true)),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            _dropdownMap('Payment mode', _paymentMode, const {
              'OFFLINE': 'Offline',
              'ONLINE': 'Online',
              'BOTH': 'Offline & Online',
            }, (v) => setState(() => _paymentMode = v)),
            const SizedBox(height: 4),
            Text('A fee is an obligation — it becomes revenue only when a payment is recorded.',
                style: TextStyle(fontSize: 11, color: context.tokens.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: context.tokens.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: _isEdit ? 'Save changes' : 'Create Program',
              loadingLabel: 'Saving…',
              isLoading: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  /// The program's first batch — the weekly slot students are enrolled into.
  List<Widget> _batchSection() {
    return [
      const SizedBox(height: AppSpacing.md),
      Text('Batch', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 2),
      Text(
        "The weekly slot students join. Every enrollment is placed in a batch, and the batch's coach becomes the student's coach.",
        style: TextStyle(fontSize: 11, color: context.tokens.textSecondary),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(controller: _batchName, decoration: const InputDecoration(labelText: 'Batch name')),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (var d = 0; d < 7; d++)
            FilterChip(
              label: Text(_dayLabels[d], semanticsLabel: _dayNames[d]),
              tooltip: _dayNames[d],
              selected: _days.contains(d),
              showCheckmark: false,
              onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        children: [
          Expanded(child: _timeField('Starts', _batchStart, (t) => setState(() => _batchStart = t))),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _timeField('Ends', _batchEnd, (t) => setState(() => _batchEnd = t))),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      AppDropdown<String>(
        initialValue: _courtId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Court'),
        items: _courts
            .map((c) => DropdownMenuItem(value: c.id, child: Text('${c.name} · ${c.sportName}', overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: (v) => setState(() => _courtId = v),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppDropdown<String>(
        initialValue: _coachId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Coach'),
        items: [
          const DropdownMenuItem(value: null, child: Text('No specific coach')),
          ..._coaches.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: (v) => setState(() => _coachId = v),
      ),
    ];
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime?> onPicked, {DateTime? first}) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? first ?? now,
          firstDate: first ?? DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) onPicked(picked);
      },
      child: AppSelectField(
        decoration: InputDecoration(labelText: label),
        child: Text(value == null ? '—' : DateFormat('d MMM yyyy').format(value)),
      ),
    );
  }

  Widget _timeField(String label, TimeOfDay value, ValueChanged<TimeOfDay> onPicked) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: value);
        if (picked != null) onPicked(picked);
      },
      child: AppSelectField(
        decoration: InputDecoration(labelText: label),
        child: Text(value.format(context)),
      ),
    );
  }

  Widget _pricingChip(String value, String label, bool enabled) {
    return ChoiceChip(
      label: Text(label),
      selected: _pricingMode == value,
      onSelected: enabled ? (_) => setState(() => _pricingMode = value) : null,
    );
  }

  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return AppDropdown<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
      onChanged: (v) => onChanged(v ?? value),
    );
  }

  Widget _dropdownMap(String label, String value, Map<String, String> options, ValueChanged<String> onChanged) {
    return AppDropdown<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options.entries.map((o) => DropdownMenuItem(value: o.key, child: Text(o.value))).toList(),
      onChanged: (v) => onChanged(v ?? value),
    );
  }

  Widget _num(TextEditingController c, String label, {bool decimal = false}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        decimal ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')) : FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(labelText: label),
    );
  }
}
