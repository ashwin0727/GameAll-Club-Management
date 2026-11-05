import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/venue_scene.dart';
import '../application/venue_filters.dart';

/// The venue's photos: a large picture you can swipe (or step with the arrows), dots under it, the heart that saves the venue, and
/// optionally a column of small pictures to jump between them. A venue with no photo shows a drawn court for its sport.
class VenueGallery extends ConsumerStatefulWidget {
  const VenueGallery({
    super.key,
    required this.venueId,
    required this.photos,
    required this.sport,
    this.thumbnails = false,
    this.arrows = true,
    this.counter = false,
    this.verifiedBadge = false,
    this.aspectRatio = 1.78,
    this.borderRadius = 22,
  });

  final String venueId;
  final List<String> photos;

  /// The venue's main sport, for the drawn picture when there are no photos.
  final String? sport;
  final bool thumbnails;
  final bool arrows;

  /// "1 / 6" in the corner (the phone design) instead of dots only.
  final bool counter;
  final bool verifiedBadge;
  final double aspectRatio;
  final double borderRadius;

  @override
  ConsumerState<VenueGallery> createState() => _VenueGalleryState();
}

class _VenueGalleryState extends ConsumerState<VenueGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) {
    final n = widget.photos.length;
    if (n == 0) return;
    final target = (i % n + n) % n;
    _controller.animateToPage(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  Widget _photo(String url) => Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (context, child, frame, sync) => sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 350), curve: Curves.easeOut, child: child),
        errorBuilder: (_, _, _) => VenueScene(sport: widget.sport),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final photos = widget.photos;
    final saved = ref.watch(savedVenuesProvider).contains(widget.venueId);
    final radius = BorderRadius.circular(widget.borderRadius);

    final main = ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photos.isEmpty)
              VenueScene(sport: widget.sport)
            else
              PageView.builder(
                key: const ValueKey('gallery-pages'),
                controller: _controller,
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _photo(photos[i]),
              ),
            if (widget.verifiedBadge)
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.violet.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.verified_rounded, size: 15, color: Colors.white), SizedBox(width: 6), Text('Verified Venue', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))],
                  ),
                ),
              ),
            Positioned(
              right: 12,
              top: 12,
              child: Semantics(
                button: true,
                label: saved ? 'Remove from saved' : 'Save venue',
                child: Pressable(
                  key: const ValueKey('gallery-heart'),
                  onTap: () => ref.read(savedVenuesProvider.notifier).toggle(widget.venueId),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.black.withValues(alpha: 0.5)),
                    child: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 21, color: saved ? AppColors.danger : Colors.white),
                  ),
                ),
              ),
            ),
            if (widget.arrows && photos.length > 1) ...[
              Positioned(left: 12, top: 0, bottom: 0, child: Center(child: _Arrow(key: const ValueKey('gallery-prev'), icon: Icons.chevron_left_rounded, onTap: () => _go(_page - 1)))),
              Positioned(right: 12, top: 0, bottom: 0, child: Center(child: _Arrow(key: const ValueKey('gallery-next'), icon: Icons.chevron_right_rounded, onTap: () => _go(_page + 1)))),
            ],
            if (photos.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: widget.counter
                    ? Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
                            child: Text('${_page + 1} / ${photos.length}', key: const ValueKey('gallery-counter'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < photos.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _page ? 22 : 8,
                              height: 8,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: i == _page ? AppColors.violet : Colors.white.withValues(alpha: 0.8)),
                            ),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );

    if (!widget.thumbnails || photos.length < 2) return main;

    // Wide design: the big picture and a column of up to three small ones beside it.
    final thumbs = photos.take(3).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        const SizedBox(width: 14),
        SizedBox(
          width: 150,
          child: Column(
            children: [
              for (var i = 0; i < thumbs.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                Pressable(
                  key: ValueKey('gallery-thumb-$i'),
                  onTap: () => _go(i),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: i == _page ? AppColors.cyan : p.border, width: i == _page ? 2 : 1)),
                    clipBehavior: Clip.antiAlias,
                    child: AspectRatio(aspectRatio: 1.45, child: _photo(thumbs[i])),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.5), border: Border.all(color: Colors.white24)),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      );
}
