import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sport_icon.dart';
import '../../../core/widgets/venue_scene.dart';
import '../application/venues_providers.dart';
import '../domain/venue.dart';
import '../domain/venue_detail.dart';

/// "Book a Court" for one venue, on its own page: 1 Select Sport, 2 Select Date, 3 Select Court, 4 Select Time Slot, with a Booking
/// Summary beside them (underneath on a phone). The slots are the venue's live availability; booking and payment finish on GameAll's
/// booking page, which Book Now opens for the venue.
class GuestBookingPage extends ConsumerStatefulWidget {
  const GuestBookingPage({
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
  ConsumerState<GuestBookingPage> createState() => _GuestBookingPageState();
}

class _GuestBookingPageState extends ConsumerState<GuestBookingPage> {
  late final DateTime _today = _dayOf(widget.now ?? DateTime.now());

  /// Phone only: the second screen, the Booking Summary, reached with Continue.
  bool _reviewing = false;

  /// How many day chips fit: five on a wide window, four on a phone (as in the design).
  int _chipCount = 5;
  late DateTime _anchor = _today; // the first of the five date chips
  late DateTime _day = _today;
  String? _sportId;
  String? _courtId;

  /// The hours chosen so far (one court, one day). Tap an hour to add it, tap again to take it off.
  final Set<CourtSlot> _picked = {};

  void _toggle(CourtSlot s) =>
      setState(() => _picked.contains(s) ? _picked.remove(s) : _picked.add(s));

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  void _resetBelow({bool sport = false}) {
    if (sport) _courtId = null;
    _picked.clear();
  }

  Future<void> _pickFromCalendar() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 60)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = _dayOf(picked);
      final offset = _day.difference(_anchor).inDays;
      if (offset < 0 || offset >= _chipCount) _anchor = _day;
      _courtId = null;
      _picked.clear();
    });
  }

  Future<void> _book(VenueDetail venue) async {
    final opened = await ref.read(linkOpenerProvider)(
      Uri.parse('${AppConfig.clubSiteUrl}/book/${venue.id}'),
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("We couldn't open the booking page. Please try again."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final async = ref.watch(venueDetailProvider(widget.venueId));
    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const Center(
        child: SizedBox(
          key: ValueKey('booking-loading'),
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    } else if (async.value == null) {
      body = Center(
        key: const ValueKey('booking-missing'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 44, color: p.highlight),
              const SizedBox(height: 14),
              Text(
                "This venue isn't available",
                style: AppTextStyles.sectionHeading(p.primaryText),
              ),
              const SizedBox(height: 16),
              GameAllButton.secondary(
                label: 'See venues',
                onPressed: () => widget.onNavigate(AppRoutes.explore),
              ),
            ],
          ),
        ),
      );
    } else {
      body = _content(context, async.value!);
    }
    if (widget.embedded) return SafeArea(child: body);
    return PopScope(
      canPop: !_reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _reviewing = false);
      },
      child: _scaffold(p, body),
    );
  }

  Widget _scaffold(AppPalette p, Widget body) {
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        leading: IconButton(
          key: const ValueKey('booking-back'),
          tooltip: 'Back',
          onPressed: () => _reviewing
              ? setState(() => _reviewing = false)
              : Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: p.primaryText),
        ),
        title: Text(
          _reviewing ? 'Booking Summary' : 'Book a Court',
          style: AppTextStyles.cardHeading(p.primaryText),
        ),
      ),
      body: SafeArea(child: body),
    );
  }

  /// The phone design: a venue card, then Sport / Date / Court / Time Slot as four small cards and Continue; Continue opens the
  /// Booking Summary with Book Now.
  Widget _phone(BuildContext context, VenueDetail venue) {
    final p = context.palette;
    _sportId ??= venue.sports.isEmpty ? null : venue.sports.first.id;
    final sport = venue.sports.where((s) => s.id == _sportId).firstOrNull;
    final slotsAsync = _sportId == null
        ? null
        : ref.watch(
            courtSlotsProvider(AvailabilityQuery(venue.id, _sportId!, _day)),
          );
    final courts = slotsAsync?.value ?? const <CourtSlots>[];
    final court =
        courts.where((c) => c.courtId == _courtId).firstOrNull ??
        (courts.isEmpty ? null : courts.first);
    final picked =
        (court?.slots.where(_picked.contains).toList() ?? <CourtSlot>[])
          ..sort((a, b) => a.start.compareTo(b.start));
    final mainSport = venue.sports.isEmpty ? null : venue.sports.first.name;
    final multi = venue.sports.length > 1;
    var n = 0;

    if (_reviewing && picked.isNotEmpty) {
      return _PhoneSummary(
        venue: venue,
        sport: sport?.name,
        court: court?.courtName,
        day: _day,
        slots: picked,
        onBook: () => _book(venue),
      );
    }

    Widget equalRow(List<Widget> kids) => Row(
      children: [
        for (var i = 0; i < kids.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: kids[i]),
        ],
      ],
    );

    final dates = Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          () {
            final d = _anchor.add(Duration(days: i));
            return Expanded(
              child: _DateChip(
                key: ValueKey('book-date-${d.year}-${d.month}-${d.day}'),
                day: d,
                selected: d == _day,
                compact: true,
                onTap: () => setState(() {
                  _day = d;
                  _courtId = null;
                  _picked.clear();
                }),
              ),
            );
          }(),
          const SizedBox(width: 8),
        ],
        Semantics(
          button: true,
          label: 'Pick another date',
          child: Pressable(
            key: const ValueKey('book-calendar'),
            onTap: _pickFromCalendar,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 44,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.border),
                color: p.isDark ? const Color(0xFF0E1630) : p.elevated,
              ),
              child: Icon(
                Icons.calendar_month_outlined,
                size: 20,
                color: p.primaryText,
              ),
            ),
          ),
        ),
      ],
    );

    Widget courtsBody;
    final async = slotsAsync;
    if (venue.sports.isEmpty) {
      courtsBody = Text(
        'This venue has no courts open for booking yet.',
        key: const ValueKey('book-none'),
        style: AppTextStyles.body(p.secondaryText),
      );
    } else if (async == null || (async.isLoading && !async.hasValue)) {
      courtsBody = const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: SizedBox(
          key: ValueKey('book-loading'),
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    } else if (async.hasError && !async.hasValue) {
      courtsBody = SlotsError(
        error: async.error,
        onRetry: () => ref.invalidate(
          courtSlotsProvider(AvailabilityQuery(venue.id, _sportId!, _day)),
        ),
      );
    } else if (courts.isEmpty) {
      courtsBody = Text(
        'No slots on this day. Try another day.',
        key: const ValueKey('book-no-slots'),
        style: AppTextStyles.body(p.secondaryText),
      );
    } else {
      Widget courtPill(CourtSlots c) => BookingPill(
        key: ValueKey('book-court-${c.courtName}'),
        compact: true,
        selected: c.courtId == court?.courtId,
        onTap: () => setState(() {
          _courtId = c.courtId;
          _picked.clear();
        }),
        leading: Icon(
          Icons.grid_view_rounded,
          size: 16,
          color: c.courtId == court?.courtId ? Colors.white : p.primaryText,
        ),
        label: c.courtName,
      );
      courtsBody = courts.length <= 3
          ? equalRow([for (final c in courts) courtPill(c)])
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in courts)
                  SizedBox(width: 108, child: courtPill(c)),
              ],
            );
    }

    final slots = court?.slots ?? const <CourtSlot>[];
    final timeBody = courts.isEmpty
        ? Text(
            venue.sports.isEmpty
                ? '—'
                : 'Pick a court once slots are available.',
            style: AppTextStyles.body(p.mutedText),
          )
        : slots.isEmpty
        ? Text(
            'No slots on this court today.',
            key: const ValueKey('book-full'),
            style: AppTextStyles.body(p.secondaryText),
          )
        : LayoutBuilder(
            builder: (context, box) {
              const gap = 10.0;
              final w = (box.maxWidth - gap * 2) / 3;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final s in slots)
                        _SlotChip(
                          key: ValueKey('book-slot-${time12(s.start)}'),
                          slot: s,
                          selected: picked.contains(s),
                          width: w,
                          height: 46,
                          onTap: s.available ? () => _toggle(s) : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tap more than one hour to book them together.',
                    key: const ValueKey('slots-hint'),
                    style: AppTextStyles.support(p.secondaryText),
                  ),
                ],
              );
            },
          );

    return SingleChildScrollView(
      key: const ValueKey('booking-scroll'),
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        6,
        AppDimensions.screenPadding,
        32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhoneVenueCard(venue: venue, mainSport: mainSport, showStats: true),
          const SizedBox(height: 12),
          if (multi) ...[
            _PhoneSection(
              number: ++n,
              title: 'Sport',
              child: equalRow([
                for (final sp in venue.sports)
                  BookingPill(
                    key: ValueKey('book-sport-${sp.name}'),
                    compact: true,
                    selected: sp.id == _sportId,
                    onTap: () => setState(() {
                      _sportId = sp.id;
                      _courtId = null;
                      _picked.clear();
                    }),
                    leading: SportIcon(
                      sp.name,
                      size: 18,
                      color: sp.id == _sportId ? Colors.white : p.primaryText,
                    ),
                    label: sp.name,
                  ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          _PhoneSection(number: ++n, title: 'Date', child: dates),
          const SizedBox(height: 12),
          _PhoneSection(number: ++n, title: 'Court', child: courtsBody),
          const SizedBox(height: 12),
          _PhoneSection(
            number: ++n,
            title: 'Time Slot',
            trailing: Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                _Legend(color: AppColors.success, label: 'Available'),
                _Legend(color: p.mutedText, label: 'Booked'),
              ],
            ),
            child: timeBody,
          ),
          const SizedBox(height: 18),
          Semantics(
            button: true,
            enabled: picked.isNotEmpty,
            label: 'Continue',
            child: ExcludeSemantics(
              child: Pressable(
                key: const ValueKey('book-continue'),
                onTap: picked.isEmpty
                    ? null
                    : () => setState(() => _reviewing = true),
                borderRadius: BorderRadius.circular(30),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: picked.isEmpty
                        ? null
                        : const LinearGradient(
                            colors: [AppColors.violet, AppColors.purple],
                          ),
                    color: picked.isEmpty ? p.elevated : null,
                    boxShadow: picked.isEmpty
                        ? null
                        : [
                            BoxShadow(
                              color: AppColors.violet.withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Continue',
                        style: AppTextStyles.button(
                          picked.isEmpty ? p.mutedText : Colors.white,
                        ).copyWith(fontSize: 17),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: picked.isEmpty ? p.mutedText : Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, VenueDetail venue) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    _chipCount = wide ? 5 : 4;
    if (!wide) return _phone(context, venue);

    _sportId ??= venue.sports.isEmpty ? null : venue.sports.first.id;
    final sport = venue.sports.where((s) => s.id == _sportId).firstOrNull;
    final slotsAsync = _sportId == null
        ? null
        : ref.watch(
            courtSlotsProvider(AvailabilityQuery(venue.id, _sportId!, _day)),
          );
    final courts = slotsAsync?.value ?? const <CourtSlots>[];
    final court =
        courts.where((c) => c.courtId == _courtId).firstOrNull ??
        (courts.isEmpty ? null : courts.first);
    final picked =
        (court?.slots.where(_picked.contains).toList() ?? <CourtSlot>[])
          ..sort((a, b) => a.start.compareTo(b.start));

    final steps = _Steps(
      venue: venue,
      day: _day,
      anchor: _anchor,
      today: _today,
      sportId: _sportId,
      court: court,
      courts: courts,
      slotsAsync: slotsAsync,
      onRetry: () => ref.invalidate(
        courtSlotsProvider(AvailabilityQuery(venue.id, _sportId!, _day)),
      ),
      picked: picked,
      wide: wide,
      dayCount: 5,
      onSport: (id) => setState(() {
        _sportId = id;
        _resetBelow(sport: true);
      }),
      onDay: (d) => setState(() {
        _day = d;
        _courtId = null;
        _picked.clear();
      }),
      onCalendar: _pickFromCalendar,
      onCourt: (id) => setState(() {
        _courtId = id;
        _picked.clear();
      }),
      onSlot: _toggle,
    );
    final summary = _Summary(
      venue: venue,
      sport: sport?.name,
      court: court?.courtName,
      day: _day,
      slots: picked,
      onBook: () => _book(venue),
    );

    return SingleChildScrollView(
      key: const ValueKey('booking-scroll'),
      padding: EdgeInsets.fromLTRB(side, 12, side, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.embedded)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                children: [
                  Icon(Icons.home_outlined, size: 18, color: p.secondaryText),
                  const SizedBox(width: 8),
                  BookingCrumb(
                    key: const ValueKey('crumb-venues'),
                    label: 'Venues',
                    onTap: () => widget.onNavigate(AppRoutes.explore),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: p.secondaryText,
                  ),
                  BookingCrumb(
                    key: const ValueKey('crumb-venue'),
                    label: venue.name,
                    onTap: () =>
                        widget.onNavigate(AppRoutes.venuePath(venue.id)),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: p.secondaryText,
                  ),
                  Flexible(
                    child: Text(
                      'Book a Court',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(p.secondaryText),
                    ),
                  ),
                ],
              ),
            ),
          Reveal(
            dy: 8,
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: steps),
                      const SizedBox(width: 24),
                      SizedBox(width: 380, child: summary),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [steps, const SizedBox(height: 16), summary],
                  ),
          ),
        ],
      ),
    );
  }
}

