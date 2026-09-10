import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Prev / Next over server-side pages, with the server's own total count.
///
/// The label lives in an [Expanded] and the buttons are content-sized in a
/// bounded [Row] — a full-width button (`SecondaryButton`, whose style sets
/// `minimumSize: Size.fromHeight(...)`, i.e. an infinite min width) placed in
/// an unbounded parent such as a [Wrap] forces an infinite width and breaks
/// the layout of everything around it, which is what left the finance list
/// screens rendering but un-tappable.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.totalLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int totalPages;

  /// e.g. "12 expenses" / "3 owed" — the noun the count is of.
  final String totalLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppSpacing.minTouchTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      visualDensity: VisualDensity.compact,
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            'Page ${page + 1} of $totalPages · $totalLabel',
            style: AppTypography.secondary(context),
          ),
        ),
        OutlinedButton(onPressed: onPrevious, style: style, child: const Text('Previous')),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(onPressed: onNext, style: style, child: const Text('Next')),
      ],
    );
  }
}
