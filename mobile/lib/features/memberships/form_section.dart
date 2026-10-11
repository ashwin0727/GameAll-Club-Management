import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/app_card.dart';

// Small building blocks for the edit pages, drawn with the app's own type scale (section titles,
// row titles, 12px body) so they sit with every other form in the app.

/// A titled card holding a group of fields or read-only rows.
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, this.subtitle, this.icon, required this.children});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: tokens.primary),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(child: Text(title, style: AppTypography.sectionTitle(context))),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: AppTypography.secondary(context)),
            ],
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A label on the left and its value on the right — for the facts a page shows but doesn't edit.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: AppTypography.secondary(context))),
          Expanded(
            flex: 6,
            child: Text(value, textAlign: TextAlign.end, style: AppTypography.rowTitle(context).copyWith(color: valueColor)),
          ),
        ],
      ),
    );
  }
}

/// A field that shows a value but can't be edited, drawn exactly like a disabled text field.
class LockedField extends StatelessWidget {
  const LockedField({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        enabled: false,
        suffixIcon: Icon(Icons.lock_outline, size: 16, color: tokens.textSecondary),
      ),
      child: Text(value, style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: tokens.textSecondary)),
    );
  }
}

/// A date shown in a field; tapping it opens the picker. No text controller — the value is drawn
/// straight from [value], so nothing is created or leaked on each rebuild.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onPick,
    required this.firstDate,
    required this.lastDate,
    required this.format,
    this.errorText,
    this.enabled = true,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final DateTime firstDate;
  final DateTime lastDate;
  final String Function(DateTime) format;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: !enabled
          ? null
          : () async {
              final now = DateTime.now();
              var initial = value ?? now;
              if (initial.isBefore(firstDate)) initial = firstDate;
              if (initial.isAfter(lastDate)) initial = lastDate;
              final picked = await showDatePicker(context: context, initialDate: initial, firstDate: firstDate, lastDate: lastDate);
              if (picked != null) onPick(picked);
            },
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          errorText: errorText,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(value == null ? '' : format(value!), style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

/// A status pill — a tinted rounded label.
class TintPill extends StatelessWidget {
  const TintPill(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
