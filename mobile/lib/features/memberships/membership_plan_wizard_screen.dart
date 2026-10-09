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
import '../../data/models/membership_session.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../authentication/session_controller.dart';
import '../../core/routing/page_transitions.dart';
import 'duplicate_guards.dart';
import 'plan_created_screen.dart';
import 'plan_wizard.dart';

/// Memberships → Plans → New plan — mirrors the web's Create Membership Plan wizard
/// (src/features/memberships/components/create-plan-wizard-page.tsx), step for step:
///
///   1 Plan Details        — name, description, category, badge
///   2 Plan Configuration  — time-based or recurring, duration, price, joining fee, deposit
///   3 Court Access        — which courts, playing days, time slots, booking rules
///   4 Review & Create     — confirm everything, then publish
///
/// Saving creates the plan and then one recurring session slot per time slot added in step 3 — the
/// same two calls the web makes — so a member who joins the plan is offered exactly those slots.
/// Pops `true` once the plan exists.
class MembershipPlanWizardScreen extends ConsumerStatefulWidget {
  const MembershipPlanWizardScreen({super.key});

  @override
  ConsumerState<MembershipPlanWizardScreen> createState() => _MembershipPlanWizardScreenState();
}

class _CourtOption {
  const _CourtOption({required this.id, required this.name, required this.facilitySportId, required this.sportName, required this.indoor});
  final String id;
  final String name;
  final String facilitySportId;
  final String sportName;
  final bool indoor;
}

class _MembershipPlanWizardScreenState extends ConsumerState<MembershipPlanWizardScreen> {
  final _d = PlanWizardDraft();

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _badge = TextEditingController(text: 'Popular');
  final _price = TextEditingController();
  final _joiningFee = TextEditingController();
  final _deposit = TextEditingController();
  final _customMonths = TextEditingController();

  int _step = 0;
  final Set<String> _touched = {};
  bool _customDurationOpen = false;

  List<_CourtOption> _courts = const [];

  /// Every plan and slot that already exists — a new plan can't repeat one of them exactly.
  List<MembershipPlan> _existingPlans = const [];
  List<AssignableBatch> _existingBatches = const [];
  bool _loadingCourts = true;

  bool _saving = false;
  String? _error;

  // A plan that was created but whose time slots only partly saved must not be created a second
  // time on retry (its name is unique) — remember what already exists and carry on from there.
  MembershipPlan? _createdPlan;
  final Set<String> _savedWindowIds = {};

