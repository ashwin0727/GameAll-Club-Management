import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'tournament_app_config.dart';

/// ONE phone-framed application preview. Shows a single screenshot at a time;
/// with more than one configured it cross-fades between them every few seconds,
/// and a row of dots switches manually. There is never a second phone on
/// screen. Missing asset files fall back to a labelled placeholder rather than
/// crashing.
class TournamentAppPreview extends StatefulWidget {
  const TournamentAppPreview({super.key, required this.previews, this.autoplay = true});

  final List<TournamentPreview> previews;

  /// Advance automatically every 5 seconds. Disabled in tests and when the
  /// platform requests reduced motion.
  final bool autoplay;

  @override
  State<TournamentAppPreview> createState() => _TournamentAppPreviewState();
}

class _TournamentAppPreviewState extends State<TournamentAppPreview> {
  static const _interval = Duration(seconds: 5);
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartAutoplay());
  }

  void _maybeStartAutoplay() {
    _timer?.cancel();
    if (!mounted) return;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!widget.autoplay || reduceMotion || widget.previews.length < 2) return;
    _timer = Timer.periodic(_interval, (_) {
      if (mounted) setState(() => _index = (_index + 1) % widget.previews.length);
    });
  }

  void _select(int i) {
    setState(() => _index = i);
    _maybeStartAutoplay(); // reset the clock after a manual pick
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final previews = widget.previews;
    final current = previews.isEmpty ? null : previews[_index.clamp(0, previews.length - 1)];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Device frame sized to a Samsung Galaxy S26 Ultra: 6.9" display,
        // 3120×1440 → a ~9:19.5 screen with a slim uniform bezel. The
        // screenshot keeps its own aspect ratio (contained on black), so
        // nothing is cropped.
        Container(
          width: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: const Color(0xFF171717), width: 5),
            color: const Color(0xFF0A0A0A),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 12))],
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 1440 / 3120,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: current == null
                  ? const _Fallback(key: ValueKey('fallback'), label: 'App preview coming soon')
                  : Image.asset(
                      current.asset,
                      key: ValueKey(current.asset),
                      fit: BoxFit.contain,
                      semanticLabel: 'GameAll Tournament Management — ${current.label}',
                      errorBuilder: (context, error, stack) =>
                          const _Fallback(key: ValueKey('fallback'), label: 'App preview coming soon'),
                    ),
            ),
          ),
        ),
        if (previews.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < previews.length; i++)
                Semantics(
                  button: true,
                  selected: i == _index,
                  label: 'Show ${previews[i].label}',
                  child: GestureDetector(
                    onTap: () => _select(i),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index ? t.primary : Colors.transparent,
                        border: Border.all(color: t.borderColor),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surface2,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined, size: 40, color: t.textSecondary),
            const SizedBox(height: AppSpacing.sm),
            Text('Tournament Management', style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: t.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
