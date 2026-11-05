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
import 'sport_style.dart';

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String q) => ref.read(venueFiltersProvider.notifier).update((f) => f.copyWith(query: q));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;
    final side = wide ? AppDimensions.desktopSidePadding(width) : AppDimensions.screenPadding;
    final async = ref.watch(venuesForSelectedCityProvider(VenueKind.venues));
    final filters = ref.watch(venueFiltersProvider);
    final saved = ref.watch(savedVenuesProvider);
    final city = ref.watch(selectedCityProvider);
    final all = async.value ?? const <Venue>[];

    // The search box follows the filter state (Clear All empties it).
    if (_search.text != filters.query) _search.text = filters.query;

    Widget inset(Widget child) => Padding(padding: EdgeInsets.symmetric(horizontal: side), child: child);
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('discover-scroll'),
        padding: const EdgeInsets.only(bottom: 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Reveal(dy: 10, child: _Banner(wide: wide, side: side)),
            SizedBox(height: wide ? 18 : 14),
            inset(Reveal(delay: const Duration(milliseconds: 40), child: _SearchRow(controller: _search, city: city, wide: wide, onChanged: _setQuery, onSearch: () => _setQuery(_search.text)))),
            SizedBox(height: wide ? 22 : 16),
            Reveal(delay: const Duration(milliseconds: 80), child: _SportChips(venues: all, side: side, wide: wide)),
            SizedBox(height: wide ? 28 : 18),
            inset(_Results(async: async, all: all, filters: filters, saved: saved, wide: wide, onNavigate: widget.onNavigate, p: p)),
          ],
        ),
      ),
    );
  }
}

// ── Banner ──────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({required this.wide, required this.side});

  final bool wide;
  final double side;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = wide ? 176.0 : 150.0;
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
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => LinearGradient(
                      colors: [const Color(0x00000000), Color(wide ? 0xFF000000 : 0x99000000)],
                      stops: [0.0, wide ? 0.16 : 0.5],
                    ).createShader(r),
                    child: Image.asset('assets/images/discover_banner.jpg', fit: BoxFit.cover, alignment: Alignment.centerRight),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(left: side, right: wide ? 0 : w * 0.22, top: 14, bottom: 14),
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
                            const TextSpan(text: 'Discover Sports '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFA67BFF), Color(0xFF3DD0FF)]).createShader(r),
                                child: Text('Venues', style: AppTextStyles.desktopHeroHeading(Colors.white).copyWith(fontSize: titleSize, height: 1.15)),
                              ),
                            ),
                          ],
                        ),
                        style: AppTextStyles.desktopHeroHeading(p.primaryText).copyWith(fontSize: titleSize, height: 1.15),
                      ),
                      const SizedBox(height: 8),
                      Text('Book courts, join memberships or find coaching near you.', style: AppTextStyles.body(p.primaryText.withValues(alpha: 0.88)).copyWith(fontSize: wide ? 19 : 13.5)),
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

// ── City + search ───────────────────────────────────────────────────────

class _SearchRow extends ConsumerWidget {
  const _SearchRow({required this.controller, required this.city, required this.wide, required this.onChanged, required this.onSearch});

  final TextEditingController controller;
  final String city;
  final bool wide;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final box = BoxDecoration(color: p.isDark ? const Color(0xFF0E1630) : p.elevated, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.isDark ? const Color(0xFF263552) : p.border));

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
              Expanded(child: Text(city, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w500))),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: p.secondaryText),
            ],
          ),
        ),
      ),
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
              decoration: InputDecoration(border: InputBorder.none, isDense: true, hintText: 'Search venues, sports or areas...', hintStyle: AppTextStyles.body(p.mutedText)),
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
                  gradient: const LinearGradient(colors: [Color(0xFF9B5CFF), Color(0xFF3D7BFF)]),
                  boxShadow: [BoxShadow(color: const Color(0xFF7C5CFF).withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 5))],
                ),
                child: Text('Search', style: AppTextStyles.button(Colors.white).copyWith(fontSize: 16)),
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
        border: Border.all(color: const Color(0xFF7C5CFF).withValues(alpha: p.isDark ? 0.45 : 0.30)),
        color: p.isDark ? const Color(0xFF0A1024).withValues(alpha: 0.82) : p.surface,
        boxShadow: [BoxShadow(color: const Color(0xFF7C5CFF).withValues(alpha: p.isDark ? 0.18 : 0.08), blurRadius: 30)],
      ),
      child: wide
          ? Row(children: [SizedBox(width: 350, child: citySelector), const SizedBox(width: 12), Expanded(child: searchBox)])
          : Column(children: [citySelector, const SizedBox(height: 10), searchBox]),
    );
    // on a wide window the card is centred and about three quarters of the page, like the design
    return wide ? Center(child: FractionallySizedBox(widthFactor: 0.77, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1280), child: card))) : card;
  }
}

