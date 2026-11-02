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
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
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
                  Text(title, style: AppTextStyles.greeting(p.primaryText)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.body(p.secondaryText)),
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
