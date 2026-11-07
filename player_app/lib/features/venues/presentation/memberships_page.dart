import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sport_icon.dart';
import '../../../core/widgets/venue_scene.dart';
import '../../player_home/application/player_home_controller.dart';
import '../application/membership_filters.dart';
import '../application/venue_filters.dart';
import '../application/venues_providers.dart';
import '../domain/venue.dart';
import 'discover_venues_page.dart';
import 'no_venues_state.dart';
import 'sport_picker.dart';

/// The three promises under the Memberships banner.
const membershipHighlights = [
  HighlightItem(
    Icons.event_available_outlined,
    'Dedicated Court Time',
    'Play at your preferred slot',
  ),
  HighlightItem(
    Icons.workspace_premium_outlined,
    'Priority Access',
    'Get preferred court bookings',
  ),
  HighlightItem(
    Icons.percent_rounded,
    'Better Value',
    'Save more with long-term plans',
  ),
];

/// "Explore Memberships": the same page as Discover Venues (banner, city + sport + search + grid / list switch in one card, a Filters
/// panel on the left, results on the right), but every result is a venue that has membership plans, with the lowest price of each
/// length (Monthly, 3 Months, 6 Months, Yearly) right on its card and a View Plans button.
class MembershipsPage extends ConsumerStatefulWidget {
  const MembershipsPage({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  ConsumerState<MembershipsPage> createState() => _MembershipsPageState();
}

class _MembershipsPageState extends ConsumerState<MembershipsPage> {
  final _search = TextEditingController();
  final _resultsKey = GlobalKey();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String q) => ref
      .read(membershipFiltersProvider.notifier)
      .update((f) => f.copyWith(query: q));

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    final async = ref.watch(
      venuesForSelectedCityProvider(VenueKind.memberships),
    );
    final filters = ref.watch(membershipFiltersProvider);
    final city = ref.watch(selectedCityProvider);
    final all = async.value ?? const <Venue>[];
    final ctl = ref.read(membershipFiltersProvider.notifier);

    // The search box follows the filter state (Clear All empties it).
    if (_search.text != filters.query) _search.text = filters.query;

    Widget inset(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: child,
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('memberships-scroll'),
        padding: const EdgeInsets.only(bottom: 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Reveal(
              dy: 10,
              child: DiscoverBanner(
                wide: wide,
                side: side,
                title: 'Explore ',
                accent: 'Memberships',
                subtitle: 'Long-term play plans with dedicated court time, priority access and more.',
                highlights: membershipHighlights,
                image: 'assets/images/memberships_banner.jpg',
                imageSize: const Size(440, 121),
              ),
            ),
            if (!wide) ...[
              const SizedBox(height: 4),
              inset(
                Reveal(
                  delay: const Duration(milliseconds: 20),
                  child: DiscoverHighlights(
                    room: width - side * 2,
                    compact: true,
                    items: membershipHighlights,
                  ),
                ),
              ),
            ],
            SizedBox(height: wide ? 6 : 16),
            inset(
              Reveal(
                delay: const Duration(milliseconds: 40),
                child: DiscoverSearchRow(
                  controller: _search,
                  city: city,
                  venues: all,
                  wide: wide,
                  hint: 'Search venues (e.g., "Champz Turf")',
                  onChanged: _setQuery,
                  onSearch: () => _setQuery(_search.text),
                  sport: filters.sport,
                  onSport: (s) => ctl.update((f) => f.copyWith(sport: s)),
                  view: filters.view,
                  onView: (v) => ctl.update((f) => f.copyWith(view: v)),
                ),
              ),
            ),
            SizedBox(height: wide ? 26 : 18),
            inset(
              _Results(
                async: async,
                all: all,
                filters: filters,
                wide: wide,
                onNavigate: widget.onNavigate,
                resultsKey: _resultsKey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    required this.async,
    required this.all,
    required this.filters,
    required this.wide,
    required this.onNavigate,
    required this.resultsKey,
  });

  final AsyncValue<List<Venue>> async;
  final List<Venue> all;
  final MembershipFilters filters;
  final bool wide;
  final void Function(String route) onNavigate;
  final GlobalKey resultsKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    if (async.isLoading && !async.hasValue) {
      return const SizedBox(
        height: 300,
        child: Center(
          child: SizedBox(
            key: ValueKey('venues-loading'),
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }
    if (async.hasError && !async.hasValue) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Column(
            key: const ValueKey('venues-error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: p.secondaryText),
              const SizedBox(height: 14),
              Text(
                "We couldn't load memberships just now.",
                style: AppTextStyles.body(p.primaryText),
              ),
              const SizedBox(height: 16),
              GameAllButton.secondary(
                label: 'Try again',
                onPressed: () => ref.invalidate(
                  venuesForSelectedCityProvider(VenueKind.memberships),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (all.isEmpty) {
      return const SizedBox(
        height: 420,
        child: NoVenuesState(kind: VenueKind.memberships),
      );
    }

    final shown = applyMembershipFilters(all, filters);
    final panel = MembershipFiltersPanel(
      onApply: () {
        final target = resultsKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      },
    );

    final results = Column(
      key: resultsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(count: shown.length, wide: wide, filters: filters),
        const SizedBox(height: 18),
        if (shown.isEmpty)
          _NoMatches(
            onClear: () => ref.read(membershipFiltersProvider.notifier).clear(),
          )
        else
          _Cards(
            venues: shown,
            view: filters.view,
            sport: filters.sport,
            onNavigate: onNavigate,
          ),
      ],
    );

    if (!wide) return results;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 264,
          child: Reveal(delay: const Duration(milliseconds: 100), child: panel),
        ),
        const SizedBox(width: 26),
        Expanded(child: results),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.wide,
    required this.filters,
  });

  final int count;
  final bool wide;
  final MembershipFilters filters;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final found = Text(
      count == 1 ? '1 Venue Found' : '$count Venues Found',
      key: const ValueKey('venues-found'),
      style: AppTextStyles.sectionHeading(p.primaryText).copyWith(fontSize: 20),
    );
    if (wide) return Align(alignment: Alignment.centerLeft, child: found);
    return Row(
      children: [
        Expanded(child: found),
        Pressable(
          key: const ValueKey('open-filters'),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            backgroundColor: p.surface,
            builder: (sheet) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: MembershipFiltersPanel(
                  inSheet: true,
                  onApply: () => Navigator.of(sheet).pop(),
                ),
              ),
            ),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
              color: p.surface,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 18, color: p.primaryText),
                const SizedBox(width: 8),
                Text(
                  filters.activeCount == 0
                      ? 'Filters'
                      : 'Filters (${filters.activeCount})',
                  style: AppTextStyles.button(p.primaryText),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      key: const ValueKey('no-matches'),
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 44, color: p.highlight),
          const SizedBox(height: 14),
          Text(
            'No memberships match these filters',
            style: AppTextStyles.sectionHeading(p.primaryText),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different length or sport, or clear the filters.',
            style: AppTextStyles.body(p.secondaryText),
          ),
          const SizedBox(height: 18),
          GameAllButton.secondary(
            label: 'Clear all filters',
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

// ── Filters panel ───────────────────────────────────────────────────────

/// The "Filters" box: Clear All, Membership Duration, Time Slot, Days and "Apply Filters (N)". Each duration and day shows how many
/// venues have it. On a phone it opens in a bottom sheet.
class MembershipFiltersPanel extends ConsumerWidget {
  const MembershipFiltersPanel({super.key, this.inSheet = false, this.onApply});

  final bool inSheet;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final f = ref.watch(membershipFiltersProvider);
    final ctl = ref.read(membershipFiltersProvider.notifier);
    final all =
        ref.watch(venuesForSelectedCityProvider(VenueKind.memberships)).value ??
        const <Venue>[];
    final counts = membershipCounts(all);
    final matching = applyMembershipFilters(all, f).length;

    Widget check(
      String label,
      bool value,
      VoidCallback onTap,
      int count,
      Key key,
    ) => Semantics(
      checked: value,
      label: label,
      child: Pressable(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: value ? AppColors.violet : p.border,
                    width: 1.5,
                  ),
                  color: value ? AppColors.violet : Colors.transparent,
                ),
                child: value
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(p.primaryText)
                      .copyWith(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '($count)',
                key: ValueKey('count-$label'),
                style: AppTextStyles.body(p.secondaryText)
                    .copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(text, style: AppTextStyles.cardHeading(p.primaryText)),
    );
    Widget rule() => Container(
      height: 1,
      margin: const EdgeInsets.only(top: 10),
      color: p.border,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.filter_alt_outlined, size: 20, color: p.primaryText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Filters',
                style: AppTextStyles.sectionHeading(p.primaryText)
                    .copyWith(fontSize: 18),
              ),
            ),
            Pressable(
              key: const ValueKey('clear-filters'),
              onTap: f.activeCount == 0 ? null : ctl.clear,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  'Clear All',
                  style: AppTextStyles.meta(
                    f.activeCount == 0 ? p.mutedText : AppColors.purple,
                  ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(height: 1, color: p.border),
        heading('Membership Duration'),
        for (final d in PlanDuration.values)
          check(
            d.label,
            f.durations.contains(d),
            () => ctl.update((cur) {
              final next = {...cur.durations};
              if (!next.remove(d)) next.add(d);
              return cur.copyWith(durations: next);
            }),
            counts.durations[d] ?? 0,
            ValueKey('filter-duration-${d.name}'),
          ),
        rule(),
        heading('Time Slot'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.border),
            color: p.isDark ? p.background.withValues(alpha: 0.5) : p.elevated,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<TimeSlot>(
              key: const ValueKey('slot-dropdown'),
              isExpanded: true,
              value: f.slot,
              dropdownColor: p.surface,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: p.secondaryText,
              ),
              style: AppTextStyles.body(p.primaryText),
              items: [
                for (final s in TimeSlot.values)
                  DropdownMenuItem(
                    value: s,
                    child: Text(
                      s.label,
                      style: AppTextStyles.body(p.primaryText)
                          .copyWith(fontSize: 14),
                    ),
                  ),
              ],
              onChanged: (s) =>
                  s == null ? null : ctl.update((cur) => cur.copyWith(slot: s)),
            ),
          ),
        ),
        rule(),
        heading('Days'),
        for (final g in DayCover.values)
          check(
            g.label,
            f.days.contains(g),
            () => ctl.update((cur) {
              final next = {...cur.days};
              if (!next.remove(g)) next.add(g);
              return cur.copyWith(days: next);
            }),
            counts.days[g] ?? 0,
            ValueKey('filter-days-${g.name}'),
          ),
        const SizedBox(height: 18),
        // Filters apply as they are ticked; this shows how many venues that leaves and takes you to them
        Pressable(
          key: const ValueKey('apply-filters'),
          onTap: onApply,
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.filter_alt_outlined,
                  size: 20,
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Text(
                  'Apply Filters ($matching)',
                  style: AppTextStyles.button(Colors.white)
                      .copyWith(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (inSheet) return content;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
        color: p.surface.withValues(alpha: p.isDark ? 0.55 : 1),
      ),
      child: content,
    );
  }
}

// ── Cards ───────────────────────────────────────────────────────────────

class _Cards extends StatelessWidget {
  const _Cards({
    required this.venues,
    required this.view,
    required this.sport,
    required this.onNavigate,
  });

  final List<Venue> venues;
  final VenueView view;

  /// The sport picked in the search card (null = all).
  final String? sport;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 18.0;
        final w = box.maxWidth;
        // List: one wide row per venue (as in the design) when there is room, otherwise the stacked card.
        // Grid: stacked cards, two or three across.
        final rowLayout = view == VenueView.list && w >= 900;
        final cols = view == VenueView.list
            ? 1
            : (w >= 1000 ? 3 : (w >= 640 ? 2 : 1));
        final cardWidth = (w - gap * (cols - 1)) / cols;
        Widget card(int i) => SizedBox(
          width: cardWidth,
          child: Reveal(
            key: ValueKey('card-${venues[i].id}'),
            delay: Duration(milliseconds: 30 * (i < 6 ? i : 6)),
            child: _CardHost(
              venue: venues[i],
              row: rowLayout,
              sportFilter: sport,
              onOpen: () => onNavigate(AppRoutes.enrollPath(venues[i].id)),
            ),
          ),
        );
        return Column(
          key: const ValueKey('venue-grid'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var start = 0; start < venues.length; start += cols) ...[
              if (start > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = start;
                      i < start + cols && i < venues.length;
                      i++
                    ) ...[if (i > start) const SizedBox(width: gap), card(i)],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Remembers which sport a venue's card is showing. The sport picked in the search card wins when the venue has it; a chip tapped on
/// the card overrides that until the search card's sport changes again.
class _CardHost extends StatefulWidget {
  const _CardHost({
    required this.venue,
    required this.row,
    required this.sportFilter,
    required this.onOpen,
  });

  final Venue venue;
  final bool row;
  final String? sportFilter;
  final VoidCallback onOpen;

  @override
  State<_CardHost> createState() => _CardHostState();
}

class _CardHostState extends State<_CardHost> {
  String? _picked;

  @override
  void didUpdateWidget(_CardHost old) {
    super.didUpdateWidget(old);
    if (old.sportFilter != widget.sportFilter) _picked = null;
  }

  String? _match(List<String> sports, String? want) {
    if (want == null) return null;
    for (final s in sports) {
      if (s.trim().toLowerCase() == want.trim().toLowerCase()) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sports = widget.venue.membershipSports;
    final shown =
        _match(sports, _picked) ??
        _match(sports, widget.sportFilter) ??
        (sports.isEmpty ? null : sports.first);
    return MembershipVenueCard(
      venue: widget.venue,
      row: widget.row,
      sport: shown,
      // chips only when the venue has plans of its own in more than one sport (otherwise the prices would not change)
      onSport: widget.venue.sportPlans.length > 1
          ? (s) => setState(() => _picked = s)
          : null,
      // the sport shown on the card is the sport the enrolment page starts on
      onOpen: () {
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(preferredSportProvider.notifier).set(shown);
        widget.onOpen();
      },
    );
  }
}

/// One venue that sells memberships: photo, name, place, its sport / courts / hours, the lowest price of each membership length, and
/// View Plans (which opens the venue's Enroll Membership page).
class MembershipVenueCard extends StatelessWidget {
  const MembershipVenueCard({
    super.key,
    required this.venue,
    required this.row,
    required this.onOpen,
    this.sport,
    this.onSport,
  });

  final Venue venue;

  /// The wide one-line layout of the design; false is the stacked card (grid, tablet, phone).
  final bool row;
  final VoidCallback onOpen;

  /// The sport whose prices are shown, and what to do when another sport chip is tapped (null: the venue has one sport, no chips).
  final String? sport;
  final ValueChanged<String>? onSport;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(16);
    final main = venue.sports.isEmpty ? null : venue.sports.first;
    final photo = venue.heroImageUrl;

    final placeholder = VenueScene(sport: main);
    final image = photo == null
        ? placeholder
        : Image.network(
            photo,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    child: child,
                  ),
            errorBuilder: (_, _, _) => placeholder,
          );

    // name with the "verified" tick (its photos were approved by GameAll), and the place
    final nameAndPlace = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                venue.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.cardHeading(p.primaryText)
                    .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (venue.photos.isNotEmpty) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Photos verified by GameAll',
                child: Icon(
                  Icons.verified_rounded,
                  key: ValueKey('verified-${venue.id}'),
                  size: 18,
                  color: AppColors.purple,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.location_on_outlined, size: 15, color: p.secondaryText),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                venue.place,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.support(p.secondaryText),
              ),
            ),
          ],
        ),
      ],
    );

    // sport, number of courts, opening hours
    Widget fact(Widget icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 22, child: Center(child: icon)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(p.primaryText).copyWith(fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
    final sportsText = venue.sports.isEmpty
        ? null
        : venue.sports.length <= 2
        ? venue.sports.join(', ')
        : '${venue.sports.take(2).join(', ')} +${venue.sports.length - 2}';
    final facts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sportsText != null)
          fact(SportIcon(main!, size: 18, color: p.secondaryText), sportsText),
        if (venue.courtCount > 0)
          fact(
            Icon(Icons.grid_view_rounded, size: 17, color: p.secondaryText),
            venue.courtCount == 1 ? '1 Court' : '${venue.courtCount} Courts',
          ),
        if (venue.hoursLabel != null)
          fact(
            Icon(Icons.schedule_rounded, size: 17, color: p.secondaryText),
            venue.hoursLabel!,
          ),
      ],
    );

    final plans = _PlanTiles(venue: venue, sport: sport, onSport: onSport);
    final button = Pressable(
      key: ValueKey('view-plans-${venue.id}'),
      onTap: onOpen,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF9B5CFF), Color(0xFF5B6CFF)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C5CFF).withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'View Plans',
              style: AppTextStyles.button(Colors.white).copyWith(fontSize: 14),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 17,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );

