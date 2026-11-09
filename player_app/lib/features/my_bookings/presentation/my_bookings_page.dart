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
import '../../../core/widgets/venue_scene.dart';
import '../../auth/application/auth_providers.dart';
import '../../my_membership/domain/membership_detail.dart' show clock12;
import '../../my_membership/presentation/details_widgets.dart';
import '../../payments/application/payment_flow.dart';
import '../../payments/data/receipt_pdf.dart';
import '../../payments/domain/payment_receipt.dart';
import '../../player_home/application/player_home_controller.dart';
import '../../player_home/domain/player_dashboard_models.dart'
    show PendingPayment, PendingPaymentKind;
import '../../venues/domain/venue.dart' show rupees;
import '../application/guest_bookings_providers.dart';
import '../domain/cancellation_quote.dart';
import '../domain/guest_booking.dart';
import '../data/guest_bookings_repository.dart' show CancelException;
import 'cancel_booking_dialog.dart';

enum _Tab { upcoming, completed, cancelled }

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

/// "Wed, 23 Sep 2026".
String bookingDate(DateTime d) =>
    '${_weekdays[d.weekday % 7]}, ${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

/// "8:00 PM – 9:00 PM".
String bookingTime(GuestBooking b) =>
    '${clock12('${b.start.hour}:${b.start.minute}')} – ${clock12('${b.end.hour}:${b.end.minute}')}';