class BookingCrumb extends StatelessWidget {
  const BookingCrumb({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Text(
        label,
        style: AppTextStyles.body(context.palette.primaryText),
      ),
    ),
  );
}

// ── the four steps ─────────────────────────────────────────────────────────

class _Steps extends StatelessWidget {
  const _Steps({
    required this.venue,
    required this.day,
    required this.anchor,
    required this.today,
    required this.sportId,
    required this.court,
    required this.courts,
    required this.slotsAsync,
    required this.onRetry,
    required this.picked,
    required this.wide,
    required this.dayCount,
    required this.onSport,
    required this.onDay,
    required this.onCalendar,
    required this.onCourt,
    required this.onSlot,
  });

  final VenueDetail venue;
  final DateTime day;
  final DateTime anchor;
  final DateTime today;
  final String? sportId;
  final CourtSlots? court;
  final List<CourtSlots> courts;
  final AsyncValue<List<CourtSlots>>? slotsAsync;
  final VoidCallback onRetry;
  final List<CourtSlot> picked;
  final bool wide;
  final int dayCount;
  final ValueChanged<String> onSport;
  final ValueChanged<DateTime> onDay;
  final VoidCallback onCalendar;
  final ValueChanged<String> onCourt;
  final ValueChanged<CourtSlot> onSlot;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final photo = venue.photos.isEmpty ? null : venue.photos.first;
    final mainSport = venue.sports.isEmpty ? null : venue.sports.first.name;

