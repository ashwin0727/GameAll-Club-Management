import 'dart:math' as math;

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
import '../../../core/widgets/venue_scene.dart';
import '../../player_home/application/player_home_controller.dart';
import '../../payments/application/payment_flow.dart';
import '../../payments/domain/payment_receipt.dart';
import '../../player_home/domain/player_dashboard_models.dart'
    show PendingPayment, PendingPaymentKind;
import '../../venues/application/venues_providers.dart';
import '../../venues/domain/venue.dart' show rupees;
import '../application/membership_detail_providers.dart';
import '../domain/membership_detail.dart';
import 'details_widgets.dart';

enum _Tab { overview, bookings, payments, benefits }

/// "Membership Details": the page a player with an active membership lands on from Home. A purple summary card (plan, status, venue, member
/// since / valid till / membership id), this month's usage, then Overview / Bookings / Payments / Benefits. Everything comes from the
/// player's own membership rows (see `get_my_membership_details`, migration 0180).
class MyMembershipPage extends ConsumerStatefulWidget {
  const MyMembershipPage({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  ConsumerState<MyMembershipPage> createState() => _MyMembershipPageState();
}

class _MyMembershipPageState extends ConsumerState<MyMembershipPage>
    with WidgetsBindingObserver {
  int _index = 0;
  _Tab _tab = _Tab.overview;
  bool _busy = false;

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

  // Back from the payment page (or the browser tab): look again at what is paid.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(myMembershipDetailsProvider);
    }
  }


