import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/hover_scope.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sport_icon.dart';
import '../../../core/widgets/venue_scene.dart';
import '../../player_home/application/player_home_controller.dart';
import '../../player_home/presentation/widgets/player_search_bar.dart';
import '../application/venue_filters.dart';
import '../application/venues_providers.dart';
import '../domain/venue.dart';
import 'no_venues_state.dart';

/// "Discover Sports Venues": a banner, the city and a search box, a row of sports, a Filters panel on the left and the venues as cards.
///
/// Everything here works on the venues already loaded for the picked city, so searching, choosing a sport and filtering are instant.
/// Filters offered are the ones the database can answer: price per hour, turf, coaching and membership venues, and venues the player
/// has saved with the heart. (There are no distances, ratings, indoor/outdoor flags or facility lists in the database yet.)
class DiscoverVenuesPage extends ConsumerStatefulWidget {
  const DiscoverVenuesPage({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  ConsumerState<DiscoverVenuesPage> createState() => _DiscoverVenuesPageState();
}

class _DiscoverVenuesPageState extends ConsumerState<DiscoverVenuesPage> {
  final _search = TextEditingController();
  final _resultsKey = GlobalKey();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String q) => ref
      .read(venueFiltersProvider.notifier)
      .update((f) => f.copyWith(query: q));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    final async = ref.watch(venuesForSelectedCityProvider(VenueKind.venues));
    final filters = ref.watch(venueFiltersProvider);
    final saved = ref.watch(savedVenuesProvider);
    final city = ref.watch(selectedCityProvider);
    final all = async.value ?? const <Venue>[];

    // The search box follows the filter state (Clear All empties it).
    if (_search.text != filters.query) _search.text = filters.query;

    Widget inset(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: child,
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('discover-scroll'),
        padding: const EdgeInsets.only(bottom: 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Reveal(
              dy: 10,
              child: DiscoverBanner(wide: wide, side: side),
            ),
            if (!wide) ...[
              const SizedBox(height: 4),
              inset(
                Reveal(
                  delay: const Duration(milliseconds: 20),
                  child: DiscoverHighlights(room: width - side * 2, compact: true),
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
                  onChanged: _setQuery,
                  onSearch: () => _setQuery(_search.text),
                  sport: filters.sport,
                  onSport: (s) => ref
                      .read(venueFiltersProvider.notifier)
                      .update((f) => f.copyWith(sport: s)),
                  view: filters.view,
                  onView: (v) => ref
                      .read(venueFiltersProvider.notifier)
                      .update((f) => f.copyWith(view: v)),
                ),
              ),
            ),
            SizedBox(height: wide ? 26 : 18),
            inset(
              _Results(
                async: async,
                all: all,
                filters: filters,
                saved: saved,
                wide: wide,
                onNavigate: widget.onNavigate,
                p: p,
                resultsKey: _resultsKey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Banner ──────────────────────────────────────────────────────────────

/// One of the three short promises under a banner title.
class HighlightItem {
  const HighlightItem(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;
}

/// The three promises on the Venues page.
const venueHighlights = [
  HighlightItem(
    Icons.calendar_month_outlined,
    'Instant Booking',
    'Check real-time availability',
  ),
  HighlightItem(
    Icons.groups_2_outlined,
    'Memberships',
    'Long-term playing plans',
  ),
  HighlightItem(
    Icons.school_outlined,
    'Coaching',
    'Train with certified coaches',
  ),
];

/// The page banner: a big title (the second word in a blue-to-violet gradient), a line under it, the three highlights and the artwork.
class DiscoverBanner extends StatelessWidget {
  const DiscoverBanner({
    super.key,
    required this.wide,
    required this.side,
    this.title = 'Discover Sports ',
    this.accent = 'Venues',
    this.subtitle = 'Book courts, join memberships or find coaching near you.',
    this.highlights = venueHighlights,
    this.image = 'assets/images/discover_banner.jpg',
    this.imageSize = const Size(760, 172),
  });

  final bool wide;
  final double side;
  final String title;
  final String accent;
  final String subtitle;
  final List<HighlightItem> highlights;

  /// The artwork and its own pixel size (it is scaled by height, so all of it shows).
  final String image;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        // no fixed height on a wide window: the banner is as tall as its text and highlights, so there is no empty band above or below
        final h = wide ? 0.0 : 150.0;
        final art = wide ? (w * 0.47).clamp(0.0, 900.0) : w * 0.62;
        final titleSize = wide ? 50.0 : 28.0;
        // at least this tall, and taller when larger text needs the room
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: h),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // the artwork, sliced diagonally as in the design, fading into the page on its left edge
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: art,
                child: ExcludeSemantics(
                  // The picture is 760 x 172. On a wide window it is scaled to the banner's height (about its own size), so all of it
                  // shows, nothing is cropped and it is not blown up. The fade is on the picture itself, so its left edge melts into the
                  // page however wide the window is. On a phone the picture fills its box and fades the same way.
                  child: wide
                      ? FittedBox(
                          fit: BoxFit.fitHeight,
                          alignment: Alignment.centerRight,
                          child: ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (r) => const LinearGradient(
                              colors: [Color(0x00000000), Color(0xFF000000)],
                              stops: [0.0, 0.34],
                            ).createShader(r),
                            child: Image.asset(
                              image,
                              width: imageSize.width,
                              height: imageSize.height,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        )
                      : ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (r) => const LinearGradient(
                            colors: [Color(0x00000000), Color(0x99000000)],
                            stops: [0.0, 0.5],
                          ).createShader(r),
                          child: Image.asset(
                            image,
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: side,
                  right: wide ? 0 : w * 0.22,
                  top: wide ? 6 : 14,
                  bottom: wide ? 6 : 14,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: title),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (r) => const LinearGradient(
                                  colors: [
                                    Color(0xFFA67BFF),
                                    Color(0xFF3DD0FF),
                                  ],
                                ).createShader(r),
                                child: Text(
                                  accent,
                                  style: AppTextStyles.desktopHeroHeading(
                                    Colors.white,
                                  ).copyWith(fontSize: titleSize, height: 1.15),
                                ),
                              ),
                            ),
                          ],
                        ),
                        style: AppTextStyles.desktopHeroHeading(p.primaryText)
                            .copyWith(fontSize: titleSize, height: 1.15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: AppTextStyles.body(
                          p.primaryText.withValues(alpha: 0.88),
                        ).copyWith(fontSize: wide ? 19 : 13.5),
                      ),
                      // on a phone the three highlights get their own row under the banner instead
                      if (wide) ...[
                        const SizedBox(height: 22),
                        DiscoverHighlights(
                          room: w * 0.53 - side,
                          items: highlights,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Instant Booking · Memberships · Coaching": three short promises with an icon, under the banner title.
/// With room (a wide window) each has a second line and a thin divider between them; otherwise just the icon and title.
class DiscoverHighlights extends StatelessWidget {
  const DiscoverHighlights({
    super.key,
    required this.room,
    this.compact = false,
    this.items = venueHighlights,
  });

  /// The width available to the row.
  final double room;

  /// A phone: three small items in one line.
  final bool compact;

  final List<HighlightItem> items;

  List<(IconData, String, String)> get _items => [
    for (final i in items) (i.icon, i.title, i.subtitle),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final detailed = !compact && room >= 640;

    Widget item((IconData, String, String) it) {
      final icon = Container(
        width: compact ? 34 : 46,
        height: compact ? 34 : 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.isDark ? const Color(0xFF151E3A) : p.elevated,
          border: Border.all(
            color: p.isDark ? const Color(0xFF2E3B63) : p.border,
          ),
        ),
        child: Icon(
          it.$1,
          size: compact ? 18 : 22,
          color: p.isDark ? const Color(0xFFB9A4FF) : AppColors.violet,
        ),
      );
      final title = Text(
        it.$2,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.cardHeading(
          p.primaryText,
        ).copyWith(fontSize: compact ? 12.5 : 16, fontWeight: FontWeight.w700),
      );
      if (!detailed) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            SizedBox(width: compact ? 8 : 10),
            Flexible(child: title),
          ],
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                const SizedBox(height: 2),
                Text(
                  it.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.support(p.secondaryText)
                      .copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final divider = Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 22),
      color: p.isDark ? const Color(0xFF2E3B63) : p.border,
    );
    return KeyedSubtree(
      key: const ValueKey('discover-highlights'),
      child: compact
          ? (_items.length > 3
                // four items do not fit one phone line: two by two
                ? Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      for (final it in _items)
                        SizedBox(width: (room - 12) / 2, child: item(it)),
                    ],
                  )
                : Row(children: [for (final it in _items) Expanded(child: item(it))]))
          : detailed
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) divider,
                  Flexible(child: item(_items[i])),
                ],
              ],
            )
          : Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [for (final it in _items) item(it)],
            ),
    );
  }
}

