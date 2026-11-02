import 'package:flutter/material.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/gameall_buttons.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/reveal.dart';
import '../../domain/player_home_models.dart';
import '../widgets/player_shortcut_card.dart';

/// The wide-screen (web) body of the Home page. The brand bar and the page background belong to the app shell.
///
/// The first screen holds everything in the design without scrolling: the hero (headline, promise, buttons and the player), the
/// three shortcut cards and the four feature points. The hero stretches or shrinks to fill whatever height the window has;
/// "Your Next Game" sits just below, a scroll away. The page uses the full width, with the same side margin as the brand bar.
class PlayerHomeDesktopBody extends StatelessWidget {
  const PlayerHomeDesktopBody({
    super.key,
    required this.data,
    required this.next,
    required this.loading,
    required this.onNavigate,
    this.now,
    this.header,
  });

  /// The brand bar, shown at the very top of the scrolling content.
  final Widget? header;
  final PlayerHomeData data;
  final NextGame next;
  final bool loading;
  final RouteCallback onNavigate;
  final DateTime? now;

  /// The shortest the first screen is allowed to get: below this the page scrolls instead of squeezing further.
  static const double _minFirstScreen = 640;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final side = AppDimensions.desktopSidePadding(width);
        final firstScreen = box.maxHeight < _minFirstScreen
            ? _minFirstScreen
            : box.maxHeight;
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: firstScreen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?header,
                    Expanded(
                      child: _Hero(side: side, onNavigate: onNavigate),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: Reveal(
                        delay: const Duration(milliseconds: 180),
                        child: PlayerShortcutCards(
                          hasActiveMembership: data.hasActiveMembership,
                          hasActiveCoaching: data.hasActiveCoaching,
                          onNavigate: onNavigate,
                          wide: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: const Reveal(
                        delay: Duration(milliseconds: 224),
                        child: _FeatureStrip(),
                      ),
                    ),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.side, required this.onNavigate});

  final double side;
  final RouteCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        // Type scales with the window, and is held back when the window is short so the text never crowds the cards.
        final headline = (w * 0.034).clamp(34.0, 68.0).clamp(0.0, h * 0.15);
        final lead = (w * 0.0105).clamp(15.0, 21.0);
        final compact = w < 900;

        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Reveal(
              child: Text(
                'BOOK  ·  TRAIN  ·  PLAY',
                style: AppTextStyles.eyebrow(p.highlight),
              ),
            ),
            SizedBox(height: (h * 0.035).clamp(10.0, 22.0)),
            Reveal(
              delay: const Duration(milliseconds: 36),
              child: Text(
                'Your Game,',
                style: AppTextStyles.desktopHeroHeading(p.primaryText)
                    .copyWith(fontSize: headline),
              ),
            ),
            // "All in" is white; "One Place" keeps the blue-to-purple of the original gradient (the part of it that sat under those words).
            Reveal(
              delay: const Duration(milliseconds: 72),
              child: Wrap(
                children: [
                  Text(
                    'All in ',
                    style: AppTextStyles.desktopHeroHeading(Colors.white)
                        .copyWith(fontSize: headline),
                  ),
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (rect) => LinearGradient(
                      colors: [
                        Color.lerp(AppColors.cyan, AppColors.blue, 0.84)!,
                        AppColors.blue,
                        AppColors.purple,
                      ],
                    ).createShader(rect),
                    child: Text(
                      'One Place',
                      style: AppTextStyles.desktopHeroHeading(Colors.white)
                          .copyWith(fontSize: headline),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: (h * 0.035).clamp(10.0, 20.0)),
            Reveal(
              delay: const Duration(milliseconds: 108),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: lead * 24),
                child: Text(
                  'Book courts, explore memberships, find coaching and join sports events near you.',
                  style: AppTextStyles.body(p.secondaryText)
                      .copyWith(fontSize: lead, height: 1.5),
                ),
              ),
            ),
            SizedBox(height: (h * 0.06).clamp(14.0, 34.0)),
            Reveal(
              delay: const Duration(milliseconds: 144),
              child: Wrap(
                spacing: 20,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GameAllButton.gradient(
                    label: 'Find a Court',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => onNavigate(AppRoutes.guestBooking),
                    height: 52,
                  ),
                  Pressable(
                    onTap: () => onNavigate(AppRoutes.howItWorks),
                    borderRadius: BorderRadius.circular(26),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: p.border, width: 1.5),
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: p.primaryText,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'How GameAll Works',
                            style: AppTextStyles.button(p.primaryText)
                                .copyWith(fontSize: 15),
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

        // The player, on the right. The picture's own edges fade to nothing (a mask, not a coloured overlay) so it sits in the
        // page background without a frame.
        Widget player(double imageWidth, double imageHeight) => SizedBox(
          width: imageWidth,
          height: imageHeight,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x00000000), Color(0xFF000000)],
              stops: [0.0, 0.30],
            ).createShader(rect),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00000000),
                  Color(0xFF000000),
                  Color(0xFF000000),
                  Color(0x00000000),
                ],
                stops: [0.0, 0.16, 0.84, 1.0],
              ).createShader(rect),
              child: Image.asset(
                'assets/images/hero_player.webp',
                fit: BoxFit.cover,
                alignment: Alignment.topRight,
              ),
            ),
          ),
        );

        if (compact) {
          return SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(side, 8, side, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 16),
                Reveal(
                  delay: const Duration(milliseconds: 80),
                  child: player(w - side * 2, (w - side * 2) / 1.75),
                ),
              ],
            ),
          );
        }

        // The picture is 1.75 times wider than it is tall; it fills the hero's height and runs to the right edge of the screen.
        final imageHeight = h;
        final imageWidth = (imageHeight * 1.75).clamp(0.0, w * 0.62);
        return Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Reveal(
                delay: const Duration(milliseconds: 60),
                duration: const Duration(milliseconds: 450),
                dy: 0,
                child: player(imageWidth, imageHeight),
              ),
            ),
            Positioned(
              left: side,
              top: 0,
              bottom: 0,
              width: w * 0.5,
              child: Align(alignment: Alignment.centerLeft, child: text),
            ),
          ],
        );
      },
    );
  }
}

class _FeatureStrip extends StatelessWidget {
  const _FeatureStrip();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const items = [
      (Icons.bolt_rounded, 'Real-time Availability', AppColors.violet),
      (Icons.event_available_outlined, 'Easy Booking', AppColors.cyan),
      (Icons.groups_outlined, 'Coaches & Academies', AppColors.blue),
      (Icons.emoji_events_outlined, 'Events & Tournaments', AppColors.purple),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(width: 1, height: 28, color: p.border),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(items[i].$1, color: items[i].$3, size: 24),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    items[i].$2,
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
    );
  }
}
