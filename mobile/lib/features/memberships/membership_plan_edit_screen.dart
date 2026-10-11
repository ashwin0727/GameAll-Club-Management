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
import 'form_section.dart';
import 'plan_wizard.dart' show planCategories, planWizardDurationLabel;

/// Which part of a plan the sheet edits: the Overview fields, or its Benefits list.
enum PlanEditSection { overview, benefits }

/// Edit a plan, as a full page. The price and duration are shown but locked — members may already be on the plan, so
/// what it costs and how long it runs stay as created. Everything else can change: name, description,
/// category, badge, joining fee, security deposit, and (in the Benefits tab) the benefits.
///
/// [memberCount] and [slotCount] only fill the summary card at the top. Pops the saved
/// [MembershipPlan], or null when dismissed.
class MembershipPlanEditScreen extends ConsumerStatefulWidget {
  const MembershipPlanEditScreen({
    super.key,
    required this.plan,
    this.section = PlanEditSection.overview,
    this.memberCount,
    this.slotCount,
  });

  final MembershipPlan plan;
  final PlanEditSection section;
  final int? memberCount;
  final int? slotCount;

  @override
  ConsumerState<MembershipPlanEditScreen> createState() => _MembershipPlanEditScreenState();
}

class _MembershipPlanEditScreenState extends ConsumerState<MembershipPlanEditScreen> {
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
    return c == null || c.isEmpty ? planCategories.first : c;
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
    setState(() => _error = null);
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
        setState(() => _saving = true);
        if (name.toLowerCase() != widget.plan.name.trim().toLowerCase()) {
          final plans = await repo.getFacilityPlans(widget.plan.facilityId);
          if (plans.any((p) => p.id != widget.plan.id && p.name.trim().toLowerCase() == name.toLowerCase())) {
            setState(() {
              _saving = false;
              _error = 'Another plan already has this name.';
            });
            return;
          }
        }
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final benefits = widget.section == PlanEditSection.benefits;
    final plan = widget.plan;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(benefits ? 'Edit Benefits' : 'Edit Plan')),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            decoration: BoxDecoration(color: tokens.surface0, border: Border(top: BorderSide(color: tokens.borderColor))),
            child: Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel'))),
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
            _summary(tokens, plan),
            const SizedBox(height: AppSpacing.md),
            if (benefits) ..._benefitsFields(tokens) else ..._overviewFields(),
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

  /// The plan at a glance — status, how many members are on it and how many slots it has.
  Widget _summary(AppColorTokens tokens, MembershipPlan plan) {
    Widget cell(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption(context)),
              const SizedBox(height: 2),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.rowTitle(context)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
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
              Expanded(child: Text(plan.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.sectionTitle(context))),
              TintPill(plan.isActive ? 'Active' : 'Inactive', plan.isActive ? tokens.success : tokens.destructive),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              cell('Duration', planWizardDurationLabel(plan.durationDays)),
              cell('Price', Formatters.currencyInr(plan.priceInr)),
              cell('Members', widget.memberCount?.toString() ?? '—'),
              cell('Slots', widget.slotCount?.toString() ?? '—'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Created ${Formatters.dateShort(plan.createdAt.toLocal())}', style: AppTypography.caption(context)),
        ],
      ),
    );
  }

  List<Widget> _overviewFields() => [
        FormSection(
          title: 'Plan Details',
          icon: Icons.edit_note_rounded,
          children: [
            TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: 'Plan name *', counterText: '')),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _description, maxLines: 2, maxLength: 200, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: AppSpacing.sm),
            AppDropdown<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Plan category'),
              items: [for (final c in _categoryOptions) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
          ],
        ),
        FormSection(
          title: 'Pricing',
          subtitle: "The price and duration can't be changed once a plan is created.",
          icon: Icons.payments_outlined,
          children: [
            Row(
              children: [
                Expanded(child: LockedField(label: 'Price (₹)', value: '${widget.plan.priceInr}')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: LockedField(label: 'Duration', value: planWizardDurationLabel(widget.plan.durationDays))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _joining,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                    decoration: const InputDecoration(labelText: 'Joining fee (₹)'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _deposit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                    decoration: const InputDecoration(labelText: 'Security deposit (₹)'),
                  ),
                ),
              ],
            ),
          ],
        ),
        FormSection(
          title: 'Badge',
          subtitle: "Shown as a small tag on this plan's card.",
          icon: Icons.local_offer_outlined,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Show a badge on this plan', style: AppTypography.rowTitle(context)),
              value: _showBadge,
              onChanged: (v) => setState(() => _showBadge = v),
            ),
            if (_showBadge) TextField(controller: _badge, maxLength: 20, decoration: const InputDecoration(labelText: 'Badge text', counterText: '')),
          ],
        ),
      ];

  List<Widget> _benefitsFields(AppColorTokens tokens) => [
        FormSection(
          title: 'Benefits',
          subtitle: 'What members get with this plan.',
          icon: Icons.verified_outlined,
          children: [
            if (_features.isEmpty) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Text('No benefits yet.', style: AppTypography.secondary(context))),
            for (final f in _features)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Container(
                  padding: const EdgeInsets.only(left: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: tokens.borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: tokens.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(f, style: AppTypography.rowTitle(context))),
                      IconButton(
                        tooltip: 'Remove',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _features = _features.where((x) => x != f).toList()),
                      ),
                    ],
                  ),
                ),
              ),
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
                const SizedBox(width: AppSpacing.sm),
                IconButton.filledTonal(onPressed: _addBenefit, icon: const Icon(Icons.add)),
              ],
            ),
          ],
        ),
      ];
}