  Future<void> _pay(MembershipDetail m) async {
    setState(() => _busy = true);
    try {
      await openPaymentFlow(
        context,
        onNavigate: widget.onNavigate,
        job: PaymentJob(
          kind: PaymentKind.membership,
          title: m.planName,
          venueName: m.venue.name,
          prepare: () async => PaymentTarget(
            id: m.id,
            link: await ref
                .read(pendingPaymentRepositoryProvider)
                .paymentLink(
                  PendingPayment(
                    kind: PendingPaymentKind.membership,
                    id: m.id,
                    title: m.planName,
                    venueName: m.venue.name,
                  ),
                ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(myMembershipDetailsProvider);
      }
    }
  }

  final _synced = <String>{};

  /// Razorpay may have taken the payment while our webhook was late: ask once per membership, and reload if it turns out paid.
  void _syncIfUnpaid(MembershipDetail m) {
    if (m.isPaid || m.id.isEmpty || !_synced.add(m.id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final r = await ref
          .read(paymentReceiptRepositoryProvider)
          .sync(PaymentKind.membership, m.id)
          .catchError((_) => null);
      if (mounted && r != null && r.isPaid) {
        ref.invalidate(myMembershipDetailsProvider);
        ref.read(playerHomeProvider.notifier).refresh();
      }
    });
  }

  void _bookSlot(MembershipDetail m) {
    if (m.venue.id.isNotEmpty) {
      widget.onNavigate(AppRoutes.bookPath(m.venue.id));
    }
  }

  void _renew(MembershipDetail m) {
    if (m.venue.id.isEmpty) return;
    // the enrolment page starts on the sport this membership is for
    ref.read(preferredSportProvider.notifier).set(m.slot?.sport);
    widget.onNavigate(AppRoutes.enrollPath(m.venue.id));
  }

  /// Pause and Cancel are decided by the club (refund and session rules are theirs), so the player is pointed to them.
  void _askClub(MembershipDetail m, {required bool cancel}) {
    final p = context.palette;
    final verb = cancel ? 'cancel' : 'pause';
    final phone = m.venue.phone;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: p.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            key: ValueKey('mm-ask-${cancel ? 'cancel' : 'pause'}'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cancel ? 'Cancel membership' : 'Pause membership',
                style: AppTextStyles.sectionHeading(p.primaryText),
              ),
              const SizedBox(height: 10),
              Text(
                'To $verb ${m.planName} at ${m.venue.name}, please ask the club. They set the pause, refund and session rules for your plan, and will update it for you.',
                style: AppTextStyles.body(p.secondaryText),
              ),
              const SizedBox(height: 18),
              if (phone != null)
                GameAllButton.gradient(
                  label: 'Call ${m.venue.name}',
                  onPressed: () async {
                    Navigator.of(sheet).pop();
                    await ref.read(linkOpenerProvider)(
                      Uri(scheme: 'tel', path: phone),
                    );
                  },
                )
              else
                Text(
                  'Ask at the front desk next time you visit.',
                  style: AppTextStyles.support(p.mutedText),
                ),
              const SizedBox(height: 10),
              GameAllButton.secondary(
                label: 'Close',
                onPressed: () => Navigator.of(sheet).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    final async = ref.watch(myMembershipDetailsProvider);

    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const SizedBox(
        height: 320,
        child: Center(
          child: SizedBox(
            key: ValueKey('mm-loading'),
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    } else if (async.hasError && !async.hasValue) {
      body = SizedBox(
        height: 320,
        child: Center(
          child: Column(
            key: const ValueKey('mm-error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: p.secondaryText),
              const SizedBox(height: 14),
              Text(
                "We couldn't load your membership just now.",
                style: AppTextStyles.body(p.primaryText),
              ),
              const SizedBox(height: 16),
              GameAllButton.secondary(
                label: 'Try again',
                onPressed: () => ref.invalidate(myMembershipDetailsProvider),
              ),
            ],
          ),
        ),
      );
    } else {
      final list = async.value ?? const <MembershipDetail>[];
      if (list.isEmpty) {
        body = _Empty(
          onExplore: () => widget.onNavigate(AppRoutes.memberships),
        );
      } else {
        final m = list[_index.clamp(0, list.length - 1)];
        _syncIfUnpaid(m);
        body = _Content(
          list: list,
          m: m,
          index: _index.clamp(0, list.length - 1),
          tab: _tab,
          wide: wide,
          busy: _busy,
          onSwitch: (i) => setState(() {
            _index = i;
            _tab = _Tab.overview;
          }),
          onTab: (t) => setState(() => _tab = t),
          onBook: () => _bookSlot(m),
          onRenew: () => _renew(m),
          onPause: () => _askClub(m, cancel: false),
          onCancel: () => _askClub(m, cancel: true),
          onPay: () => _pay(m),
          onVenue: () {
            if (m.venue.id.isNotEmpty) {
              widget.onNavigate(AppRoutes.venuePath(m.venue.id));
            }
          },
        );
      }
    }

    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('mm-scroll'),
        padding: EdgeInsets.fromLTRB(side, wide ? 16 : 8, side, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Membership Details',
                    key: const ValueKey('mm-title'),
                    style: AppTextStyles.desktopHeroHeading(p.primaryText)
                        .copyWith(fontSize: wide ? 34 : 26),
                  ),
                ),
                Pressable(
                  key: const ValueKey('mm-browse'),
                  onTap: () => widget.onNavigate(AppRoutes.memberships),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      'Browse memberships',
                      style: AppTextStyles.meta(
                        p.highlight,
                      ).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            body,
          ],
        ),
      ),
    );
  }
}

// ── no membership ───────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DetailsCard(
      key: const ValueKey('mm-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            Icon(
              Icons.workspace_premium_outlined,
              size: 46,
              color: p.highlight,
            ),
            const SizedBox(height: 14),
            Text(
              'No active membership',
              style: AppTextStyles.sectionHeading(p.primaryText),
            ),
            const SizedBox(height: 6),
            Text(
              'Join a club to get dedicated court time and save more.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(p.secondaryText),
            ),
            const SizedBox(height: 20),
            GameAllButton.gradient(
              label: 'Explore memberships',
              onPressed: onExplore,
            ),
          ],
        ),
      ),
    );
  }
}

// ── the page content ────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  const _Content({
    required this.list,
    required this.m,
    required this.index,
    required this.tab,
    required this.wide,
    required this.busy,
    required this.onSwitch,
    required this.onTab,
    required this.onBook,
    required this.onRenew,
    required this.onPause,
    required this.onCancel,
    required this.onPay,
    required this.onVenue,
  });

  final List<MembershipDetail> list;
  final MembershipDetail m;
  final int index;
  final _Tab tab;
  final bool wide;
  final bool busy;
  final ValueChanged<int> onSwitch;
  final ValueChanged<_Tab> onTab;
  final VoidCallback onBook;
  final VoidCallback onRenew;
  final VoidCallback onPause;
  final VoidCallback onCancel;
  final VoidCallback onPay;
  final VoidCallback onVenue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hero = _Hero(m: m, wide: wide, onVenue: onVenue);
    final usage = _UsageCard(m: m, onBook: onBook);

    final top = wide
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 7, child: hero),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: usage),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [hero, const SizedBox(height: 14), usage],
          );

    final tabContent = switch (tab) {
      _Tab.overview => _Overview(
        m: m,
        wide: wide,
        onBook: onBook,
        onRenew: onRenew,
        onPause: onPause,
        onCancel: onCancel,
      ),
      _Tab.bookings => _BookingsTab(m: m, onBook: onBook),
      _Tab.payments => _PaymentsTab(m: m, busy: busy, onPay: onPay),
      _Tab.benefits => _BenefitsTab(m: m),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // a player with several memberships picks which one to look at
        if (list.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Pressable(
                    key: ValueKey('mm-switch-$i'),
                    onTap: () => onSwitch(i),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: i == index ? AppColors.violet : p.border,
                        ),
                        color: i == index
                            ? AppColors.violet.withValues(alpha: 0.18)
                            : Colors.transparent,
                      ),
                      child: Text(
                        '${list[i].planName} · ${list[i].venue.name}',
                        style: AppTextStyles.body(p.primaryText).copyWith(
                          fontSize: 13.5,
                          fontWeight: i == index
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (!m.isPaid) ...[
          _PayBanner(m: m, busy: busy, onPay: onPay),
          const SizedBox(height: 16),
        ],
        Reveal(child: top),
        const SizedBox(height: 22),
        _Tabs(current: tab, onTab: onTab),
        const SizedBox(height: 18),
        tabContent,
      ],
    );
  }
}

