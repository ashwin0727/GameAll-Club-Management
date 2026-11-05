import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/hover_scope.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sport_icon.dart';
import '../../../core/widgets/venue_scene.dart';
import '../../player_home/application/player_home_controller.dart';
import '../application/venues_providers.dart';
import '../domain/venue.dart';
import 'location_aware_body.dart';
import 'section_scaffold.dart';

enum _Sort { name, priceLow, priceHigh }

/// The Venues, Memberships and Coaching pages: "1319 Sports Venues In Chennai", sort tabs on the right, and a grid of photo cards.
/// Which venues appear depends on [kind]: every bookable venue, only those that have created a membership plan, or only those that
/// have created a coaching programme. With none in the picked city the page shows the no-venues message instead.
class VenuesPage extends ConsumerStatefulWidget {
  const VenuesPage({super.key, required this.onNavigate, this.kind = VenueKind.venues});

  final void Function(String route) onNavigate;
  final VenueKind kind;

  @override
  ConsumerState<VenuesPage> createState() => _VenuesPageState();
}

class _VenuesPageState extends ConsumerState<VenuesPage> {
  _Sort _sort = _Sort.name;

  List<Venue> _sorted(List<Venue> venues) {
    final list = [...venues];
    int byName(Venue a, Venue b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    list.sort((a, b) {
      if (_sort == _Sort.name) return byName(a, b);
      final pa = a.priceFor(widget.kind);
      final pb = b.priceFor(widget.kind);
      // venues without a price go last either way
      if (pa == null && pb == null) return byName(a, b);
      if (pa == null) return 1;
      if (pb == null) return -1;
      final c = _sort == _Sort.priceLow ? pa.compareTo(pb) : pb.compareTo(pa);
      return c != 0 ? c : byName(a, b);
    });
    return list;
  }

  String _title(String city, int? count) {
    final n = count == null ? '' : '$count ';
    return switch (widget.kind) {
      VenueKind.venues => '${n}Sports Venues In $city',
      VenueKind.memberships => '${n}Venues With Memberships In $city',
      VenueKind.coaching => '${n}Venues With Coaching In $city',
    };
  }

  @override
  Widget build(BuildContext context) {
    final city = cityOf(ref.watch(selectedCityProvider));
    final count = ref.watch(venuesForSelectedCityProvider(widget.kind)).value?.length;
    final side = MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint
        ? AppDimensions.desktopSidePadding(MediaQuery.sizeOf(context).width)
        : AppDimensions.screenPadding;
    return SectionScaffold(
      title: _title(city, (count ?? 0) == 0 ? null : count),
      trailing: (count ?? 0) == 0 ? null : _SortTabs(sort: _sort, onChanged: (s) => setState(() => _sort = s)),
      child: LocationAwareBody(
        kind: widget.kind,
        builder: (context, venues) => _Grid(
          venues: _sorted(venues),
          kind: widget.kind,
          side: side,
          onOpen: (v) => widget.onNavigate(AppRoutes.venuePath(v.id)),
        ),
      ),
    );
  }
}

/// "Name" and "Price" with a blue line under the chosen one; Price flips between low-to-high and high-to-low.
class _SortTabs extends StatelessWidget {
  const _SortTabs({required this.sort, required this.onChanged});

  final _Sort sort;
  final ValueChanged<_Sort> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget tab(String label, bool selected, VoidCallback onTap, {IconData? icon, Key? key}) => Pressable(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            margin: const EdgeInsets.only(left: 22),
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected ? AppColors.blue : Colors.transparent, width: 3))),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppTextStyles.body(selected ? p.primaryText : p.secondaryText).copyWith(fontSize: 16, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                if (icon != null) ...[const SizedBox(width: 6), Icon(icon, size: 20, color: selected ? p.primaryText : p.secondaryText)],
              ],
            ),
          ),
        );
    final byPrice = sort == _Sort.priceLow || sort == _Sort.priceHigh;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tab('Name', sort == _Sort.name, () => onChanged(_Sort.name), key: const ValueKey('sort-name')),
        tab(
          'Price',
          byPrice,
          () => onChanged(sort == _Sort.priceLow ? _Sort.priceHigh : _Sort.priceLow),
          icon: sort == _Sort.priceHigh ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          key: const ValueKey('sort-price'),
        ),
      ],
    );
  }
}

