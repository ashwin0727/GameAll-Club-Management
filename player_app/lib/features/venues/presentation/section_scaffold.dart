import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/reveal.dart';

/// The frame shared by the Venues, Memberships, Coaching and Tournaments pages: the page title at the top left (in line with the
/// logo on a wide window) and the content below, centred across the whole width of the page.
class SectionScaffold extends StatelessWidget {
  const SectionScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;

  /// Shown at the right of the title row (the sort tabs); a thin line then separates the header from the content.
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final side = width >= AppDimensions.desktopBreakpoint
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(side, 12, side, 0),
            child: Reveal(
              dy: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: Text(title, style: AppTextStyles.greeting(p.primaryText))),
                      ?trailing,
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppTextStyles.body(p.secondaryText)),
                  ],
                  if (trailing != null) Container(height: 1, margin: const EdgeInsets.only(top: 0), color: p.border),
                ],
              ),
            ),
          ),
          Expanded(
            child: SizedBox(width: double.infinity, child: child),
          ),
        ],
      ),
    );
  }
}