// ── hero ────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.m, required this.wide, required this.onVenue});

  final MembershipDetail m;
  final bool wide;
  final VoidCallback onVenue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ok = m.isPaid;
    final pillColor = ok
        ? AppColors.success
        : (m.payState == 'FAILED' ? AppColors.danger : AppColors.warning);
    final sport = m.slot?.sport;
    final subtitle = [?sport, m.periodLabel].join(' • ');

    final badge = SizedBox(
      key: const ValueKey('mm-badge'),
      width: wide ? 64 : 54,
      height: wide ? 64 : 54,
      child: const CustomPaint(painter: MembershipCrownBadgePainter()),
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('mm-status'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: pillColor.withValues(alpha: 0.16),
            border: Border.all(color: pillColor.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pillColor,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  m.statusPill,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.meta(pillColor)
                      .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          m.planName,
          key: const ValueKey('mm-plan-name'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.desktopHeroHeading(Colors.white)
              .copyWith(fontSize: wide ? 24 : 20, height: 1.1),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          key: const ValueKey('mm-subtitle'),
          style: AppTextStyles.body(Colors.white.withValues(alpha: 0.85)),
        ),
      ],
    );

    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: wide ? 150 : 110,
        height: wide ? 92 : 78,
        child: m.venue.imageUrl == null
            ? VenueScene(sport: sport)
            : Image.network(
                m.venue.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => VenueScene(sport: sport),
              ),
      ),
    );
    final venueBlock = Row(
      children: [
        photo,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                m.venue.name,
                key: const ValueKey('mm-venue-name'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.cardHeading(Colors.white)
                    .copyWith(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              if (m.venue.place.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        m.venue.place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.support(
                          Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              if (m.venue.id.isNotEmpty)
                Pressable(
                  key: const ValueKey('mm-view-venue'),
                  onTap: onVenue,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      color: Colors.black.withValues(alpha: 0.2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'View Venue',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.button(Colors.white)
                                .copyWith(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    Widget fact(IconData icon, String label, String value, Key key) => Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, size: 19, color: const Color(0xFFC9B8FF)),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.support(
                  Colors.white.withValues(alpha: 0.7),
                ).copyWith(fontSize: 12),
              ),
              Text(
                value,
                key: key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(Colors.white)
                    .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
    final since = m.memberSince ?? m.startDate;
    final facts = <Widget>[
      if (since != null)
        fact(
          Icons.calendar_month_outlined,
          'Member Since',
          fmtDate(since),
          const ValueKey('mm-member-since'),
        ),
      if (m.endDate != null)
        fact(
          Icons.event_available_outlined,
          'Valid Till',
          fmtDate(m.endDate!),
          const ValueKey('mm-valid-till'),
        ),
      if (m.ref.isNotEmpty)
        fact(
          Icons.tag_rounded,
          'Membership ID',
          m.ref,
          const ValueKey('mm-ref'),
        ),
    ];

    // Two cards, as in the design: the plan banner on top (badge, status, name, the shuttlecock), and under it a card with the venue
    // on the left and the membership's dates and ID on the right.
    final banner = Container(
      key: const ValueKey('mm-banner'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
        ),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B0F2E), Color(0xFF15104A), Color(0xFF2A1068)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Stack(
        children: [
          // the design's artwork: the glowing swirl and the shuttlecock, fading into the card on its left
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: wide ? 400 : 190,
            child: ExcludeSemantics(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => const LinearGradient(
                  colors: [Color(0x00000000), Color(0xFF000000)],
                  stops: [0.0, 0.55],
                ).createShader(r),
                child: Image.asset(
                  'assets/images/membership_cork_art.png',
                  key: const ValueKey('mm-banner-art'),
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  filterQuality: FilterQuality.high,
                  isAntiAlias: true,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 14, wide ? 160 : 70, 14),
            child: Row(
              children: [
                badge,
                const SizedBox(width: 16),
                Expanded(child: titleBlock),
              ],
            ),
          ),
        ],
      ),
    );

    final details = Container(
      key: const ValueKey('mm-details'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: p.isDark ? const Color(0xFF0C1230) : const Color(0xFF1B1658),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
        ),
      ),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 5, child: venueBlock),
                if (facts.isNotEmpty) ...[
                  Container(
                    width: 1,
                    height: 96,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  Expanded(
                    flex: 5,
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 14,
                      children: [
                        for (final f in facts) SizedBox(width: 168, child: f),
                      ],
                    ),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                venueBlock,
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      for (final f in facts) SizedBox(width: 200, child: f),
                    ],
                  ),
                ],
              ],
            ),
    );

    return Column(
      key: const ValueKey('mm-hero'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [banner, const SizedBox(height: 12), details],
    );
  }
}

// ── usage ───────────────────────────────────────────────────────────────

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.m, required this.onBook});

  final MembershipDetail m;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final u = m.usage;
    final hasTotal = u.total != null;
    return DetailsCard(
      key: const ValueKey('mm-usage'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "This Month's Usage",
                  style: AppTextStyles.cardHeading(p.primaryText)
                      .copyWith(fontSize: 16),
                ),
              ),
              if (hasTotal)
                Text(
                  '${u.used} / ${u.total} Sessions',
                  key: const ValueKey('mm-usage-count'),
                  style: AppTextStyles.meta(p.secondaryText)
                      .copyWith(fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasTotal) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(
                    height: 12,
                    color: p.isDark ? const Color(0xFF2A3560) : p.border,
                  ),
                  FractionallySizedBox(
                    widthFactor: u.fraction,
                    child: Container(
                      key: const ValueKey('mm-usage-bar'),
                      height: 12,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF7C5CFF), Color(0xFF3D7BFF)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${u.used} Used  ·  ${u.remaining} Remaining',
              key: const ValueKey('mm-usage-text'),
              style: AppTextStyles.body(p.secondaryText).copyWith(fontSize: 14),
            ),
          ] else
            Text(
              'Your sessions will count here once the club has allocated your time slot.',
              key: const ValueKey('mm-usage-none'),
              style: AppTextStyles.support(p.secondaryText),
            ),
          const SizedBox(height: 18),
          if (m.venue.id.isNotEmpty)
            Pressable(
              key: const ValueKey('mm-book-slot'),
              onTap: onBook,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9B5CFF), Color(0xFF3D7BFF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C5CFF).withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      size: 20,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Book a Slot',
                      style: AppTextStyles.button(Colors.white)
                          .copyWith(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── pay banner ──────────────────────────────────────────────────────────

class _PayBanner extends StatelessWidget {
  const _PayBanner({required this.m, required this.busy, required this.onPay});

  final MembershipDetail m;
  final bool busy;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final failed = m.payState == 'FAILED';
    final tint = failed ? AppColors.danger : AppColors.warning;
    final msg = failed
        ? 'Your payment for ${m.planName} did not go through. Please complete it so your membership is not cancelled.'
        : 'Your payment for ${m.planName} is not complete${m.balanceInr > 0 ? ' — ${rupees(m.balanceInr)} to pay' : ''}. Please complete it so your membership is not cancelled.';
    return Container(
      key: const ValueKey('mm-pay-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.6)),
        color: Color.alphaBlend(
          tint.withValues(alpha: p.isDark ? 0.12 : 0.08),
          p.surface,
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 10,
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.schedule_rounded,
            color: tint,
            size: 26,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              msg,
              style: AppTextStyles.body(p.primaryText).copyWith(fontSize: 14),
            ),
          ),
          GameAllButton.gradient(
            key: const ValueKey('mm-pay'),
            label: failed ? 'Retry payment' : 'Complete payment',
            onPressed: busy ? null : onPay,
          ),
        ],
      ),
    );
  }
}