    Widget vline() => Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      color: p.isDark ? const Color(0xFF2E3B63) : p.border,
    );

    final Widget body = row
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 172,
                  height: 128,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: image,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(flex: 3, child: nameAndPlace),
                vline(),
                Expanded(flex: 3, child: facts),
                vline(),
                Expanded(flex: 6, child: plans),
                const SizedBox(width: 16),
                button,
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(aspectRatio: 2.0, child: image),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      nameAndPlace,
                      const SizedBox(height: 10),
                      facts,
                      const SizedBox(height: 14),
                      plans,
                      const Spacer(),
                      const SizedBox(height: 14),
                      SizedBox(width: double.infinity, child: button),
                    ],
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      label: '${venue.name}, ${venue.place}, view membership plans',
      child: Pressable(
        onTap: onOpen,
        scale: 0.99,
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: p.isDark ? const Color(0xFF2E3B63) : p.border,
            ),
            color: p.surface.withValues(alpha: p.isDark ? 0.75 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      ),
    );
  }
}

/// "Available Memberships": the lowest price of each length the venue sells, two tiles across. The cheapest of all is lit up.
/// When the venue has plans but none of the usual lengths (or the list does not carry prices per length yet) one "From ₹X" tile shows.
class _PlanTiles extends StatelessWidget {
  const _PlanTiles({required this.venue, this.sport, this.onSport});

