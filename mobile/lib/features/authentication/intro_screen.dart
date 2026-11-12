import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import 'intro_art.dart';
import 'welcome_screen.dart';

/// How long each intro page stays up before it moves on by itself.
const introAutoAdvance = Duration(seconds: 5);

class _IntroPage {
  const _IntroPage(this.kind, this.title, this.body);

  final IntroArtKind kind;
  final String title;
  final String body;
}

const _pages = <_IntroPage>[
  _IntroPage(IntroArtKind.bookings, 'Simplify Bookings', 'Manage court availability, member slots, and guest bookings effortlessly.'),
  _IntroPage(IntroArtKind.growth, 'Grow Your Business', 'Track revenue, utilization, memberships, and more with powerful insights.'),
];

/// The short intro after "Get Started" on the welcome page: two pages that move on by themselves every five seconds (or by
/// swiping), with Skip at the top right. After the last page, or on Skip, the person goes to Create Account.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// (Re)starts the five-second countdown for the page now showing.
  void _arm() {
    _timer?.cancel();
    _timer = Timer(introAutoAdvance, _next);
  }

  void _next() {
    if (!mounted || _left) return;
    if (_page < _pages.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  /// To Create Account. Replaces this page, so Back from there returns to the welcome page.
  void _finish() {
    if (_left) return;
    _left = true;
    _timer?.cancel();
    context.pushReplacement(AppRoutes.createAccount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: introBackground,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, right: 12),
                  child: TextButton(
                    key: const ValueKey('intro-skip'),
                    onPressed: _finish,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF666666),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    child: const Text('Skip', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) {
                    setState(() => _page = i);
                    _arm();
                  },
                  itemBuilder: (context, i) => _IntroPageView(page: _pages[i]),
                ),
              ),
              // Dot 0 belongs to the welcome page, so these pages are dots 1 and 2.
              IntroDots(count: introTotalSteps, index: _page + 1),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroPageView extends StatelessWidget {
  const _IntroPageView({required this.page});

  final _IntroPage page;

  @override
  Widget build(BuildContext context) {
    // Scrolls instead of overflowing on a short phone or a large font size.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IntroArt(kind: page.kind, width: (constraints.maxHeight * 0.5 * 240 / 200).clamp(180.0, 300.0)),
                const SizedBox(height: 28),
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2, color: Color(0xFF171717)),
                ),
                const SizedBox(height: 12),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, height: 1.4, color: Color(0xFF2B2B2B)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