  bool get _planLocked => _createdPlan != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCourts());
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _badge, _price, _joiningFee, _deposit, _customMonths]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _loadCourts() async {
    final fid = _facilityId;
    if (fid == null) {
      setState(() => _loadingCourts = false);
      return;
    }
    try {
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(fid);
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final sports = await sportsRepo.getActiveSports();
      final facilitySports = await sportsRepo.getFacilitySports(fid);
      String sportName(String facilitySportId) {
        final fs = facilitySports.where((f) => f.id == facilitySportId).firstOrNull;
        if (fs == null) return 'Sport';
        if (fs.customSportName != null && fs.customSportName!.isNotEmpty) return fs.customSportName!;
        return sports.where((s) => s.id == fs.sportId).firstOrNull?.name ?? 'Sport';
      }

      final courts = [
        for (final a in areas)
          if (a.status == 'ACTIVE' && !a.archived)
            _CourtOption(
              id: a.id,
              name: a.name,
              facilitySportId: a.facilitySportId,
              sportName: sportName(a.facilitySportId),
              indoor: a.areaType == 'INDOOR',
            ),
      ]..sort((a, b) => a.name.compareTo(b.name));
      final repo = ref.read(membershipRepositoryProvider);
      final plans = await repo.getFacilityPlans(fid);
      final batches = await repo.listAssignableBatches(fid);
      if (mounted) {
        setState(() {
          _courts = courts;
          _existingPlans = plans;
          _existingBatches = batches;
        });
      }
    } on AppException {
      // The step shows "no active courts" and the owner can retry by re-entering the screen.
    } finally {
      if (mounted) setState(() => _loadingCourts = false);
    }
  }

  // ── navigation ─────────────────────────────────────────────────────────

  /// The existing plan this draft would exactly repeat (same courts, days and hours), if any.
  MembershipPlan? get _duplicatePlan => findDuplicatePlan(
        [for (final w in _d.timeWindows) SlotShape(courtId: w.courtId, daysOfWeek: w.daysOfWeek, startTime: w.startTime, endTime: w.endTime)],
        _existingPlans,
        _existingBatches,
      );

  Map<String, String> get _errors {
    final errors = planFieldErrors(_step, _d);
    final dup = _duplicatePlan;
    if (_step == 2 && dup != null && !_planLocked) errors['timeWindows'] = duplicatePlanMessage(dup.name);
    return errors;
  }
  String? _show(String field) => _touched.contains(field) ? _errors[field] : null;

  void _next() {
    final errors = _errors;
    if (errors.isNotEmpty) {
      setState(() => _touched.addAll(errors.keys));
      return;
    }
    setState(() {
      _touched.clear();
      _step = (_step + 1).clamp(0, 3);
    });
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
    if (_planLocked && step < 2) return;
    setState(() {
      _touched.clear();
      _step = step;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    for (var s = 0; s <= 2; s++) {
      if (validatePlanStep(s, _d) != null) {
        setState(() {
          _step = s;
          _touched.addAll(planFieldErrors(s, _d).keys);
        });
        return;
      }
    }
    final fid = _facilityId;
    if (fid == null) {
      setState(() => _error = 'Complete your facility setup before creating a plan.');
      return;
    }
    final dup = _duplicatePlan;
    if (dup != null && !_planLocked) {
      setState(() {
        _step = 2;
        _touched.add('timeWindows');
        _error = duplicatePlanMessage(dup.name);
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(membershipRepositoryProvider);
      final plan = _createdPlan ??
          await repo.createPlan(MembershipPlanInput(
            facilityId: fid,
            name: _d.name.trim(),
            description: _d.description.trim().isEmpty ? null : _d.description.trim(),
            category: _d.category,
            planType: _d.planType,
            priceInr: _d.priceInr,
            durationDays: _d.durationDays,
            joiningFeeInr: _d.joiningFeeInr > 0 ? _d.joiningFeeInr : null,
            securityDepositInr: _d.securityDepositInr > 0 ? _d.securityDepositInr : null,
            badgeText: _d.showBadge ? (_d.badgeText.trim().isEmpty ? 'Popular' : _d.badgeText.trim()) : null,
            features: composePlanFeatures(_d),
          ));
      _createdPlan = plan;

      // The time slots become real recurring slots now that the plan they belong to exists.
      final sessionRepo = ref.read(membershipSessionRepositoryProvider);
      for (final w in _d.timeWindows) {
        if (_savedWindowIds.contains(w.id)) continue;
        final court = _courts.where((c) => c.id == w.courtId).firstOrNull;
        if (court == null) continue;
        await sessionRepo.createBatch(MembershipBatchInput(
          facilityId: fid,
          planId: plan.id,
          facilitySportId: court.facilitySportId,
          courtId: w.courtId,
          name: '${plan.name} — ${w.startTime}',
          daysOfWeek: [...w.daysOfWeek]..sort(),
          startTime: w.startTime,
          endTime: w.endTime,
          capacity: w.capacity,
        ));
        _savedWindowIds.add(w.id);
      }
      if (!mounted) return;
      // The plan's own slots, for the plan page the success screen can open (best effort).
      var planBatches = const <AssignableBatch>[];
      try {
        planBatches = await repo.listAssignableBatches(fid, planId: plan.id);
      } on AppException catch (_) {}
      if (!mounted) return;
      final sports = {
        for (final id in _d.courtIds) _courts.where((c) => c.id == id).firstOrNull?.sportName,
      }.whereType<String>().where((n) => n.isNotEmpty).join(', ');
      // Replacing this route completes it with true, so the plan list behind refreshes at once.
      Navigator.of(context).pushReplacement<bool, bool>(
        AppPageRoute<bool>(
          builder: (_) => PlanCreatedScreen(plan: plan, facilityId: fid, sportLabel: sports.isEmpty ? null : sports, batches: planBatches),
        ),
        result: true,
      );
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final last = _step == 3;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Create Plan')),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            decoration: BoxDecoration(color: tokens.surface0, border: Border(top: BorderSide(color: tokens.borderColor))),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || (_planLocked && _step <= 2) ? null : _back,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(_step == 0 ? 'Cancel' : 'Back'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : (last ? _submit : _next),
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  last ? (_planLocked ? 'Finish saving slots' : 'Create Plan') : 'Next: ${planWizardSteps[_step + 1].title}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!last) ...[const SizedBox(width: 6), const Icon(Icons.arrow_forward, size: 18)],
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: ListView(
          // A list per step, so each opens at its top — one shared list kept its scroll position and
          // opened the next step part-way down it.
          key: ValueKey(_step),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _WizardStepper(
              current: _step,
              furthest: furthestReachablePlanStep(_d),
              onSelect: _goTo,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_step == 0) ..._stepDetails(tokens),
            if (_step == 1) ..._stepConfiguration(tokens),
            if (_step == 2) ..._stepCourtAccess(tokens),
            if (_step == 3) ..._stepReview(tokens),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
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

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text, style: AppTypography.caption(context)),
      );

  Widget _error_(String? message) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(message, style: TextStyle(fontSize: 12, color: context.tokens.destructive)),
        );

  Widget _note(IconData icon, Color color, String title, String body) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: AppTypography.caption(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: tokens.electricBlue.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: tokens.electricBlue),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: context.tokens.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );

  // ── step 1 — Plan Details ──────────────────────────────────────────────

  List<Widget> _stepDetails(AppColorTokens tokens) {
    return [
      _heading('Plan Details', 'Enter the basic information for this membership plan.'),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        onChanged: (v) => setState(() => _d.name = v),
        decoration: InputDecoration(
          labelText: 'Plan Name *',
          hintText: 'Monthly Membership',
          errorText: _show('name'),
          helperText: 'e.g. Monthly Membership, 3 Months Plan, Weekend Plan',
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _description,
        maxLines: 3,
        maxLength: 200,
        onChanged: (v) => setState(() => _d.description = v),
        decoration: InputDecoration(
          labelText: 'Description',
          hintText: 'Perfect for regular players who want consistent court access.',
          errorText: _show('description'),
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppDropdown<String>(
        initialValue: _d.category,
        decoration: const InputDecoration(labelText: 'Plan Category', helperText: 'Choose a category to group this plan.'),
        items: [for (final c in planCategories) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => setState(() => _d.category = v ?? _d.category),
      ),
      const SizedBox(height: AppSpacing.md),
      Text('Plan Badge', style: AppTypography.rowTitle(context)),
      _hint("Shown as a small tag on this plan's card in the plan list."),
      const SizedBox(height: AppSpacing.sm),
      _switchRow('Show a badge on this plan', _d.showBadge, (v) => setState(() => _d.showBadge = v)),
      if (_d.showBadge) ...[
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _badge,
          maxLength: 24,
          onChanged: (v) => setState(() => _d.badgeText = v),
          decoration: const InputDecoration(labelText: 'Badge text', hintText: 'Popular'),
        ),
      ],
    ];
  }

  // ── step 2 — Plan Configuration ────────────────────────────────────────

  Widget _planTypeCard({required bool selected, required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? tokens.primary.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: selected ? tokens.primary : tokens.borderColor, width: selected ? 1.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? tokens.primary : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: selected ? null : Border.all(color: tokens.borderColor),
              ),
              child: Icon(icon, size: 19, color: selected ? tokens.onPrimary : tokens.textSecondary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.caption(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setDuration(int days) => setState(() => _d.durationDays = days);

  Widget _durationPicker() {
    final tokens = context.tokens;
    final presetLabel = durationPresets.where((p) => p.days == _d.durationDays).map((p) => p.label).firstOrNull ?? 'Custom';
    final customActive = _customDurationOpen || presetLabel == 'Custom';
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final p in durationPresets)
          if (p.label != 'Custom')
            _presetButton(
              label: p.label,
              selected: !customActive && _d.durationDays == p.days,
              onTap: () {
                _customDurationOpen = false;
                _setDuration(p.days!);
              },
            )
          else if (customActive)
            SizedBox(
              width: 140,
              height: 44,
              child: TextField(
                controller: _customMonths,
                autofocus: _customDurationOpen,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (raw) {
                  final months = int.tryParse(raw.trim()) ?? 0;
                  // Blank / zero means "no valid value yet" — 0 days, which validation blocks Next on.
                  _setDuration(months >= 1 ? months * 30 : 0);
                },
                decoration: InputDecoration(
                  hintText: 'Months',
                  suffixText: _customMonths.text.trim() == '1' ? 'month' : 'months',
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: _show('durationDays') != null ? tokens.destructive : tokens.primary),
                  ),
                ),
              ),
            )
          else
            _presetButton(
              label: 'Custom',
              selected: false,
              onTap: () {
                // A value that happens to equal a preset would keep that preset looking selected too,
                // so nudge off it — only Custom should be active.
                final days = durationPresets.any((pp) => pp.days == _d.durationDays) ? _d.durationDays + 1 : _d.durationDays;
                _customMonths.text = '${planMonths(days)}';
                setState(() {
                  _customDurationOpen = true;
                  _d.durationDays = days;
                });
              },
            ),
      ],
    );
  }

  Widget _presetButton({required String label, required bool selected, required VoidCallback onTap}) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primary.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? tokens.primary : tokens.borderColor, width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? tokens.primary : tokens.textPrimary)),
      ),
    );
  }

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? helper,
    String? error,
    required ValueChanged<int> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (v) => setState(() => onChanged(int.tryParse(v.trim()) ?? 0)),
      decoration: InputDecoration(labelText: label, hintText: hint, prefixText: '₹ ', helperText: helper, errorText: error),
    );
  }

  List<Widget> _stepConfiguration(AppColorTokens tokens) {
    final recurring = _d.isRecurring;
    return [
      _heading('Plan Configuration', 'Set the duration, pricing and billing options for this plan.'),
      Text('Plan Type *', style: AppTypography.rowTitle(context)),
      const SizedBox(height: AppSpacing.sm),
      _planTypeCard(
        selected: !recurring,
        icon: Icons.calendar_today_outlined,
        title: 'Time Based',
        subtitle: 'Fixed duration (e.g. 1 month, 3 months)',
        onTap: () => setState(() => _d.planType = 'TIME_BASED'),
      ),
      const SizedBox(height: AppSpacing.sm),
      _planTypeCard(
        selected: recurring,
        icon: Icons.all_inclusive_rounded,
        title: 'Recurring',
        subtitle: 'Auto-renewal (Ongoing)',
        onTap: () => setState(() => _d.planType = 'RECURRING'),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(recurring ? 'Billing Interval *' : 'Duration *', style: AppTypography.rowTitle(context)),
      if (recurring) _hint('Choose how often the membership will be renewed automatically.'),
      const SizedBox(height: AppSpacing.sm),
      _durationPicker(),
      _error_(_show('durationDays')),
      const SizedBox(height: AppSpacing.lg),
      _moneyField(
        controller: _price,
        label: recurring ? 'Price per billing cycle (₹) *' : 'Price (₹) *',
        hint: '2500',
        error: _show('priceInr'),
        onChanged: (v) => _d.priceInr = v,
      ),
      const SizedBox(height: AppSpacing.md),
      if (recurring) ...[
        InputDecorator(
          decoration: appSelectDecoration(context, labelText: 'Billing Frequency'),
          child: Text('Auto-renewal', style: TextStyle(color: tokens.textSecondary)),
        ),
        const SizedBox(height: AppSpacing.md),
        _note(Icons.all_inclusive_rounded, tokens.primary, 'Recurring Payment', 'The membership will be automatically renewed at the selected interval.'),
        const SizedBox(height: AppSpacing.sm),
        _note(Icons.credit_card_outlined, tokens.electricBlue, 'Auto-Renewal', 'Payment will be charged automatically using the saved payment method.'),
      ] else
        _note(Icons.credit_card_outlined, tokens.primary, 'One-time Payment',
            'Members pay the full membership amount once. The membership remains active until its expiry date.'),
      const SizedBox(height: AppSpacing.lg),
      _moneyField(
        controller: _joiningFee,
        label: 'Joining Fee (Optional)',
        hint: 'Enter joining fee',
        helper: 'One-time fee charged during registration (e.g. ₹500).',
        error: _show('joiningFeeInr'),
        onChanged: (v) => _d.joiningFeeInr = v,
      ),
      const SizedBox(height: AppSpacing.md),
      _moneyField(
        controller: _deposit,
        label: 'Security Deposit (Optional)',
        hint: 'Enter security deposit',
        helper: 'Refundable amount (e.g. ₹1,000).',
        error: _show('securityDepositInr'),
        onChanged: (v) => _d.securityDepositInr = v,
      ),
      const SizedBox(height: AppSpacing.md),
      _banner(
        recurring
            ? 'This membership will automatically renew ${planBillingIntervalLabel(_d.durationDays)}. Members can cancel at any time from their account or by contacting the club.'
            : 'This membership has a fixed duration and will expire automatically at the end of the selected period.',
      ),
    ];
  }

  // ── step 3 — Court Access ──────────────────────────────────────────────

  Widget _numbered(int n, String title, String subtitle, Widget child, {Widget? trailing}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tokens.surface2, shape: BoxShape.circle),
            child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.textSecondary)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                    ?trailing,
                  ],
                ),
                Text(subtitle, style: AppTypography.caption(context)),
                const SizedBox(height: AppSpacing.sm),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(PlanTimeWindow w, {required bool start}) async {
    final current = start ? w.startTime : w.endTime;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 7, minute: int.tryParse(parts[1]) ?? 0),
    );
    if (picked == null) return;
    final text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => start ? w.startTime = text : w.endTime = text);
  }

  void _addWindow() {
    if (_d.courtIds.isEmpty) return;
    setState(() {
      _d.timeWindows.add(PlanTimeWindow(
        id: newPlanWindowId(),
        courtId: _d.courtIds.first,
        daysOfWeek: _d.playingDays.isNotEmpty ? [..._d.playingDays] : [1, 2, 3, 4, 5],
      ));
    });
  }

  List<Widget> _stepCourtAccess(AppColorTokens tokens) {
    final allSelected = _courts.isNotEmpty && _courts.every((c) => _d.courtIds.contains(c.id));
    return [
      _heading('Court Access', 'Select which courts are accessible and set preferred days & time slots for this plan.'),
      _numbered(
        1,
        'Select Courts',
        'Choose which courts members can book under this plan.',
        _loadingCourts
            ? Text('Loading courts…', style: AppTypography.caption(context))
            : _courts.isEmpty
                ? Text('No active courts are set up at this facility yet.', style: AppTypography.caption(context))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in _courts) _courtTile(c, tokens),
                      _error_(_show('courtIds')),
                    ],
                  ),
        trailing: _courts.isEmpty
            ? null
            : InkWell(
                onTap: () => setState(() {
                  _d.courtIds = allSelected ? [] : _courts.map((c) => c.id).toList();
                  _dropWindowsOnUnselectedCourts();
                }),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: allSelected,
                        onChanged: (_) => setState(() {
                          _d.courtIds = allSelected ? [] : _courts.map((c) => c.id).toList();
                          _dropWindowsOnUnselectedCourts();
                        }),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('All', style: AppTypography.caption(context)),
                  ],
                ),
              ),
      ),
      _numbered(
        2,
        'Set Playing Days',
        'Select available days for this membership plan.',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(planDayAbbr[i]),
                    selected: _d.playingDays.contains(i),
                    showCheckmark: false,
                    onSelected: (on) => setState(() {
                      if (on) {
                        _d.playingDays = [..._d.playingDays, i]..sort();
                      } else {
                        _d.playingDays = _d.playingDays.where((d) => d != i).toList();
                      }
                    }),
                  ),
              ],
            ),
            _error_(_show('playingDays')),
          ],
        ),
      ),
      _numbered(
        3,
        'Set Playing Time Slots',
        'Choose the time slots members can book on selected days.',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _d.courtIds.isEmpty ? null : _addWindow,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Time Slot'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_d.timeWindows.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: tokens.borderColor),
                ),
                child: Text(
                  _d.courtIds.isEmpty ? 'Select a court above, then add a time slot.' : 'No time slots yet — add one above.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption(context),
                ),
              )
            else
              for (final w in _d.timeWindows) _windowCard(w, tokens),
            _error_(_show('timeWindows')),
          ],
        ),
      ),
      _numbered(
        4,
        'Slot Booking Rules (Optional)',
        'Set additional rules for how members can book courts.',
        Column(
          children: [
            _switchRow('Allow Advance Booking', _d.allowAdvanceBooking, (v) => setState(() => _d.allowAdvanceBooking = v)),
            const SizedBox(height: AppSpacing.sm),
            _switchRow('Limit Consecutive Slots', _d.limitConsecutiveSlots, (v) => setState(() => _d.limitConsecutiveSlots = v)),
          ],
        ),
      ),
      _note(
        Icons.lock_outline_rounded,
        tokens.violet,
        'Membership Reserved Time',
        'Selected court capacity is reserved for members on this plan. Guest bookings cannot use it unless the owner explicitly releases it from the Release Member Time to Guest workflow.',
      ),
    ];
  }

  void _dropWindowsOnUnselectedCourts() {
    // A slot on a court that is no longer selected would save against a court the plan can't use.
    for (final w in _d.timeWindows) {
      if (!_d.courtIds.contains(w.courtId) && _d.courtIds.isNotEmpty) w.courtId = _d.courtIds.first;
    }
    if (_d.courtIds.isEmpty) _d.timeWindows = [];
  }

  Widget _courtTile(_CourtOption c, AppColorTokens tokens) {
    final selected = _d.courtIds.contains(c.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => setState(() {
          _d.courtIds = selected ? _d.courtIds.where((x) => x != c.id).toList() : [..._d.courtIds, c.id];
          _dropWindowsOnUnselectedCourts();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? tokens.primary.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: selected ? tokens.primary : tokens.borderColor, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.check_circle : Icons.circle_outlined, size: 22, color: selected ? tokens.primary : tokens.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text('${c.indoor ? 'Indoor' : 'Outdoor'} Court · ${c.sportName}', style: AppTypography.caption(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _windowCard(PlanTimeWindow w, AppColorTokens tokens) {
    final overlap = findOverlap(_d.timeWindows, w);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: tokens.borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickTime(w, start: true),
                  child: AppSelectField(
                    decoration: const InputDecoration(labelText: 'Start'),
                    child: Text(Formatters.time12h(w.startTime)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: InkWell(
                  onTap: () => _pickTime(w, start: false),
                  child: AppSelectField(
                    decoration: const InputDecoration(labelText: 'End'),
                    child: Text(Formatters.time12h(w.endTime)),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove this time slot',
                onPressed: () => setState(() => _d.timeWindows.removeWhere((x) => x.id == w.id)),
                icon: Icon(Icons.delete_outline, color: tokens.textSecondary),
              ),
            ],
          ),
          if (_d.courtIds.length > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            AppDropdown<String>(
              initialValue: w.courtId,
              decoration: const InputDecoration(labelText: 'Court'),
              items: [
                for (final id in _d.courtIds)
                  DropdownMenuItem(value: id, child: Text(_courts.where((c) => c.id == id).firstOrNull?.name ?? id)),
              ],
              onChanged: (v) => setState(() => w.courtId = v ?? w.courtId),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < 7; i++)
                if (_d.playingDays.contains(i) || w.daysOfWeek.contains(i))
                  FilterChip(
                    label: Text(planDayAbbr[i]),
                    selected: w.daysOfWeek.contains(i),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (on) => setState(() {
                      w.daysOfWeek = on ? ([...w.daysOfWeek, i]..sort()) : w.daysOfWeek.where((d) => d != i).toList();
                    }),
                  ),
            ],
          ),
          if (overlap != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: tokens.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Overlaps another slot on the same court and day — allowed (courts can share capacity), just flagging it.',
                    style: TextStyle(fontSize: 12, color: tokens.warning),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── step 4 — Review & Create ───────────────────────────────────────────

  Widget _reviewSection(int n, String title, int editStep, List<Widget> children, {bool editable = true}) {
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
                if (editable && !(_planLocked && editStep < 2))
                  TextButton.icon(
                    onPressed: () => _goTo(editStep),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
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
            SizedBox(width: 128, child: Text(k, style: AppTypography.caption(context))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  String _inr(int v) => Formatters.currencyInr(v);

  List<Widget> _stepReview(AppColorTokens tokens) {
    final recurring = _d.isRecurring;
    final selectedCourts = [for (final id in _d.courtIds) _courts.where((c) => c.id == id).firstOrNull].whereType<_CourtOption>().toList();
    final sports = {for (final c in selectedCourts) c.sportName}.join(', ');
    final days = [for (var i = 0; i < 7; i++) if (_d.playingDays.contains(i)) planDayAbbr[i]].join(', ');
    final slotTimes = _d.timeWindows.map((w) => '${Formatters.time12h(w.startTime)} – ${Formatters.time12h(w.endTime)}').toList();
    final priceText = recurring ? '${_inr(_d.priceInr)} / ${planPriceUnit(_d.durationDays)}' : _inr(_d.priceInr);

    return [
      _heading('Review & Create', 'Please review all the plan details below. You can go back and make changes if needed.'),
      if (_planLocked)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _banner('The plan "${_createdPlan!.name}" has been created. Only its time slots still need saving.'),
        ),
      _reviewSection(1, 'Plan Details', 0, [
        Row(
          children: [
            Expanded(
              child: Text(_d.name.trim().isEmpty ? 'New Plan' : _d.name.trim(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            if (_d.showBadge)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: tokens.primary.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                child: Text(_d.badgeText.trim().isEmpty ? 'Popular' : _d.badgeText.trim(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tokens.primary)),
              ),
          ],
        ),
        Text(_d.category, style: AppTypography.caption(context)),
        const SizedBox(height: AppSpacing.sm),
        _kv('Plan Type', recurring ? 'Recurring' : 'Time Based'),
        _kv('Description', _d.description.trim().isEmpty ? '—' : _d.description.trim()),
        _kv('Status', 'Active (after creation)'),
      ]),
      _reviewSection(2, 'Plan Configuration', 1, [
        _kv('Plan Type', recurring ? 'Recurring' : 'Time Based'),
        _kv(recurring ? 'Billing Interval' : 'Duration', recurring ? planBillingIntervalLabel(_d.durationDays) : planWizardDurationLabel(_d.durationDays)),
        _kv('Price', priceText),
        _kv('Payment', recurring ? 'Recurring Payment' : 'One-time Payment'),
        _kv('Joining Fee', _d.joiningFeeInr > 0 ? _inr(_d.joiningFeeInr) : 'No Joining Fee'),
        _kv('Security Deposit', _d.securityDepositInr > 0 ? '${_inr(_d.securityDepositInr)} (Refundable)' : 'No Security Deposit'),
      ]),
      _reviewSection(3, 'Court Access', 2, [
        _kv('Sport', sports.isEmpty ? '—' : sports),
        _kv('Selected Courts', selectedCourts.isEmpty ? '—' : selectedCourts.map((c) => '${c.name} (${c.indoor ? 'Indoor' : 'Outdoor'})').join(', ')),
        _kv('Playing Days', days.isEmpty ? '—' : days),
        _kv('Time Slots', slotTimes.isEmpty ? '—' : slotTimes.join('\n')),
      ]),
      _note(
        Icons.info_outline,
        tokens.textSecondary,
        'Membership Access',
        'Members assigned to this plan will receive access to the selected courts and recurring time windows during their active membership period. ${recurring ? 'Access continues while the recurring membership remains active.' : 'Access ends when the membership expires.'}',
      ),
      const SizedBox(height: AppSpacing.sm),
      _note(
        Icons.shield_outlined,
        tokens.textSecondary,
        'Reserved Membership Capacity',
        'Selected court capacity will be reserved for members. Guest bookings cannot use this reserved capacity unless the owner explicitly releases it through the Guest Booking workflow.',
      ),
      const SizedBox(height: AppSpacing.md),
      _reviewSection(4, 'Final Summary', 0, [
        _kv('Membership Plan', _d.name.trim().isEmpty ? '—' : _d.name.trim()),
        _kv('Price', priceText),
        _kv(recurring ? 'Billing Interval' : 'Membership Duration',
            recurring ? planBillingIntervalLabel(_d.durationDays) : planWizardDurationLabel(_d.durationDays)),
        _kv('Court Access', selectedCourts.isEmpty ? '—' : selectedCourts.map((c) => c.name).join(', ')),
        _kv('Playing Schedule', days.isEmpty || slotTimes.isEmpty ? '—' : '$days, ${slotTimes.join('; ')}'),
        if (_d.joiningFeeInr > 0) _kv('Joining Fee', _inr(_d.joiningFeeInr)),
        if (_d.securityDepositInr > 0) _kv('Security Deposit', _inr(_d.securityDepositInr)),
      ], editable: false),
      if (_error != null)
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: tokens.destructive.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.destructive.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Unable to create membership plan.', style: TextStyle(fontWeight: FontWeight.w700, color: tokens.destructive)),
              const SizedBox(height: 2),
              Text(_error!, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  OutlinedButton(onPressed: _saving ? null : _submit, child: const Text('Try Again')),
                  const SizedBox(width: AppSpacing.sm),
                  if (!_planLocked) OutlinedButton(onPressed: () => _goTo(0), child: const Text('Go Back & Edit')),
                ],
              ),
            ],
          ),
        ),
    ];
  }
}

/// The four circles across the top: filled for the current step, ticked once done, and only the
/// steps already unlocked can be tapped.
class _WizardStepper extends StatelessWidget {
  const _WizardStepper({required this.current, required this.furthest, required this.onSelect});

  final int current;
  final int furthest;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < planWizardSteps.length; i++)
          Expanded(
            child: InkWell(
              onTap: i <= furthest || i <= current ? () => onSelect(i) : null,
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
                              color: i == planWizardSteps.length - 1 ? Colors.transparent : (i < current ? tokens.primary : tokens.borderColor))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    planWizardSteps[i].label,
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
