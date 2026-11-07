import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sport_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../payments/application/payment_flow.dart';
import '../../payments/domain/payment_receipt.dart';
import '../application/venues_providers.dart';
import '../domain/membership_enroll.dart';
import '../domain/venue.dart';
import 'guest_booking_page.dart' show BookingPill, SlotsError;

/// "Enroll Membership" for one venue: 1 Select Time Slot, 2 Choose Plan, 3 Enroll & Pay.
///
/// The player picks a sport and a time slot (each slot says how many members play there now), then one of the plans the club made for
/// that slot, reads the plan's benefits and pays. Every membership is paid through UPI AutoPay: Pay & Enroll makes the pending
/// membership, then opens Razorpay's page where the player authorises AutoPay (GPay, PhonePe, Paytm or any UPI app).
class EnrollMembershipPage extends ConsumerStatefulWidget {
  const EnrollMembershipPage({
    super.key,
    required this.venueId,
    required this.onNavigate,
    this.embedded = false,
    this.now,
  });

  final String venueId;
  final void Function(String route) onNavigate;

  /// True inside the shell on a wide window (the brand bar is already above).
  final bool embedded;

  /// For tests; the real clock otherwise.
  final DateTime? now;

  @override
  ConsumerState<EnrollMembershipPage> createState() =>
      _EnrollMembershipPageState();
}

class _EnrollMembershipPageState extends ConsumerState<EnrollMembershipPage> {
  String? _sportId;
  String? _slotKey;
  String? _planId;
  bool _paying = false;
  bool _policyOpen = true;

