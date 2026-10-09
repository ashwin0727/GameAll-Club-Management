import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import 'plan_wizard.dart' show planCategories, planWizardDurationLabel;

/// Which part of a plan the sheet edits: the Overview fields, or its Benefits list.
enum PlanEditSection { overview, benefits }

/// Edit a plan. The price and duration are shown but locked — members may already be on the plan, so
/// what it costs and how long it runs stay as created. Everything else can change: name, description,
/// category, badge, joining fee, security deposit, and (in the Benefits tab) the benefits.
///
/// Pops the saved [MembershipPlan], or null when dismissed.
class MembershipPlanEditSheet extends ConsumerStatefulWidget {
  const MembershipPlanEditSheet({super.key, required this.plan, this.section = PlanEditSection.overview});

  final MembershipPlan plan;
  final PlanEditSection section;

  @override
  ConsumerState<MembershipPlanEditSheet> createState() => _MembershipPlanEditSheetState();
}

class _MembershipPlanEditSheetState extends ConsumerState<MembershipPlanEditSheet> {
  late final _name = TextEditingController(text: widget.plan.name);
  late final _description = TextEditingController(text: widget.plan.description ?? '');
  late final _joining = TextEditingController(text: (widget.plan.joiningFeeInr ?? 0) > 0 ? '${widget.plan.joiningFeeInr}' : '');
  late final _deposit = TextEditingController(text: (widget.plan.securityDepositInr ?? 0) > 0 ? '${widget.plan.securityDepositInr}' : '');
  late final _badge = TextEditingController(text: widget.plan.badgeText ?? 'Popular');
  late final _newBenefit = TextEditingController();

  late String _category = _initialCategory();
  late bool _showBadge = (widget.plan.badgeText ?? '').trim().isNotEmpty;
  late List<String> _features = [...widget.plan.features];
  bool _saving = false;
  String? _error;

  String _initialCategory() {
    final c = widget.plan.category;
    return c != null && planCategories.contains(c) ? c : (c == null || c.isEmpty ? planCategories.first : c);
  }

  List<String> get _categoryOptions => planCategories.contains(_category) ? planCategories : [...planCategories, _category];

  @override
  void dispose() {
    for (final c in [_name, _description, _joining, _deposit, _badge, _newBenefit]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addBenefit() {
    final text = _newBenefit.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!_features.contains(text)) _features = [..._features, text];
      _newBenefit.clear();
    });
  }

  Future<void> _save() async {
    final repo = ref.read(membershipRepositoryProvider);
    setState(() {
      _error = null;
    });
    try {
      final MembershipPlan saved;
      if (widget.section == PlanEditSection.benefits) {
        // A half-typed benefit still in the box is kept rather than silently dropped.
        _addBenefit();
        setState(() => _saving = true);
        saved = await repo.updatePlan(widget.plan.id, features: _features.map((f) => f.trim()).where((f) => f.isNotEmpty).toList());
      } else {
        final name = _name.text.trim();
        if (name.length < 2) {
          setState(() => _error = 'Plan name is required.');
          return;
        }
        if (name.toLowerCase() != widget.plan.name.trim().toLowerCase()) {
          final plans = await repo.getFacilityPlans(widget.plan.facilityId);
          if (plans.any((p) => p.id != widget.plan.id && p.name.trim().toLowerCase() == name.toLowerCase())) {
            setState(() => _error = 'Another plan already has this name.');
            return;
          }
        }
        if (_description.text.length > 200) {
          setState(() => _error = "Description can't be more than 200 characters.");
          return;
        }
        setState(() => _saving = true);
        saved = await repo.updatePlan(
          widget.plan.id,
          name: name,
          description: _description.text,
          category: _category,
          joiningFeeInr: int.tryParse(_joining.text.trim()) ?? 0,
          securityDepositInr: int.tryParse(_deposit.text.trim()) ?? 0,
          setBadge: true,
          badgeText: _showBadge ? (_badge.text.trim().isEmpty ? 'Popular' : _badge.text.trim()) : null,
        );
      }
      if (mounted) Navigator.of(context).pop(saved);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  Widget _locked(String label, String value) => InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.lock_outline, size: 16)),
        child: Text(value),
      );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final benefits = widget.section == PlanEditSection.benefits;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(benefits ? 'Edit Benefits' : 'Edit Plan', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            if (benefits) ...[
              for (final f in _features)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 18, color: tokens.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(f)),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _features = _features.where((x) => x != f).toList()),
                      ),
                    ],
                  ),
                ),
              if (_features.isEmpty) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Text('No benefits yet.', style: TextStyle(color: tokens.textSecondary))),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newBenefit,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addBenefit(),
                      decoration: const InputDecoration(labelText: 'Add a benefit', hintText: 'e.g. Free locker'),
                    ),
                  ),
                  IconButton.filledTonal(onPressed: _addBenefit, icon: const Icon(Icons.add)),
                ],
              ),
            ] else ...[
              TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: 'Plan Name *', counterText: '')),
              const SizedBox(height: AppSpacing.md),
              _locked('Duration', planWizardDurationLabel(widget.plan.durationDays)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _description,
                maxLines: 2,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppDropdown<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Plan Category'),
                items: [for (final c in _categoryOptions) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: AppSpacing.md),
              _locked('Price (₹)', '₹ ${widget.plan.priceInr}'),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _joining,
                      decoration: const InputDecoration(labelText: 'Joining Fee (₹)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _deposit,
                      decoration: const InputDecoration(labelText: 'Security Deposit (₹)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show a badge on this plan'),
                value: _showBadge,
                onChanged: (v) => setState(() => _showBadge = v),
              ),
              if (_showBadge) TextField(controller: _badge, maxLength: 20, decoration: const InputDecoration(labelText: 'Badge text')),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: tokens.destructive)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save Changes')),
          ],
        ),
      ),
    );
  }
}
