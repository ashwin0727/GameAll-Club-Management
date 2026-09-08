import 'package:flutter/material.dart';
import 'breakpoints.dart';

/// Builds a different widget per [ScreenSize] without scattering raw width
/// checks through feature code. Falls back medium → small → large so a
/// caller never has to supply all three.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.medium,
    this.small,
    this.large,
  });

  final WidgetBuilder medium;
  final WidgetBuilder? small;
  final WidgetBuilder? large;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Breakpoints.classify(constraints.maxWidth);
        switch (size) {
          case ScreenSize.small:
            return (small ?? medium)(context);
          case ScreenSize.large:
            return (large ?? medium)(context);
          case ScreenSize.medium:
            return medium(context);
        }
      },
    );
  }
}

/// Centers and caps content width on large phones/tablets (item 49) while
/// remaining full-width, scrollable, and keyboard-safe on normal phones —
/// the standard shell every form/screen in this app is built on (item 51).
class ResponsivePage extends StatelessWidget {
  const ResponsivePage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.scrollable = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    // Align.topCenter, not Center — this should only cap/center width on
    // wide screens. Center also centers vertically, which on a short page
    // (few list rows) inside the minHeight-forced scroll view below pushes
    // everything down into a large empty band at the top.
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
        child: Padding(padding: padding, child: child),
      ),
    );

    if (!scrollable) return content;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        );
      },
    );
  }
}