// ── City + search ───────────────────────────────────────────────────────

class DiscoverSearchRow extends ConsumerWidget {
  const DiscoverSearchRow({
    super.key,
    required this.sport,
    required this.onSport,
    required this.view,
    required this.onView,
    this.hint = 'Search venues, sports or areas...',
    required this.controller,
    required this.city,
    required this.venues,
    required this.wide,
    required this.onChanged,
    required this.onSearch,
  });

  final TextEditingController controller;
  final String city;
  final List<Venue> venues;
  final bool wide;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;
  final String? sport;
  final ValueChanged<String?> onSport;
  final VenueView view;
  final ValueChanged<VenueView> onView;
  final String hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final box = BoxDecoration(
      color: p.isDark ? const Color(0xFF0E1630) : p.elevated,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: p.isDark ? const Color(0xFF263552) : p.border),
    );

    final citySelector = Semantics(
      button: true,
      label: 'Location: $city',
      child: Pressable(
        key: const ValueKey('discover-city'),
        onTap: () => showCityPicker(context, ref),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: box,
          child: Row(
            children: [
              Icon(Icons.location_on_outlined, size: 20, color: p.highlight),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(p.primaryText)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: p.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );

    final sportSelector = DiscoverSportDropdown(
      venues: venues,
      decoration: box,
      selected: sport,
      onChanged: onSport,
    );

    final searchBox = Container(
      height: 56,
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: box,
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 22, color: p.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('discover-search'),
              controller: controller,
              onChanged: onChanged,
              onSubmitted: (_) => onSearch(),
              textInputAction: TextInputAction.search,
              style: AppTextStyles.body(p.primaryText),
              cursorColor: AppColors.cyan,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: hint,
                hintStyle: AppTextStyles.body(p.mutedText),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              key: const ValueKey('discover-search-clear'),
              tooltip: 'Clear',
              onPressed: () => onChanged(''),
              icon: Icon(Icons.close_rounded, size: 18, color: p.secondaryText),
            ),
          if (wide) ...[
            const SizedBox(width: 6),
            Pressable(
              key: const ValueKey('discover-search-button'),
              onTap: onSearch,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 146,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9B5CFF), Color(0xFF3D7BFF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C5CFF).withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Text(
                  'Search',
                  style: AppTextStyles.button(Colors.white)
                      .copyWith(fontSize: 16),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF7C5CFF)
              .withValues(alpha: p.isDark ? 0.45 : 0.30),
        ),
        color: p.isDark
            ? const Color(0xFF0A1024).withValues(alpha: 0.82)
            : p.surface,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C5CFF)
                .withValues(alpha: p.isDark ? 0.18 : 0.08),
            blurRadius: 30,
          ),
        ],
      ),
      // wide: city, sport, the search box and the grid / list switch on one line.
      // phone: city and sport stacked, then the search box with the switch beside it
      child: wide
          ? Row(
              children: [
                SizedBox(width: 280, child: citySelector),
                const SizedBox(width: 12),
                SizedBox(width: 220, child: sportSelector),
                const SizedBox(width: 12),
                Expanded(child: searchBox),
                const SizedBox(width: 12),
                DiscoverViewToggle(current: view, onChanged: onView),
              ],
            )
          : Column(
              children: [
                citySelector,
                const SizedBox(height: 10),
                sportSelector,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: searchBox),
                    const SizedBox(width: 10),
                    DiscoverViewToggle(current: view, onChanged: onView),
                  ],
                ),
              ],
            ),
    );
    return card;
  }
}