// ── Sports row ──────────────────────────────────────────────────────────

class _SportChips extends ConsumerWidget {
  const _SportChips({required this.venues, required this.side, required this.wide});
  final List<Venue> venues;
  final double side;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final selected = ref.watch(venueFiltersProvider.select((f) => f.sport));
    final more = otherSports(venues);
    void pick(String? sport) => ref.read(venueFiltersProvider.notifier).update((f) => f.copyWith(sport: sport));
    bool isOn(String? s) => selected == null ? s == null : (s != null && s.toLowerCase() == selected.toLowerCase());

    Widget chip(String label, Widget Function(Color c) icon, String? sport, {Key? key}) {
      final on = isOn(sport);
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: ExcludeSemantics(
          child: Pressable(
            key: key,
            onTap: () => pick(sport),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              // the chosen sport is outlined with a cyan-to-violet gradient and a soft glow
              padding: EdgeInsets.all(on ? 1.6 : 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: on ? const LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6)]) : null,
                color: on ? null : (p.isDark ? const Color(0xFF263552) : p.border),
                boxShadow: on ? [BoxShadow(color: const Color(0xFF22D3EE).withValues(alpha: 0.25), blurRadius: 14)] : null,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(25), color: p.isDark ? const Color(0xFF0A1126) : p.surface),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon(on ? AppColors.cyan : p.primaryText.withValues(alpha: 0.9)),
                    const SizedBox(width: 9),
                    Text(label, style: AppTextStyles.body(p.primaryText.withValues(alpha: on ? 1 : 0.92)).copyWith(fontSize: 14.5, fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final chips = <Widget>[
      chip('All Sports', (c) => Icon(Icons.grid_view_rounded, size: 20, color: c), null, key: const ValueKey('sport-all')),
      for (final s in featuredSports) chip(s, (c) => SportIcon(s, size: 22, color: c), s, key: ValueKey('sport-$s')),
      if (more.isNotEmpty)
        PopupMenuButton<String>(
          key: const ValueKey('sport-more'),
          tooltip: 'More sports',
          color: p.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.border)),
          onSelected: pick,
          itemBuilder: (_) => [for (final s in more) PopupMenuItem(value: s, child: Row(children: [SportIcon(s, size: 22, color: p.highlight), const SizedBox(width: 10), Text(s, style: AppTextStyles.body(p.primaryText))]))],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(25), border: Border.all(color: p.isDark ? const Color(0xFF263552) : p.border), color: p.isDark ? const Color(0xFF0A1126) : p.surface),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text('More', style: AppTextStyles.body(p.primaryText.withValues(alpha: 0.92)).copyWith(fontSize: 14.5)), const SizedBox(width: 6), Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: p.secondaryText)]),
          ),
        ),
    ];
    // a sport picked from "More" is shown as its own chip too, so the choice is visible
    if (selected != null && !featuredSports.any((f) => f.toLowerCase() == selected.toLowerCase())) {
      chips.insert(1, chip(selected, (c) => SportIcon(selected, size: 22, color: c), selected));
    }
    // wide: centred under the search card; phone: one row that scrolls sideways
    if (wide) return Padding(padding: EdgeInsets.symmetric(horizontal: side), child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: chips));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Row(children: [for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: 10), chips[i]]]),
    );
  }
}

// ── Results: filters panel + cards ──────────────────────────────────────

