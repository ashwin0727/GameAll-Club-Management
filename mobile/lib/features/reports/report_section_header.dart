import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// A report section header — a green accent bar + bold title, the same
/// motif the dashboard uses (e.g. "Free slots left today") and Refunds/
/// Transactions have since adopted, so every list-style page in the app
/// reads as one consistent design rather than each using the generic
/// Material `SectionHeader`.
class ReportSectionHeader extends StatelessWidget {
  const ReportSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(color: tokens.primary, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
        ),
        ?trailing,
      ],
    );
  }
}
