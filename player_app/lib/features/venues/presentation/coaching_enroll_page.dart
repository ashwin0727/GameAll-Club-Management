import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sport_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../application/venues_providers.dart';
import '../data/coaching_enroll_repository.dart';
import '../domain/coaching_enroll.dart';
import '../domain/venue.dart';
import 'enroll_membership_page.dart'
    show EnrollBackButton, EnrollBarHeading, EnrollCard;
import 'guest_booking_page.dart' show BookingPill, SlotsError;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Sat, 24 Aug 2026".
String _fullDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';

/// "Coaching at the venue": pick a sport, a coaching type and a regular time slot, choose a programme (each card is one coach in one
/// batch the club's staff created), read the fee, and pay.
///
/// What is on a card comes only from what the club set up: the coach is the staff member behind the batch, the price is the
/// programme's fee (less any early-bird discount, plus tax), and whether it is a one-time or a monthly fee is the programme's own
/// fee type. Paying never trusts the app's numbers: Pay & Enroll makes the pending enrolment in the database (which prices it) and
/// then opens Razorpay: a payment link for a one-time fee, a UPI AutoPay mandate for a monthly one.
class CoachingEnrollPage extends ConsumerStatefulWidget {
  const CoachingEnrollPage({
    super.key,
    required this.venueId,
    required this.onNavigate,
    this.embedded = false,
  });

  final String venueId;
  final void Function(String route) onNavigate;

  /// True inside the shell on a wide window (the brand bar is already above).
  final bool embedded;

  @override
  ConsumerState<CoachingEnrollPage> createState() => _CoachingEnrollPageState();
}