// ── tabs ────────────────────────────────────────────────────────────────

class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onTab});

  final _Tab current;
  final ValueChanged<_Tab> onTab;

  @override
  Widget build(BuildContext context) {
    const labels = {
      _Tab.overview: 'Overview',
      _Tab.bookings: 'Bookings',
      _Tab.payments: 'Payments',
      _Tab.benefits: 'Benefits',
    };
    return PillTabs(
      labels: [for (final t in _Tab.values) labels[t]!],
      current: current.index,
      onTab: (i) => onTab(_Tab.values[i]),
      keyOf: (i) => 'mm-tab-${_Tab.values[i].name}',
    );
  }
}

// ── overview ────────────────────────────────────────────────────────────

class _Overview extends StatelessWidget {
  const _Overview({
    required this.m,
    required this.wide,
    required this.onBook,
    required this.onRenew,
    required this.onPause,
    required this.onCancel,
  });

  final MembershipDetail m;
  final bool wide;
  final VoidCallback onBook;
  final VoidCallback onRenew;
  final VoidCallback onPause;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final plan = _PlanCard(m: m);
    final status = _StatusCard(m: m);
    final actions = _ActionsCard(
      m: m,
      onBook: onBook,
      onRenew: onRenew,
      onPause: onPause,
      onCancel: onCancel,
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          plan,
          const SizedBox(height: 16),
          status,
          const SizedBox(height: 16),
          actions,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: plan),
        const SizedBox(width: 20),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [status, const SizedBox(height: 16), actions],
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.m});
  final MembershipDetail m;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final slot = m.slot;
    Widget row(Widget icon, String label, String? value, Key key) =>
        value == null
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                SizedBox(width: 30, child: Center(child: icon)),
                const SizedBox(width: 14),
                SizedBox(
                  width: 150,
                  child: Text(
                    label,
                    style: AppTextStyles.body(p.secondaryText),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    key: key,
                    style: AppTextStyles.body(p.primaryText)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          );
    final ic = p.isDark ? const Color(0xFFB9A4FF) : AppColors.violet;
    return DetailsCard(
      key: const ValueKey('mm-plan-card'),
      title: 'Membership Plan',
      icon: Icons.layers_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: p.isDark ? const Color(0xFF111A35) : p.elevated,
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 12,
              spacing: 16,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            m.planName,
                            style: AppTextStyles.cardHeading(p.primaryText)
                                .copyWith(fontSize: 18),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: AppColors.violet.withValues(alpha: 0.22),
                              border: Border.all(
                                color: AppColors.violet.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Text(
                              m.periodLabel,
                              key: const ValueKey('mm-period'),
                              style:
                                  AppTextStyles.meta(
                                    p.isDark ? Colors.white : AppColors.violet,
                                  ).copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      if (m.description != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          m.description!,
                          key: const ValueKey('mm-description'),
                          style: AppTextStyles.support(p.secondaryText),
                        ),
                      ],
                    ],
                  ),
                ),
                if (m.priceInr != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Plan Price',
                        style: AppTextStyles.support(p.secondaryText)
                            .copyWith(fontSize: 12),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: rupees(m.priceInr!),
                              style: AppTextStyles.cardHeading(p.primaryText)
                                  .copyWith(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            TextSpan(
                              text: ' / ${m.pricePeriod}',
                              style: AppTextStyles.body(p.secondaryText),
                            ),
                          ],
                        ),
                        key: const ValueKey('mm-price'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          row(
            SportIcon(slot?.sport ?? 'Sport', size: 22, color: ic),
            'Sport',
            slot?.sport,
            const ValueKey('mm-row-sport'),
          ),
          row(
            Icon(Icons.grid_view_rounded, size: 21, color: ic),
            'Court',
            slot?.court,
            const ValueKey('mm-row-court'),
          ),
          row(
            Icon(Icons.schedule_rounded, size: 21, color: ic),
            'Allocated Time Slot',
            slot?.label,
            const ValueKey('mm-row-slot'),
          ),
          row(
            Icon(Icons.layers_outlined, size: 21, color: ic),
            'Session Limit',
            m.sessionLimitLabel,
            const ValueKey('mm-row-limit'),
          ),
          row(
            Icon(Icons.credit_card_rounded, size: 21, color: ic),
            'Payment Mode',
            m.paymentMode,
            const ValueKey('mm-row-payment'),
          ),
          if (slot == null && !m.limited)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'The club has not allocated your court and time slot yet.',
                key: const ValueKey('mm-no-slot'),
                style: AppTextStyles.support(p.mutedText),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.m});
  final MembershipDetail m;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ok = m.isPaid;
    final tint = ok
        ? AppColors.success
        : (m.payState == 'FAILED' ? AppColors.danger : AppColors.warning);
    final start = m.startDate;
    final end = m.endDate;
    const nodeW = 96.0; // width of each step's label; the line runs from the middle of the first to the middle of the last
    const dotSize = 26.0;
    final track = p.isDark ? const Color(0xFF2A3560) : p.border;
    final solidBg = p.isDark ? const Color(0xFF0F1838) : p.background;

    Widget label(String title, String? date, {bool strong = false}) => SizedBox(
      width: nodeW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: AppTextStyles.body(p.primaryText).copyWith(
              fontSize: 13.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (date != null)
            Text(
              date,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: AppTextStyles.support(p.secondaryText)
                  .copyWith(fontSize: 12.5),
            ),
        ],
      ),
    );

    Widget ring({required Color color, required Widget child, Color? fill}) =>
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // opaque, so the line never shows through a step
            color: Color.alphaBlend(fill ?? Colors.transparent, solidBg),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(child: child),
        );

    return DetailsCard(
      key: const ValueKey('mm-status-card'),
      title: 'Membership Status',
      icon: Icons.view_in_ar_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: tint.withValues(alpha: 0.16),
          border: Border.all(color: tint.withValues(alpha: 0.5)),
        ),
        child: Text(
          m.statusShort,
          key: const ValueKey('mm-status-short'),
          style: AppTextStyles.meta(tint)
              .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth.isFinite ? c.maxWidth : 360.0;
            final line = (width - nodeW).clamp(40.0, double.infinity);
            // as in the design: Activated, Active and Expires are three equal steps; the line is green up to the current step
            final nowX = nodeW / 2 + line * 0.5;
            final top = dotSize / 2 - 2;
            return SizedBox(
              height: dotSize + 8 + 38,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // the track, and the part already travelled in green
                  Positioned(
                    left: nodeW / 2,
                    width: line,
                    top: top,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: track,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    left: nodeW / 2,
                    width: nowX - nodeW / 2,
                    top: top,
                    child: Container(
                      key: const ValueKey('mm-progress'),
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Activated
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Column(
                      children: [
                        ring(
                          color: AppColors.success,
                          fill: AppColors.success.withValues(alpha: 0.25),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(height: 8),
                        label('Activated', start == null ? null : fmtDate(start)),
                      ],
                    ),
                  ),
                  // Now
                  Positioned(
                    left: nowX - nodeW / 2,
                    top: 0,
                    child: Column(
                      children: [
                        ring(
                          color: AppColors.success,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        label('Active', 'Now', strong: true),
                      ],
                    ),
                  ),
                  // Expires
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Column(
                      children: [
                        ring(
                          color: p.mutedText,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.mutedText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        label('Expires', end == null ? null : fmtDate(end)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.m,
    required this.onBook,
    required this.onRenew,
    required this.onPause,
    required this.onCancel,
  });

  final MembershipDetail m;
  final VoidCallback onBook;
  final VoidCallback onRenew;
  final VoidCallback onPause;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget tile(
      String key,
      IconData icon,
      String label,
      Color color,
      VoidCallback? onTap,
    ) => Pressable(
      key: ValueKey(key),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: p.isDark ? const Color(0xFF2E3B63) : p.border,
          ),
          color: p.isDark ? const Color(0xFF111A35) : p.elevated,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.7),
                  width: 1.5,
                ),
                color: color.withValues(alpha: 0.14),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: AppTextStyles.meta(p.primaryText)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
    final hasVenue = m.venue.id.isNotEmpty;
    return DetailsCard(
      key: const ValueKey('mm-actions-card'),
      title: 'Quick Actions',
      icon: Icons.bolt_rounded,
      child: LayoutBuilder(
        builder: (context, box) {
          final cols = box.maxWidth >= 420 ? 4 : 2;
          const gap = 10.0;
          final w = (box.maxWidth - gap * (cols - 1)) / cols;
          final tiles = [
            tile(
              'mm-action-book',
              Icons.calendar_month_outlined,
              'Book a Slot',
              AppColors.cyan,
              hasVenue ? onBook : null,
            ),
            tile(
              'mm-action-renew',
              Icons.autorenew_rounded,
              'Renew Membership',
              AppColors.blue,
              hasVenue ? onRenew : null,
            ),
            tile(
              'mm-action-pause',
              Icons.pause_rounded,
              'Pause (Temporary)',
              AppColors.violet,
              onPause,
            ),
            tile(
              'mm-action-cancel',
              Icons.close_rounded,
              'Cancel Membership',
              AppColors.danger,
              onCancel,
            ),
          ];
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        },
      ),
    );
  }
}

// ── bookings / payments / benefits ──────────────────────────────────────

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({required this.m, required this.onBook});

  final MembershipDetail m;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final upcoming = [
      for (final b in m.bookings)
        if (b.upcoming) b,
    ]..sort((a, b) => a.start!.compareTo(b.start!));
    final past = [
      for (final b in m.bookings)
        if (!b.upcoming) b,
    ];
    Widget row(MembershipBooking b) {
      final tint = switch (b.status) {
        'confirmed' => AppColors.cyan,
        'completed' => AppColors.success,
        'cancelled' => AppColors.danger,
        _ => AppColors.warning,
      };
      final when = b.start == null
          ? ''
          : '${fmtDate(b.start!)}  ·  ${clock12('${b.start!.hour}:${b.start!.minute}')}${b.end == null ? '' : ' – ${clock12('${b.end!.hour}:${b.end!.minute}')}'}';
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Row(
          children: [
            SportIcon(
              b.sport ?? 'Sport',
              size: 22,
              color: p.isDark ? const Color(0xFFB9A4FF) : AppColors.violet,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    when,
                    style: AppTextStyles.body(p.primaryText)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [?b.court, ?b.sport].join(' · '),
                    style: AppTextStyles.support(p.secondaryText),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: tint.withValues(alpha: 0.14),
                border: Border.all(color: tint.withValues(alpha: 0.5)),
              ),
              child: Text(
                b.statusLabel,
                style: AppTextStyles.meta(tint)
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return DetailsCard(
      key: const ValueKey('mm-bookings'),
      title: 'Bookings',
      icon: Icons.event_note_outlined,
      child: m.bookings.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Text(
                    m.limited
                        ? 'Your bookings appear here after the latest update.'
                        : 'No bookings yet. Book a slot to get started.',
                    key: const ValueKey('mm-no-bookings'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(p.secondaryText),
                  ),
                  if (m.venue.id.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    GameAllButton.gradient(
                      label: 'Book a Slot',
                      onPressed: onBook,
                    ),
                  ],
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (upcoming.isNotEmpty) ...[
                  Text(
                    'Upcoming',
                    style: AppTextStyles.cardHeading(p.primaryText)
                        .copyWith(fontSize: 14),
                  ),
                  for (final b in upcoming) row(b),
                  const SizedBox(height: 16),
                ],
                if (past.isNotEmpty) ...[
                  Text(
                    'Past',
                    style: AppTextStyles.cardHeading(p.primaryText)
                        .copyWith(fontSize: 14),
                  ),
                  for (final b in past) row(b),
                ],
              ],
            ),
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({
    required this.m,
    required this.busy,
    required this.onPay,
  });

  final MembershipDetail m;
  final bool busy;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget stat(String label, String value, Color color, Key key) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.support(p.secondaryText)
                .copyWith(fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            key: key,
            style: AppTextStyles.cardHeading(color)
                .copyWith(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
    Widget row(MembershipPayment x) {
      final tint = switch (x.status) {
        'paid' => AppColors.success,
        'failed' => AppColors.danger,
        'refunded' => AppColors.cyan,
        _ => AppColors.warning,
      };
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 22,
              color: p.isDark ? const Color(0xFFB9A4FF) : AppColors.violet,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    x.when == null ? '—' : fmtDate(x.when!),
                    style: AppTextStyles.body(p.primaryText)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [?x.method, ?x.reference].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.support(p.secondaryText),
                  ),
                ],
              ),
            ),
            Text(
              rupees(x.amountInr),
              style: AppTextStyles.body(p.primaryText)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 14),
            Container(
              width: 84,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: tint.withValues(alpha: 0.14),
                border: Border.all(color: tint.withValues(alpha: 0.5)),
              ),
              child: Text(
                x.statusLabel,
                textAlign: TextAlign.center,
                style: AppTextStyles.meta(tint)
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return DetailsCard(
      key: const ValueKey('mm-payments'),
      title: 'Payments',
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m.totalInr != null || m.priceInr != null)
            Row(
              children: [
                stat(
                  'Plan Price',
                  rupees(m.totalInr ?? m.priceInr ?? 0),
                  p.primaryText,
                  const ValueKey('mm-pay-total'),
                ),
                stat(
                  'Paid',
                  rupees(m.paidInr),
                  AppColors.success,
                  const ValueKey('mm-pay-paid'),
                ),
                stat(
                  'Balance',
                  rupees(m.balanceInr),
                  m.balanceInr > 0 ? AppColors.warning : p.secondaryText,
                  const ValueKey('mm-pay-balance'),
                ),
              ],
            ),
          const SizedBox(height: 14),
          if (m.payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                m.limited
                    ? 'Your payment history appears here after the latest update.'
                    : 'No payments yet.',
                key: const ValueKey('mm-no-payments'),
                style: AppTextStyles.body(p.secondaryText),
              ),
            )
          else
            for (final x in m.payments) row(x),
          if (!m.isPaid) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: GameAllButton.gradient(
                key: const ValueKey('mm-pay-tab'),
                label: m.payState == 'FAILED'
                    ? 'Retry payment'
                    : 'Complete payment',
                onPressed: busy ? null : onPay,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BenefitsTab extends StatelessWidget {
  const _BenefitsTab({required this.m});
  final MembershipDetail m;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final features = m.features.isNotEmpty
        ? m.features
        : const ['Dedicated court time at your allocated slot'];
    Widget line(
      String text, {
      IconData icon = Icons.check_circle_rounded,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: color ?? AppColors.success),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppTextStyles.body(p.primaryText))),
        ],
      ),
    );
    return DetailsCard(
      key: const ValueKey('mm-benefits'),
      title: 'Benefits',
      icon: Icons.card_giftcard_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m.description != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                m.description!,
                style: AppTextStyles.support(p.secondaryText),
              ),
            ),
          for (final f in features) line(f),
          if (m.sessionLimitLabel != null)
            line(
              m.sessionLimitLabel!,
              icon: Icons.layers_outlined,
              color: p.highlight,
            ),
          if (m.hasAutopay)
            line(
              'Renews automatically with UPI AutoPay',
              icon: Icons.autorenew_rounded,
              color: p.highlight,
            ),
          if (m.registrationFeeInr > 0)
            line(
              'Joining fee ${rupees(m.registrationFeeInr)} (one time)',
              icon: Icons.sell_outlined,
              color: p.secondaryText,
            ),
        ],
      ),
    );
  }
}