    Widget step(int n, String title, Widget content) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 230, child: BookingStepTitle(n, title)),
                Expanded(child: content),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookingStepTitle(n, title),
                const SizedBox(height: 14),
                content,
              ],
            ),
    );
    Widget rule() => Container(height: 1, color: p.border);

    final header = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border),
        color: p.surface.withValues(alpha: p.isDark ? 0.5 : 1),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: wide ? 160 : 84,
              height: wide ? 88 : 60,
              child: photo == null
                  ? VenueScene(sport: mainSport)
                  : Image.network(
                      photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => VenueScene(sport: mainSport),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        venue.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.sectionHeading(p.primaryText)
                            .copyWith(fontSize: wide ? 24 : 18),
                      ),
                    ),
                    if (venue.locationVerified) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.verified_rounded,
                        size: wide ? 22 : 18,
                        color: AppColors.violet,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: p.highlight,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        venue.place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(p.secondaryText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (wide) ...[
            Container(
              width: 1,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              color: p.border,
            ),
            Row(
              children: [
                Icon(Icons.grid_view_rounded, size: 24, color: p.primaryText),
                const SizedBox(width: 10),
                Text(
                  venue.courtCount == 1
                      ? '1 Court'
                      : '${venue.courtCount} Courts',
                  style: AppTextStyles.body(p.primaryText),
                ),
              ],
            ),
            if (venue.hoursLabel != null) ...[
              Container(
                width: 1,
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: 18),
                color: p.border,
              ),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 24, color: p.primaryText),
                  const SizedBox(width: 10),
                  Text(
                    venue.hoursLabel!,
                    style: AppTextStyles.body(p.primaryText),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );

    final sports = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final s in venue.sports)
          BookingPill(
            key: ValueKey('book-sport-${s.name}'),
            selected: s.id == sportId,
            onTap: () => onSport(s.id),
            leading: SportIcon(
              s.name,
              size: 20,
              color: s.id == sportId ? Colors.white : p.primaryText,
            ),
            label: s.name,
          ),
      ],
    );

    final dates = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < dayCount; i++)
          () {
            final d = anchor.add(Duration(days: i));
            final on = d == day;
            return _DateChip(
              key: ValueKey('book-date-${d.year}-${d.month}-${d.day}'),
              day: d,
              selected: on,
              onTap: () => onDay(d),
            );
          }(),
        Semantics(
          button: true,
          label: 'Pick another date',
          child: Pressable(
            key: const ValueKey('book-calendar'),
            onTap: onCalendar,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.border),
                color: p.isDark ? const Color(0xFF0E1630) : p.elevated,
              ),
              child: Icon(Icons.calendar_month_outlined, color: p.primaryText),
            ),
          ),
        ),
      ],
    );

    Widget courtsAndSlots;
    final async = slotsAsync;
    if (venue.sports.isEmpty) {
      courtsAndSlots = Text(
        'This venue has no courts open for booking yet.',
        key: const ValueKey('book-none'),
        style: AppTextStyles.body(p.secondaryText),
      );
    } else if (async == null || (async.isLoading && !async.hasValue)) {
      courtsAndSlots = const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: SizedBox(
          key: ValueKey('book-loading'),
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    } else if (async.hasError && !async.hasValue) {
      courtsAndSlots = SlotsError(error: async.error, onRetry: onRetry);
    } else if (courts.isEmpty) {
      courtsAndSlots = Text(
        'No slots on this day. Try another day.',
        key: const ValueKey('book-no-slots'),
        style: AppTextStyles.body(p.secondaryText),
      );
    } else {
      courtsAndSlots = const SizedBox.shrink();
    }

    final courtChips = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final c in courts)
          BookingPill(
            key: ValueKey('book-court-${c.courtName}'),
            selected: c.courtId == court?.courtId,
            onTap: () => onCourt(c.courtId),
            leading: Icon(
              Icons.grid_view_rounded,
              size: 18,
              color: c.courtId == court?.courtId ? Colors.white : p.primaryText,
            ),
            label: c.courtName,
          ),
      ],
    );

    final slotChips = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final s in court?.slots ?? const <CourtSlot>[])
          _SlotChip(
            key: ValueKey('book-slot-${time12(s.start)}'),
            slot: s,
            selected: picked.contains(s),
            onTap: s.available ? () => onSlot(s) : null,
          ),
      ],
    );

    final hasCourts = courts.isNotEmpty;
    return Container(
      padding: EdgeInsets.all(wide ? 22 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.border),
        color: p.surface.withValues(alpha: p.isDark ? 0.45 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (venue.sports.length > 1) ...[
            step(1, 'Select Sport', sports),
            rule(),
          ] else
            const SizedBox(height: 4),
          step(venue.sports.length > 1 ? 2 : 1, 'Select Date', dates),
          rule(),
          if (!hasCourts)
            step(
              venue.sports.length > 1 ? 3 : 2,
              'Select Court',
              courtsAndSlots,
            )
          else ...[
            step(venue.sports.length > 1 ? 3 : 2, 'Select Court', courtChips),
            rule(),
            step(
              venue.sports.length > 1 ? 4 : 3,
              'Select Time Slot',
              court!.slots.isEmpty
                  ? Text(
                      'No slots on this court today.',
                      key: const ValueKey('book-full'),
                      style: AppTextStyles.body(p.secondaryText),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        slotChips,
                        const SizedBox(height: 12),
                        Text(
                          'Tap more than one hour to book them together.',
                          key: const ValueKey('slots-hint'),
                          style: AppTextStyles.support(p.secondaryText),
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

class BookingStepTitle extends StatelessWidget {
  const BookingStepTitle(this.n, this.title, {super.key});
  final int n;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.violet, AppColors.purple],
            ),
          ),
          child: Text(
            '$n',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            title,
            style: AppTextStyles.sectionHeading(p.primaryText)
                .copyWith(fontSize: 18),
          ),
        ),
      ],
    );
  }
}

