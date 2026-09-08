import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared, consistent route transitions for the whole app.
///
/// go_router has no global page builder, so every route opts in through one of
/// these helpers. Two flavours:
///  * [fadeThrough] — for switching between peer destinations (the bottom-nav
///    tabs and the "More" menu). A quick cross-fade with a hair of scale; no
///    directional slide, because peers have no "forward"/"back" relationship.
///  * [slideOver] — for drilling into a screen (detail pages, the onboarding
///    flow). Slides in from the right and fades, matching the platform's
///    push semantics but faster and lighter than the default.
const _fastIn = Duration(milliseconds: 200);
const _fastOut = Duration(milliseconds: 160);

CustomTransitionPage<void> fadeThrough(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: _fastIn,
    reverseTransitionDuration: _fastOut,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

CustomTransitionPage<void> slideOver(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: _fastIn,
    reverseTransitionDuration: _fastOut,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// A [MaterialPageRoute] replacement with the same [slideOver] feel, for the
/// screens still pushed imperatively with `Navigator.push`.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: _fastIn,
          reverseTransitionDuration: _fastOut,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.06, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        );
}
