import 'package:flutter/material.dart';

import 'hover_scope.dart';

/// Makes anything tappable with the app's 150ms press animation (a small scale-down). A null [onTap] makes it inert.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.97,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  /// Shape of the ripple; defaults to a square one.
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hovered = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  void _hover(bool v) {
    if (_hovered != v && mounted) setState(() => _hovered = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: HoverScope(hovered: _hovered && enabled, child: _body(enabled)),
    );
  }

  Widget _body(bool enabled) {
    return AnimatedScale(
      scale: _down && enabled ? widget.scale : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          // No shaded background on hover, press or focus-by-mouse: the text thickens on hover and the control shrinks slightly
          // when pressed instead.
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          onTapDown: (_) => _set(true),
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          borderRadius: widget.borderRadius,
          child: widget.child,
        ),
      ),
    );
  }
}
