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
import '../../my_membership/domain/membership_detail.dart'
    show clock12, daysLabel, fmtDate;
import '../../my_membership/presentation/details_widgets.dart';
import '../../payments/application/payment_flow.dart';
import '../../payments/domain/payment_receipt.dart';
import '../../player_home/application/player_home_controller.dart';
import '../../player_home/domain/player_dashboard_models.dart'
    show PendingPayment, PendingPaymentKind;
import '../../venues/application/venues_providers.dart';
import '../../venues/domain/venue.dart' show rupees;
import '../application/coaching_detail_providers.dart';
import '../domain/coaching_detail.dart';

enum _Tab { overview, sessions, attendance, payments, notes }

const _tabLabels = {
  _Tab.overview: 'Overview',
  _Tab.sessions: 'Sessions',
  _Tab.attendance: 'Attendance',
  _Tab.payments: 'Payments',
  _Tab.notes: 'Coach Notes',
};

const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
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

String _clock(DateTime d) => clock12('${d.hour}:${d.minute}');
String _range(DateTime a, DateTime b) => '${_clock(a)} – ${_clock(b)}';

/// "My Coaching": the page a player enrolled in coaching lands on from Home. A purple summary (programme, status, coach, venue), the
/// programme's progress, then Overview / Sessions / Attendance / Payments / Coach Notes. Everything comes from the club's own records
/// (see `get_my_coaching_details`, migration 0183), the same way Membership Details does.
class MyCoachingPage extends ConsumerStatefulWidget {
  const MyCoachingPage({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  ConsumerState<MyCoachingPage> createState() => _MyCoachingPageState();
}

class _MyCoachingPageState extends ConsumerState<MyCoachingPage>
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

  // Back from the payment page (or the browser tab): look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      ref.invalidate(myCoachingDetailsProvider);
  }

  Future<void> _pay(CoachingDetail c) async {
    setState(() => _busy = true);
    try {
      await openPaymentFlow(
        context,
        onNavigate: widget.onNavigate,
        job: PaymentJob(
          kind: PaymentKind.coaching,
          title: c.programName,
          venueName: c.venue.name,
          prepare: () async => PaymentTarget(
            id: c.id,
            link: await ref
                .read(pendingPaymentRepositoryProvider)
                .paymentLink(
                  PendingPayment(
                    kind: PendingPaymentKind.coaching,
                    id: c.id,
                    title: c.programName,
                    venueName: c.venue.name,
                  ),
                ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(myCoachingDetailsProvider);
        ref.read(playerHomeProvider.notifier).refresh();
      }
    }
  }

  void _renew(CoachingDetail c) {
    if (c.venue.id.isEmpty) return;
    ref.read(preferredSportProvider.notifier).set(c.sport);
    widget.onNavigate(AppRoutes.coachingEnrollPath(c.venue.id));
  }

  /// Reschedule and pause are the club's decision (their session and refund rules), so the player is pointed to them.
  void _askClub(CoachingDetail c, String what) {
    final p = context.palette;
    final phone = c.venue.phone;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: p.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ask ${c.venue.name}',
                style: AppTextStyles.sectionHeading(p.primaryText),
              ),
              const SizedBox(height: 10),
              Text(
                'To $what for ${c.programName}, please ask the club. They set the session and refund rules for the programme and will update it for you.',
                style: AppTextStyles.body(p.secondaryText),
              ),
              const SizedBox(height: 18),
              if (phone != null)
                GameAllButton.gradient(
                  label: 'Call ${c.venue.name}',
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

  Future<void> _contact(CoachingDetail c) async {
    final phone = c.venue.phone;
    if (phone == null) {
      _askClub(c, 'reach your coach');
      return;
    }
    await ref.read(linkOpenerProvider)(Uri(scheme: 'tel', path: phone));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    final async = ref.watch(myCoachingDetailsProvider);

    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const SizedBox(
        height: 320,
        child: Center(
          child: SizedBox(
            key: ValueKey('mc-loading'),
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
            key: const ValueKey('mc-error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: p.secondaryText),
              const SizedBox(height: 14),
              Text(
                "We couldn't load your coaching just now.",
                style: AppTextStyles.body(p.primaryText),
              ),
              const SizedBox(height: 16),
              GameAllButton.secondary(
                label: 'Try again',
                onPressed: () => ref.invalidate(myCoachingDetailsProvider),
              ),
            ],
          ),
        ),
      );
    } else {
      final list = async.value ?? const <CoachingDetail>[];
      if (list.isEmpty) {
        body = _Empty(onExplore: () => widget.onNavigate(AppRoutes.coaching));
      } else {
        final i = _index.clamp(0, list.length - 1);
        final c = list[i];
        body = _Content(
          list: list,
          c: c,
          index: i,
          tab: _tab,
          wide: wide,
          busy: _busy,
          onSwitch: (n) => setState(() {
            _index = n;
            _tab = _Tab.overview;
          }),
          onTab: (t) => setState(() => _tab = t),
          onPay: () => _pay(c),
          onVenue: () {
            if (c.venue.id.isNotEmpty)
              widget.onNavigate(AppRoutes.venuePath(c.venue.id));
          },
          onRenew: () => _renew(c),
          onReschedule: () => _askClub(c, 'reschedule a session'),
          onPause: () => _askClub(c, 'pause'),
          onContact: () => _contact(c),
        );
      }
    }

    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('mc-scroll'),
        padding: EdgeInsets.fromLTRB(side, wide ? 16 : 8, side, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            () {
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Coaching',
                    key: const ValueKey('mc-title'),
                    style: AppTextStyles.desktopHeroHeading(p.primaryText)
                        .copyWith(fontSize: wide ? 34 : 26),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'View your enrolled coaching program, schedule, attendance and progress.',
                    style: AppTextStyles.body(p.secondaryText),
                  ),
                ],
              );
              final browse = Pressable(
                key: const ValueKey('mc-browse'),
                onTap: () => widget.onNavigate(AppRoutes.coaching),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 8 : 0,
                    vertical: 6,
                  ),
                  child: Text(
                    'Browse coaching',
                    style: AppTextStyles.meta(p.highlight)
                        .copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              );
              // a phone: the heading has the whole line, the link sits under it
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: heading),
                        browse,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [heading, browse],
                    );
            }(),
            const SizedBox(height: 18),
            body,
          ],
        ),
      ),
    );
  }
}