// ── shared card ─────────────────────────────────────────────────────────

/// The design's membership badge: a lavender scalloped seal, a deep-violet disc inside it and a crown.
class MembershipCrownBadgePainter extends CustomPainter {
  const MembershipCrownBadgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // the seal: nine soft points
    final seal = Path();
    const n = 9;
    for (var i = 0; i <= 360; i += 3) {
      final a = i * math.pi / 180 - math.pi / 2;
      final rr = r * (0.93 + 0.07 * math.cos(n * a + n * math.pi / 2));
      final pt = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      i == 0 ? seal.moveTo(pt.dx, pt.dy) : seal.lineTo(pt.dx, pt.dy);
    }
    seal.close();
    canvas.drawShadow(seal, const Color(0xFF8B5CF6), 8, true);
    canvas.drawPath(
      seal,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF9B7BFF), Color(0xFF6A3FE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      seal,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.3),
    );
    // the disc
    canvas.drawCircle(
      c,
      r * 0.66,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF4A2AAE), Color(0xFF35208A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.66)),
    );
    canvas.drawCircle(
      c,
      r * 0.66,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.18),
    );
    // the crown
    final w = r * 0.62;
    final top = c.dy - r * 0.22;
    final bottom = c.dy + r * 0.12;
    final left = c.dx - w / 2;
    final crown = Path()
      ..moveTo(left, bottom)
      ..lineTo(left - w * 0.04, top + (bottom - top) * 0.1)
      ..lineTo(left + w * 0.27, top + (bottom - top) * 0.45)
      ..lineTo(c.dx, top)
      ..lineTo(left + w * 0.73, top + (bottom - top) * 0.45)
      ..lineTo(left + w + w * 0.04, top + (bottom - top) * 0.1)
      ..lineTo(left + w, bottom)
      ..close();
    final lav = Paint()..color = const Color(0xFFD9CCFF);
    canvas.drawPath(crown, lav);
    for (final p in [
      Offset(left - w * 0.04, top + (bottom - top) * 0.1),
      Offset(c.dx, top),
      Offset(left + w + w * 0.04, top + (bottom - top) * 0.1),
    ]) {
      canvas.drawCircle(p, r * 0.065, lav);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, bottom + r * 0.07, w, r * 0.08),
        Radius.circular(r * 0.03),
      ),
      lav,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
