import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// The Players app's first page: the badminton backdrop, the GameAll mark, and a single "Get Started" action.
///
/// Every size is derived from the screen width (the design is a portrait phone), so the layout holds from small
/// phones to large ones, and every text style is still subject to the system font scale.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, this.onGetStarted});

  /// Called when the player taps "Get Started".
  final VoidCallback? onGetStarted;

  // The design's greens: the bright brand green for emphasis, a soft mint at the start of the button.
  static const Color _green = AppColors.primary;
  static const Color _mint = Color(0xFF3DF0A6);
  static const Color _subtitle = Color(0xFFC3CCD3);
  static const Color _tagline = Color(0xFFD4DBE0);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: const Color(0xFF040B14),
        body: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final pad = w * 0.08;
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.asset('assets/images/players.png', fit: BoxFit.cover, alignment: Alignment.bottomCenter),
                // Keeps the white type readable: a little weight at the very top, a lot at the bottom.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.22, 0.5, 0.72, 1.0],
                      colors: [Color(0x66000000), Color(0x00000000), Color(0x00000000), Color(0x8C020A12), Color(0xE6020A12)],
                    ),
                  ),
                ),
                SafeArea(
                  // Fills the screen on a normal phone; on a small one, or with very large system text, it scrolls
                  // instead of overflowing.
                  child: LayoutBuilder(
                    builder: (context, inner) => SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: inner.maxHeight),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(pad, w * 0.12, pad, w * 0.06),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _Brand(width: w),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Headline(width: w),
                                  SizedBox(height: w * 0.085),
                                  _GetStartedButton(width: w, onPressed: onGetStarted),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Logo, the "GameAll" wordmark (white "Game", green "All") and the tagline.
class _Brand extends StatelessWidget {
  const _Brand({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    final fontSize = width * 0.115;
    return Column(
      children: [
        Image.asset('assets/images/logo-icon.png', width: width * 0.2, height: width * 0.2, fit: BoxFit.contain),
        SizedBox(height: width * 0.02),
        Semantics(
          label: 'GameAll',
          child: ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Game', style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600, height: 1.1, letterSpacing: 0)),
                  TextSpan(text: 'All', style: TextStyle(color: WelcomeScreen._green, fontSize: fontSize, fontWeight: FontWeight.w600, height: 1.1, letterSpacing: 0)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: width * 0.03),
        Text(
          'PLAY  ·  BOOK  ·  COMPETE',
          textAlign: TextAlign.center,
          style: TextStyle(color: WelcomeScreen._tagline, fontSize: width * 0.033, fontWeight: FontWeight.w500, letterSpacing: width * 0.0075),
        ),
      ],
    );
  }
}

/// "Your Badminton Playground" and its one-line promise, left aligned above the button.
class _Headline extends StatelessWidget {
  const _Headline({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    final size = width * 0.092;
    TextStyle line(Color color) => TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -0.4);
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: width * 0.09, height: 2, color: WelcomeScreen._green),
          SizedBox(height: width * 0.05),
          Text('Your', style: line(Colors.white)),
          Text('Badminton', style: line(WelcomeScreen._green)),
          Text('Playground', style: line(Colors.white)),
          SizedBox(height: width * 0.035),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width * 0.76),
            child: Text(
              'Book courts, manage memberships, join tournaments and more.',
              style: TextStyle(color: WelcomeScreen._subtitle, fontSize: width * 0.036, fontWeight: FontWeight.w400, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full-width green pill. Dark text on a mint-to-green gradient, with a soft green glow under it.
class _GetStartedButton extends StatelessWidget {
  const _GetStartedButton({required this.width, required this.onPressed});
  final double width;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final height = (width * 0.145).clamp(52.0, 64.0);
    return Semantics(
      button: true,
      label: 'Get Started',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          gradient: const LinearGradient(colors: [WelcomeScreen._mint, WelcomeScreen._green]),
          boxShadow: [BoxShadow(color: WelcomeScreen._green.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(height / 2),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Get Started', style: TextStyle(color: AppColors.onPrimary, fontSize: width * 0.04, fontWeight: FontWeight.w800)),
                  SizedBox(width: width * 0.03),
                  Icon(Icons.arrow_forward_rounded, color: AppColors.onPrimary, size: width * 0.056),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