/// Cards in rows: three across on a wide window, two on a tablet, one on a phone.
class _Grid extends StatelessWidget {
  const _Grid({required this.venues, required this.kind, required this.side, required this.onOpen});

  final List<Venue> venues;
  final VenueKind kind;
  final double side;
  final void Function(Venue venue)? onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 28.0;
        final inner = box.maxWidth - side * 2;
        final cols = inner >= 960 ? 3 : (inner >= 600 ? 2 : 1);
        final cardWidth = (inner - gap * (cols - 1)) / cols;
        return SingleChildScrollView(
          key: const ValueKey('venue-grid'),
          padding: EdgeInsets.fromLTRB(side, 28, side, 48),
          child: Wrap(
            spacing: gap,
            runSpacing: 36,
            children: [
              for (var i = 0; i < venues.length; i++)
                SizedBox(
                  width: cardWidth,
                  child: Reveal(
                    delay: Duration(milliseconds: 30 * (i < 6 ? i : 6)),
                    child: VenueCard(venue: venues[i], kind: kind, onTap: onOpen == null ? null : () => onOpen!(venues[i])),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One venue: its photo with the main sport on it, the name and area, and chips with the price.
class VenueCard extends StatelessWidget {
  const VenueCard({super.key, required this.venue, required this.onTap, this.kind = VenueKind.venues});

  final Venue venue;
  final VenueKind kind;

  /// Null makes the card inert (the Memberships and Coaching cards have no detail page yet).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final photo = venue.heroImageUrl;
    final logo = venue.logoUrl;
    final mainSport = venue.sports.isEmpty ? null : venue.sports.first;
    final chips = venue.chipsFor(kind);
    final price = venue.priceFor(kind);
    final priceText = price == null
        ? null
        : switch (kind) {
            VenueKind.venues => '${rupees(price)} / hr',
            VenueKind.memberships || VenueKind.coaching => 'from ${rupees(price)}',
          };

    // No photo: a picture of the court or pitch for this sport (drawn in code), with the venue's logo as a small badge when it has one.
    final placeholder = Stack(
      fit: StackFit.expand,
      children: [
        VenueScene(sport: mainSport),
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

    return Semantics(
      button: onTap != null,
      label: '${venue.name}, ${venue.place}',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          scale: 0.985,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      photo == null
                          ? placeholder
                          : Image.network(
                              photo,
                              fit: BoxFit.cover,
                              // The picture fades in when it arrives instead of popping in; a broken link shows the placeholder.
                              frameBuilder: (context, child, frame, sync) => sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 350), curve: Curves.easeOut, child: child),
                              errorBuilder: (_, _, _) => placeholder,
                            ),
                      if (mainSport != null)
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.black.withValues(alpha: 0.55)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SportIcon(mainSport, size: 18, color: Colors.white),
                                const SizedBox(width: 7),
                                Text(mainSport, style: AppTextStyles.meta(Colors.white).copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: venue.name, style: AppTextStyles.cardHeading(p.primaryText).copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
                    if (venue.area != null) TextSpan(text: ',  ${venue.area}', style: AppTextStyles.body(p.secondaryText).copyWith(fontSize: 16)),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final c in chips.take(2)) _Chip(label: c),
                  if (chips.length > 2) _Chip(label: '+${chips.length - 2}'),
                  if (priceText != null) ...[
                    Text('•', style: AppTextStyles.body(p.secondaryText)),
                    Text(priceText, style: AppTextStyles.body(p.secondaryText).copyWith(fontSize: 16)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: p.isDark ? p.elevated.withValues(alpha: 0.9) : p.elevated, borderRadius: BorderRadius.circular(22)),
      child: HoverText(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(p.primaryText).copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }
}
