import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// A compact KPI tile (spec §"Owner Summary": "compact metric cards", not
/// "four enormous KPI cards occupying the entire screen") — the trend
/// arrow only renders when [changePercent] is actually known, never a
/// fabricated 0%.
class AppMetricCard extends StatelessWidget {
  const AppMetricCard({super.key, required this.label, required this.value, this.changePercent, this.icon, this.accentColor});

  final String label;
  final String value;
  final double? changePercent;
  final IconData? icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = accentColor ?? tokens.primary;
    final trendUp = changePercent != null && changePercent! > 0;
    final trendDown = changePercent != null && changePercent! < 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (changePercent != null) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  trendUp ? Icons.arrow_upward : (trendDown ? Icons.arrow_downward : Icons.remove),
                  size: 12,
                  color: trendUp ? tokens.success : (trendDown ? tokens.destructive : tokens.textSecondary),
                ),
                const SizedBox(width: 2),
                Text(
                  '${changePercent!.abs().round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: trendUp ? tokens.success : (trendDown ? tokens.destructive : tokens.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}