// ── Sport dropdown and grid / list switch (both live in the search card) ──

/// "All Sports ⌄": a menu of every sport, left of the search box. Picking one narrows the venues; "All Sports" brings them all back.
class DiscoverSportDropdown extends ConsumerWidget {
  const DiscoverSportDropdown({
    super.key,
    required this.venues,
    required this.decoration,
    required this.selected,
    required this.onChanged,
  });

  /// The chosen sport, or null for All Sports.
  final String? selected;
  final ValueChanged<String?> onChanged;

  final List<Venue> venues;
  final BoxDecoration decoration;

  /// The menu value for "All Sports" (a menu cannot return null).
  static const _all = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final sports = [...featuredSports, ...otherSports(venues)];
    final label = selected ?? 'All Sports';
    final icon = selected == null
        ? Icon(Icons.grid_view_rounded, size: 20, color: AppColors.cyan)
        : SportIcon(selected, size: 22, color: AppColors.cyan);

    PopupMenuItem<String> item(String value, String text, Widget leading) =>
        PopupMenuItem<String>(
          key: ValueKey(value.isEmpty ? 'sport-all' : 'sport-$value'),
          value: value,
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Text(
                text,
                style: AppTextStyles.body(p.primaryText).copyWith(
                  fontWeight: (selected ?? _all) == value
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        );

    return Semantics(
      button: true,
      label: 'Sport: $label',
      child: PopupMenuButton<String>(
        key: const ValueKey('sport-dropdown'),
        tooltip: 'Choose a sport',
        color: p.surface,
        offset: const Offset(0, 60),
        constraints: const BoxConstraints(minWidth: 220),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
        onSelected: (s) => onChanged(s.isEmpty ? null : s),
        itemBuilder: (_) => [
          item(
            _all,
            'All Sports',
            Icon(Icons.grid_view_rounded, size: 20, color: p.highlight),
          ),
          for (final s in sports)
            item(s, s, SportIcon(s, size: 22, color: p.highlight)),
        ],
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: decoration,
          child: Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(p.primaryText)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: p.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The grid / list switch, at the right-hand end of the search bar.
class DiscoverViewToggle extends ConsumerWidget {
  const DiscoverViewToggle({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final VenueView current;
  final ValueChanged<VenueView> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    Widget toggle(IconData icon, String label, VenueView v) {
      final on = current == v;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: Pressable(
          key: ValueKey('view-${v.name}'),
          onTap: () => onChanged(v),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 40,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: on
                  ? const LinearGradient(
                      colors: [AppColors.violet, AppColors.purple],
                    )
                  : null,
            ),
            child: Icon(
              icon,
              size: 20,
              color: on ? Colors.white : p.secondaryText,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: p.isDark ? const Color(0xFF263552) : p.border,
        ),
        color: p.isDark ? const Color(0xFF0E1630) : p.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          toggle(Icons.grid_view_rounded, 'Grid view', VenueView.grid),
          toggle(Icons.view_list_rounded, 'List view', VenueView.list),
        ],
      ),
    );
  }
}

// ── Results: filters panel + cards ──────────────────────────────────────

class _Results extends ConsumerWidget {
  const _Results({
    required this.async,
    required this.all,
    required this.filters,
    required this.saved,
    required this.wide,
    required this.onNavigate,
    required this.p,
    required this.resultsKey,
  });

  final GlobalKey resultsKey;
  final AsyncValue<List<Venue>> async;
  final List<Venue> all;
  final VenueFilters filters;
  final Set<String> saved;
  final bool wide;
  final void Function(String route) onNavigate;
  final AppPalette p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                "We couldn't load venues just now.",
                style: AppTextStyles.body(p.primaryText),
              ),
              const SizedBox(height: 16),
              GameAllButton.secondary(
                label: 'Try again',
                onPressed: () => ref.invalidate(
                  venuesForSelectedCityProvider(VenueKind.venues),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (all.isEmpty) return const SizedBox(height: 420, child: NoVenuesState());

    final shown = applyVenueFilters(all, filters, saved);
    final ceiling = priceCeiling(all);
    // Apply Filters: the filters are already in force, so this just brings the results into view
    final panel = FiltersPanel(
      ceiling: ceiling,
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
        _ResultsHeader(
          count: shown.length,
          wide: wide,
          filters: filters,
          ceiling: ceiling,
        ),
        const SizedBox(height: 18),
        if (shown.isEmpty)
          _NoMatches(
            onClear: () => ref.read(venueFiltersProvider.notifier).clear(),
          )
        else
          _CardGrid(
            venues: shown,
            view: filters.view,
            saved: saved,
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

class _ResultsHeader extends ConsumerWidget {
  const _ResultsHeader({
    required this.count,
    required this.wide,
    required this.filters,
    required this.ceiling,
  });

  final int count;
  final bool wide;
  final VenueFilters filters;
  final int ceiling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final found = Text(
      count == 1 ? '1 Venue Found' : '$count Venues Found',
      key: const ValueKey('venues-found'),
      style: AppTextStyles.sectionHeading(p.primaryText).copyWith(fontSize: 20),
    );
    // wide: the Filters panel is on the left, so only the count is needed here
    if (wide) return Align(alignment: Alignment.centerLeft, child: found);
    // phone: the count, and the button that opens the filters
    return Row(
      children: [
        Expanded(child: found),
        Pressable(
          key: const ValueKey('open-filters'),
          onTap: () => _openFilters(context, ceiling),
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

  void _openFilters(BuildContext context, int ceiling) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.palette.surface,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: FiltersPanel(
            ceiling: ceiling,
            inSheet: true,
            onApply: () => Navigator.of(sheet).pop(),
          ),
        ),
      ),
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
            'No venues match these filters',
            style: AppTextStyles.sectionHeading(p.primaryText),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different sport, or clear the filters.',
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

/// The "Filters" box: Clear All, price range, venue type, facilities, what else a venue offers, and "Apply Filters (N)".
/// Every box counts the venues that have it. On a phone the panel opens in a bottom sheet.
class FiltersPanel extends ConsumerWidget {
  const FiltersPanel({
    super.key,
    required this.ceiling,
    this.inSheet = false,
    this.onApply,
  });

  final int ceiling;
  final bool inSheet;

  /// What the Apply Filters button does after the filters are already in force (close the sheet, or scroll to the results).
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final f = ref.watch(venueFiltersProvider);
    final ctl = ref.read(venueFiltersProvider.notifier);

    final all =
        ref.watch(venuesForSelectedCityProvider(VenueKind.venues)).value ??
        const <Venue>[];
    final saved = ref.watch(savedVenuesProvider);
    final counts = FilterCounts.of(all);
    final matching = applyVenueFilters(all, f, saved).length;
    final low = priceFloor(all);

    Widget check(
      String label,
      bool value,
      VenueFilters Function(VenueFilters f, bool v) change, {
      Key? key,
      int? count,
    }) => Semantics(
      checked: value,
      label: label,
      child: Pressable(
        key: key,
        onTap: () => ctl.update((cur) => change(cur, !value)),
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
              // the name takes the room that is left on one line; the count sits at the right edge, so all the counts line up
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(p.primaryText)
                      .copyWith(fontSize: 14),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                Text(
                  '($count)',
                  key: ValueKey('count-$label'),
                  style: AppTextStyles.body(p.secondaryText)
                      .copyWith(fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(text, style: AppTextStyles.cardHeading(p.primaryText)),
    );

    // the slider runs from the cheapest venue to the dearest, in steps of ₹50 (and is never shorter than ₹100)
    final hi = ceiling < low + 100 ? low + 100 : ceiling;
    final from = (f.minPrice ?? low).clamp(low, hi);
    final to = (f.maxPrice ?? hi).clamp(low, hi);
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
        if (ceiling > 0) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Price per hour',
                    style: AppTextStyles.cardHeading(p.primaryText),
                  ),
                ),
                Text(
                  '${rupees(from)} – ${rupees(to)}',
                  key: const ValueKey('price-label'),
                  style: AppTextStyles.meta(p.secondaryText)
                      .copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.violet,
              inactiveTrackColor: p.border,
              thumbColor: Colors.white,
              overlayColor: AppColors.violet.withValues(alpha: 0.15),
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 8,
              ),
            ),
            child: RangeSlider(
              key: const ValueKey('price-slider'),
              min: low.toDouble(),
              max: hi.toDouble(),
              divisions: (hi - low) ~/ 50 == 0 ? null : (hi - low) ~/ 50,
              values: RangeValues(from.toDouble(), to.toDouble()),
              // a handle at its end of the track means "no limit" on that side
              onChanged: (r) => ctl.update(
                (cur) => cur.copyWith(
                  minPrice: r.start.round() <= low ? null : r.start.round(),
                  maxPrice: r.end.round() >= hi ? null : r.end.round(),
                ),
              ),
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.only(top: 8),
            color: p.border,
          ),
        ],
        heading('Venue Type'),
        check(
          'Indoor',
          f.indoor,
          (cur, v) => cur.copyWith(indoor: v),
          key: const ValueKey('filter-indoor'),
          count: counts.indoor,
        ),
        check(
          'Outdoor',
          f.outdoor,
          (cur, v) => cur.copyWith(outdoor: v),
          key: const ValueKey('filter-outdoor'),
          count: counts.outdoor,
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.only(top: 10),
          color: p.border,
        ),
        heading('Facilities'),
        check(
          'Parking',
          f.parking,
          (cur, v) => cur.copyWith(parking: v),
          key: const ValueKey('filter-parking'),
          count: counts.parking,
        ),
        check(
          'Locker Room',
          f.changingRooms,
          (cur, v) => cur.copyWith(changingRooms: v),
          key: const ValueKey('filter-changing'),
          count: counts.changingRooms,
        ),
        check(
          'Café / Snacks',
          f.cafeteria,
          (cur, v) => cur.copyWith(cafeteria: v),
          key: const ValueKey('filter-cafeteria'),
          count: counts.cafeteria,
        ),
        check(
          'Washroom',
          f.toilets,
          (cur, v) => cur.copyWith(toilets: v),
          key: const ValueKey('filter-toilets'),
          count: counts.toilets,
        ),
        check(
          'Equipment Rental',
          f.equipmentRental,
          (cur, v) => cur.copyWith(equipmentRental: v),
          key: const ValueKey('filter-rental'),
          count: counts.equipmentRental,
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.only(top: 10),
          color: p.border,
        ),
        heading('Also offers'),
        check(
          'Academy / Coaching',
          f.academy,
          (cur, v) => cur.copyWith(academy: v),
          key: const ValueKey('filter-academy'),
          count: counts.academy,
        ),
        check(
          'Memberships',
          f.memberships,
          (cur, v) => cur.copyWith(memberships: v),
          key: const ValueKey('filter-memberships'),
          count: counts.memberships,
        ),
        check(
          'Saved venues only',
          f.savedOnly,
          (cur, v) => cur.copyWith(savedOnly: v),
          key: const ValueKey('filter-saved'),
          count: saved.length,
        ),
        const SizedBox(height: 18),
        // Filters apply as they are ticked; this button shows how many venues that leaves and takes you to them
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

class _CardGrid extends StatelessWidget {
  const _CardGrid({
    required this.venues,
    required this.view,
    required this.saved,
    required this.onNavigate,
  });

  final List<Venue> venues;
  final VenueView view;
  final Set<String> saved;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 18.0;
        final w = box.maxWidth;
        final cols = view == VenueView.list
            ? 1
            : (w >= 880 ? 3 : (w >= 560 ? 2 : 1));
        final cardWidth = (w - gap * (cols - 1)) / cols;
        Widget card(int i) => SizedBox(
          width: cardWidth,
          child: Reveal(
            key: ValueKey('card-${venues[i].id}'),
            delay: Duration(milliseconds: 30 * (i < 6 ? i : 6)),
            child: DiscoverVenueCard(
              venue: venues[i],
              list: view == VenueView.list,
              saved: saved.contains(venues[i].id),
              onOpen: () => onNavigate(AppRoutes.venuePath(venues[i].id)),
            ),
          ),
        );
        // Rows of `cols` cards. Every card in a row is as tall as the tallest one (a venue with more sport chips would otherwise
        // be taller than its neighbour), and the last row keeps the same card width.
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
                    for (var i = start; i < start + cols && i < venues.length; i++) ...[
                      if (i > start) const SizedBox(width: gap),
                      card(i),
                    ],
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

/// One venue in the results: photo, heart (save), name, place, chips with price, and an arrow that opens booking.
class DiscoverVenueCard extends ConsumerWidget {
  const DiscoverVenueCard({
    super.key,
    required this.venue,
    required this.onOpen,
    this.list = false,
    this.saved = false,
  });

  final Venue venue;
  final bool list;
  final bool saved;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final photo = venue.heroImageUrl;
    final logo = venue.logoUrl;
    final main = venue.sports.isEmpty ? null : venue.sports.first;
    final radius = BorderRadius.circular(16);

    // No photo: a picture of the court or pitch for this sport (drawn in code), with the venue's logo as a small badge when it has one.
    final placeholder = Stack(
      fit: StackFit.expand,
      children: [
        VenueScene(sport: main),
        if (logo != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
              ),
              child: ClipOval(
                child: Image.network(
                  logo,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
      ],
    );

    final image = Stack(
      fit: StackFit.expand,
      children: [
        photo == null
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
              ),
        // Indoor / Outdoor, where the design has the rating (there are no ratings yet)
        if (venue.venueType != null)
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              key: ValueKey('type-${venue.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Text(
                venue.venueType == VenueType.indoor ? 'Indoor' : 'Outdoor',
                style: AppTextStyles.meta(Colors.white)
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        Positioned(
          right: 10,
          top: 10,
          child: Semantics(
            button: true,
            label: saved
                ? 'Remove ${venue.name} from saved'
                : 'Save ${venue.name}',
            child: Pressable(
              key: ValueKey('heart-${venue.id}'),
              onTap: () =>
                  ref.read(savedVenuesProvider.notifier).toggle(venue.id),
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
      ],
    );

    // up to two sports, then "2+ more" for the rest
    final extra = venue.sports.length - 2;
    final chips = <Widget>[
      for (final s in venue.sports.take(2)) _TypeChip(label: s),
      if (extra > 0) _TypeChip(label: '$extra+ more', muted: true),
    ];

    final details = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // in the grid the details fill the card, so the chips and the button sit at the bottom of every card
        mainAxisSize: list ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: HoverText(
                  venue.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.cardHeading(p.primaryText)
                      .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              if (venue.priceFor(VenueKind.venues) != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${rupees(venue.priceFor(VenueKind.venues)!)} / hr',
                  style: AppTextStyles.meta(p.secondaryText)
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
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
                  venue.place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.support(p.secondaryText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!list) const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
              const SizedBox(width: 8),
              Container(
                key: ValueKey('view-book-${venue.id}'),
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9B5CFF), Color(0xFF5B6CFF)],
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View & Book',
                      style: AppTextStyles.button(Colors.white)
                          .copyWith(fontSize: 13.5),
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
            ],
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: '${venue.name}, ${venue.place}',
      child: Pressable(
        onTap: onOpen,
        scale: 0.985,
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: p.border),
            color: p.surface.withValues(alpha: p.isDark ? 0.75 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: list
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 220, child: image),
                      Expanded(child: Center(child: details)),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(aspectRatio: 2.0, child: image),
                    Expanded(child: details),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A sport on a card: a plain outlined pill ("Pickleball"); the "2+ more" one is a little dimmer.
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, this.muted = false});
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: p.isDark ? const Color(0xFF3A4A73) : p.border,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppTextStyles.meta(muted ? p.secondaryText : p.primaryText)
            .copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}
