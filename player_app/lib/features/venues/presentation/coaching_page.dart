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
import '../application/coaching_filters.dart';
import '../application/membership_filters.dart' show TimeSlot;
import '../application/venue_filters.dart';
import '../application/venues_providers.dart';
import '../domain/coaching_listing.dart';
import '../domain/venue.dart';
import 'discover_venues_page.dart';
import 'no_venues_state.dart';

/// The four promises under the Coaching banner.
const coachingHighlights = [
  HighlightItem(
    Icons.verified_user_outlined,
    'Certified Coaches',
    'Train with verified experts',
  ),
  HighlightItem(
    Icons.bar_chart_rounded,
    'All Skill Levels',
    'Beginner to advanced',
  ),
  HighlightItem(
    Icons.groups_2_outlined,
    'Flexible Batches',
    'Group or individual training',
  ),
  HighlightItem(
    Icons.location_on_outlined,
    'Multiple Venues',
    'Choose a venue near you',
  ),
];

/// "Explore Coaching Programs": the Venues page's layout (banner, city + sport + search + grid / list switch in one card, a Filters
/// panel on the left, results on the right) where every result is a coaching programme of a venue, with the coach who takes it, the
/// programme's type, level and size, and its fee.
class CoachingPage extends ConsumerStatefulWidget {
  const CoachingPage({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  ConsumerState<CoachingPage> createState() => _CoachingPageState();
}

class _CoachingPageState extends ConsumerState<CoachingPage> {
  final _search = TextEditingController();
  final _resultsKey = GlobalKey();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String q) => ref
      .read(coachingFiltersProvider.notifier)
      .update((f) => f.copyWith(query: q));

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    final async = ref.watch(coachingListingsProvider);
    final filters = ref.watch(coachingFiltersProvider);
    final city = ref.watch(selectedCityProvider);
    final all = async.value ?? const <CoachingListing>[];
    final ctl = ref.read(coachingFiltersProvider.notifier);
    // the sport menu is built from venues: one stand-in per sport that has a programme
    final sportVenues = [
      for (final s in coachingSports(all))
        Venue(id: s, name: s, city: '', sports: [s]),
    ];

    if (_search.text != filters.query) _search.text = filters.query;

    Widget inset(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: child,
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('coaching-scroll'),
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
                accent: 'Coaching Programs',
                subtitle: 'Learn, improve and compete with certified coaches near you.',
                highlights: coachingHighlights,
                image: 'assets/images/coaching_banner.jpg',
                imageSize: const Size(334, 118),
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
                    items: coachingHighlights,
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
                  venues: sportVenues,
                  wide: wide,
                  hint: 'Search coaches, venues or programs...',
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

  final AsyncValue<List<CoachingListing>> async;
  final List<CoachingListing> all;
  final CoachingFilters filters;
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
                "We couldn't load coaching programs just now.",
                style: AppTextStyles.body(p.primaryText),
              ),
              const SizedBox(height: 16),
              GameAllButton.secondary(
                label: 'Try again',
                onPressed: () => ref.invalidate(coachingListingsProvider),
              ),
            ],
          ),
        ),
      );
    }
    if (all.isEmpty) {
      return const SizedBox(
        height: 420,
        child: NoVenuesState(kind: VenueKind.coaching),
      );
    }

    final matching = applyCoachingFilters(all, filters);
    // one card per venue: its latest programme in each sport (the sport chips on the card switch between them)
    final shown = <List<CoachingListing>>[];
    final byVenue = <String, List<CoachingListing>>{};
    for (final l in matching) {
      final g = byVenue[l.venueId];
      if (g == null) {
        byVenue[l.venueId] = [l];
        shown.add(byVenue[l.venueId]!);
      } else {
        g.add(l);
      }
    }
    final panel = CoachingFiltersPanel(
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

    final found = Text(
      shown.length == 1
          ? '1 Coaching Program Found'
          : '${shown.length} Coaching Programs Found',
      key: const ValueKey('venues-found'),
      style: AppTextStyles.sectionHeading(p.primaryText).copyWith(fontSize: 20),
    );
    final header = wide
        ? Align(alignment: Alignment.centerLeft, child: found)
        : Row(
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
                      child: CoachingFiltersPanel(
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

    final results = Column(
      key: resultsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 18),
        if (shown.isEmpty)
          _NoMatches(
            onClear: () => ref.read(coachingFiltersProvider.notifier).clear(),
          )
        else
          _Cards(
            groups: shown,
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
            'No coaching programs match these filters',
            style: AppTextStyles.sectionHeading(p.primaryText),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different sport or level, or clear the filters.',
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

/// "Filters": Clear All, Coaching Level, Coaching Type, Preferred Time, Days and "Apply Filters (N)". The sport is chosen in the
/// search card (as on the Venues page). On a phone the panel opens in a bottom sheet.
class CoachingFiltersPanel extends ConsumerWidget {
  const CoachingFiltersPanel({super.key, this.inSheet = false, this.onApply});

  final bool inSheet;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final f = ref.watch(coachingFiltersProvider);
    final ctl = ref.read(coachingFiltersProvider.notifier);
    final all =
        ref.watch(coachingListingsProvider).value ?? const <CoachingListing>[];
    final counts = coachingCounts(all);
    // the cards are venues (one each), so "Apply Filters (N)" counts venues too
    final matching = applyCoachingFilters(
      all,
      f,
    ).map((l) => l.venueId).toSet().length;

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
    Widget dropdown<T>({
      required Key key,
      required T value,
      required List<T> values,
      required String Function(T) label,
      required ValueChanged<T> onChanged,
    }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
        color: p.isDark ? p.background.withValues(alpha: 0.5) : p.elevated,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: key,
          isExpanded: true,
          value: value,
          dropdownColor: p.surface,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.secondaryText),
          style: AppTextStyles.body(p.primaryText),
          items: [
            for (final v in values)
              DropdownMenuItem(
                value: v,
                child: Text(
                  label(v),
                  style: AppTextStyles.body(p.primaryText)
                      .copyWith(fontSize: 14),
                ),
              ),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
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
        heading('Coaching Level'),
        for (final l in CoachingLevel.values)
          check(
            l.label,
            f.levels.contains(l),
            () => ctl.update((cur) {
              final next = {...cur.levels};
              if (!next.remove(l)) next.add(l);
              return cur.copyWith(levels: next);
            }),
            counts.levels[l] ?? 0,
            ValueKey('filter-level-${l.name}'),
          ),
        rule(),
        heading('Coaching Type'),
        for (final t in CoachingType.values)
          check(
            t.label,
            f.types.contains(t),
            () => ctl.update((cur) {
              final next = {...cur.types};
              if (!next.remove(t)) next.add(t);
              return cur.copyWith(types: next);
            }),
            counts.types[t] ?? 0,
            ValueKey('filter-type-${t.name}'),
          ),
        rule(),
        heading('Preferred Time'),
        dropdown<TimeSlot>(
          key: const ValueKey('time-dropdown'),
          value: f.time,
          values: TimeSlot.values,
          label: (s) => s.label,
          onChanged: (s) => ctl.update((cur) => cur.copyWith(time: s)),
        ),
        heading('Days'),
        dropdown<DaysPick>(
          key: const ValueKey('days-dropdown'),
          value: f.days,
          values: DaysPick.values,
          label: (d) => d.label,
          onChanged: (d) => ctl.update((cur) => cur.copyWith(days: d)),
        ),
        const SizedBox(height: 18),
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
    required this.groups,
    required this.view,
    required this.sport,
    required this.onNavigate,
  });

  /// One list per venue: its programmes, one per sport.
  final List<List<CoachingListing>> groups;
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
        // Grid: the design's tall cards, three across when there is room. List: one wide row per programme.
        final rowLayout = view == VenueView.list && w >= 760;
        final cols = view == VenueView.list
            ? 1
            : (w >= 1000 ? 3 : (w >= 640 ? 2 : 1));
        final cardWidth = (w - gap * (cols - 1)) / cols;
        Widget card(int i) => SizedBox(
          width: cardWidth,
          child: Reveal(
            key: ValueKey('card-${groups[i].first.venueId}'),
            delay: Duration(milliseconds: 30 * (i < 6 ? i : 6)),
            child: _CoachCardHost(
              group: groups[i],
              sportFilter: sport,
              row: rowLayout,
              narrow: cardWidth < 330,
              onNavigate: onNavigate,
            ),
          ),
        );
        return Column(
          key: const ValueKey('venue-grid'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var start = 0; start < groups.length; start += cols) ...[
              if (start > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = start;
                      i < start + cols && i < groups.length;
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
class _CoachCardHost extends StatefulWidget {
  const _CoachCardHost({
    required this.group,
    required this.sportFilter,
    required this.row,
    required this.narrow,
    required this.onNavigate,
  });

  /// The venue's programmes, one per sport (the same venue in each).
  final List<CoachingListing> group;
  final String? sportFilter;
  final bool row;
  final bool narrow;
  final void Function(String route) onNavigate;

  @override
  State<_CoachCardHost> createState() => _CoachCardHostState();
}

class _CoachCardHostState extends State<_CoachCardHost> {
  String? _picked;

  @override
  void didUpdateWidget(_CoachCardHost old) {
    super.didUpdateWidget(old);
    if (old.sportFilter != widget.sportFilter) _picked = null;
  }

  CoachingListing? _find(String? sport) {
    if (sport == null) return null;
    for (final l in widget.group) {
      if ((l.sport ?? '').trim().toLowerCase() == sport.trim().toLowerCase()) {
        return l;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item =
        _find(_picked) ?? _find(widget.sportFilter) ?? widget.group.first;
    final sports = [
      for (final l in widget.group)
        if (l.sport != null) l.sport!,
    ];
    return CoachingProgramCard(
      item: item,
      row: widget.row,
      narrow: widget.narrow,
      sports: sports,
      onSport: sports.length > 1 ? (s) => setState(() => _picked = s) : null,
      // the sport shown on the card is the sport the enrolment page starts on
      onEnroll: () {
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(preferredSportProvider.notifier).set(item.sport);
        widget.onNavigate(AppRoutes.coachingEnrollPath(item.venueId));
      },
      onVenue: () => widget.onNavigate(AppRoutes.venuePath(item.venueId)),
    );
  }
}

/// One coaching programme: the venue's photo with its name and place, the coach (photo, name, certification, rating, experience), the
/// programme (sport, name, what it is, type, level, size) and the fee with View & Enroll.
class CoachingProgramCard extends ConsumerWidget {
  const CoachingProgramCard({
    super.key,
    required this.item,
    required this.row,
    required this.onEnroll,
    required this.onVenue,
    this.narrow = false,
    this.sports = const [],
    this.onSport,
  });

  final CoachingListing item;

  /// The sports of the venue's programmes, and the handler for a tapped sport chip (null: one sport, no chips).
  final List<String> sports;
  final ValueChanged<String>? onSport;

  /// The wide one-line layout (list view); false is the stacked card of the design.
  final bool row;
  final VoidCallback onEnroll;
  final VoidCallback onVenue;

  /// A card too narrow for the fee and the button side by side: the button goes under the fee.
  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final radius = BorderRadius.circular(18);
    final saved = ref.watch(savedVenuesProvider).contains(item.venueId);

    final placeholder = VenueScene(sport: item.sport);
    final photo = item.venueImage == null
        ? placeholder
        : Image.network(
            item.venueImage!,
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

    // venue photo: the venue's name and place along the bottom, a heart to save it, an arrow to open it
    final header = Stack(
      fit: StackFit.expand,
      children: [
        photo,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xCC000000)],
              stops: [0.35, 1],
            ),
          ),
        ),
        Positioned(
          right: 10,
          top: 10,
          child: Semantics(
            button: true,
            label: saved
                ? 'Remove ${item.venueName} from saved'
                : 'Save ${item.venueName}',
            child: Pressable(
              key: ValueKey('heart-${item.programId}'),
              onTap: () =>
                  ref.read(savedVenuesProvider.notifier).toggle(item.venueId),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 19,
                  color: saved ? AppColors.danger : Colors.white,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 56,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.venueName,
                key: ValueKey('venue-${item.programId}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.cardHeading(Colors.white)
                    .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              if (item.venuePlace.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        item.venuePlace,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.support(Colors.white70)
                            .copyWith(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: Semantics(
            button: true,
            label: 'Open ${item.venueName}',
            child: Pressable(
              key: ValueKey('open-venue-${item.programId}'),
              onTap: onVenue,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.black.withValues(alpha: 0.5),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.north_east_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final coach = _CoachRow(item: item);
    final program = _ProgramBox(item: item);
    final price = _Price(item: item);
    final button = Pressable(
      key: ValueKey('enroll-${item.programId}'),
      onTap: onEnroll,
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
              'View & Enroll',
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

    final Widget body = row
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 260, child: header),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        coach,
                        const SizedBox(height: 12),
                        program,
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [price, const SizedBox(height: 12), button],
                    ),
                  ),
                ),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(aspectRatio: 2.2, child: header),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The coach strip has one height on every card, and the programme box takes all the room that is left, so
                      // the boxes, the fee and the button sit at the same height on every card of a row.
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 76),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: coach,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(child: _ProgramBox(item: item, expand: true)),
                      const SizedBox(height: 14),
                      // the fee, and View & Enroll beside it (under it when the card is narrow). The choice is made from the card's
                      // width, not with a LayoutBuilder: a LayoutBuilder has no height of its own to equalise the cards by.
                      if (narrow)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [price, const SizedBox(height: 10), button],
                        )
                      else
                        Row(
                          children: [
                            Expanded(child: price),
                            const SizedBox(width: 10),
                            button,
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      label: '${item.title} at ${item.venueName}, view and enroll',
      child: Pressable(
        onTap: onEnroll,
        scale: 0.99,
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: p.isDark ? const Color(0xFF3A2F7A) : p.border,
            ),
            color: p.surface.withValues(alpha: p.isDark ? 0.8 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      ),
    );
  }
}

/// The coach: photo (or initials), "Coach Arjun" with a tick, the certification, the rating and the years of experience.
/// A programme with no coach yet says so instead of leaving a gap.
class _CoachRow extends StatelessWidget {
  const _CoachRow({required this.item});

  final CoachingListing item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final coach = item.coach;
    if (coach == null) {
      // no coach on this programme yet: just say so (no picture, the text starts at the left like the coach's name does)
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Coach Details are not available',
          key: ValueKey('coach-${item.programId}'),
          style: AppTextStyles.support(p.secondaryText),
        ),
      );
    }
    final displayName = coach.name.toLowerCase().startsWith('coach')
        ? coach.name
        : 'Coach ${coach.name}';
    final avatar = ClipOval(
      child: SizedBox(
        width: 52,
        height: 52,
        child: coach.avatarUrl == null
            ? _Initials(coach.initials)
            : Image.network(
                coach.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _Initials(coach.initials),
              ),
      ),
    );
    final experience = coach.experienceLabel;
    return Row(
      key: ValueKey('coach-${item.programId}'),
      children: [
        avatar,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      key: ValueKey('coach-name-${item.programId}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardHeading(p.primaryText)
                          .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (coach.certifications != null) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified_rounded,
                      size: 17,
                      color: AppColors.purple,
                    ),
                  ],
                ],
              ),
              if (coach.headline != null) ...[
                const SizedBox(height: 2),
                Text(
                  coach.headline!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.support(p.secondaryText)
                      .copyWith(fontSize: 12.5),
                ),
              ],
              if (coach.ratingLabel != null || experience != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (coach.ratingLabel != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFFFB020),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            coach.ratingLabel!,
                            style: AppTextStyles.meta(p.primaryText).copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    if (experience != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: p.isDark
                              ? const Color(0xFF1B2547)
                              : p.elevated,
                          border: Border.all(
                            color: p.isDark
                                ? const Color(0xFF2E3B63)
                                : p.border,
                          ),
                        ),
                        child: Text(
                          experience,
                          style: AppTextStyles.meta(p.secondaryText)
                              .copyWith(fontSize: 11.5),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF7C5CFF), Color(0xFF3D7BFF)]),
    ),
    child: Text(
      text,
      style: AppTextStyles.cardHeading(Colors.white).copyWith(fontSize: 18),
    ),
  );
}

/// The programme in a box: its sport icon, "Badminton – Beginner Program", what it is, and chips for type, level and size.
class _ProgramBox extends StatelessWidget {
  const _ProgramBox({required this.item, this.expand = false});

  final CoachingListing item;

  /// Fill the height the card gives it (title and text at the top, the chips along the bottom), so the boxes of a row are equally tall.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget chip(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: p.secondaryText),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.meta(p.secondaryText).copyWith(fontSize: 12.5),
          ),
        ),
      ],
    );
    return Container(
      key: ValueKey('program-${item.programId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: p.isDark ? const Color(0xFF111A35) : p.elevated,
        border: Border.all(
          color: p.isDark ? const Color(0xFF2E3B63) : p.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        // when the row makes the box taller than its content, the content sits in the middle with an even margin above and below
        // (not the title at the top and the chips stranded at the bottom with a hole between them)
        mainAxisAlignment: expand
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF7C5CFF)
                      .withValues(alpha: p.isDark ? 0.25 : 0.12),
                ),
                child: Center(
                  child: SportIcon(
                    item.sport ?? 'Sport',
                    size: 22,
                    color: p.isDark
                        ? const Color(0xFFC9B8FF)
                        : AppColors.violet,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      key: ValueKey('title-${item.programId}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardHeading(p.primaryText)
                          .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (item.description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.support(p.secondaryText)
                            .copyWith(fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              chip(
                item.programType == 'ONE_ON_ONE'
                    ? Icons.person_outline_rounded
                    : Icons.groups_2_outlined,
                item.typeLabel,
              ),
              chip(Icons.bar_chart_rounded, item.level),
              if (item.maxCapacity != null && item.maxCapacity! > 0)
                chip(Icons.person_outline_rounded, 'Max ${item.maxCapacity}'),
            ],
          ),
        ],
      ),
    );
  }
}

/// "₹2,999 / month" (or "₹4,999 one-time").
class _Price extends StatelessWidget {
  const _Price({required this.item});

  final CoachingListing item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final price = item.priceInr;
    if (price == null) {
      return Text(
        'Ask the venue',
        key: ValueKey('price-${item.programId}'),
        style: AppTextStyles.body(p.secondaryText),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: rupees(price),
            style: AppTextStyles.cardHeading(p.primaryText)
                .copyWith(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: item.isMonthly ? ' / month' : ' one-time',
            style: AppTextStyles.body(p.secondaryText).copyWith(fontSize: 13),
          ),
        ],
      ),
      key: ValueKey('price-${item.programId}'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