  DateTime get _today {
    final n = widget.now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _pay(EnrollInfo info, EnrollSlot? slot, EnrollPlan plan) async {
    if (ref.read(currentPlayerProvider) == null) {
      widget.onNavigate(AppRoutes.login);
      return;
    }
    final repo = ref.read(membershipEnrollRepositoryProvider);
    setState(() => _paying = true);
    try {
      await openPaymentFlow(
        context,
        onNavigate: widget.onNavigate,
        job: PaymentJob(
          kind: PaymentKind.membership,
          title: plan.name,
          venueName: info.venueName,
          prepare: () async {
            final start = await repo.start(
              venueId: info.venueId,
              planId: plan.id,
              batchId: slot?.batchFor(plan.id)?.id,
            );
            final link = await repo.autopayLink(start.membershipId);
            return PaymentTarget(id: start.membershipId, link: link);
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final async = ref.watch(enrollInfoProvider(widget.venueId));
    final Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const Center(
        child: SizedBox(
          key: ValueKey('enroll-loading'),
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    } else if (async.hasError) {
      body = Center(
        key: const ValueKey('enroll-error'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: SlotsError(
            message: "We couldn't load this venue's memberships.",
            error: async.error,
            onRetry: () => ref.invalidate(enrollInfoProvider(widget.venueId)),
          ),
        ),
      );
    } else if (async.value == null) {
      body = _message(
        p,
        key: 'enroll-missing',
        icon: Icons.storefront_outlined,
        title: "This venue isn't available",
        action: 'See venues',
        route: AppRoutes.explore,
      );
    } else if (!async.value!.accepting || async.value!.plans.isEmpty) {
      body = _message(
        p,
        key: 'enroll-closed',
        icon: Icons.workspace_premium_outlined,
        title: !async.value!.accepting
            ? "This club isn't taking online memberships yet"
            : 'No membership plans yet',
        text: 'You can still book a court, or ask the club about joining.',
        action: 'Back to venue',
        route: AppRoutes.venuePath(widget.venueId),
      );
    } else {
      body = _content(context, async.value!);
    }
    if (widget.embedded) return SafeArea(child: body);
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        leading: IconButton(
          key: const ValueKey('enroll-back'),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: p.primaryText),
        ),
        title: Text(
          'Enroll Membership',
          style: AppTextStyles.cardHeading(p.primaryText),
        ),
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _message(
    AppPalette p, {
    required String key,
    required IconData icon,
    required String title,
    String? text,
    required String action,
    required String route,
  }) {
    return Center(
      key: ValueKey(key),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: p.highlight),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.sectionHeading(p.primaryText),
            ),
            if (text != null) ...[
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(p.secondaryText),
              ),
            ],
            const SizedBox(height: 16),
            GameAllButton.secondary(
              label: action,
              onPressed: () => widget.onNavigate(route),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, EnrollInfo info) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    final mine =
        ref.watch(myMembershipsAtProvider(widget.venueId)).value ??
        const <ExistingMembership>[];

    // 1 · the sport and time slot
    final sports = info.sports;
    if (_sportId == null && sports.isNotEmpty) {
      // the sport chosen on the venue's card, else the first
      final want = ref.read(preferredSportProvider)?.trim().toLowerCase();
      _sportId = sports
          .where((s) => s.name.trim().toLowerCase() == want)
          .firstOrNull
          ?.id ??
          sports.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(preferredSportProvider.notifier).set(null);
      });
    }
    final slots = [
      for (final s in info.slots)
        if (s.sportId == _sportId) s,
    ];
    final slot = slots.where((s) => s.key == _slotKey).firstOrNull;

    // 2 · the plans of that slot (every plan when the club made no time slots)
    final needsSlot = info.hasSlots;
    final plans = !needsSlot
        ? info.plans
        : (slot == null
              ? <EnrollPlan>[]
              : [
                  for (final pl in info.plans)
                    if (slot.planIds.contains(pl.id)) pl,
                ]);
    final plan = plans.where((pl) => pl.id == _planId).firstOrNull;
    final full = plan != null && slot != null && slot.batchFor(plan.id) == null;
    final ready =
        plan != null &&
        !full &&
        info.autopayAvailable &&
        !(needsSlot && slot == null);

    final sportRow = _SportRow(
      sports: sports,
      selected: _sportId,
      onTap: (id) => setState(() {
        _sportId = id;
        _slotKey = null;
        _planId = null;
      }),
    );
    final slotGrid = _SlotGrid(
      slots: slots,
      selected: _slotKey,
      onTap: (s) => setState(() {
        _slotKey = s.key;
        if (!s.planIds.contains(_planId)) _planId = null;
        // a slot that offers one plan only has that plan chosen for the player
        if (s.planIds.length == 1) _planId = s.planIds.first;
      }),
    );

    // the sport is always the first step, even for a venue with one sport (it shows as the chosen chip)
    final hasSportRow = sports.isNotEmpty;
    final left = EnrollCard(
      key: const ValueKey('enroll-left'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasSportRow) ...[
            const EnrollBarHeading(title: 'Select Sport'),
            const SizedBox(height: 14),
            sportRow,
          ],
          if (needsSlot) ...[
            if (hasSportRow) _rule(p),
            const EnrollBarHeading(
              title: 'Select Membership Time Slot',
              subtitle: 'Choose a fixed court time for your membership',
            ),
            const SizedBox(height: 14),
            slotGrid,
          ],
          // a club with one sport and no time slots has nothing to pick here
          if (!hasSportRow && !needsSlot)
            EnrollBarHeading(
              title: info.venueName,
              subtitle: 'Choose a plan to join',
            ),
        ],
      ),
    );

    final middle = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EnrollCard(
          key: const ValueKey('enroll-plans'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EnrollBarHeading(
                title: 'Available Membership Plans',
                fontSize: 22,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Text(
                  needsSlot
                      ? (slot == null
                            ? 'Pick a time slot to see its plans'
                            : 'Plans for the selected time slot:  ${slot.label}')
                      : 'Plans at ${info.venueName}',
                  style: AppTextStyles.body(p.secondaryText),
                  key: const ValueKey('plans-for'),
                ),
              ),
              const SizedBox(height: 14),
              if (plans.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'No plans to show yet.',
                    key: const ValueKey('plans-empty'),
                    style: AppTextStyles.body(p.mutedText),
                  ),
                )
              else
                for (final pl in plans)
                  _PlanTile(
                    plan: pl,
                    selected: pl.id == _planId,
                    full: slot != null && slot.batchFor(pl.id) == null,
                    onTap: () => setState(() => _planId = pl.id),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Benefits(plan: plan, slot: slot, full: full),
      ],
    );

    final summary = _SummaryPanel(
      info: info,
      sport: sports.where((s) => s.id == _sportId).firstOrNull?.name,
      slot: slot,
      plan: plan,
      today: _today,
      ready: ready,
      full: full,
      paying: _paying,
      policyOpen: _policyOpen,
      onPolicy: () => setState(() => _policyOpen = !_policyOpen),
      onPay: ready ? () => _pay(info, slot, plan) : null,
    );

    final existing = mine.isEmpty ? null : _Existing(memberships: mine);

    return SingleChildScrollView(
      key: const ValueKey('enroll-scroll'),
      padding: EdgeInsets.fromLTRB(side, 12, side, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Reveal(
            dy: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (widget.embedded) ...[
                            EnrollBackButton(
                              key: const ValueKey('enroll-back-button'),
                              onTap: () => widget.onNavigate(
                                AppRoutes.venuePath(widget.venueId),
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Enroll Membership',
                                  style:
                                      AppTextStyles.sectionHeading(
                                        p.primaryText,
                                      ).copyWith(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Choose your time slot, select a plan, review details and complete the payment.',
                                  style: AppTextStyles.body(p.secondaryText),
                                ),
                              ],
                            ),
                          ),
                          _Progress(
                            step: plan != null
                                ? 3
                                : (slot != null || !needsSlot ? 2 : 1),
                            needsSlot: needsSlot,
                          ),
                        ],
                      )
                    : Text(
                        'Choose your time slot, select a plan, review details and complete the payment.',
                        style: AppTextStyles.body(p.secondaryText),
                      ),
                const SizedBox(height: 22),
                if (existing != null) ...[existing, const SizedBox(height: 16)],
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 10, child: left),
                      const SizedBox(width: 20),
                      Expanded(flex: 11, child: middle),
                      const SizedBox(width: 20),
                      Expanded(flex: 10, child: summary),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      left,
                      const SizedBox(height: 16),
                      middle,
                      const SizedBox(height: 16),
                      summary,
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rule(AppPalette p) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Container(height: 1, color: p.border),
  );
}