class BookingPill extends StatelessWidget {
  const BookingPill({
    super.key,
    required this.selected,
    required this.onTap,
    required this.label,
    required this.leading,
    this.compact = false,
  });

  /// The phone's smaller chip (it fills the cell it is given).
  final bool compact;
  final bool selected;
  final VoidCallback onTap;
  final String label;
  final Widget leading;

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
          borderRadius: BorderRadius.circular(26),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: BoxConstraints(minHeight: compact ? 46 : 52),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 24,
              vertical: compact ? 6 : 0,
            ),
            // only the phone's chip fills its cell; on the web it is as wide as its label
            alignment: compact ? Alignment.center : null,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
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
            child: Row(
              mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                leading,
                SizedBox(width: compact ? 6 : 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppTextStyles.body(
                          selected ? Colors.white : p.primaryText,
                        ).copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: compact ? 13 : 14,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    super.key,
    required this.day,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final bool compact;

  final DateTime day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = shortDate(day); // "Sat, 24 Aug"
    final parts = label.split(', ');
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: compact ? null : 92,
            constraints: BoxConstraints(minHeight: compact ? 58 : 62),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppColors.violet, AppColors.purple],
                    )
                  : null,
              color: selected
                  ? null
                  : (p.isDark ? const Color(0xFF0E1630) : p.elevated),
              border: Border.all(color: selected ? AppColors.purple : p.border),
            ),
            // scales down rather than overflowing when the chip is narrow and the text is large
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    parts.first,
                    style: AppTextStyles.body(
                      selected ? Colors.white : p.primaryText,
                    ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    parts.length > 1 ? parts.last : '',
                    style: AppTextStyles.body(
                      selected ? Colors.white : p.primaryText,
                    ).copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    super.key,
    required this.slot,
    required this.selected,
    required this.onTap,
    this.width = 118,
    this.height = 52,
  });

  final double width;
  final double height;

  final CourtSlot slot;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final free = slot.available;
    return Semantics(
      button: true,
      enabled: free,
      selected: selected,
      label: '${time12(slot.start)}${free ? '' : ', booked'}',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: BoxConstraints(
              minWidth: width,
              maxWidth: width,
              minHeight: height,
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppColors.violet, AppColors.purple],
                    )
                  : null,
              color: selected
                  ? null
                  : (free
                        ? AppColors.success.withValues(alpha: 0.08)
                        : p.elevated.withValues(alpha: 0.6)),
              border: Border.all(
                color: selected
                    ? AppColors.purple
                    : (free ? AppColors.success : p.border),
                width: free ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      time12(slot.start),
                      style: AppTextStyles.body(
                        selected
                            ? Colors.white
                            : (free ? p.primaryText : p.mutedText),
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── the booking summary ────────────────────────────────────────────────────

class _Summary extends StatelessWidget {
  const _Summary({
    required this.venue,
    required this.sport,
    required this.court,
    required this.day,
    required this.slots,
    required this.onBook,
  });

  final VenueDetail venue;
  final String? sport;
  final String? court;
  final DateTime day;
  final List<CourtSlot> slots;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = slots.isEmpty ? null : slots.first;
    final time = describeSlots(slots);
    final amount = slotsAmount(slots);

    Widget row(IconData icon, String label, String value, {Key? key}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: p.primaryText),
              const SizedBox(width: 14),
              Text(label, style: AppTextStyles.body(p.primaryText)),
              const Spacer(),
              Flexible(
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

    return Container(
      key: const ValueKey('booking-summary'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.violet.withValues(alpha: 0.6)),
        gradient: LinearGradient(
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
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 30,
                color: p.primaryText,
              ),
              const SizedBox(width: 14),
              Text(
                'Booking Summary',
                style: AppTextStyles.sectionHeading(p.primaryText)
                    .copyWith(fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: p.border),
          row(
            Icons.sports_tennis_rounded,
            'Sport',
            sport ?? '—',
            key: const ValueKey('summary-sport'),
          ),
          Container(height: 1, color: p.border),
          row(
            Icons.grid_view_rounded,
            'Court',
            court ?? '—',
            key: const ValueKey('summary-court'),
          ),
          Container(height: 1, color: p.border),
          row(
            Icons.event_outlined,
            'Date',
            '${shortDate(day)} ${day.year}',
            key: const ValueKey('summary-date'),
          ),
          Container(height: 1, color: p.border),
          row(
            Icons.schedule_rounded,
            'Time',
            time,
            key: const ValueKey('summary-time'),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: p.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                Text(
                  'Amount',
                  style: AppTextStyles.sectionHeading(p.primaryText)
                      .copyWith(fontSize: 19),
                ),
                const Spacer(),
                Text(
                  amount ?? (s == null ? '—' : 'At the venue'),
                  key: const ValueKey('summary-amount'),
                  style: AppTextStyles.desktopHeroHeading(p.primaryText)
                      .copyWith(fontSize: 34),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            enabled: s != null,
            label: 'Book Now',
            child: ExcludeSemantics(
              child: Pressable(
                key: const ValueKey('book-now'),
                onTap: s == null ? null : onBook,
                borderRadius: BorderRadius.circular(30),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: s == null
                        ? null
                        : const LinearGradient(
                            colors: [AppColors.violet, AppColors.purple],
                          ),
                    color: s == null ? p.elevated : null,
                    boxShadow: s == null
                        ? null
                        : [
                            BoxShadow(
                              color: AppColors.violet.withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Book Now',
                        style: AppTextStyles.button(
                          s == null ? p.mutedText : Colors.white,
                        ).copyWith(fontSize: 18),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: s == null ? p.mutedText : Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "You'll confirm and pay on GameAll's booking page.",
            textAlign: TextAlign.center,
            style: AppTextStyles.meta(p.mutedText),
          ),
        ],
      ),
    );
  }
}

// ── phone design pieces ────────────────────────────────────────────────────

class _PhoneVenueCard extends StatelessWidget {
  const _PhoneVenueCard({
    required this.venue,
    required this.mainSport,
    this.showStats = false,
  });

  final VenueDetail venue;
  final String? mainSport;
  final bool showStats;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final photo = venue.photos.isEmpty ? null : venue.photos.first;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
        color: p.surface.withValues(alpha: p.isDark ? 0.55 : 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 92,
                  height: 64,
                  child: photo == null
                      ? VenueScene(sport: mainSport)
                      : Image.network(
                          photo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              VenueScene(sport: mainSport),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            venue.name,
                            key: const ValueKey('booking-venue-name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.sectionHeading(p.primaryText)
                                .copyWith(fontSize: 18),
                          ),
                        ),
                        if (venue.locationVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified_rounded,
                            size: 18,
                            color: AppColors.violet,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: p.highlight,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            venue.place,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.support(p.secondaryText),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showStats) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: p.border),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 18,
                        color: p.primaryText,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          venue.courtCount == 1
                              ? '1 Court'
                              : '${venue.courtCount} Courts',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(p.primaryText),
                        ),
                      ),
                    ],
                  ),
                ),
                if (venue.hoursLabel != null) ...[
                  Container(width: 1, height: 22, color: p.border),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: p.primaryText,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            venue.hoursLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body(p.primaryText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PhoneSection extends StatelessWidget {
  const _PhoneSection({
    required this.number,
    required this.title,
    required this.child,
    this.trailing,
  });

  final int number;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
        color: p.surface.withValues(alpha: p.isDark ? 0.45 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.violet, AppColors.purple],
                  ),
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.body(p.primaryText)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (trailing != null) Flexible(child: trailing!),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const SizedBox(width: 6),
      Text(label, style: AppTextStyles.meta(context.palette.secondaryText)),
    ],
  );
}

/// The phone's second screen: what is about to be booked, the price, and Book Now.
class _PhoneSummary extends StatelessWidget {
  const _PhoneSummary({
    required this.venue,
    required this.sport,
    required this.court,
    required this.day,
    required this.slots,
    required this.onBook,
  });

  final VenueDetail venue;
  final String? sport;
  final String? court;
  final DateTime day;
  final List<CourtSlot> slots;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final time = describeSlots(slots);
    final amount = slotsAmount(slots) ?? 'At the venue';
    final mainSport = venue.sports.isEmpty ? null : venue.sports.first.name;

    Widget row(Widget icon, String label, String value, Key key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 14),
          Text(label, style: AppTextStyles.body(p.primaryText)),
          const Spacer(),
          Flexible(
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

    return SingleChildScrollView(
      key: const ValueKey('booking-summary-scroll'),
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        6,
        AppDimensions.screenPadding,
        32,
      ),
      child: Container(
        key: const ValueKey('booking-summary'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.violet.withValues(alpha: 0.5)),
          color: p.surface.withValues(alpha: p.isDark ? 0.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: p.elevated,
                  ),
                  child: Icon(
                    Icons.calendar_month_outlined,
                    color: p.primaryText,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking Summary',
                        style: AppTextStyles.sectionHeading(p.primaryText)
                            .copyWith(fontSize: 19),
                      ),
                      Text(
                        'Review your booking details',
                        style: AppTextStyles.support(p.secondaryText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _PhoneVenueCard(venue: venue, mainSport: mainSport),
            const SizedBox(height: 6),
            row(
              Icon(Icons.sports_tennis_rounded, size: 22, color: p.primaryText),
              'Sport',
              sport ?? '—',
              const ValueKey('summary-sport'),
            ),
            Container(height: 1, color: p.border),
            row(
              Icon(Icons.grid_view_rounded, size: 22, color: p.primaryText),
              'Court',
              court ?? '—',
              const ValueKey('summary-court'),
            ),
            Container(height: 1, color: p.border),
            row(
              Icon(Icons.event_outlined, size: 22, color: p.primaryText),
              'Date',
              '${shortDate(day)} ${day.year}',
              const ValueKey('summary-date'),
            ),
            Container(height: 1, color: p.border),
            row(
              Icon(Icons.schedule_rounded, size: 22, color: p.primaryText),
              'Time',
              time,
              const ValueKey('summary-time'),
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  for (var i = 0; i < (box.maxWidth / 8).floor(); i++)
                    Expanded(
                      child: Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: p.border,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Text(
                    'Amount',
                    style: AppTextStyles.sectionHeading(p.primaryText)
                        .copyWith(fontSize: 18),
                  ),
                  const Spacer(),
                  Text(
                    amount,
                    key: const ValueKey('summary-amount'),
                    style: AppTextStyles.desktopHeroHeading(p.primaryText)
                        .copyWith(fontSize: 30),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Book Now',
              child: ExcludeSemantics(
                child: Pressable(
                  key: const ValueKey('book-now'),
                  onTap: onBook,
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
                        colors: [AppColors.violet, AppColors.purple],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.violet.withValues(alpha: 0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Text(
                      'Book Now',
                      style: AppTextStyles.button(Colors.white)
                          .copyWith(fontSize: 17),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: p.secondaryText,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    "You'll confirm and pay on GameAll's booking page.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.meta(p.secondaryText),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The chosen hours as the booking will read: hours that follow one another merge ("7:00 PM – 9:00 PM"), separate ones are listed,
/// with the total ("(3 hr)").
String describeSlots(List<CourtSlot> picked) {
  if (picked.isEmpty) return '—';
  final sorted = [...picked]..sort((a, b) => a.start.compareTo(b.start));
  final ranges = <(DateTime, DateTime)>[];
  for (final s in sorted) {
    if (ranges.isNotEmpty && ranges.last.$2 == s.start) {
      ranges[ranges.length - 1] = (ranges.last.$1, s.end);
    } else {
      ranges.add((s.start, s.end));
    }
  }
  final hours =
      sorted.fold<int>(
        0,
        (sum, s) => sum + s.end.difference(s.start).inMinutes,
      ) /
      60;
  return '${ranges.map((r) => timeRange(r.$1, r.$2)).join(', ')} (${hours == hours.roundToDouble() ? hours.round() : hours} hr)';
}

/// The price of all the chosen hours, or null when any of them has no price set.
String? slotsAmount(List<CourtSlot> picked) {
  if (picked.isEmpty) return null;
  var total = 0;
  for (final s in picked) {
    final price = s.priceMinor;
    if (price == null || price <= 0) return null;
    total += price;
  }
  return rupees((total / 100).round());
}

/// The hours could not be loaded: says so, shows what went wrong (so it can be reported) and lets the player try again.
class SlotsError extends StatelessWidget {
  const SlotsError({
    super.key,
    required this.error,
    required this.onRetry,
    this.message = "We couldn't load the slots just now.",
  });
  final String message;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final detail = error.toString().replaceAll(RegExp(r'\s+'), ' ');
    return Column(
      key: const ValueKey('book-error'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: AppTextStyles.body(p.secondaryText)),
        const SizedBox(height: 4),
        Text(
          detail.length > 160 ? '${detail.substring(0, 160)}…' : detail,
          key: const ValueKey('book-error-detail'),
          style: AppTextStyles.meta(p.mutedText),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const ValueKey('book-retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
