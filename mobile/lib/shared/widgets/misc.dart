import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import 'app_card.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

enum StatusTone { success, warning, danger, info, neutral }

/// A status is never communicated by color alone (spec §"Status Component":
/// "Status must include icon + text, not just color") — every tone gets a
/// default icon that reads correctly even for a color-blind user; pass
/// [icon] to override it for a more specific status (e.g. a lock for
/// "Protected").
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.tone = StatusTone.neutral, this.icon});

  final String label;
  final StatusTone tone;
  final IconData? icon;

  Color _color(BuildContext context) {
    final tokens = context.tokens;
    switch (tone) {
      case StatusTone.success:
        return tokens.success;
      case StatusTone.warning:
        return tokens.warning;
      case StatusTone.danger:
        return tokens.destructive;
      case StatusTone.info:
        return tokens.info;
      case StatusTone.neutral:
        return tokens.textSecondary;
    }
  }

  IconData get _defaultIcon {
    switch (tone) {
      case StatusTone.success:
        return Icons.check_circle;
      case StatusTone.warning:
        return Icons.error_outline;
      case StatusTone.danger:
        return Icons.cancel;
      case StatusTone.info:
        return Icons.info;
      case StatusTone.neutral:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? _defaultIcon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Never string-concatenates ₹ inline — always through [Formatters.currencyInr]
/// so a future currency change is one place, not scattered widgets.
class CurrencyText extends StatelessWidget {
  const CurrencyText(this.amountInr, {super.key, this.style});

  final num amountInr;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(Formatters.currencyInr(amountInr), style: style);
  }
}

/// An honest "not available yet" placeholder — used instead of fabricating
/// zeros for dashboard modules with no backing table/write-path yet.
/// Mirrors src/features/dashboard/components/unavailable-card.tsx.
class UnavailableCard extends StatelessWidget {
  const UnavailableCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}