// ── pieces ──────────────────────────────────────────────────────────────────

class EnrollCard extends StatelessWidget {
  const EnrollCard({super.key, required this.child, this.glow = false});
  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: glow ? AppColors.violet.withValues(alpha: 0.6) : p.border,
        ),
        color: glow ? null : p.surface.withValues(alpha: p.isDark ? 0.55 : 1),
        gradient: glow
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    AppColors.violet.withValues(alpha: 0.28),
                    p.surface,
                  ),
                  Color.alphaBlend(
                    AppColors.violet.withValues(alpha: 0.10),
                    p.surface,
                  ),
                ],
              )
            : null,
      ),
      child: child,
    );
  }
}

/// A section title with the short violet bar in front of it, and an optional line under it. Used by the Coaching and Membership
/// pages for the filter sections and the cards ("Coaching Programs", "Available Membership Plans" ...).
class EnrollBarHeading extends StatelessWidget {
  const EnrollBarHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.fontSize = 20,
  });
  final String title;
  final String? subtitle;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: subtitle == null ? fontSize + 4 : fontSize + 24,
          margin: const EdgeInsets.only(right: 10, top: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: AppColors.violet,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.sectionHeading(p.primaryText)
                    .copyWith(fontSize: fontSize),
              ),
              if (subtitle != null)
                Text(subtitle!, style: AppTextStyles.support(p.secondaryText)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The round Back button that leads the title of the Enroll pages inside the shell (the phone has an app bar with its own).
class EnrollBackButton extends StatelessWidget {
  const EnrollBackButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: 'Back',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.border),
              color: p.surface.withValues(alpha: p.isDark ? 0.55 : 1),
            ),
            child: Icon(Icons.arrow_back_rounded, color: p.primaryText),
          ),
        ),
      ),
    );
  }
}