  final Venue venue;

  /// The sport whose prices are shown (null: every plan), and the chip handler (null: no chips).
  final String? sport;
  final ValueChanged<String>? onSport;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final byLength = lowestPriceByDuration(venue, sport: sport);
    final tiles = <({String key, String label, int price})>[
      for (final d in PlanDuration.values)
        if (byLength[d] != null)
          (key: d.name, label: d.label, price: byLength[d]!),
    ];
    if (tiles.isEmpty) {
      final from = venue.minPlanPriceInr;
      if (from != null) tiles.add((key: 'from', label: 'From', price: from));
    }
    final lowest = tiles.isEmpty
        ? null
        : tiles.map((t) => t.price).reduce((a, b) => a < b ? a : b);

    Widget tile(({String key, String label, int price}) t) {
      final best = t.price == lowest;
      final inner = Container(
        key: ValueKey('mem-tile-${venue.id}-${t.key}'),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: best
              ? const Color(0xFF7C5CFF)
                    .withValues(alpha: p.isDark ? 0.22 : 0.12)
              : (p.isDark ? const Color(0xFF111A35) : p.elevated),
          border: Border.all(
            color: best
                ? const Color(0xFFA67BFF)
                : (p.isDark ? const Color(0xFF2E3B63) : p.border),
            width: best ? 1.6 : 1,
          ),
          boxShadow: best
              ? [
                  BoxShadow(
                    color: const Color(0xFF7C5CFF).withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                t.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(p.primaryText).copyWith(
                  fontSize: 13.5,
                  fontWeight: best ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              rupees(t.price),
              style: AppTextStyles.body(p.primaryText)
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
      return inner;
    }

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: tile(tiles[i])),
            const SizedBox(width: 10),
            Expanded(
              child: i + 1 < tiles.length
                  ? tile(tiles[i + 1])
                  : const SizedBox(),
            ),
          ],
        ),
      );
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: 10));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // a venue with memberships in several sports: choose the sport, the prices below follow it
        if (onSport != null) ...[
          SportPicker(
            keyPrefix: 'mem-sport-${venue.id}',
            sports: venue.sportPlans.keys.toList(),
            selected: sport,
            onSelected: onSport!,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'Available Memberships',
          style: AppTextStyles.cardHeading(p.primaryText)
              .copyWith(fontSize: 14),
        ),
        const SizedBox(height: 10),
        ...rows,
      ],
    );
  }
}
