import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A small message that drops in at the TOP of the screen, over the page, and goes away by itself after a few seconds (or when
/// tapped). Only one shows at a time: a new one replaces the one on screen.
class TopToast {
  const TopToast._();

  static OverlayEntry? _entry;

  /// Shows [message] using the screen the [context] belongs to.
  static void of(BuildContext context, String message, {Duration duration = const Duration(seconds: 5), bool success = false}) =>
      show(Overlay.of(context, rootOverlay: true), context.palette, message, duration: duration, success: success);

  /// Same, from an overlay and palette taken earlier (safe to call after the page that asked has been closed).
  static void show(
    OverlayState overlay,
    AppPalette palette,
    String message, {
    Duration duration = const Duration(seconds: 5),
    bool success = false,
  }) {
    _entry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        palette: palette,
        duration: duration,
        success: success,
        onDone: () {
          if (entry.mounted) entry.remove();
          if (identical(_entry, entry)) _entry = null;
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.palette,
    required this.duration,
    required this.success,
    required this.onDone,
  });

  final String message;
  final AppPalette palette;
  final Duration duration;
  final bool success;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _leave);
  }

  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final accent = widget.success ? AppColors.success : p.highlight;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 14,
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: false,
        child: FadeTransition(
          opacity: _c,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
            child: Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                key: const ValueKey('top-toast'),
                onTap: _leave,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Material(
                    color: p.isDark ? const Color(0xFF14213F) : p.surface,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: accent.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.success ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 18, color: accent),
                          const SizedBox(width: 10),
                          Flexible(child: Text(widget.message, style: AppTextStyles.body(p.primaryText))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
