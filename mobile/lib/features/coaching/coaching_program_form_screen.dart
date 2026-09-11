import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';

/// Create a coaching program — mirrors the web's Create Program wizard as a
/// single scrolling form on mobile. Edit reuses via [existing].
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

  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description = TextEditingController(text: widget.existing?.description ?? '');
  late final _duration =
      TextEditingController(text: '${widget.existing?.defaultDurationMinutes ?? 60}');
  late final _capacity = TextEditingController(text: '${widget.existing?.defaultCapacity ?? 10}');
  late final _sessionCount =
      TextEditingController(text: widget.existing?.sessionCount != null ? '${widget.existing!.sessionCount}' : '');
  late final _price = TextEditingController(
      text: widget.existing?.defaultPriceMinor != null ? (widget.existing!.defaultPriceMinor! / 100).toString() : '');

  late String _level = widget.existing?.level ?? 'Beginner';
  late String _ageGroup = widget.existing?.ageGroup ?? 'All Ages';
  late String _category = widget.existing?.category ?? 'General';
  // PAID | INCLUDED | PER_ENROLLMENT
  String _pricingMode = 'PAID';
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
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _duration, _capacity, _sessionCount, _price]) {
      c.dispose();
    }
    super.dispose();
  }

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
    setState(() {
      _saving = true;
      _error = null;
    });
    final priceMinor = switch (_pricingMode) {
      'PAID' => ((priceRupees ?? 0) * 100).round(),
      'INCLUDED' => 0,
      _ => null,
    };
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
        );
      } else {
        await repo.createProgram(
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
            _num(_sessionCount, 'Sessions per package (optional)'),
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
            if (_pricingMode == 'PAID') _num(_price, 'Program fee (₹)', decimal: true),
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

  Widget _pricingChip(String value, String label, bool enabled) {
    return ChoiceChip(
      label: Text(label),
      selected: _pricingMode == value,
      onSelected: enabled ? (_) => setState(() => _pricingMode = value) : null,
    );
  }

  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
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
