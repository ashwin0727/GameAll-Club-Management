import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// One full-width KPI card at a time, advancing itself every [interval].
///
/// Auto-advance pauses while the owner is swiping and resumes after, so it
/// never yanks a card away mid-gesture, and each card replays its entrance
/// (and count-up) as it slides in.
class MetricCarousel extends StatefulWidget {
  const MetricCarousel({
    super.key,
    required this.cards,
    this.height = 132,
    this.interval = const Duration(seconds: 5),
  });

  final List<Widget> cards;
  final double height;
  final Duration interval;

  @override
  State<MetricCarousel> createState() => _MetricCarouselState();
}

class _MetricCarouselState extends State<MetricCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || widget.cards.isEmpty || !_controller.hasClients) return;
      final next = (_page + 1) % widget.cards.length;
      // Reduced motion still advances (otherwise every card but the first
      // stays hidden) but jumps instead of sliding.
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _controller.jumpToPage(next);
      } else {
        _controller.animateToPage(next, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // Hold the timer while the owner is dragging, restart it
                // from zero once they let go.
                if (n is ScrollStartNotification && n.dragDetails != null) {
                  _timer?.cancel();
                } else if (n is ScrollEndNotification) {
                  _startTimer();
                }
                return false;
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.cards.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => KeyedSubtree(
                  // Re-keying the active card replays its entrance and
                  // count-up each time it slides into view.
                  key: ValueKey('kpi-$i-${_page == i}'),
                  child: widget.cards[i],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.cards.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _page == i ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _page == i ? tokens.primary : tokens.borderColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