/// "Guest Booking": the page a player lands on from Home's Guest Bookings. Upcoming / Completed / Cancelled tabs, the last two past
/// bookings under the upcoming ones, and a details panel for the booking that is picked (on a phone, tapping a booking opens its own
/// "Booking Details" page). Everything comes from the player's own bookings (see `get_my_guest_bookings`, migration 0184).
class MyBookingsPage extends ConsumerStatefulWidget {
  const MyBookingsPage({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  ConsumerState<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends ConsumerState<MyBookingsPage>
    with WidgetsBindingObserver {
  _Tab _tab = _Tab.upcoming;
  String? _selected;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      ref.invalidate(myGuestBookingsProvider);
  }

  List<GuestBooking> _listFor(GuestBookings g) => switch (_tab) {
    _Tab.upcoming => g.upcoming,
    _Tab.completed => g.completed,
    _Tab.cancelled => g.cancelled,
  };

  void _open(GuestBooking b, bool wide) {
    if (wide) {
      setState(() => _selected = b.id);
      return;
    }
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => GuestBookingDetailsPage(
              booking: b,
              onNavigate: widget.onNavigate,
            ),
          ),
        )
        .then((_) {
          if (mounted) ref.invalidate(myGuestBookingsProvider);
        });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    final async = ref.watch(myGuestBookingsProvider);

    final bookButton = GameAllButton.gradient(
      key: const ValueKey('gb-book'),
      label: 'Book a Court',
      icon: Icons.add_rounded,
      onPressed: () => widget.onNavigate(AppRoutes.guestBooking),
    );

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Guest ',
                      style: AppTextStyles.desktopHeroHeading(p.primaryText)
                          .copyWith(fontSize: wide ? 34 : 26),
                    ),
                    TextSpan(
                      text: 'Booking',
                      style: AppTextStyles.desktopHeroHeading(p.primaryText)
                          .copyWith(
                            fontSize: wide ? 34 : 26,
                            foreground: Paint()
                              ..shader =
                                  const LinearGradient(
                                    colors: [
                                      Color(0xFFB57CFF),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ).createShader(
                                    const Rect.fromLTWH(0, 0, 200, 40),
                                  ),
                          ),
                    ),
                  ],
                ),
                key: const ValueKey('gb-title'),
              ),
              const SizedBox(height: 4),
              Text(
                'View and manage your court bookings.',
                style: AppTextStyles.body(p.secondaryText),
              ),
            ],
          ),
        ),
        if (wide) ...[
          SizedBox(
            width: 260,
            height: 84,
            child: ExcludeSemantics(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => const LinearGradient(
                  colors: [
                    Color(0x00000000),
                    Color(0xFF000000),
                    Color(0x00000000),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ).createShader(r),
                child: Image.asset(
                  'assets/images/membership_cork_art.png',
                  key: const ValueKey('gb-art'),
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
        if (wide) bookButton,
      ],
    );

    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const SizedBox(
        height: 320,
        child: Center(
          child: SizedBox(
            key: ValueKey('gb-loading'),
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
            key: const ValueKey('gb-error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: p.secondaryText),
              const SizedBox(height: 14),
              Text(
                "We couldn't load your bookings just now.",
                style: AppTextStyles.body(p.primaryText),
              ),
              const SizedBox(height: 16),
              GameAllButton.secondary(
                label: 'Try again',
                onPressed: () => ref.invalidate(myGuestBookingsProvider),
              ),
            ],
          ),
        ),
      );
    } else {
      final g = async.value ?? const GuestBookings();
      if (g.isEmpty) {
        body = _Empty(onBook: () => widget.onNavigate(AppRoutes.guestBooking));
      } else {
        final list = _listFor(g);
        final selected =
            list.where((b) => b.id == _selected).firstOrNull ??
            (list.isEmpty ? null : list.first);
        final showPast = _tab == _Tab.upcoming && g.lastPast.isNotEmpty;

        final listCard = DetailsCard(
          key: const ValueKey('gb-list'),
          title: switch (_tab) {
            _Tab.upcoming => 'Upcoming Bookings',
            _Tab.completed => 'Completed Bookings',
            _Tab.cancelled => 'Cancelled Bookings',
          },
          child: list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: [
                      Text(
                        switch (_tab) {
                          _Tab.upcoming => 'You have no upcoming bookings.',
                          _Tab.completed => 'No completed bookings yet.',
                          _Tab.cancelled => 'No cancelled bookings.',
                        },
                        key: const ValueKey('gb-tab-empty'),
                        style: AppTextStyles.body(p.secondaryText),
                      ),
                      if (_tab == _Tab.upcoming) ...[
                        const SizedBox(height: 14),
                        GameAllButton.secondary(
                          label: 'Book a Court',
                          onPressed: () =>
                              widget.onNavigate(AppRoutes.guestBooking),
                        ),
                      ],
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (final b in list)
                      _BookingCard(
                        b: b,
                        selected: wide && selected?.id == b.id,
                        onTap: () => _open(b, wide),
                      ),
                  ],
                ),
        );

        final pastCard = !showPast
            ? null
            : DetailsCard(
                key: const ValueKey('gb-past'),
                title: 'Past Bookings',
                trailing: Pressable(
                  key: const ValueKey('gb-view-all'),
                  onTap: () => setState(() {
                    _tab = _Tab.completed;
                    _selected = null;
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View All',
                          style: AppTextStyles.meta(p.highlight).copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
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
                child: Column(
                  children: [
                    for (final b in g.lastPast)
                      _PastRow(b: b, onTap: () => _open(b, wide)),
                  ],
                ),
              );

        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            listCard,
            if (pastCard != null) ...[const SizedBox(height: 18), pastCard],
          ],
        );

        final tabs = PillTabs(
          labels: [
            'Upcoming (${g.upcoming.length})',
            'Completed (${g.completedCount})',
            'Cancelled (${g.cancelledCount})',
          ],
          current: _tab.index,
          onTab: (i) => setState(() {
            _tab = _Tab.values[i];
            _selected = null;
          }),
          keyOf: (i) => 'gb-tab-${_Tab.values[i].name}',
        );

        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tabs,
            const SizedBox(height: 18),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: left),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 4,
                    child: selected == null
                        ? const SizedBox.shrink()
                        : BookingDetailsPanel(
                            booking: selected,
                            onNavigate: widget.onNavigate,
                          ),
                  ),
                ],
              )
            else
              left,
          ],
        );
      }
    }

    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('gb-scroll'),
        padding: EdgeInsets.fromLTRB(side, wide ? 16 : 8, side, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,

            const SizedBox(height: 18),
            Reveal(child: body),
          ],
        ),
      ),
    );
  }
}