class _SportRow extends StatelessWidget {
  const _SportRow({
    required this.sports,
    required this.selected,
    required this.onTap,
  });
  final List<EnrollSport> sports;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in sports)
          BookingPill(
            key: ValueKey('enroll-sport-${s.name}'),
            selected: s.id == selected,
            onTap: () => onTap(s.id),
            leading: SportIcon(
              s.name,
              size: 20,
              color: s.id == selected ? Colors.white : p.primaryText,
            ),
            label: s.name,
          ),
      ],
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.slots,
    required this.selected,
    required this.onTap,
  });
  final List<EnrollSlot> slots;
  final String? selected;
  final ValueChanged<EnrollSlot> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (slots.isEmpty) {
      return Text(
        'No time slots for this sport yet.',
        key: const ValueKey('slots-empty'),
        style: AppTextStyles.body(p.secondaryText),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final cols = box.maxWidth >= 300 ? 2 : 1;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in slots)
              SizedBox(
                width: w,
                child: Semantics(
                  button: true,
                  selected: s.key == selected,
                  label: s.label,
                  child: ExcludeSemantics(
                    child: Pressable(
                      key: ValueKey('enroll-slot-${s.label}'),
                      onTap: () => onTap(s),
                      borderRadius: BorderRadius.circular(22),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: s.key == selected
                              ? const LinearGradient(
                                  colors: [AppColors.violet, AppColors.purple],
                                )
                              : null,
                          color: s.key == selected
                              ? null
                              : (p.isDark
                                    ? const Color(0xFF0E1630)
                                    : p.elevated),
                          border: Border.all(
                            color: s.key == selected
                                ? AppColors.purple
                                : p.border,
                          ),
                          boxShadow: s.key == selected
                              ? [
                                  BoxShadow(
                                    color: AppColors.violet.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 14,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (s.key == selected) ...[
                              const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  s.label,
                                  maxLines: 1,
                                  style: AppTextStyles.body(
                                    s.key == selected
                                        ? Colors.white
                                        : p.primaryText,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.full,
    required this.onTap,
  });
  final EnrollPlan plan;
  final bool selected;
  final bool full;
  final VoidCallback onTap;

  IconData get _icon {
    switch (plan.months) {
      case 1:
        return Icons.calendar_month_outlined;
      case 3:
        return Icons.layers_outlined;
      case 6:
        return Icons.bolt_rounded;
      case 12:
        return Icons.workspace_premium_outlined;
      default:
        return Icons.event_repeat_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        selected: selected,
        enabled: !full,
        label: '${plan.name}, ${rupees(plan.priceInr)}',
        child: ExcludeSemantics(
          child: Pressable(
            key: ValueKey('enroll-plan-${plan.name}'),
            onTap: full ? null : onTap,
            borderRadius: BorderRadius.circular(20),
            child: Opacity(
              opacity: full ? 0.55 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? AppColors.purple : p.border,
                    width: selected ? 2 : 1,
                  ),
                  color: selected
                      ? AppColors.violet.withValues(alpha: 0.16)
                      : (p.isDark ? const Color(0xFF0E1630) : p.elevated),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.violet.withValues(alpha: 0.35),
                            blurRadius: 16,
                          ),
                        ]
                      : null,
                ),
                child: LayoutBuilder(
                  builder: (context, box) => Row(
                    children: [
                      // on a very narrow phone the icon makes way for the name and price
                      if (box.maxWidth >= 300) ...[
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: AppColors.violet.withValues(alpha: 0.2),
                          ),
                          child: Icon(_icon, color: AppColors.cyan),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  plan.name,
                                  style: AppTextStyles.cardHeading(
                                    p.primaryText,
                                  ).copyWith(fontSize: 17),
                                ),
                                if (full)
                                  EnrollTag('Full', color: AppColors.danger)
                                else if (plan.badge != null)
                                  EnrollTag(
                                    plan.badge!,
                                    color: AppColors.success,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              plan.validFor,
                              style: AppTextStyles.support(p.secondaryText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 0,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            rupees(plan.priceInr),
                            style: AppTextStyles.sectionHeading(p.primaryText)
                                .copyWith(fontSize: 22),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected ? AppColors.violet : p.mutedText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EnrollTag extends StatelessWidget {
  const EnrollTag(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: color.withValues(alpha: 0.2),
    ),
    child: Text(
      text,
      style: AppTextStyles.meta(color).copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

/// What the chosen plan gives, and who already plays in the chosen slot.
class _Benefits extends StatelessWidget {
  const _Benefits({required this.plan, required this.slot, required this.full});
  final EnrollPlan? plan;
  final EnrollSlot? slot;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pl = plan;
    String? crowd;
    if (slot != null) {
      final n = slot!.membersNow;
      crowd = full
          ? 'This time slot is full for this plan.'
          : n == 0
          ? "You'd be the first member in ${slot!.label}."
          : '$n ${n == 1 ? 'member plays' : 'members play'} in ${slot!.label} right now.';
    }
    return EnrollCard(
      key: const ValueKey('enroll-benefits'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnrollBarHeading(title: 'Plan Benefits'),
          const SizedBox(height: 12),
          Container(height: 1, color: p.border),
          const SizedBox(height: 14),
          if (pl == null)
            Text(
              'Choose a plan to see what it includes.',
              key: const ValueKey('benefits-empty'),
              style: AppTextStyles.body(p.mutedText),
            )
          else ...[
            if (crowd != null)
              Container(
                key: const ValueKey('benefits-crowd'),
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color:
                      (slot!.membersNow == 0 && !full
                              ? AppColors.cyan
                              : AppColors.violet)
                          .withValues(alpha: 0.14),
                ),
                child: Row(
                  children: [
                    Icon(
                      slot!.membersNow == 0 && !full
                          ? Icons.emoji_events_outlined
                          : Icons.groups_outlined,
                      size: 22,
                      color: p.primaryText,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        crowd,
                        style: AppTextStyles.body(p.primaryText),
                      ),
                    ),
                  ],
                ),
              ),
            if (pl.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  pl.description!,
                  key: const ValueKey('benefits-description'),
                  style: AppTextStyles.body(p.secondaryText),
                ),
              ),
            if (pl.features.isEmpty && pl.description == null)
              Text(
                '${pl.validFor}. Your court time is kept for you.',
                style: AppTextStyles.body(p.secondaryText),
              )
            else
              for (final f in pl.features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f,
                          style: AppTextStyles.body(p.primaryText),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.info,
    required this.sport,
    required this.slot,
    required this.plan,
    required this.today,
    required this.ready,
    required this.full,
    required this.paying,
    required this.policyOpen,
    required this.onPolicy,
    required this.onPay,
  });

  final EnrollInfo info;
  final String? sport;
  final EnrollSlot? slot;
  final EnrollPlan? plan;
  final DateTime today;
  final bool ready;
  final bool full;
  final bool paying;
  final bool policyOpen;
  final VoidCallback onPolicy;
  final VoidCallback? onPay;

  String _date(DateTime d) => '${shortDate(d)} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pl = plan;
    final fee = pl?.joiningFeeInr ?? 0;
    final total = pl == null ? null : pl.priceInr + fee;

    Widget row(IconData icon, String label, String value, {Key? key, Widget? leading}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              leading ?? Icon(icon, size: 20, color: p.primaryText),
              const SizedBox(width: 12),
              Flexible(
                flex: 0,
                child: Text(label, style: AppTextStyles.body(p.primaryText)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  key: key,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.body(p.primaryText)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
    // the label takes the room that is left; the amount ends exactly on the right edge, like the rows above
    Widget money(String label, String value, {Key? key, bool big = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: big
                      ? AppTextStyles.sectionHeading(p.primaryText)
                            .copyWith(fontSize: 18)
                      : AppTextStyles.body(p.primaryText),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                key: key,
                textAlign: TextAlign.right,
                style: big
                    ? AppTextStyles.sectionHeading(p.primaryText)
                          .copyWith(fontSize: 26)
                    : AppTextStyles.body(p.primaryText)
                          .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EnrollCard(
          key: const ValueKey('enroll-summary'),
          glow: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_note_outlined,
                    size: 28,
                    color: p.primaryText,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Membership Summary',
                      style: AppTextStyles.sectionHeading(p.primaryText)
                          .copyWith(fontSize: 21),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: p.border),
              if (sport != null)
                row(
                  Icons.sports_rounded,
                  'Sport',
                  sport!,
                  leading: SportIcon(sport, size: 20, color: p.primaryText),
                  key: const ValueKey('summary-sport'),
                ),
              if (info.hasSlots)
                row(
                  Icons.schedule_rounded,
                  'Time Slot',
                  slot?.label ?? '—',
                  key: const ValueKey('summary-slot'),
                ),
              row(
                Icons.workspace_premium_outlined,
                'Plan',
                pl == null
                    ? '—'
                    : '${pl.name} (${pl.validFor.replaceFirst('Valid for ', '')})',
                key: const ValueKey('summary-plan'),
              ),
              row(
                Icons.event_outlined,
                'Start Date',
                pl == null ? '—' : _date(today),
                key: const ValueKey('summary-start'),
              ),
              row(
                Icons.event_available_outlined,
                'End Date',
                pl == null ? '—' : _date(pl.endFrom(today)),
                key: const ValueKey('summary-end'),
              ),
              const SizedBox(height: 6),
              Container(height: 1, color: p.border),
              const SizedBox(height: 8),
              money(
                'Plan Amount',
                pl == null ? '—' : rupees(pl.priceInr),
                key: const ValueKey('summary-plan-amount'),
              ),
              if (fee > 0)
                money(
                  'Joining Fee (one time)',
                  rupees(fee),
                  key: const ValueKey('summary-fee'),
                ),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: p.border,
              ),
              money(
                'Total Payable',
                total == null ? '—' : rupees(total),
                key: const ValueKey('summary-total'),
                big: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _AutoPayCard(plan: pl, available: info.autopayAvailable),
        const SizedBox(height: 14),
        _Policy(open: policyOpen, onToggle: onPolicy),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          enabled: onPay != null && !paying,
          label: 'Pay and Enroll',
          child: ExcludeSemantics(
            child: Pressable(
              key: const ValueKey('enroll-pay'),
              onTap: paying ? null : onPay,
              borderRadius: BorderRadius.circular(30),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: ready
                      ? const LinearGradient(
                          colors: [AppColors.violet, AppColors.purple],
                        )
                      : null,
                  color: ready ? null : p.elevated,
                  boxShadow: ready
                      ? [
                          BoxShadow(
                            color: AppColors.violet.withValues(alpha: 0.45),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: paying
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 20,
                            color: ready ? Colors.white : p.mutedText,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              total == null
                                  ? 'Pay & Enroll'
                                  : 'Pay & Enroll  ${rupees(total)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.button(
                                ready ? Colors.white : p.mutedText,
                              ).copyWith(fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: ready ? Colors.white : p.mutedText,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          !info.autopayAvailable
              ? "This club hasn't turned on online payments yet. Please ask the club."
              : (full
                    ? 'That time slot is full for this plan. Pick another.'
                    : "You'll set up AutoPay on Razorpay's secure page."),
          key: const ValueKey('enroll-note'),
          textAlign: TextAlign.center,
          style: AppTextStyles.meta(
            !info.autopayAvailable || full ? AppColors.danger : p.mutedText,
          ),
        ),
      ],
    );
  }
}

class _AutoPayCard extends StatelessWidget {
  const _AutoPayCard({required this.plan, required this.available});
  final EnrollPlan? plan;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pl = plan;
    final every = pl == null
        ? 'every billing period'
        : (pl.months == 1 ? 'every month' : 'every ${pl.cadence}');
    return Container(
      key: const ValueKey('enroll-autopay'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.violet.withValues(alpha: 0.5)),
        color: AppColors.violet.withValues(alpha: 0.12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.autorenew_rounded, size: 30, color: AppColors.cyan),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Auto Pay ',
                        style: AppTextStyles.cardHeading(p.primaryText),
                      ),
                      TextSpan(
                        text: '(UPI AutoPay)',
                        style: AppTextStyles.cardHeading(AppColors.purple),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pl == null
                      ? 'Your membership is paid by UPI AutoPay: set it up once in GPay, PhonePe, Paytm or any UPI app.'
                      : 'Set up UPI AutoPay once in GPay, PhonePe, Paytm or any UPI app. ${rupees(pl.priceInr)} is then charged $every, and the first payment is taken today.',
                  style: AppTextStyles.support(p.secondaryText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.check_circle_rounded,
            color: available ? AppColors.success : p.mutedText,
          ),
        ],
      ),
    );
  }
}

class _Policy extends StatelessWidget {
  const _Policy({required this.open, required this.onToggle});
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const lines = [
      'Cancel anytime before the next billing date.',
      'Membership remains active until the end of the current period.',
      'No refund for the current period (partial or full).',
      'Cancel auto-renewal anytime from My Memberships.',
    ];
    return Container(
      key: const ValueKey('enroll-policy'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
        color: p.surface.withValues(alpha: p.isDark ? 0.55 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            key: const ValueKey('policy-toggle'),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 24, color: p.primaryText),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cancellation Policy',
                    style: AppTextStyles.cardHeading(p.primaryText),
                  ),
                ),
                Icon(
                  open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: p.secondaryText,
                ),
              ],
            ),
          ),
          if (open) ...[
            const SizedBox(height: 10),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: AppTextStyles.support(p.secondaryText)),
                    Expanded(
                      child: Text(
                        l,
                        style: AppTextStyles.support(p.secondaryText),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Memberships this phone number already has at the venue. Joining another is still fine.
class _Existing extends StatelessWidget {
  const _Existing({required this.memberships});
  final List<ExistingMembership> memberships;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String until(DateTime? d) => d == null
        ? ''
        : 'active till ${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
    return Container(
      key: const ValueKey('enroll-existing'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.5)),
        color: AppColors.cyan.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: AppColors.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  memberships.length == 1
                      ? 'You already have a membership here'
                      : 'You already have ${memberships.length} memberships here',
                  style: AppTextStyles.cardHeading(p.primaryText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final m in memberships)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                [
                  m.planName,
                  if (m.slots.isNotEmpty) m.slots.join(', '),
                  until(m.endDate),
                  if (m.autoRenew) 'AutoPay on',
                ].where((s) => s.isNotEmpty).join('  ·  '),
                style: AppTextStyles.body(p.secondaryText),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Want another one? Pick a time slot and plan below.',
            style: AppTextStyles.support(p.mutedText),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.needsSlot});
  final int step;
  final bool needsSlot;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final labels = [
      if (needsSlot) 'Select Time Slot',
      'Choose Plan',
      'Enroll & Pay',
    ];
    final shift = needsSlot ? 0 : 1;
    Widget dot(int i) {
      final n = i + 1 + shift;
      final reached = n <= step;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: reached
                  ? const LinearGradient(
                      colors: [AppColors.violet, AppColors.purple],
                    )
                  : null,
              border: Border.all(color: reached ? AppColors.purple : p.border),
            ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                color: reached ? Colors.white : p.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(labels[i], style: AppTextStyles.body(p.primaryText)),
        ],
      );
    }

    return Row(
      key: const ValueKey('enroll-progress'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Container(
              width: 44,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: p.border,
            ),
          dot(i),
        ],
      ],
    );
  }
}