// ── no coaching ─────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DetailsCard(
      key: const ValueKey('mc-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            Icon(Icons.school_outlined, size: 46, color: p.highlight),
            const SizedBox(height: 14),
            Text(
              'No active coaching',
              style: AppTextStyles.sectionHeading(p.primaryText),
            ),
            const SizedBox(height: 6),
            Text(
              'Train with certified coaches and improve your game.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(p.secondaryText),
            ),
            const SizedBox(height: 20),
            GameAllButton.gradient(
              label: 'Explore coaching',
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
    required this.c,
    required this.index,
    required this.tab,
    required this.wide,
    required this.busy,
    required this.onSwitch,
    required this.onTab,
    required this.onPay,
    required this.onVenue,
    required this.onRenew,
    required this.onReschedule,
    required this.onPause,
    required this.onContact,
  });

  final List<CoachingDetail> list;
  final CoachingDetail c;
  final int index;
  final _Tab tab;
  final bool wide;
  final bool busy;
  final ValueChanged<int> onSwitch;
  final ValueChanged<_Tab> onTab;
  final VoidCallback onPay;
  final VoidCallback onVenue;
  final VoidCallback onRenew;
  final VoidCallback onReschedule;
  final VoidCallback onPause;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hero = _Hero(c: c, wide: wide, onVenue: onVenue);
    final progress = _ProgressCard(c: c);
    final top = wide
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 7, child: hero),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: progress),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [hero, const SizedBox(height: 14), progress],
          );

    final tabContent = switch (tab) {
      _Tab.overview => _Overview(
        c: c,
        wide: wide,
        onRenew: onRenew,
        onReschedule: onReschedule,
        onPause: onPause,
        onContact: onContact,
        onAllSessions: () => onTab(_Tab.sessions),
      ),
      _Tab.sessions => _SessionsTab(c: c),
      _Tab.attendance => _AttendanceTab(c: c),
      _Tab.payments => _PaymentsTab(c: c, busy: busy, onPay: onPay),
      _Tab.notes => _NotesTab(c: c),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // a player enrolled in several programmes picks which one to look at
        if (list.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Pressable(
                    key: ValueKey('mc-switch-$i'),
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
                        '${list[i].programName} · ${list[i].venue.name}',
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
        if (!c.isPaid) ...[
          _PayBanner(c: c, busy: busy, onPay: onPay),
          const SizedBox(height: 16),
        ],
        if (c.isPaused) ...[_PausedBanner(c: c), const SizedBox(height: 16)],
        Reveal(child: top),
        const SizedBox(height: 22),
        PillTabs(
          labels: [for (final t in _Tab.values) _tabLabels[t]!],
          current: tab.index,
          onTab: (i) => onTab(_Tab.values[i]),
          keyOf: (i) => 'mc-tab-${_Tab.values[i].name}',
        ),
        const SizedBox(height: 18),
        tabContent,
      ],
    );
  }
}

