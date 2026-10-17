import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// A short confirmation (or error) that slides down from the top of the screen, sits under the status bar for a
/// few seconds and slides away — instead of the SnackBar that hides at the bottom behind the nav. Tap to dismiss.
void showTopNotice(BuildContext context, String message, {bool success = true, Duration duration = const Duration(seconds: 3)}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _TopNotice(message: message, success: success, duration: duration, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _TopNotice extends StatefulWidget {
  const _TopNotice({required this.message, required this.success, required this.duration, required this.onDone});

  final String message;
  final bool success;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_TopNotice> createState() => _TopNoticeState();
}

class _TopNoticeState extends State<_TopNotice> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) await _c.reverse();
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
    final t = context.tokens;
    final accent = widget.success ? t.success : t.destructive;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.4), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: _c,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _close,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: t.surface1,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: Icon(widget.success ? Icons.check_rounded : Icons.error_outline_rounded, size: 18, color: accent),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(widget.message, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