class _Results extends ConsumerWidget {
  const _Results({required this.async, required this.all, required this.filters, required this.saved, required this.wide, required this.onNavigate, required this.p});

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
      return const SizedBox(height: 300, child: Center(child: SizedBox(key: ValueKey('venues-loading'), width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))));
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
              Text("We couldn't load venues just now.", style: AppTextStyles.body(p.primaryText)),
              const SizedBox(height: 16),
              GameAllButton.secondary(label: 'Try again', onPressed: () => ref.invalidate(venuesForSelectedCityProvider(VenueKind.venues))),
            ],
          ),
        ),
      );
    }
    if (all.isEmpty) return const SizedBox(height: 420, child: NoVenuesState());

    final shown = applyVenueFilters(all, filters, saved);
    final ceiling = priceCeiling(all);
    final panel = FiltersPanel(ceiling: ceiling);

    final results = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResultsHeader(count: shown.length, wide: wide, filters: filters, ceiling: ceiling),
        const SizedBox(height: 18),
        if (shown.isEmpty)
          _NoMatches(onClear: () => ref.read(venueFiltersProvider.notifier).clear())
        else
          _CardGrid(venues: shown, view: filters.view, saved: saved, onNavigate: onNavigate),
      ],
    );

    if (!wide) return results;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 264, child: Reveal(delay: const Duration(milliseconds: 100), child: panel)),
        const SizedBox(width: 26),
        Expanded(child: results),
      ],
    );
  }
}

class _ResultsHeader extends ConsumerWidget {
  const _ResultsHeader({required this.count, required this.wide, required this.filters, required this.ceiling});

  final int count;
  final bool wide;
  final VenueFilters filters;
  final int ceiling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    void setView(VenueView v) => ref.read(venueFiltersProvider.notifier).update((f) => f.copyWith(view: v));
    Widget toggle(IconData icon, String label, VenueView v) {
      final on = filters.view == v;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: Pressable(
          key: ValueKey('view-${v.name}'),
          onTap: () => setView(v),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 40,
            height: 36,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: on ? const LinearGradient(colors: [AppColors.violet, AppColors.purple]) : null),
            child: Icon(icon, size: 20, color: on ? Colors.white : p.secondaryText),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            count == 1 ? '1 Venue Found' : '$count Venues Found',
            key: const ValueKey('venues-found'),
            style: AppTextStyles.sectionHeading(p.primaryText).copyWith(fontSize: 18),
          ),
        ),
        if (!wide) ...[
          Pressable(
            key: const ValueKey('open-filters'),
            onTap: () => _openFilters(context, ceiling),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border), color: p.surface),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: p.primaryText),
                  const SizedBox(width: 8),
                  Text(filters.activeCount == 0 ? 'Filters' : 'Filters (${filters.activeCount})', style: AppTextStyles.button(p.primaryText)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), border: Border.all(color: p.border), color: p.surface.withValues(alpha: p.isDark ? 0.5 : 1)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [toggle(Icons.grid_view_rounded, 'Grid view', VenueView.grid), toggle(Icons.view_list_rounded, 'List view', VenueView.list)]),
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
      builder: (_) => SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), child: FiltersPanel(ceiling: ceiling, inSheet: true))),
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
          Text('No venues match these filters', style: AppTextStyles.sectionHeading(p.primaryText)),
          const SizedBox(height: 6),
          Text('Try a different sport, or clear the filters.', style: AppTextStyles.body(p.secondaryText)),
          const SizedBox(height: 18),
          GameAllButton.secondary(label: 'Clear all filters', onPressed: onClear),
        ],
      ),
    );
  }
}

// ── Filters panel ───────────────────────────────────────────────────────

/// The "Filters" box: Clear All, price per hour, venue type, saved venues and Sort By. On a phone it opens in a bottom sheet.
class FiltersPanel extends ConsumerWidget {
  const FiltersPanel({super.key, required this.ceiling, this.inSheet = false});

  final int ceiling;
  final bool inSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final f = ref.watch(venueFiltersProvider);
    final ctl = ref.read(venueFiltersProvider.notifier);