// ── hero ────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.c, required this.wide, required this.onVenue});

  final CoachingDetail c;
  final bool wide;
  final VoidCallback onVenue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pillColor = c.isPaused
        ? AppColors.warning
        : (c.isPaid
              ? AppColors.success
              : (c.payState == 'FAILED'
                    ? AppColors.danger
                    : AppColors.warning));
    final statusText = c.isPaused
        ? 'Paused'
        : (c.isPaid
              ? 'Enrolled'
              : (c.payState == 'FAILED'
                    ? 'Payment Failed'
                    : 'Payment Incomplete'));
    final art =
        (c.sport ?? '').toLowerCase().contains('badminton') ||
        (c.sport ?? '').toLowerCase().contains('padel');

    final badge = Container(
      width: wide ? 64 : 54,
      height: wide ? 64 : 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF9B7BFF), Color(0xFF6A3FE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
            blurRadius: 18,
          ),
        ],
      ),
      child: Center(
        child: SportIcon(
          c.sport ?? 'Sport',
          size: wide ? 32 : 26,
          color: Colors.white,
        ),
      ),
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('mc-status'),
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
                  statusText,
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
          c.sport == null ? c.programName : '${c.sport} – ${c.programName}',
          key: const ValueKey('mc-program-name'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.desktopHeroHeading(Colors.white)
              .copyWith(fontSize: wide ? 24 : 19, height: 1.15),
        ),
        const SizedBox(height: 4),
        Text(
          c.subtitle,
          key: const ValueKey('mc-subtitle'),
          style: AppTextStyles.body(Colors.white.withValues(alpha: 0.85)),
        ),
      ],
    );

    final banner = Container(
      key: const ValueKey('mc-banner'),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF241466), Color(0xFF5128B8), Color(0xFF3A1D94)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Stack(
        children: [
          if (art)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: wide ? 380 : 170,
              child: ExcludeSemantics(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Color(0x00000000), Color(0xFF000000)],
                    stops: [0.0, 0.55],
                  ).createShader(r),
                  child: Image.asset(
                    'assets/images/membership_cork_art.png',
                    key: const ValueKey('mc-banner-art'),
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              14,
              art ? (wide ? 160 : 70) : 18,
              14,
            ),
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

    final coach = c.coach;
    final coachBlock = coach == null
        ? Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 40, color: p.mutedText),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your coach will be assigned by the club.',
                  key: const ValueKey('mc-no-coach'),
                  style: AppTextStyles.body(p.secondaryText),
                ),
              ),
            ],
          )
        : Row(
            children: [
              _Avatar(coach: coach, size: wide ? 78 : 62),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            coach.name,
                            key: const ValueKey('mc-coach-name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardHeading(Colors.white)
                                .copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: Color(0xFFB57CFF),
                        ),
                      ],
                    ),
                    if (coach.certification != null)
                      Text(
                        coach.certification!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.support(
                          Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    if (coach.rating != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 17,
                            color: Color(0xFFFFC857),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            coach.reviews == null
                                ? coach.rating!.toStringAsFixed(1)
                                : '${coach.rating!.toStringAsFixed(1)} (${coach.reviews} reviews)',
                            key: const ValueKey('mc-coach-rating'),
                            style: AppTextStyles.body(Colors.white).copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (coach.experienceLabel != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        child: Text(
                          coach.experienceLabel!,
                          key: const ValueKey('mc-coach-experience'),
                          style: AppTextStyles.support(Colors.white)
                              .copyWith(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

    final venueBlock = Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: wide ? 150 : 100,
            height: wide ? 92 : 72,
            child: c.venue.imageUrl == null
                ? VenueScene(sport: c.sport)
                : Image.network(
                    c.venue.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => VenueScene(sport: c.sport),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.venue.name,
                key: const ValueKey('mc-venue-name'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.cardHeading(Colors.white)
                    .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if (c.venue.place.isNotEmpty) ...[
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
                        c.venue.place,
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
              if (c.venue.id.isNotEmpty)
                Pressable(
                  key: const ValueKey('mc-view-venue'),
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

    final lower = Container(
      padding: const EdgeInsets.all(16),
      color: p.isDark ? const Color(0xFF0C1230) : const Color(0xFF1B1658),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 5, child: coachBlock),
                Container(
                  width: 1,
                  height: 96,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                Expanded(flex: 5, child: venueBlock),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                coachBlock,
                const SizedBox(height: 14),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                const SizedBox(height: 14),
                venueBlock,
              ],
            ),
    );

    return Container(
      key: const ValueKey('mc-hero'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C5CFF)
                .withValues(alpha: p.isDark ? 0.2 : 0.1),
            blurRadius: 28,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [banner, lower],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.coach, required this.size});
  final CoachingCoach coach;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = coach.name.trim().isEmpty
        ? '?'
        : coach.name
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
        ),
      ),
      child: Text(
        initials,
        style: AppTextStyles.sectionHeading(Colors.white)
            .copyWith(fontSize: size * 0.36),
      ),
    );
    final url = coach.avatarUrl;
    if (url == null)
      return KeyedSubtree(key: const ValueKey('mc-avatar'), child: fallback);
    return ClipOval(
      key: const ValueKey('mc-avatar'),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

// ── progress ────────────────────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.c});
  final CoachingDetail c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = c.progress;
    Widget fact(IconData icon, String label, String value, Key key) => Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.border),
          ),
          child: Icon(
            icon,
            size: 19,
            color: p.isDark ? const Color(0xFFC9B8FF) : AppColors.violet,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.support(p.secondaryText)
                    .copyWith(fontSize: 12),
              ),
              Text(
                value,
                key: key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(p.primaryText)
                    .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
    return DetailsCard(
      key: const ValueKey('mc-progress'),
      title: 'Program Progress',
      trailing: Text(
        '${pr.percent}%',
        key: const ValueKey('mc-progress-percent'),
        style: AppTextStyles.cardHeading(p.primaryText).copyWith(fontSize: 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              key: const ValueKey('mc-progress-bar'),
              value: pr.percent / 100,
              minHeight: 10,
              backgroundColor: p.isDark ? const Color(0xFF2A3560) : p.border,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF9B5CFF)),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 18,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 150,
                child: fact(
                  Icons.calendar_month_outlined,
                  'Started On',
                  c.startDate == null ? '—' : fmtDate(c.startDate!),
                  const ValueKey('mc-started'),
                ),
              ),
              SizedBox(
                width: 150,
                child: fact(
                  Icons.event_available_outlined,
                  'Ends On',
                  c.endDate == null ? 'Ongoing' : fmtDate(c.endDate!),
                  const ValueKey('mc-ends'),
                ),
              ),
              SizedBox(
                width: 150,
                child: fact(
                  Icons.view_list_outlined,
                  'Total Sessions',
                  pr.total == null ? '—' : '${pr.total}',
                  const ValueKey('mc-total-sessions'),
                ),
              ),
              SizedBox(
                width: 150,
                child: fact(
                  Icons.check_circle_outline_rounded,
                  'Attended',
                  '${pr.attended}',
                  const ValueKey('mc-attended'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── banners ─────────────────────────────────────────────────────────────

class _PayBanner extends StatelessWidget {
  const _PayBanner({required this.c, required this.busy, required this.onPay});

  final CoachingDetail c;
  final bool busy;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final failed = c.payState == 'FAILED';
    final tint = failed ? AppColors.danger : AppColors.warning;
    final what = c.isMonthly ? 'AutoPay' : 'payment';
    final msg = failed
        ? 'Your $what for ${c.programName} did not go through. Please complete it so you keep your place.'
        : 'Your $what for ${c.programName} is not complete${c.balanceInr > 0 ? ' — ${rupees(c.balanceInr)} to pay' : ''}. Please complete it to keep your place.';
    return Container(
      key: const ValueKey('mc-pay-banner'),
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
            key: const ValueKey('mc-pay'),
            label: failed ? 'Retry payment' : 'Complete payment',
            onPressed: busy ? null : onPay,
          ),
        ],
      ),
    );
  }
}

class _PausedBanner extends StatelessWidget {
  const _PausedBanner({required this.c});
  final CoachingDetail c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const ValueKey('mc-paused-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
        color: AppColors.warning.withValues(alpha: 0.1),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.pause_circle_outline_rounded,
            color: AppColors.warning,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This programme is paused by the club. Sessions are not scheduled until it resumes.',
              style: AppTextStyles.body(p.primaryText).copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── overview ────────────────────────────────────────────────────────────

class _Overview extends StatelessWidget {
  const _Overview({
    required this.c,
    required this.wide,
    required this.onRenew,
    required this.onReschedule,
    required this.onPause,
    required this.onContact,
    required this.onAllSessions,
  });

  final CoachingDetail c;
  final bool wide;
  final VoidCallback onRenew;
  final VoidCallback onReschedule;
  final VoidCallback onPause;
  final VoidCallback onContact;
  final VoidCallback onAllSessions;

  @override
  Widget build(BuildContext context) {
    final details = _ProgramDetails(c: c);
    final upcoming = _UpcomingCard(c: c, onAll: onAllSessions, limit: 3);
    final top = wide
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 6, child: details),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: upcoming),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [details, const SizedBox(height: 16), upcoming],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        const SizedBox(height: 18),
        _Actions(
          onRenew: onRenew,
          onReschedule: onReschedule,
          onPause: onPause,
          onContact: onContact,
        ),
      ],
    );
  }
}

class _ProgramDetails extends StatelessWidget {
  const _ProgramDetails({required this.c});
  final CoachingDetail c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = c.batch;
    final schedule = b == null
        ? null
        : [
            if (b.days.isNotEmpty) daysLabel(b.days),
            if (b.startTime != null && b.endTime != null)
              '${clock12(b.startTime!)} – ${clock12(b.endTime!)}',
          ].where((s) => s.isNotEmpty).join('  |  ');
    final fee = c.isMonthly && c.chargeInr != c.totalInr
        ? '${rupees(c.chargeInr)} / month'
        : rupees(c.totalInr);

    Widget row(IconData icon, String label, Widget value, {Key? key}) =>
        Container(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: p.border.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: p.isDark ? const Color(0xFFB9A4FF) : AppColors.violet,
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 118,
                child: Text(
                  label,
                  style: AppTextStyles.body(p.secondaryText)
                      .copyWith(fontSize: 14),
                ),
              ),
              Expanded(child: value),
            ],
          ),
        );
    Widget text(String v, {Key? key}) => Text(
      v,
      key: key,
      style: AppTextStyles.body(p.primaryText)
          .copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
    );

    return DetailsCard(
      key: const ValueKey('mc-details'),
      title: 'Program Details',
      icon: Icons.assignment_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.sport != null)
            row(
              Icons.sports_tennis_rounded,
              'Sport',
              text(c.sport!, key: const ValueKey('mc-d-sport')),
            ),
          if (c.level != null)
            row(
              Icons.bar_chart_rounded,
              'Level',
              text(c.level!, key: const ValueKey('mc-d-level')),
            ),
          row(
            Icons.groups_2_outlined,
            'Batch Type',
            text(c.batchTypeLabel, key: const ValueKey('mc-d-type')),
          ),
          if (b?.capacity != null)
            row(
              Icons.people_outline_rounded,
              'Batch Size',
              text(
                b!.capacity == 1 ? 'One-to-one' : 'Max ${b.capacity} Players',
                key: const ValueKey('mc-d-size'),
              ),
            ),
          if (schedule != null && schedule.isNotEmpty)
            row(
              Icons.access_time_rounded,
              'Schedule',
              text(schedule, key: const ValueKey('mc-d-schedule')),
            ),
          if (b?.court != null)
            row(
              Icons.location_on_outlined,
              'Court',
              text(b!.court!, key: const ValueKey('mc-d-court')),
            ),
          if (c.durationLabel != null)
            row(
              Icons.calendar_month_outlined,
              'Duration',
              text(
                '${c.durationLabel} (${fmtDate(c.startDate!)} – ${fmtDate(c.endDate!)})',
                key: const ValueKey('mc-d-duration'),
              ),
            ),
          row(
            Icons.currency_rupee_rounded,
            'Program Fee',
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                text(fee, key: const ValueKey('mc-fee')),
                _PayPill(c: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayPill extends StatelessWidget {
  const _PayPill({required this.c});
  final CoachingDetail c;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = c.isPaid
        ? ('Paid', AppColors.success, Icons.check_rounded)
        : (c.payState == 'FAILED'
              ? ('Payment failed', AppColors.danger, Icons.close_rounded)
              : ('Payment pending', AppColors.warning, Icons.schedule_rounded));
    return Container(
      key: const ValueKey('mc-pay-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              style: AppTextStyles.meta(color)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.s,
    required this.venue,
    required this.index,
    required this.past,
  });
  final CoachingSession s;
  final String venue;
  final int index;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, color) = s.cancelled
        ? ('Cancelled', AppColors.danger)
        : s.completed
        ? ('Attended', AppColors.success)
        : past
        ? ('Held', p.mutedText)
        : ('Upcoming', const Color(0xFF38BDF8));
    return Container(
      key: ValueKey('mc-session-${past ? 'past' : 'up'}-$index'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: p.isDark ? const Color(0xFF111A35) : p.elevated,
        border: Border.all(
          color: p.isDark ? const Color(0xFF2E3B63) : p.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: p.isDark ? const Color(0xFF1B2547) : p.surface,
            ),
            child: Column(
              children: [
                Text(
                  _weekdays[s.start.weekday % 7],
                  style: AppTextStyles.body(p.primaryText)
                      .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${s.start.day} ${_months[s.start.month - 1]}',
                  style: AppTextStyles.support(p.secondaryText)
                      .copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _range(s.start, s.end),
                  style: AppTextStyles.body(p.primaryText)
                      .copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: p.secondaryText,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        [venue, ?s.court].join(' – '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.support(p.secondaryText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Text(
              label,
              style: AppTextStyles.meta(color)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.c, required this.onAll, this.limit});
  final CoachingDetail c;
  final VoidCallback onAll;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = limit == null ? c.upcoming : c.upcoming.take(limit!).toList();
    return DetailsCard(
      key: const ValueKey('mc-upcoming'),
      title: 'Upcoming Sessions',
      icon: Icons.event_note_outlined,
      trailing: limit != null && c.upcoming.length > limit!
          ? Pressable(
              key: const ValueKey('mc-view-all'),
              onTap: onAll,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: AppTextStyles.meta(
                        p.highlight,
                      ).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
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
            )
          : null,
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                c.isPaused ? 'No sessions while the programme is paused.' : 'No upcoming sessions yet. Your club schedules them for your batch.',
                key: const ValueKey('mc-no-upcoming'),
                style: AppTextStyles.body(p.secondaryText),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _SessionRow(
                    s: items[i],
                    venue: c.venue.name,
                    index: i,
                    past: false,
                  ),
              ],
            ),
    );
  }
}

// ── quick actions ───────────────────────────────────────────────────────

class _Actions extends StatelessWidget {
  const _Actions({
    required this.onRenew,
    required this.onReschedule,
    required this.onPause,
    required this.onContact,
  });

  final VoidCallback onRenew;
  final VoidCallback onReschedule;
  final VoidCallback onPause;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget action(
      String key,
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? tint,
    }) => Pressable(
      key: ValueKey('mc-action-$key'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: p.isDark ? const Color(0xFF111A35) : p.elevated,
          border: Border.all(
            color: p.isDark ? const Color(0xFF2E3B63) : p.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color:
                  tint ??
                  (p.isDark ? const Color(0xFFB9A4FF) : AppColors.violet),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(p.primaryText)
                    .copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
    final items = [
      action(
        'reschedule',
        Icons.event_repeat_outlined,
        'Reschedule Session',
        onReschedule,
      ),
      action(
        'pause',
        Icons.pause_circle_outline_rounded,
        'Pause Coaching',
        onPause,
      ),
      action('renew', Icons.autorenew_rounded, 'Renew Program', onRenew),
      action(
        'contact',
        Icons.phone_in_talk_outlined,
        'Contact Coach',
        onContact,
        tint: AppColors.success,
      ),
    ];
    return DetailsCard(
      key: const ValueKey('mc-actions'),
      title: 'Quick Actions',
      icon: Icons.bolt_outlined,
      child: LayoutBuilder(
        builder: (context, box) {
          final cols = box.maxWidth >= 760 ? 4 : (box.maxWidth >= 380 ? 2 : 1);
          final w = (box.maxWidth - (cols - 1) * 12) / cols;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final a in items) SizedBox(width: w, child: a)],
          );
        },
      ),
    );
  }
}

// ── sessions / attendance ───────────────────────────────────────────────

class _SessionsTab extends StatelessWidget {
  const _SessionsTab({required this.c});
  final CoachingDetail c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const ValueKey('mc-sessions-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UpcomingCard(c: c, onAll: () {}),
        const SizedBox(height: 16),
        DetailsCard(
          title: 'Past Sessions',
          icon: Icons.history_rounded,
          child: c.past.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'No sessions yet.',
                    key: const ValueKey('mc-no-past'),
                    style: AppTextStyles.body(p.secondaryText),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < c.past.length; i++)
                      _SessionRow(
                        s: c.past[i],
                        venue: c.venue.name,
                        index: i,
                        past: true,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AttendanceTab extends StatelessWidget {
  const _AttendanceTab({required this.c});
  final CoachingDetail c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = c.progress;
    final cancelled = c.past.where((s) => s.cancelled).length;
    Widget stat(String label, String value, Key key) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            key: key,
            style: AppTextStyles.desktopHeroHeading(p.primaryText)
                .copyWith(fontSize: 28),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.support(p.secondaryText),
          ),
        ],
      ),
    );
    return Column(
      key: const ValueKey('mc-attendance-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailsCard(
          title: 'Attendance',
          icon: Icons.fact_check_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  stat(
                    'Attended',
                    '${pr.attended}',
                    const ValueKey('mc-att-attended'),
                  ),
                  stat(
                    'Total sessions',
                    pr.total == null ? '—' : '${pr.total}',
                    const ValueKey('mc-att-total'),
                  ),
                  stat(
                    'Cancelled by club',
                    '$cancelled',
                    const ValueKey('mc-att-cancelled'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Attendance counts the sessions your club has marked as held for your batch.',
                style: AppTextStyles.support(p.mutedText),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DetailsCard(
          title: 'Session history',
          icon: Icons.history_rounded,
          child: c.past.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'No sessions yet.',
                    key: const ValueKey('mc-no-history'),
                    style: AppTextStyles.body(p.secondaryText),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < c.past.length; i++)
                      _SessionRow(
                        s: c.past[i],
                        venue: c.venue.name,
                        index: i,
                        past: true,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ── payments ────────────────────────────────────────────────────────────

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({
    required this.c,
    required this.busy,
    required this.onPay,
  });
  final CoachingDetail c;
  final bool busy;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row(String label, String value, {Key? key, bool bold = false}) =>
        Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: p.border.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: AppTextStyles.body(p.secondaryText)
                    .copyWith(fontSize: 14),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  key: key,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.body(p.primaryText).copyWith(
                    fontSize: 14.5,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
    return Column(
      key: const ValueKey('mc-payments-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailsCard(
          title: 'Fee',
          icon: Icons.receipt_long_outlined,
          trailing: _PayPill(c: c),
          child: Column(
            children: [
              row(
                'Program fee',
                rupees(c.totalInr),
                key: const ValueKey('mc-pay-total'),
              ),
              if (c.isMonthly && c.chargeInr != c.totalInr)
                row(
                  'Charged each month (UPI AutoPay)',
                  rupees(c.chargeInr),
                  key: const ValueKey('mc-pay-charge'),
                ),
              row(
                'Paid so far',
                rupees(c.paidInr),
                key: const ValueKey('mc-pay-paid'),
              ),
              if (c.balanceInr > 0 && !c.isMonthly)
                row(
                  'Balance',
                  rupees(c.balanceInr),
                  key: const ValueKey('mc-pay-balance'),
                  bold: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DetailsCard(
          title: 'Payment history',
          icon: Icons.history_rounded,
          child: c.payments.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    c.isMonthly && c.isPaid
                        ? 'Your monthly charge is taken by UPI AutoPay.'
                        : 'No payments yet.',
                    key: const ValueKey('mc-no-payments'),
                    style: AppTextStyles.body(p.secondaryText),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < c.payments.length; i++)
                      Container(
                        key: ValueKey('mc-payment-$i'),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: p.border.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.payments[i].paidAt == null
                                        ? 'Not paid'
                                        : fmtDate(c.payments[i].paidAt!),
                                    style: AppTextStyles.body(p.primaryText)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    [
                                      ?c.payments[i].method,
                                      ?c.payments[i].reference,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.support(
                                      p.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  rupees(c.payments[i].amountInr),
                                  style: AppTextStyles.body(p.primaryText)
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  c.payments[i].status == 'paid'
                                      ? 'Paid'
                                      : (c.payments[i].status == 'failed'
                                            ? 'Failed'
                                            : c.payments[i].status),
                                  style: AppTextStyles.support(
                                    c.payments[i].status == 'paid'
                                        ? AppColors.success
                                        : (c.payments[i].status == 'failed'
                                              ? AppColors.danger
                                              : p.secondaryText),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        if (!c.isPaid) ...[
          const SizedBox(height: 16),
          GameAllButton.gradient(
            key: const ValueKey('mc-pay-tab'),
            label: c.payState == 'FAILED'
                ? 'Retry payment'
                : 'Complete payment',
            onPressed: busy ? null : onPay,
          ),
        ],
      ],
    );
  }
}

// ── coach notes ─────────────────────────────────────────────────────────

class _NotesTab extends StatelessWidget {
  const _NotesTab({required this.c});
  final CoachingDetail c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Color tint(String s) => switch (s) {
      'EXCELLING' => AppColors.success,
      'NEEDS_WORK' => AppColors.warning,
      'AT_RISK' => AppColors.danger,
      _ => const Color(0xFF38BDF8),
    };
    return DetailsCard(
      key: const ValueKey('mc-notes-tab'),
      title: 'Coach Notes',
      icon: Icons.edit_note_rounded,
      child: c.notes.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                "Your coach hasn't added any notes yet.",
                key: const ValueKey('mc-no-notes'),
                style: AppTextStyles.body(p.secondaryText),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < c.notes.length; i++)
                  Container(
                    key: ValueKey('mc-note-$i'),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: p.isDark ? const Color(0xFF111A35) : p.elevated,
                      border: Border.all(
                        color: p.isDark ? const Color(0xFF2E3B63) : p.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.notes[i].skill ?? 'Coach feedback',
                                style: AppTextStyles.body(p.primaryText)
                                    .copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: tint(c.notes[i].progress)
                                    .withValues(alpha: 0.16),
                                border: Border.all(
                                  color: tint(c.notes[i].progress)
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                c.notes[i].progressLabel,
                                style:
                                    AppTextStyles.meta(
                                      tint(c.notes[i].progress),
                                    ).copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          c.notes[i].note,
                          style: AppTextStyles.body(p.primaryText)
                              .copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            ?c.notes[i].coach,
                            if (c.notes[i].createdAt != null)
                              fmtDate(c.notes[i].createdAt!),
                          ].join(' · '),
                          style: AppTextStyles.support(p.mutedText),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