// ── pieces ──────────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty({required this.onBook});
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DetailsCard(
      key: const ValueKey('gb-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            Icon(Icons.event_available_outlined, size: 46, color: p.highlight),
            const SizedBox(height: 14),
            Text(
              'No bookings yet',
              style: AppTextStyles.sectionHeading(p.primaryText),
            ),
            const SizedBox(height: 6),
            Text(
              'Book a court in seconds and it will show up here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(p.secondaryText),
            ),
            const SizedBox(height: 20),
            GameAllButton.gradient(label: 'Book a Court', onPressed: onBook),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.b);
  final GuestBooking b;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (b.status) {
      'completed' => (
        'Completed',
        const Color(0xFFB9C4FF),
        Icons.check_rounded,
      ),
      'cancelled' => ('Cancelled', AppColors.danger, Icons.close_rounded),
      'pending' => (
        'Awaiting payment',
        AppColors.warning,
        Icons.schedule_rounded,
      ),
      _ => ('Confirmed', AppColors.success, Icons.check_circle_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.meta(color)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.b, required this.width, required this.height});
  final GuestBooking b;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: width,
      height: height,
      child: b.venue.imageUrl == null
          ? VenueScene(sport: b.sport)
          : Image.network(
              b.venue.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => VenueScene(sport: b.sport),
            ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 17,
          color: p.isDark ? const Color(0xFFB9A4FF) : AppColors.violet,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body(p.primaryText).copyWith(fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.b,
    required this.selected,
    required this.onTap,
  });
  final GuestBooking b;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        key: ValueKey('gb-card-${b.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: p.isDark ? const Color(0xFF111A35) : p.elevated,
            border: Border.all(
              color: selected
                  ? const Color(0xFF9B5CFF)
                  : (p.isDark ? const Color(0xFF2E3B63) : p.border),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF7C5CFF).withValues(alpha: 0.35),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 520;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (narrow) ...[
                    Text(
                      b.venue.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardHeading(p.primaryText)
                          .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusPill(b),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            b.venue.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardHeading(p.primaryText)
                                .copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: _StatusPill(b)),
                      ],
                    ),
                  if (b.venue.place.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: p.secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            b.venue.place,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.support(p.secondaryText),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (narrow)
                    Wrap(
                      spacing: 18,
                      runSpacing: 6,
                      children: [
                        _Meta(
                          Icons.calendar_month_outlined,
                          bookingDate(b.start),
                        ),
                        _Meta(Icons.access_time_rounded, bookingTime(b)),
                        if (b.court != null)
                          _Meta(Icons.grid_view_rounded, b.court!),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Flexible(
                          flex: 5,
                          child: _Meta(
                            Icons.calendar_month_outlined,
                            bookingDate(b.start),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          flex: 5,
                          child: _Meta(
                            Icons.access_time_rounded,
                            bookingTime(b),
                          ),
                        ),
                        if (b.court != null) ...[
                          const SizedBox(width: 14),
                          Flexible(
                            flex: 3,
                            child: _Meta(Icons.grid_view_rounded, b.court!),
                          ),
                        ],
                      ],
                    ),
                ],
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Photo(
                    b: b,
                    width: narrow ? 84 : 110,
                    height: narrow ? 84 : 96,
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: info),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: p.secondaryText,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.b, required this.onTap});
  final GuestBooking b;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = Text(
      b.venue.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.cardHeading(p.primaryText)
          .copyWith(fontSize: 15.5, fontWeight: FontWeight.w700),
    );
    final place = b.venue.place.isEmpty
        ? const SizedBox.shrink()
        : Text(
            b.venue.place,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.support(p.secondaryText),
          );
    return Pressable(
      key: ValueKey('gb-past-${b.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: p.border.withValues(alpha: 0.5)),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 560) {
              // a phone: everything stacks beside the photo
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Photo(b: b, width: 64, height: 58),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        name,
                        place,
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          children: [
                            _Meta(
                              Icons.calendar_month_outlined,
                              bookingDate(b.start),
                            ),
                            _Meta(Icons.access_time_rounded, bookingTime(b)),
                            if (b.court != null)
                              _Meta(Icons.grid_view_rounded, b.court!),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _StatusPill(b),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Photo(b: b, width: 72, height: 58),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [name, place],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Meta(
                        Icons.calendar_month_outlined,
                        bookingDate(b.start),
                      ),
                      const SizedBox(height: 3),
                      _Meta(Icons.access_time_rounded, bookingTime(b)),
                      if (b.court != null) ...[
                        const SizedBox(height: 3),
                        _Meta(Icons.grid_view_rounded, b.court!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(b),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── details ─────────────────────────────────────────────────────────────

/// Everything about one booking, with Reschedule / Cancel Booking / Download Receipt (and Pay balance when something is still owed).
class BookingDetailsPanel extends ConsumerStatefulWidget {
  const BookingDetailsPanel({
    super.key,
    required this.booking,
    required this.onNavigate,
    this.onCancelled,
  });

  final GuestBooking booking;
  final void Function(String route) onNavigate;

  /// Called after the booking was cancelled (a phone page closes itself).
  final VoidCallback? onCancelled;

  @override
  ConsumerState<BookingDetailsPanel> createState() =>
      _BookingDetailsPanelState();
}

class _BookingDetailsPanelState extends ConsumerState<BookingDetailsPanel> {
  bool _busy = false;

  void _say(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Cancelling: shows the player what it would cost (hours left, % deducted, refund) first, then cancels and refunds through Razorpay.
  Future<void> _cancel() async {
    final b = widget.booking;
    final repo = ref.read(guestBookingsRepositoryProvider);
    setState(() => _busy = true);
    CancellationQuote? quote;
    try {
      quote = await repo.cancellationQuote(b.id);
    } on CancelException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (quote == null) {
      _say("We couldn't work out the refund just now. Please try again.");
      return;
    }
    final yes = await showCancelBookingDialog(context, booking: b, quote: quote);
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      final done = await repo.cancel(b.id);
      ref.invalidate(myGuestBookingsProvider);
      ref.invalidate(playerHomeProvider);
      _say(cancelledMessage(done.quote));
      if (mounted) widget.onCancelled?.call();
    } on CancelException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Rescheduling is the club's to decide, so the player is pointed to them.
  void _askClub(String what) {
    final p = context.palette;
    final b = widget.booking;
    final phone = b.venue.phone;
    final opener = ref.read(linkOpenerProvider);
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
                'Ask ${b.venue.name}',
                style: AppTextStyles.sectionHeading(p.primaryText),
              ),
              const SizedBox(height: 10),
              Text(
                'To $what your booking on ${bookingDate(b.start)}, please ask the club. They set the timing and refund rules for it and will update it for you.',
                style: AppTextStyles.body(p.secondaryText),
              ),
              const SizedBox(height: 18),
              if (phone != null)
                GameAllButton.gradient(
                  label: 'Call ${b.venue.name}',
                  onPressed: () async {
                    Navigator.of(sheet).pop();
                    await opener(Uri(scheme: 'tel', path: phone));
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

  Future<void> _download() async {
    final b = widget.booking;
    // everything the work needs is read now, before anything is awaited
    final repo = ref.read(paymentReceiptRepositoryProvider);
    final player = ref.read(currentPlayerProvider);
    final saver = ref.read(receiptSaverProvider);
    final logoLoader = ref.read(receiptLogoProvider);
    setState(() => _busy = true);
    try {
      final r = await repo.receipt(PaymentKind.booking, b.id);
      if (r == null) {
        _say("We couldn't find the receipt for this booking.");
        return;
      }
      final logo = await logoLoader();
      final bytes = await buildReceiptPdf(
        r,
        playerName: player?.fullName,
        playerPhone: player?.phone,
        logoPng: logo,
      );
      await saver(bytes, receiptFileName(r));
      _say('Your receipt is ready.');
    } catch (_) {
      _say("We couldn't create the receipt. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    final b = widget.booking;
    final links = ref.read(pendingPaymentRepositoryProvider);
    final title = '${b.sport ?? 'Court'} booking';
    setState(() => _busy = true);
    try {
      await openPaymentFlow(
        context,
        onNavigate: widget.onNavigate,
        job: PaymentJob(
          kind: PaymentKind.booking,
          title: title,
          venueName: b.venue.name,
          balance: b.paidInr > 0,
          prepare: () async => PaymentTarget(
            id: b.id,
            link: await links.paymentLink(
              PendingPayment(
                kind: PendingPaymentKind.booking,
                id: b.id,
                title: title,
                venueName: b.venue.name,
              ),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(myGuestBookingsProvider);
        ref.read(playerHomeProvider.notifier).refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = widget.booking;
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
            children: [
              Icon(
                icon,
                size: 20,
                color: p.isDark ? const Color(0xFFB9A4FF) : AppColors.violet,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: AppTextStyles.body(p.secondaryText)
                    .copyWith(fontSize: 14),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: value),
              ),
            ],
          ),
        );
    Widget text(String v, {Key? key}) => Text(
      v,
      key: key,
      textAlign: TextAlign.right,
      style: AppTextStyles.body(p.primaryText)
          .copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
    );

    final (payLabel, payColor) = switch (b.payState) {
      'PAID' => ('Paid', AppColors.success),
      'PARTIAL' => ('Advance paid', AppColors.warning),
      _ => ('Pending', AppColors.warning),
    };
    final owes = b.isUpcoming && b.balanceInr > 0;
    final payButtonLabel = b.paidInr > 0 ? 'Pay balance' : 'Complete payment';

    return DetailsCard(
      key: const ValueKey('gb-details'),
      title: 'Booking Details',
      icon: Icons.event_note_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Photo(b: b, width: 96, height: 62),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.venue.name,
                      key: const ValueKey('gb-d-venue'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardHeading(p.primaryText)
                          .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    if (b.venue.place.isNotEmpty)
                      Text(
                        b.venue.place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.support(p.secondaryText),
                      ),
                    const SizedBox(height: 6),
                    _StatusPill(b),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          row(
            Icons.tag_rounded,
            'Booking ID',
            text(b.ref, key: const ValueKey('gb-d-ref')),
          ),
          if (b.sport != null)
            row(
              Icons.sports_tennis_rounded,
              'Sport',
              text(b.sport!, key: const ValueKey('gb-d-sport')),
            ),
          if (b.court != null)
            row(
              Icons.grid_view_rounded,
              'Court',
              text(b.court!, key: const ValueKey('gb-d-court')),
            ),
          row(
            Icons.calendar_month_outlined,
            'Date',
            text(bookingDate(b.start), key: const ValueKey('gb-d-date')),
          ),
          row(
            Icons.access_time_rounded,
            'Time',
            text(
              '${bookingTime(b)} (${b.durationLabel})',
              key: const ValueKey('gb-d-time'),
            ),
          ),
          if (b.players > 1)
            row(
              Icons.people_outline_rounded,
              'Players',
              text('${b.players}', key: const ValueKey('gb-d-players')),
            ),
          row(
            Icons.info_outline_rounded,
            'Amount',
            text(
              b.totalInr > 0 ? rupees(b.totalInr) : 'To be confirmed',
              key: const ValueKey('gb-d-amount'),
            ),
          ),
          if (b.paidInr > 0 && b.payState != 'PAID')
            row(
              Icons.payments_outlined,
              'Paid so far',
              text(rupees(b.paidInr), key: const ValueKey('gb-d-paid')),
            ),
          row(
            Icons.info_outline_rounded,
            'Payment Status',
            Container(
              key: const ValueKey('gb-d-pay'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: payColor.withValues(alpha: 0.2),
                border: Border.all(color: payColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                payLabel,
                style: AppTextStyles.meta(payColor)
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (owes) ...[
            GameAllButton.gradient(
              key: const ValueKey('gb-pay'),
              label: '$payButtonLabel · ${rupees(b.balanceInr)}',
              expand: true,
              onPressed: _busy ? null : _pay,
            ),
            const SizedBox(height: 10),
          ],
          if (b.isUpcoming)
            Row(
              children: [
                Expanded(
                  child: _OutlineAction(
                    key: const ValueKey('gb-reschedule'),
                    icon: Icons.event_repeat_outlined,
                    label: 'Reschedule',
                    onTap: () => _askClub('reschedule'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OutlineAction(
                    key: const ValueKey('gb-cancel'),
                    icon: Icons.cancel_outlined,
                    label: 'Cancel Booking',
                    onTap: _busy ? null : _cancel,
                  ),
                ),
              ],
            ),
          if (b.paidInr > 0) ...[
            const SizedBox(height: 10),
            _OutlineAction(
              key: const ValueKey('gb-receipt'),
              icon: Icons.download_rounded,
              label: _busy ? 'Preparing receipt…' : 'Download Receipt',
              onTap: _busy ? null : _download,
            ),
          ],
        ],
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: p.isDark ? const Color(0xFF3A4A80) : p.border,
          ),
          color: p.isDark ? const Color(0xFF111A35) : p.elevated,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: p.primaryText),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.button(p.primaryText)
                    .copyWith(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Booking Details" as a page of its own (a phone: tapping a booking opens it).
class GuestBookingDetailsPage extends StatelessWidget {
  const GuestBookingDetailsPage({
    super.key,
    required this.booking,
    required this.onNavigate,
  });

  final GuestBooking booking;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      key: const ValueKey('gb-details-page'),
      backgroundColor: p.background,
      appBar: AppBar(
        title: Text(
          'Booking Details',
          style: AppTextStyles.cardHeading(p.primaryText),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          child: BookingDetailsPanel(
            booking: booking,
            onCancelled: () => Navigator.of(context).pop(),
            onNavigate: (r) {
              Navigator.of(context).popUntil((route) => route.isFirst);
              onNavigate(r);
            },
          ),
        ),
      ),
    );
  }
}