    Widget check(String label, bool value, VenueFilters Function(VenueFilters f, bool v) change, {Key? key}) => Semantics(
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
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), border: Border.all(color: value ? AppColors.violet : p.border, width: 1.5), color: value ? AppColors.violet : Colors.transparent),
                    child: value ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, style: AppTextStyles.body(p.primaryText).copyWith(fontSize: 14))),
                ],
              ),
            ),
          ),
        );

    Widget heading(String text) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 8), child: Text(text, style: AppTextStyles.cardHeading(p.primaryText)));

    final price = f.maxPrice ?? ceiling;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.filter_alt_outlined, size: 20, color: p.primaryText),
            const SizedBox(width: 10),
            Expanded(child: Text('Filters', style: AppTextStyles.sectionHeading(p.primaryText).copyWith(fontSize: 18))),
            Pressable(
              key: const ValueKey('clear-filters'),
              onTap: f.activeCount == 0 ? null : ctl.clear,
              borderRadius: BorderRadius.circular(8),
              child: Padding(padding: const EdgeInsets.all(4), child: Text('Clear All', style: AppTextStyles.meta(f.activeCount == 0 ? p.mutedText : AppColors.purple).copyWith(fontSize: 13, fontWeight: FontWeight.w600))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(height: 1, color: p.border),
        if (ceiling > 0) ...[
          heading('Price per hour'),
          Align(alignment: Alignment.centerRight, child: Text(f.maxPrice == null ? 'Any price' : 'Up to ${rupees(price)}', key: const ValueKey('price-label'), style: AppTextStyles.meta(p.secondaryText).copyWith(fontSize: 12))),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 4, activeTrackColor: AppColors.violet, inactiveTrackColor: p.border, thumbColor: Colors.white, overlayColor: AppColors.violet.withValues(alpha: 0.15), thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8)),
            child: Slider(
              key: const ValueKey('price-slider'),
              min: 50,
              max: ceiling.toDouble() < 100 ? 100 : ceiling.toDouble(),
              divisions: ((ceiling < 100 ? 100 : ceiling) - 50) ~/ 50,
              value: price.toDouble().clamp(50, ceiling < 100 ? 100 : ceiling.toDouble()),
              onChanged: (v) => ctl.update((cur) => cur.copyWith(maxPrice: v.round() >= ceiling ? null : v.round())),
            ),
          ),
        ],
        heading('Venue Type'),
        check('Indoor', f.indoor, (cur, v) => cur.copyWith(indoor: v), key: const ValueKey('filter-indoor')),
        check('Outdoor', f.outdoor, (cur, v) => cur.copyWith(outdoor: v), key: const ValueKey('filter-outdoor')),
        heading('Facilities'),
        check('Free Parking', f.parking, (cur, v) => cur.copyWith(parking: v), key: const ValueKey('filter-parking')),
        check('Changing Rooms', f.changingRooms, (cur, v) => cur.copyWith(changingRooms: v), key: const ValueKey('filter-changing')),
        check('Toilets / Rest Room', f.toilets, (cur, v) => cur.copyWith(toilets: v), key: const ValueKey('filter-toilets')),
        check('Cafeteria', f.cafeteria, (cur, v) => cur.copyWith(cafeteria: v), key: const ValueKey('filter-cafeteria')),
        check('Equipment Rental', f.equipmentRental, (cur, v) => cur.copyWith(equipmentRental: v), key: const ValueKey('filter-rental')),
        heading('Also offers'),
        check('Academy / Coaching', f.academy, (cur, v) => cur.copyWith(academy: v), key: const ValueKey('filter-academy')),
        check('Memberships', f.memberships, (cur, v) => cur.copyWith(memberships: v), key: const ValueKey('filter-memberships')),
        heading('Saved'),
        check('Saved venues only', f.savedOnly, (cur, v) => cur.copyWith(savedOnly: v), key: const ValueKey('filter-saved')),
        heading('Sort By'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border), color: p.isDark ? p.background.withValues(alpha: 0.5) : p.elevated),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<VenueSort>(
              key: const ValueKey('sort-by'),
              isExpanded: true,
              value: f.sort,
              dropdownColor: p.surface,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.secondaryText),
              style: AppTextStyles.body(p.primaryText),
              items: [for (final s in VenueSort.values) DropdownMenuItem(value: s, child: Text(s.label, style: AppTextStyles.body(p.primaryText).copyWith(fontSize: 14)))],
              onChanged: (s) => s == null ? null : ctl.update((cur) => cur.copyWith(sort: s)),
            ),
          ),
        ),
      ],
    );

    if (inSheet) return content;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: p.border), color: p.surface.withValues(alpha: p.isDark ? 0.55 : 1)),
      child: content,
    );
  }
}

