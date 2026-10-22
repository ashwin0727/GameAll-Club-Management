import 'package:flutter/material.dart';

/// Swaps what a page shows (skeleton → content, content → error, one tab's body → another) with a soft cross-fade and a
/// small upward settle, instead of the content snapping in and the page seeming to jump.
///
/// Wrap the loading/error/content expression itself:
///
/// ```dart
/// body: SmoothSwitcher(child: _loading ? const _Skeleton() : _error != null ? ErrorView(...) : content)
/// ```
///
/// It animates whenever the child's type or key changes (skeleton → list, list → error), which is exactly when the page
/// would otherwise jump. Both children are laid out at the full size they are given, so the page never shrinks while one
/// fades into the other. Under reduced motion the swap is instant.
class SmoothSwitcher extends StatelessWidget {
  const SmoothSwitcher({super.key, required this.child, this.duration = const Duration(milliseconds: 320)});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : duration,
      reverseDuration: reduced ? Duration.zero : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      // Every child fills the space it is given (loose stacks let a short skeleton collapse the page).
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}

/// Animates a block's own height when its content changes size (a list that grows as data arrives, a panel that
/// expands) so the rest of the page eases down instead of jumping.
class SmoothSize extends StatelessWidget {
  const SmoothSize({super.key, required this.child, this.duration = const Duration(milliseconds: 260)});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSize(
      duration: reduced ? Duration.zero : duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
