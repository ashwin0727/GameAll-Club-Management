import 'package:flutter/material.dart';

/// Fades its child in, once, when it first appears, with a small rise (a few pixels) so it settles rather than pops. [delay] staggers
/// neighbouring items. It never changes the child's size or position in the layout (only how it is painted), so nothing shifts
/// while it plays. With "reduce motion" on, the child simply appears.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero, this.duration = const Duration(milliseconds: 320), this.dy = 8});

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// How far (in pixels) the child rises while it fades in; 0 for a plain fade.
  final double dy;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.delay + widget.duration);
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    // The delay is the first part of one timeline (no timers to leak).
    final start = widget.delay.inMilliseconds / (widget.delay + widget.duration).inMilliseconds;
    _curve = CurvedAnimation(parent: _controller, curve: Interval(start, 1, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      return widget.child;
    }
    return FadeTransition(
      opacity: _curve,
      child: widget.dy == 0
          ? widget.child
          : AnimatedBuilder(
              animation: _curve,
              child: widget.child,
              builder: (context, child) => Transform.translate(offset: Offset(0, (1 - _curve.value) * widget.dy), child: child),
            ),
    );
  }
}
