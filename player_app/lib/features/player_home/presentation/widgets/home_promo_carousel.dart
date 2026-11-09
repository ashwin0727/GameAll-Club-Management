import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/gameall_buttons.dart';

/// One slide of the promotional card.
class PromoSlide {
  const PromoSlide({
    required this.lead,
    required this.accent,
    required this.subtitle,
    required this.buttonText,
    required this.image,
    required this.route,
  });

  /// The white part of the heading, and the gradient-coloured second line.
  final String lead;
  final String accent;
  final String subtitle;
  final String buttonText;
  final String image;
  final String route;
}

const promoSlides = <PromoSlide>[
  PromoSlide(
    lead: 'Find your game,',
    accent: 'Book your court.',
    subtitle: 'Explore nearby venues and live slots.',
    buttonText: 'Explore Courts',
    image: 'assets/images/hero_badminton.webp',
    route: AppRoutes.guestBooking,
  ),
  PromoSlide(
    lead: 'Play regularly.',
    accent: 'Save more.',
    subtitle: 'Discover memberships at nearby clubs.',
    buttonText: 'Explore Memberships',
    image: 'assets/images/hero_membership.webp',
    route: AppRoutes.memberships,
  ),
  PromoSlide(
    lead: 'Take your game',
    accent: 'to the next level.',
    subtitle: 'Train with certified coaches.',
    buttonText: 'Find a Coach',
    image: 'assets/images/hero_coaching.webp',
    route: AppRoutes.coaching,
  ),
];

/// The promotional carousel: one rounded card, three slides, dots inside the card.
///
/// Turns by itself every [interval]; stops while a finger is on it or the app is in the background; swipes by hand. The timer only
/// ever changes the page; it never navigates: only a tap on the button does.
class HomePromoCarousel extends StatefulWidget {
  const HomePromoCarousel({
    super.key,
    required this.onNavigate,
    this.slides = promoSlides,
    this.interval = const Duration(seconds: 5),
    this.transition = const Duration(milliseconds: 400),
    this.height = AppDimensions.heroHeight,
  });

  final RouteCallback onNavigate;
  final List<PromoSlide> slides;
  final Duration interval;
  final Duration transition;
  final double height;

  @override
  State<HomePromoCarousel> createState() => _HomePromoCarouselState();
}

class _HomePromoCarouselState extends State<HomePromoCarousel>
    with WidgetsBindingObserver {
  // Endless in both directions: the page index is taken modulo the number of slides.
  late final PageController _controller = PageController(
    initialPage: widget.slides.length * 1000,
  );
  Timer? _timer;
  int _page = 0;
  int _pointers = 0;
  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    _inForeground && _pointers == 0 ? _startTimer() : _stopTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.slides.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted ||
          !_controller.hasClients ||
          _pointers > 0 ||
          !_inForeground) {
        return;
      }
      // `page` is null until the pages have been laid out (for instance while the screen is hidden behind another tab): skip that tick.
      final current =
          _controller.positions.length == 1 &&
              _controller.position.haveDimensions
          ? _controller.page
          : null;
      if (current == null) return;
      _controller.animateToPage(
        current.round() + 1,
        duration: widget.transition,
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final slides = widget.slides;
    return Semantics(
      container: true,
      label: 'Promotions',
      // The card clips its own content to its rounded shape (inside the border) and the border is painted over the top, so the
      // photo and the dark overlay reach every corner with no gap.
      child: Container(
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: AppDimensions.cardBorderRadius,
          color: AppColors.darkSecondary,
        ),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: p.border),
          borderRadius: AppDimensions.cardBorderRadius,
        ),
        child: Stack(
          children: [
            // A finger on the card pauses the rotation; lifting it resumes.
            Listener(
              onPointerDown: (_) {
                _pointers++;
                _stopTimer();
              },
              onPointerUp: (_) => _released(),
              onPointerCancel: (_) => _released(),
              child: PageView.builder(
                key: const ValueKey('promo-pages'),
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i % slides.length),
                itemBuilder: (context, i) {
                  final slide = slides[i % slides.length];
                  return _PromoCard(
                    slide: slide,
                    onTap: () => widget.onNavigate(slide.route),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < slides.length; i++)
                      AnimatedContainer(
                        key: ValueKey('promo-dot-$i'),
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: i == _page
                              ? AppColors.cyan
                              : Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _released() {
    if (_pointers > 0) _pointers--;
    if (_pointers == 0 && _inForeground) _startTimer();
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.slide, required this.onTap});

  final PromoSlide slide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The photograph sits to the right.
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 230,
          child: Image.asset(
            slide.image,
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
        ),
        // Dark left-to-right overlay: keeps the text readable and the right side clear.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0.0, 0.5, 0.82],
                colors: [
                  Color(0xFA050C19),
                  Color(0xD9050C19),
                  Color(0x00050C19),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'BOOK  ·  TRAIN  ·  PLAY',
                style: AppTextStyles.eyebrow(AppColors.cyan)
                    .copyWith(fontSize: 10),
              ),
              const SizedBox(height: 8),
              // The text block shrinks to fit (large system fonts, small phones) instead of overflowing the card.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: box.maxWidth * 0.8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slide.lead,
                            style: AppTextStyles.heroHeading(Colors.white),
                          ),
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (rect) => const LinearGradient(
                              colors: [
                                AppColors.cyan,
                                AppColors.blue,
                                AppColors.purple,
                              ],
                            ).createShader(rect),
                            child: Text(
                              slide.accent,
                              style: AppTextStyles.heroHeading(Colors.white),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            slide.subtitle,
                            style: AppTextStyles.support(
                              const Color(0xFFD3DDEE),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: GameAllButton.gradient(
                  label: slide.buttonText,
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onTap,
                  height: 44,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
