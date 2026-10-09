import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

class InsightData {
  const InsightData({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.sub,
    this.subColor,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String? sub;
  final Color? subColor;
  final VoidCallback onTap;
}

/// "View More Insights" — a quiet tile that expands into the four headline figures.
class InsightsPanel extends StatelessWidget {
  const InsightsPanel({
    super.key,
    required this.open,
    required this.onToggle,
    required this.tiles,
  });

  final bool open;
  final VoidCallback onToggle;
  final List<InsightData> tiles;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.violet.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.violet.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tokens.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(Icons.bar_chart_rounded,
                        size: 22, color: tokens.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('View More Insights',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          'Total members, revenue, expiring soon and more',
                          style: TextStyle(
                              fontSize: 12, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: tokens.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0,
                        AppSpacing.md, AppSpacing.md),
                    child: Column(
                      children: [
                        for (var i = 0; i < tiles.length; i += 2) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.sm),
                          // IntrinsicHeight: a stretching Row has no height to stretch to inside a
                          // Column, which threw a layout error and left the panel blank. This sizes
                          // the row to its taller tile and stretches the shorter one to match.
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: InsightTile(data: tiles[i])),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: i + 1 < tiles.length
                                      ? InsightTile(data: tiles[i + 1])
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class InsightTile extends StatelessWidget {
  const InsightTile({super.key, required this.data});

  final InsightData data;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(data.icon, size: 19, color: data.color),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: tokens.textSecondary)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(data.value,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    if (data.sub != null)
                      Text(data.sub!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: data.subColor ?? tokens.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