class _CoachingEnrollPageState extends ConsumerState<CoachingEnrollPage>
    with WidgetsBindingObserver {
  String? _sportId;
  String? _level; // Beginner / Intermediate / Advanced; null = All
  CoachingSlot? _slot;
  String? _offerKey;
  bool _paying = false;
  bool _policyOpen = true;
  final _summaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the Razorpay page: look again at what has been paid.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(myCoachingAtProvider(widget.venueId));
    }
  }

  /// The programmes' cards for the filters picked: one card per programme per batch (a coach, a time, a price).
  List<CoachingOffer> _offers(CoachingInfo info, {required bool needsSlot}) {
    // Like Memberships: when the club made time slots, programmes appear only once a slot is picked.
    if (needsSlot && _slot == null) return const [];
    final out = <CoachingOffer>[];
    for (final p in info.forSport(_sportId)) {
      final k = p.levelKey;
      if (_level != null && k != null && k != _level) continue;
      if (p.batches.isEmpty) {
        if (!needsSlot) out.add(CoachingOffer(program: p));
        continue;
      }
      for (final b in p.batches) {
        if (_slot == null || b.slot == _slot) {
          out.add(CoachingOffer(program: p, batch: b));
        }
      }
    }
    return out;
  }

  bool _enrollable(CoachingInfo info, CoachingOffer o, List<MyCoaching> mine) =>
      info.accepting &&
      o.program.enrollmentOpen &&
      o.program.onlinePayable &&
      !o.full &&
      !(o.program.isMonthly && !info.autopayAvailable) &&
      !mine.any((m) => m.programId == o.program.id && m.settled);

  /// "Recommended": the batch most players have joined (only once somebody has).
  CoachingOffer? _recommended(
    CoachingInfo info,
    List<CoachingOffer> offers,
    List<MyCoaching> mine,
  ) {
    CoachingOffer? best;
    for (final o in offers) {
      if (!_enrollable(info, o, mine)) continue;
      final n = o.batch?.enrolled ?? 0;
      if (n > 0 && (best == null || n > (best.batch?.enrolled ?? 0))) best = o;
    }
    return best;
  }

  void _choose(CoachingOffer o) => setState(() => _offerKey = o.key);

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _pay(CoachingInfo info, CoachingOffer o) async {
    if (ref.read(currentPlayerProvider) == null) {
      widget.onNavigate(AppRoutes.login);
      return;
    }
    setState(() => _paying = true);
    try {
      final repo = ref.read(coachingEnrollRepositoryProvider);
      final start = await repo.start(
        venueId: info.venueId,
        programId: o.program.id,
        batchId: o.batch?.id,
      );
      await _openPayment(
        start.enrollmentId,
        monthly: start.feeType == 'MONTHLY',
      );
    } on CoachingException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast("We couldn't start your enrolment. Please try again.");
    } finally {
      if (mounted) setState(() => _paying = false);
      ref.invalidate(myCoachingAtProvider(widget.venueId));
    }
  }

  Future<void> _openPayment(
    String enrollmentId, {
    required bool monthly,
  }) async {
    final repo = ref.read(coachingEnrollRepositoryProvider);
    final link = await repo.paymentLink(enrollmentId);
    final opened = await ref.read(linkOpenerProvider)(link);
    if (!opened) {
      throw const CoachingException(
        "We couldn't open the payment page. Please try again.",
      );
    }
    _toast(
      monthly
          ? 'Finish setting up AutoPay on the page that opened. You are enrolled once it is done.'
          : 'Finish your payment on the page that opened. You are enrolled once it is paid.',
    );
  }

  Future<void> _resume(MyCoaching m) async {
    setState(() => _paying = true);
    try {
      await _openPayment(m.enrollmentId, monthly: m.feeType == 'MONTHLY');
    } on CoachingException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast("We couldn't open the payment page. Please try again.");
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final async = ref.watch(coachingInfoProvider(widget.venueId));
    final Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const Center(
        child: SizedBox(
          key: ValueKey('coaching-loading'),
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    } else if (async.hasError) {
      body = Center(
        key: const ValueKey('coaching-error'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: SlotsError(
            message: "We couldn't load this venue's coaching.",
            error: async.error,
            onRetry: () => ref.invalidate(coachingInfoProvider(widget.venueId)),
          ),
        ),
      );
    } else if (async.value == null) {
      body = _message(
        p,
        key: 'coaching-missing',
        icon: Icons.storefront_outlined,
        title: "This venue isn't available",
        action: 'See venues',
        route: AppRoutes.explore,
      );
    } else if (!async.value!.accepting) {
      body = _message(
        p,
        key: 'coaching-closed',
        icon: Icons.school_outlined,
        title: "This club isn't taking online coaching enrolments yet",
        text: 'Please ask the club about joining a programme.',
        action: 'Back to venue',
        route: AppRoutes.venuePath(widget.venueId),
      );
    } else if (async.value!.programs.isEmpty) {
      body = _message(
        p,
        key: 'coaching-none',
        icon: Icons.school_outlined,
        title: 'No coaching programs yet',
        text: 'This venue has no coaching programme open right now.',
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
          key: const ValueKey('coaching-back'),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: p.primaryText),
        ),
        title: Text(
          'Coaching',
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

  Widget _content(BuildContext context, CoachingInfo info) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    final venue = ref.watch(venueDetailProvider(widget.venueId)).value;
    final mine =
        ref.watch(myCoachingAtProvider(widget.venueId)).value ??
        const <MyCoaching>[];

    final sports = info.sports;
    _sportId ??= sports.isEmpty ? null : sports.first.id;
    final sportName = sports.where((s) => s.id == _sportId).firstOrNull?.name;

    // every time slot the club made for this sport
    final slots = <CoachingSlot>{
      for (final pr in info.forSport(_sportId))
        for (final b in pr.batches) b.slot,
    }.toList()..sort();

    final needsSlot = slots.isNotEmpty;
    final offers = _offers(info, needsSlot: needsSlot);
    final recommended = _recommended(info, offers, mine);
    // The summary follows the card the player chose; until then it follows the recommended one (or the first that can be joined).
    CoachingOffer? chosen = offers.where((o) => o.key == _offerKey).firstOrNull;
    chosen ??=
        recommended ??
        offers.where((o) => _enrollable(info, o, mine)).firstOrNull;
    final canPay = chosen != null && _enrollable(info, chosen, mine);

    final left = EnrollCard(
      key: const ValueKey('coaching-left'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sports.isNotEmpty) ...[
            const EnrollBarHeading(title: 'Sport'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final s in sports)
                  BookingPill(
                    key: ValueKey('coaching-sport-${s.name}'),
                    selected: s.id == _sportId,
                    onTap: () => setState(() {
                      _sportId = s.id;
                      _slot = null;
                      _offerKey = null;
                    }),
                    leading: SportIcon(
                      s.name,
                      size: 20,
                      color: s.id == _sportId ? Colors.white : p.primaryText,
                    ),
                    label: s.name,
                  ),
              ],
            ),
          ],
          if (sports.isNotEmpty) _rule(p),
          const EnrollBarHeading(title: 'Coaching Type'),
          const SizedBox(height: 14),
          // two by two: All / Beginner on the first row, Intermediate / Advanced on the second
          LayoutBuilder(
            builder: (context, box) {
              const gap = 10.0;
              final w = (box.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final l in const [
                    null,
                    'Beginner',
                    'Intermediate',
                    'Advanced',
                  ])
                    SizedBox(
                      width: w,
                      child: _Chip(
                        key: ValueKey('coaching-level-${l ?? 'All'}'),
                        label: l ?? 'All',
                        selected: _level == l,
                        onTap: () => setState(() {
                          _level = l;
                          _offerKey = null;
                        }),
                      ),
                    ),
                ],
              );
            },
          ),
          _rule(p),
          const EnrollBarHeading(
            title: 'Preferred Time Slot',
            subtitle: 'Choose your regular training time',
          ),
          const SizedBox(height: 14),
          _SlotGrid(
            slots: slots,
            selected: _slot,
            onTap: (s) => setState(() {
              _slot = s;
              _offerKey = null;
            }),
          ),
        ],
      ),
    );

    final middle = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EnrollCard(
          key: const ValueKey('coaching-programs'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 26,
                    margin: const EdgeInsets.only(right: 10, top: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: AppColors.violet,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Coaching Programs',
                      style: AppTextStyles.sectionHeading(p.primaryText)
                          .copyWith(fontSize: 22),
                    ),
                  ),
                  if (chosen != null)
                    Pressable(
                      key: const ValueKey('coaching-view-details'),
                      onTap: () => _showDetails(context, chosen!.program),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View Program Details',
                              style: AppTextStyles.body(p.highlight)
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: p.highlight,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Text(
                  needsSlot && _slot == null
                      ? 'Pick a time slot to see its programs'
                      : 'Programs available for ${sportName ?? 'this venue'}${_slot == null ? '' : ' at ${_slot!.label}'}',
                  key: const ValueKey('coaching-programs-for'),
                  style: AppTextStyles.body(p.secondaryText),
                ),
              ),
              const SizedBox(height: 14),
              if (mine.isNotEmpty) ...[
                _Mine(mine: mine, paying: _paying, onResume: _resume),
                const SizedBox(height: 4),
              ],
              if (offers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Text(
                    needsSlot && _slot == null ? 'No programs to show yet.' : 'No programs match these filters. Try another coaching type or time slot.',
                    key: const ValueKey('coaching-empty'),
                    style: AppTextStyles.body(p.mutedText),
                  ),
                )
              else
                _OfferSlider(
                  offers: offers,
                  cardBuilder: (o) => _OfferCard(
                    key: ValueKey(
                      'coaching-offer-${o.program.name}-${o.batch?.name ?? ''}',
                    ),
                    offer: o,
                    info: info,
                    selected: chosen?.key == o.key,
                    recommended: recommended?.key == o.key,
                    mine: mine
                        .where((m) => m.programId == o.program.id)
                        .firstOrNull,
                    enrollable: _enrollable(info, o, mine),
                    onSelect: () => _choose(o),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _Features(),
      ],
    );

    final summary = KeyedSubtree(
      key: _summaryKey,
      child: _SummaryPanel(
        info: info,
        offer: chosen,
        sport: chosen?.program.sportName ?? sportName,
        slot: chosen?.batch?.slot,
        ready: canPay,
        paying: _paying,
        policyOpen: _policyOpen,
        onPolicy: () => setState(() => _policyOpen = !_policyOpen),
        onPay: canPay ? () => _pay(info, chosen!) : null,
      ),
    );

    final venueName = venue?.name ?? info.venueName;
    return SingleChildScrollView(
      key: const ValueKey('coaching-scroll'),
      padding: EdgeInsets.fromLTRB(side, 12, side, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Reveal(
            dy: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Banner(
                  venueName: venueName,
                  verified: venue?.locationVerified ?? false,
                  wide: wide,
                  onBack: widget.embedded
                      ? () => widget.onNavigate(
                          AppRoutes.venuePath(widget.venueId),
                        )
                      : null,
                ),
                const SizedBox(height: 22),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 28, child: left),
                      const SizedBox(width: 20),
                      Expanded(flex: 44, child: middle),
                      const SizedBox(width: 20),
                      Expanded(flex: 28, child: summary),
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

  /// "View Program Details": everything the club wrote about the programme.
  void _showDetails(BuildContext context, CoachingProgram pr) {
    final p = context.palette;
    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: p.highlight),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(label, style: AppTextStyles.body(p.secondaryText)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body(p.primaryText)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('coaching-details'),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pr.name,
                style: AppTextStyles.sectionHeading(p.primaryText)
                    .copyWith(fontSize: 22),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  pr.level,
                  if (pr.ageGroup != null) pr.ageGroup!,
                  pr.typeLabel,
                ].join('  ·  '),
                style: AppTextStyles.body(p.secondaryText),
              ),
              if (pr.description != null) ...[
                const SizedBox(height: 14),
                Text(pr.description!, style: AppTextStyles.body(p.primaryText)),
              ],
              const SizedBox(height: 14),
              Container(height: 1, color: p.border),
              row(
                Icons.payments_outlined,
                'Fee',
                pr.isMonthly
                    ? '${rupees(pr.chargeInr)} every month (recurring)'
                    : '${rupees(pr.chargeInr)} one-time',
              ),
              row(
                Icons.timer_outlined,
                'Session length',
                '${pr.durationMinutes} minutes',
              ),
              if (pr.sessionsPerWeek != null)
                row(
                  Icons.repeat_rounded,
                  'Sessions a week',
                  '${pr.sessionsPerWeek}',
                ),
              if (pr.sessionCount != null)
                row(
                  Icons.format_list_numbered_rounded,
                  'Total sessions',
                  '${pr.sessionCount}',
                ),
              if (pr.startDate != null)
                row(Icons.event_outlined, 'Starts', _fullDate(pr.startDate!)),
              if (pr.endDate != null)
                row(
                  Icons.event_available_outlined,
                  'Ends',
                  _fullDate(pr.endDate!),
                ),
              if (pr.enrollmentDeadline != null)
                row(
                  Icons.hourglass_bottom_rounded,
                  'Enrol before',
                  _fullDate(pr.enrollmentDeadline!),
                ),
              if (pr.paymentNotes != null)
                row(
                  Icons.info_outline_rounded,
                  'Payment note',
                  pr.paymentNotes!,
                ),
              if (pr.structure.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'What you will work on',
                  style: AppTextStyles.cardHeading(p.primaryText),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final s in pr.structure) _Pill(s)],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── pieces ──────────────────────────────────────────────────────────────────

/// "Coaching at Champz Turf ✓" with a line under it. Inside the shell (no app bar of its own) a round Back button leads it, to the
/// venue's page.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.venueName,
    required this.verified,
    required this.wide,
    required this.onBack,
  });
  final String venueName;
  final bool verified;
  final bool wide;

  /// Null when the page has an app bar with its own Back button.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = Row(
      children: [
        Flexible(
          child: Text(
            'Coaching at $venueName',
            key: const ValueKey('coaching-title'),
            style: AppTextStyles.sectionHeading(
              p.primaryText,
            ).copyWith(fontSize: wide ? 34 : 24, fontWeight: FontWeight.w800),
          ),
        ),
        if (verified) ...[
          const SizedBox(width: 10),
          Icon(
            Icons.verified_rounded,
            size: wide ? 28 : 22,
            color: AppColors.violet,
          ),
        ],
      ],
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 6),
        Text(
          'Learn, improve and play better with certified coaches.',
          style: AppTextStyles.body(p.secondaryText),
        ),
      ],
    );
    if (onBack == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        EnrollBackButton(
          key: const ValueKey('coaching-back-button'),
          onTap: onBack!,
        ),
        const SizedBox(width: 16),
        Expanded(child: text),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 42, minWidth: 56),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppColors.violet, AppColors.purple],
                    )
                  : null,
              color: selected
                  ? null
                  : (p.isDark ? const Color(0xFF0E1630) : p.elevated),
              border: Border.all(color: selected ? AppColors.purple : p.border),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.violet.withValues(alpha: 0.4),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: AppTextStyles.body(selected ? Colors.white : p.primaryText)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.violet.withValues(alpha: 0.16),
      ),
      child: Text(text, style: AppTextStyles.support(p.primaryText)),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.slots,
    required this.selected,
    required this.onTap,
  });
  final List<CoachingSlot> slots;
  final CoachingSlot? selected;
  final ValueChanged<CoachingSlot> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (slots.isEmpty) {
      return Text(
        'No fixed time slots yet.',
        key: const ValueKey('coaching-slots-empty'),
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
                  selected: s == selected,
                  label: s.label,
                  child: ExcludeSemantics(
                    child: Pressable(
                      key: ValueKey('coaching-slot-${s.label}'),
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
                          gradient: s == selected
                              ? const LinearGradient(
                                  colors: [AppColors.violet, AppColors.purple],
                                )
                              : null,
                          color: s == selected
                              ? null
                              : (p.isDark
                                    ? const Color(0xFF0E1630)
                                    : p.elevated),
                          border: Border.all(
                            color: s == selected ? AppColors.purple : p.border,
                          ),
                          boxShadow: s == selected
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
                            if (s == selected) ...[
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
                                    s == selected
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

/// One programme in one batch: the coach, the programme, what it costs and the way to join.
class _OfferCard extends StatelessWidget {
  const _OfferCard({
    super.key,
    required this.offer,
    required this.info,
    required this.selected,
    required this.recommended,
    required this.mine,
    required this.enrollable,
    required this.onSelect,
  });

  final CoachingOffer offer;
  final CoachingInfo info;
  final bool selected;
  final bool recommended;
  final MyCoaching? mine;
  final bool enrollable;
  final VoidCallback onSelect;

  /// What the button says when the programme cannot be joined from here.
  String? get _blocked {
    final pr = offer.program;
    if (mine != null && mine!.settled) return 'Enrolled';
    if (!pr.enrollmentOpen) return 'Closed';
    if (offer.full) return 'Full';
    if (!pr.onlinePayable || (pr.isMonthly && !info.autopayAvailable)) {
      return 'Pay at club';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // A wide column shows one horizontal row (coach | programme | price and button); a narrower one puts the coach on top.
    return LayoutBuilder(
      builder: (context, box) => _card(context, box.maxWidth - 34),
    );
  }

  Widget _card(BuildContext context, double width) {
    final p = context.palette;
    final pr = offer.program;
    final b = offer.batch;
    final coach = b?.coach;
    final wide = width >= 620;
    final phone = width < 420;
    const avatarSize = 84.0;

    final coachBlock = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Avatar(coach: coach, size: avatarSize),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      coach?.name ?? 'Coach to be announced',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.sectionHeading(p.primaryText)
                          .copyWith(fontSize: 17),
                    ),
                  ),
                  if (coach?.certifications != null) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified_rounded,
                      size: 18,
                      color: AppColors.violet,
                    ),
                  ],
                ],
              ),
              if (coach?.credential != null)
                Text(
                  coach!.credential!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.support(p.secondaryText),
                ),
              if (coach != null && (coach.rating != null || coach.sessions > 0))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (coach.rating != null) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          coach.rating!.toStringAsFixed(1),
                          style: AppTextStyles.body(p.primaryText)
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (coach.sessions > 0)
                        Flexible(
                          child: Text(
                            "(${coach.sessions} sessions)",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.support(p.secondaryText),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final infoBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pr.name,
          style: AppTextStyles.sectionHeading(p.primaryText)
              .copyWith(fontSize: 18),
        ),
        if (pr.description != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              pr.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.support(p.secondaryText),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _Meta(
              pr.isMonthly ? Icons.autorenew_rounded : Icons.payments_outlined,
              pr.isMonthly ? 'Monthly' : 'One time',
              key: const ValueKey('offer-fee-type'),
            ),
            _Meta(Icons.groups_2_outlined, offer.groupLabel),
            if (b != null)
              _Meta(
                Icons.calendar_today_outlined,
                '${b.daysLabel} · ${b.slot.label}',
              ),
            if (b != null && !b.full && b.capacity > 0 && b.seatsLeft <= 3)
              _Meta(
                Icons.event_seat_outlined,
                '${b.seatsLeft} ${b.seatsLeft == 1 ? 'seat' : 'seats'} left',
              ),
          ],
        ),
      ],
    );

    final blocked = _blocked;
    final priceText = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pr.discountMinor > 0)
          Text(
            rupees(pr.baseInr),
            style: AppTextStyles.support(p.mutedText)
                .copyWith(decoration: TextDecoration.lineThrough),
          ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            rupees(pr.chargeInr),
            key: const ValueKey('offer-price'),
            style: AppTextStyles.sectionHeading(p.primaryText)
                .copyWith(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          pr.isMonthly ? '/ month' : 'one-time fee',
          key: const ValueKey('offer-price-unit'),
          style: AppTextStyles.support(p.secondaryText),
        ),
        if (pr.isMonthly && pr.cycles > 1)
          Text(
            'for ${pr.cycles} months',
            style: AppTextStyles.meta(p.mutedText),
          ),
        if (blocked != null) ...[
          const SizedBox(height: 6),
          Container(
            key: const ValueKey('offer-blocked'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color:
                  (blocked == 'Enrolled'
                          ? AppColors.success
                          : AppColors.warning)
                      .withValues(alpha: 0.18),
            ),
            child: Text(
              blocked,
              style: AppTextStyles.meta(
                blocked == 'Enrolled' ? AppColors.success : AppColors.warning,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
    // The way to choose this card: a radio button next to the price. A card that cannot be joined from here shows why instead.
    final radio = Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      enabled: blocked == null,
      label: 'Select ${pr.name}',
      child: ExcludeSemantics(
        child: Pressable(
          key: const ValueKey('offer-select'),
          onTap: blocked == null ? onSelect : null,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 30,
              color: blocked != null
                  ? p.mutedText.withValues(alpha: 0.4)
                  : (selected ? AppColors.violet : p.secondaryText),
            ),
          ),
        ),
      ),
    );
    final priceRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [priceText, const SizedBox(width: 6), radio],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // the whole card chooses the programme, not only the radio button
          Pressable(
            key: const ValueKey('offer-card'),
            onTap: blocked == null ? onSelect : null,
            scale: 0.99,
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? AppColors.purple : p.border,
                  width: selected ? 2 : 1,
                ),
                color: selected
                    ? AppColors.violet.withValues(alpha: 0.14)
                    : (p.isDark ? const Color(0xFF0E1630) : p.elevated),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.violet.withValues(alpha: 0.35),
                          blurRadius: 18,
                        ),
                      ]
                    : null,
              ),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(width: width * 0.30, child: coachBlock),
                        Container(
                          width: 1,
                          height: 96,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          color: p.border,
                        ),
                        Expanded(child: infoBlock),
                        const SizedBox(width: 14),
                        priceRow,
                      ],
                    )
                  : phone
                  // A phone: coach, programme, then the price with its radio button on one line.
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        coachBlock,
                        const SizedBox(height: 12),
                        infoBlock,
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: priceRow,
                        ),
                      ],
                    )
                  // In between: the price and its radio button sit beside the coach.
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: coachBlock),
                            const SizedBox(width: 12),
                            priceRow,
                          ],
                        ),
                        const SizedBox(height: 12),
                        infoBlock,
                      ],
                    ),
            ),
          ),
          if (recommended)
            Positioned(
              top: -10,
              right: 18,
              child: Container(
                key: const ValueKey('offer-recommended'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [AppColors.violet, AppColors.purple],
                  ),
                ),
                child: Text(
                  'Recommended',
                  style: AppTextStyles.meta(Colors.white)
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: p.secondaryText),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: AppTextStyles.body(p.primaryText))),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.coach, this.size = 84});
  final double size;
  final CoachInfo? coach;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = coach;
    final initials = c == null
        ? '?'
        : c.name
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();
    final fallback = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue, AppColors.violet],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTextStyles.sectionHeading(Colors.white)
            .copyWith(fontSize: size * 0.32),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: c?.avatarUrl == null
            ? fallback
            : Image.network(
                c!.avatarUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// The bottom strip of the programmes card.
class _Features extends StatelessWidget {
  const _Features();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const items = [
      (Icons.sports_tennis_rounded, 'Certified\nCoaches'),
      (Icons.bar_chart_rounded, 'Structured\nTraining'),
      (Icons.groups_2_outlined, 'Small\nBatch Size'),
      (Icons.emoji_events_outlined, 'Skill & Match\nDevelopment'),
      (Icons.calendar_month_outlined, 'Flexible\nTime Slots'),
    ];
    return EnrollCard(
      key: const ValueKey('coaching-features'),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 16,
        spacing: 12,
        children: [
          for (final i in items)
            SizedBox(
              width: 96,
              child: Column(
                children: [
                  Icon(i.$1, size: 30, color: AppColors.violet),
                  const SizedBox(height: 8),
                  Text(
                    i.$2,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.support(p.primaryText)
                        .copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Coaching this phone number already has at the venue: a finished one says so, an unpaid one can be paid from here.
class _Mine extends StatelessWidget {
  const _Mine({
    required this.mine,
    required this.paying,
    required this.onResume,
  });
  final List<MyCoaching> mine;
  final bool paying;
  final ValueChanged<MyCoaching> onResume;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const ValueKey('coaching-mine'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
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
                  'Your coaching here',
                  style: AppTextStyles.cardHeading(p.primaryText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final m in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        m.programName,
                        if (m.settled)
                          (m.feeType == 'MONTHLY' ? 'AutoPay on' : 'Paid')
                        else
                          'Payment pending',
                        if (m.endDate != null && m.settled)
                          'till ${_fullDate(m.endDate!)}',
                      ].join('  ·  '),
                      style: AppTextStyles.body(p.secondaryText),
                    ),
                  ),
                  if (m.awaitingPayment)
                    Pressable(
                      key: ValueKey('mine-resume-${m.programName}'),
                      onTap: paying ? null : () => onResume(m),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          'Complete payment',
                          style: AppTextStyles.body(p.highlight)
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.info,
    required this.offer,
    required this.sport,
    required this.slot,
    required this.ready,
    required this.paying,
    required this.policyOpen,
    required this.onPolicy,
    required this.onPay,
  });

  final CoachingInfo info;
  final CoachingOffer? offer;
  final String? sport;
  final CoachingSlot? slot;
  final bool ready;
  final bool paying;
  final bool policyOpen;
  final VoidCallback onPolicy;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = offer?.program;
    final coach = offer?.batch?.coach;

    Widget row(IconData icon, String label, String value, {Key? key}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 20, color: p.primaryText),
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
    Widget money(
      String label,
      String value, {
      Key? key,
      bool big = false,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: big
                  ? AppTextStyles.sectionHeading(p.primaryText)
                        .copyWith(fontSize: 18)
                  : AppTextStyles.body(color ?? p.primaryText),
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
                : AppTextStyles.body(color ?? p.primaryText)
                      .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );

    final multi = pr != null && pr.isMonthly && pr.cycles > 1;
    final note = !info.accepting
        ? "This club isn't taking online enrolments yet."
        : (pr != null && pr.isMonthly && !info.autopayAvailable)
        ? "This club hasn't turned on monthly AutoPay yet. Please ask the club."
        : offer == null
        ? 'Pick a program to enroll.'
        : !ready
        ? "This program can't be joined from here right now."
        : (pr!.isMonthly
              ? "You'll set up UPI AutoPay on Razorpay's secure page."
              : "You'll pay on Razorpay's secure page.");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EnrollCard(
          key: const ValueKey('coaching-summary'),
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
                      'Enrollment Summary',
                      style: AppTextStyles.sectionHeading(p.primaryText)
                          .copyWith(fontSize: 21),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: p.border),
              row(
                Icons.sports_tennis_rounded,
                'Sport',
                sport ?? '—',
                key: const ValueKey('summary-sport'),
              ),
              row(
                Icons.person_outline_rounded,
                'Coach',
                coach?.name ?? '—',
                key: const ValueKey('summary-coach'),
              ),
              row(
                Icons.layers_outlined,
                'Program',
                pr?.name ?? '—',
                key: const ValueKey('summary-program'),
              ),
              row(
                Icons.schedule_rounded,
                'Time Slot',
                slot?.label ?? (pr == null ? '—' : 'As per the club'),
                key: const ValueKey('summary-slot'),
              ),
              row(
                Icons.calendar_month_outlined,
                'Duration',
                pr?.durationLabel ?? '—',
                key: const ValueKey('summary-duration'),
              ),
              row(
                Icons.event_outlined,
                'Start Date',
                pr?.startDate == null ? '—' : _fullDate(pr!.startDate!),
                key: const ValueKey('summary-start'),
              ),
              row(
                Icons.event_available_outlined,
                'End Date',
                pr == null
                    ? '—'
                    : (pr.endDate == null ? 'Ongoing' : _fullDate(pr.endDate!)),
                key: const ValueKey('summary-end'),
              ),
              const SizedBox(height: 6),
              Container(height: 1, color: p.border),
              const SizedBox(height: 8),
              money(
                pr == null
                    ? 'Program Fee'
                    : (pr.isMonthly
                          ? 'Program Fee (monthly)'
                          : 'Program Fee (one time)'),
                pr == null ? '—' : rupees(pr.baseInr),
                key: const ValueKey('summary-fee'),
              ),
              if (pr != null && pr.discountMinor > 0)
                money(
                  'Early-bird discount',
                  '-${rupees(pr.discountInr)}',
                  key: const ValueKey('summary-discount'),
                  color: AppColors.success,
                ),
              if (pr != null && pr.taxInr > 0)
                money(
                  'Tax (${pr.taxPercent == pr.taxPercent.roundToDouble() ? pr.taxPercent.round() : pr.taxPercent}%)',
                  rupees(pr.taxInr),
                  key: const ValueKey('summary-tax'),
                ),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: p.border,
              ),
              money(
                multi ? 'Total Payable Today' : 'Total Payable',
                pr == null ? '—' : rupees(pr.chargeInr),
                key: const ValueKey('summary-total'),
                big: true,
              ),
              if (multi)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${rupees(pr.chargeInr)} a month for ${pr.cycles} months · ${rupees(pr.totalInr)} in total',
                    key: const ValueKey('summary-total-all'),
                    textAlign: TextAlign.right,
                    style: AppTextStyles.support(p.secondaryText),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (pr != null && !pr.isMonthly)
          _OneTimeCard(amount: pr.chargeInr)
        else
          _AutoPayCard(program: pr, available: info.autopayAvailable),
        const SizedBox(height: 14),
        _Policy(
          open: policyOpen,
          onToggle: onPolicy,
          monthly: pr?.isMonthly ?? true,
        ),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          enabled: onPay != null && !paying,
          label: 'Pay and Enroll',
          child: ExcludeSemantics(
            child: Pressable(
              key: const ValueKey('coaching-pay'),
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
                          colors: [
                            AppColors.blue,
                            AppColors.violet,
                            AppColors.purple,
                          ],
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
                              pr == null
                                  ? 'Pay & Enroll'
                                  : 'Pay & Enroll  ${rupees(pr.chargeInr)}',
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
          note,
          key: const ValueKey('coaching-note'),
          textAlign: TextAlign.center,
          style: AppTextStyles.meta(
            offer != null && !ready ? AppColors.danger : p.mutedText,
          ),
        ),
      ],
    );
  }
}

/// Monthly programmes: paid through UPI AutoPay, which the club's monthly billing needs, so it is shown on and not a switch.
class _AutoPayCard extends StatelessWidget {
  const _AutoPayCard({required this.program, required this.available});
  final CoachingProgram? program;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = program;
    return Container(
      key: const ValueKey('coaching-autopay'),
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
                  pr == null
                      ? 'Monthly programs are paid by UPI AutoPay: set it up once in GPay, PhonePe, Paytm or any UPI app.'
                      : 'Monthly recurring fee. Set up UPI AutoPay once; ${rupees(pr.chargeInr)} is charged every month${pr.cycles > 1 ? ' for ${pr.cycles} months' : ''}, and the first payment is taken today.',
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

/// One-time programmes: a single payment, nothing recurring.
class _OneTimeCard extends StatelessWidget {
  const _OneTimeCard({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const ValueKey('coaching-one-time'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.5)),
        color: AppColors.cyan.withValues(alpha: 0.08),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.payments_outlined, size: 30, color: AppColors.cyan),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'One-time payment',
                  style: AppTextStyles.cardHeading(p.primaryText),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pay ${rupees(amount)} once with UPI, a card or net banking. Nothing recurring: you are not charged again.',
                  style: AppTextStyles.support(p.secondaryText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Policy extends StatelessWidget {
  const _Policy({
    required this.open,
    required this.onToggle,
    required this.monthly,
  });
  final bool open;
  final VoidCallback onToggle;
  final bool monthly;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lines = monthly
        ? const [
            'Cancel anytime before the next billing date.',
            'The coaching remains active until the end of the current period.',
            'No refund for the current period (partial or full).',
            'Cancel auto-renewal anytime from My Coaching.',
          ]
        : const [
            'This is a one-time fee for the whole program.',
            'Nothing is charged again after this payment.',
            'No refund once the fee is paid. Please ask the club for any change.',
          ];
    return Container(
      key: const ValueKey('coaching-policy'),
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

/// The programme cards as a slider when there are several: swipe, or use the arrows at either side; a "1 / 3" counter and dots say
/// how many there are. One card is shown plain, with no arrows.
class _OfferSlider extends StatefulWidget {
  const _OfferSlider({required this.offers, required this.cardBuilder});

  final List<CoachingOffer> offers;
  final Widget Function(CoachingOffer offer) cardBuilder;

  @override
  State<_OfferSlider> createState() => _OfferSliderState();
}

class _OfferSliderState extends State<_OfferSlider> {
  final _ctrl = ScrollController();
  int _index = 0;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_width <= 0 || !_ctrl.hasClients) return;
    final i = (_ctrl.offset / _width).round().clamp(
      0,
      widget.offers.length - 1,
    );
    if (i != _index) setState(() => _index = i);
  }

  @override
  void didUpdateWidget(_OfferSlider old) {
    super.didUpdateWidget(old);
    final same =
        old.offers.length == widget.offers.length &&
        [
          for (var i = 0; i < old.offers.length; i++)
            old.offers[i].key == widget.offers[i].key,
        ].every((e) => e);
    if (!same) {
      // another sport, type or time slot: start again at the first card
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctrl.hasClients) _ctrl.jumpTo(0);
      });
    }
  }

  void _go(int i) {
    final target = i.clamp(0, widget.offers.length - 1);
    if (!_ctrl.hasClients) return;
    _ctrl.animateTo(
      target * _width,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final offers = widget.offers;
    if (offers.length == 1) return widget.cardBuilder(offers.first);
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        final index = _index.clamp(0, offers.length - 1);
        Widget arrow({required bool left, required bool enabled}) => Positioned(
          left: left ? -14 : null,
          right: left ? null : -14,
          top: 0,
          bottom: 0,
          child: Center(
            child: Semantics(
              button: true,
              enabled: enabled,
              label: left ? 'Previous program' : 'Next program',
              child: ExcludeSemantics(
                child: Pressable(
                  key: ValueKey(left ? 'coaching-prev' : 'coaching-next'),
                  onTap: enabled
                      ? () => _go(left ? index - 1 : index + 1)
                      : null,
                  borderRadius: BorderRadius.circular(18),
                  child: Opacity(
                    opacity: enabled ? 1 : 0.35,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.surface,
                        border: Border.all(
                          color: AppColors.violet.withValues(alpha: 0.7),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Icon(
                        left
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        color: p.primaryText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SingleChildScrollView(
                  key: const ValueKey('coaching-slider'),
                  controller: _ctrl,
                  scrollDirection: Axis.horizontal,
                  physics: const PageScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final o in offers)
                        SizedBox(
                          width: _width,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                            child: widget.cardBuilder(o),
                          ),
                        ),
                    ],
                  ),
                ),
                arrow(left: true, enabled: index > 0),
                arrow(left: false, enabled: index < offers.length - 1),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < offers.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: i == index ? 18 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == index ? AppColors.violet : p.border,
                    ),
                  ),
                const SizedBox(width: 10),
                Text(
                  '${index + 1} / ${offers.length}',
                  key: const ValueKey('coaching-slide-count'),
                  style: AppTextStyles.support(p.secondaryText),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
