import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared, consistent route transitions for the whole app.
///
/// go_router has no global page builder, so routes opt in through one of these helpers — and the same motion is
/// registered as the theme's page transition ([AppPageTransitionsBuilder]), so a route that doesn't opt in still moves
/// the same way. Two flavours:
///  * [fadeThrough] — for switching between peer destinations (the bottom-nav tabs and the "More" menu): the old page
///    fades out while the new one fades in with a hair of scale. No directional slide, because peers have no
///    "forward"/"back" relationship.
///  * [slideOver] — for drilling into a screen (detail pages, the onboarding flow): the new page glides in from the
///    right while the page underneath drifts a little left and dims, so the two read as one continuous movement.
///
/// Durations are a touch longer than a snap on purpose: the eye needs ~300ms to follow a page change, and the curve
/// eases out so it settles instead of stopping dead.
const _enter = Duration(milliseconds: 340);
const _exit = Duration(milliseconds: 280);

const _enterCurve = Curves.easeOutQuart;
const _exitCurve = Curves.easeInCubic;

/// Slide-over motion shared by [slideOver], [AppPageRoute] and the theme's page transition.
Widget appSlideTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final incoming = CurvedAnimation(parent: animation, curve: _enterCurve, reverseCurve: _exitCurve);
  final covered = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

  // The page underneath drifts left a little and dims as the new one arrives.
  return SlideTransition(
    position: Tween<Offset>(begin: Offset.zero, end: const Offset(-0.08, 0)).animate(covered),
    child: FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.82).animate(covered),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero).animate(incoming),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.7, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    ),
  );
}

/// Cross-fade motion for peer destinations.
Widget appFadeThroughTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curved = CurvedAnimation(parent: animation, curve: _enterCurve, reverseCurve: _exitCurve);
  final leaving = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic, reverseCurve: Curves.easeOutCubic);
  return FadeTransition(
    opacity: Tween<double>(begin: 1, end: 0).animate(leaving),
    child: FadeTransition(
      opacity: curved,
      child: ScaleTransition(scale: Tween<double>(begin: 0.985, end: 1).animate(curved), child: child),
    ),
  );
}

CustomTransitionPage<void> fadeThrough(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: _enter,
    reverseTransitionDuration: _exit,
    child: child,
    transitionsBuilder: appFadeThroughTransition,
  );
}

CustomTransitionPage<void> slideOver(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: _enter,
    reverseTransitionDuration: _exit,
    child: child,
    transitionsBuilder: appSlideTransition,
  );
}

/// A [MaterialPageRoute] replacement with the same [slideOver] feel, for the
/// screens still pushed imperatively with `Navigator.push`.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: _enter,
          reverseTransitionDuration: _exit,
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: appSlideTransition,
        );
}

/// The theme's page transition: any route that isn't wrapped by [slideOver] / [fadeThrough] still moves the same way.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Reduced motion: show the page straight away.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return appSlideTransition(context, animation, secondaryAnimation, child);
  }
}