// ── Cards ───────────────────────────────────────────────────────────────

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.venues, required this.view, required this.saved, required this.onNavigate});

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
        final cols = view == VenueView.list ? 1 : (w >= 880 ? 3 : (w >= 560 ? 2 : 1));
        final cardWidth = (w - gap * (cols - 1)) / cols;
        return Wrap(
          key: const ValueKey('venue-grid'),
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < venues.length; i++)
              SizedBox(
                width: cardWidth,
                child: Reveal(
                  key: ValueKey('card-${venues[i].id}'),
                  delay: Duration(milliseconds: 30 * (i < 6 ? i : 6)),
                  child: DiscoverVenueCard(venue: venues[i], list: view == VenueView.list, saved: saved.contains(venues[i].id), onOpen: () => onNavigate(AppRoutes.venuePath(venues[i].id))),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One venue in the results: photo, heart (save), name, place, chips with price, and an arrow that opens booking.
class DiscoverVenueCard extends ConsumerWidget {
  const DiscoverVenueCard({super.key, required this.venue, required this.onOpen, this.list = false, this.saved = false});

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
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: Colors.black.withValues(alpha: 0.12))),
              child: ClipOval(child: Image.network(logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink())),
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
                frameBuilder: (context, child, frame, sync) => sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 350), curve: Curves.easeOut, child: child),
                errorBuilder: (_, _, _) => placeholder,
              ),
        Positioned(
          right: 10,
          top: 10,
          child: Semantics(
            button: true,
            label: saved ? 'Remove ${venue.name} from saved' : 'Save ${venue.name}',
            child: Pressable(
              key: ValueKey('heart-${venue.id}'),
              onTap: () => ref.read(savedVenuesProvider.notifier).toggle(venue.id),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.black.withValues(alpha: 0.5)),
                child: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 19, color: saved ? AppColors.danger : Colors.white),
              ),
            ),
          ),
        ),
      ],
    );

    final chips = <Widget>[
      for (final s in venue.sports.take(2)) _TypeChip(label: s, color: sportColor(s)),
      if (venue.venueType != null) _TypeChip(label: venue.venueType == VenueType.indoor ? 'Indoor' : 'Outdoor', color: AppColors.violet),
    ];

    final details = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: HoverText(venue.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.cardHeading(p.primaryText).copyWith(fontSize: 17, fontWeight: FontWeight.w700))),
              if (venue.priceFor(VenueKind.venues) != null) ...[
                const SizedBox(width: 8),
                Text('${rupees(venue.priceFor(VenueKind.venues)!)} / hr', style: AppTextStyles.meta(p.secondaryText).copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 15, color: p.secondaryText),
              const SizedBox(width: 4),
              Expanded(child: Text(venue.place, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.support(p.secondaryText))),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [AppColors.violet, AppColors.purple])),
                child: const Icon(Icons.arrow_forward_rounded, size: 19, color: Colors.white),
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
          decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: p.border), color: p.surface.withValues(alpha: p.isDark ? 0.75 : 1)),
          clipBehavior: Clip.antiAlias,
          child: list
              ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SizedBox(width: 220, child: image), Expanded(child: Center(child: details))]))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [AspectRatio(aspectRatio: 2.0, child: image), details]),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: color.withValues(alpha: p.isDark ? 0.18 : 0.12), border: Border.all(color: color.withValues(alpha: 0.55))),
      child: Text(label, style: AppTextStyles.meta(p.isDark ? Colors.white : color).copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
