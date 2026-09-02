import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// A compact KPI tile (spec §"Owner Summary": "compact metric cards", not
/// "four enormous KPI cards occupying the entire screen") — the trend
/// arrow only renders when [changePercent] is actually known, never a
/// fabricated 0%.
///
/// Optional landing motion: pass [countTo] + [formatValue] to count the
/// figure up from 0, and [entranceDelay] to stagger a row of tiles. Both
/// are skipped when the platform asks for reduced motion — the number is
/// information, not decoration, so it must read correctly either way.
class AppMetricCard extends StatelessWidget {
  const AppMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.changePercent,
    this.icon,
    this.accentColor,
    this.countTo,
    this.formatValue,
    this.entranceDelay = Duration.zero,
  });

  final String label;
  final String value;
  final double? changePercent;
  final IconData? icon;
  final Color? accentColor;

  /// Target for the count-up. Requires [formatValue]; without both, [value]
  /// renders as-is.
  final num? countTo;
  final String Function(num)? formatValue;

  /// Staggers this tile's fade/slide entrance (0 = animate immediately).
  final Duration entranceDelay;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = accentColor ?? tokens.primary;
    final trendUp = changePercent != null && changePercent! > 0;
    final trendDown = changePercent != null && changePercent! < 0;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final trendColor = trendUp ? tokens.success : (trendDown ? tokens.destructive : tokens.textSecondary);

    final figure = countTo != null && formatValue != null && !reduced
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: countTo!.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutQuart,
            builder: (context, v, _) => Text(
              formatValue!(v),
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          )
        : Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          );

    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // Neutral border and lift. The accent belongs to the icon chip alone
        // — tinting the card's own edge made the colour visible down the left
        // and right sides of every tile.
        border: Border.all(color: tokens.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 14, color: accent),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Figure and delta share a line, as in the design.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(child: figure),
              if (changePercent != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trendUp ? Icons.arrow_upward : (trendDown ? Icons.arrow_downward : Icons.remove),
                        size: 11,
                        color: trendColor,
                      ),
                      const SizedBox(width: 1),
                      Text(
                        '${changePercent!.abs().round()}%',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: trendColor),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (reduced) return card;

    // Fade + rise, matching the web dashboard's `.stat-enter`. The delay is
    // applied by holding the tile at its start state until it elapses.
    return TweenAnimationBuilder<double>(
      key: ValueKey(entranceDelay),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380) + entranceDelay,
      curve: Interval(
        entranceDelay.inMilliseconds / (380 + entranceDelay.inMilliseconds),
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: card,
    );
  }
}