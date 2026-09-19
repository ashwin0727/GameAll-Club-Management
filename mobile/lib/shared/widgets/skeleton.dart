import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// A single shimmering placeholder block.
///
/// Skeletons beat a spinner for page loads: they occupy the space the real
/// content will take, so the layout doesn't jump when data lands and the
/// screen never looks empty or stalled while a request is in flight.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = tokens.surface2;
    final highlight = Color.alphaBlend(tokens.textSecondary.withValues(alpha: 0.10), base);

    // Respect the platform's reduce-motion setting: a static block still
    // communicates "content is coming", without a looping animation.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return _block(base, null);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return _block(
          base,
          LinearGradient(
            begin: Alignment(-1 - 2 * (1 - t), 0),
            end: Alignment(1 - 2 * (1 - t), 0),
            colors: [base, highlight, base],
            stops: const [0.35, 0.5, 0.65],
          ),
        );
      },
    );
  }

  Widget _block(Color base, Gradient? gradient) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          gradient: gradient,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
}

/// A bordered card shell matching [AppCard]'s exact visual treatment
/// (surface1 fill, border, `AppRadius.lg` corners) but built from a plain
/// [Container] rather than [Card] — skeletons never want Material's ripple/
/// elevation semantics, just the same silhouette real cards have, so a
/// page's shaped skeleton lines up pixel-for-pixel with its loaded content.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.lg)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border.all(color: tokens.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: child,
    );
  }
}

/// One KPI-tile-shaped placeholder — icon circle + a value line + a label
/// line — for the many "stat grid" screens across the app (dashboard,
/// finance, maintenance, inventory, coaching, membership sessions, every
/// analytics report). Compose several into a [Row]/[Wrap]/[GridView] to
/// match a screen's real KPI grid shape and count.
class SkeletonStatTile extends StatelessWidget {
  const SkeletonStatTile({super.key, this.height = 92});

  final double height;

  /// The icon+value+label content's own natural height — fixed regardless
  /// of [height], which is only ever a hint to an ambient layout (a Wrap
  /// item's height, a GridView's childAspectRatio,…), never a promise this
  /// content will fit inside it.
  static const _contentHeight = 74.0;

  @override
  Widget build(BuildContext context) {
    // The outer SizedBox forces THIS widget to report exactly [height] in
    // any loose/unbounded ambient context (a Row/Wrap sitting in a
    // scrollable Column, which hands children an unconstrained max-height —
    // FittedBox can't size itself there without a concrete box to fit
    // into). In a TIGHT context (GridView.count/childAspectRatio, which
    // hands down a fixed, non-negotiable cell height) the incoming
    // constraint simply overrides this request, exactly as any SizedBox
    // does. Either way, FittedBox below always receives a bounded box and
    // scales the fixed-size content DOWN to fit it — never overflowing,
    // never crashing on an infinite-height constraint.
    return SizedBox(
      height: height,
      child: SkeletonCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            height: _contentHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AppSkeleton(width: 32, height: 32, radius: AppRadius.md),
                const SizedBox(height: AppSpacing.sm),
                const AppSkeleton(width: 56, height: 17),
                const SizedBox(height: 6),
                AppSkeleton(width: height > 80 ? 76 : 56, height: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row-of-pill-shaped placeholders — for the filter-chip strips almost
/// every list screen renders above its data (category/status/date filters).
class SkeletonChipRow extends StatelessWidget {
  const SkeletonChipRow({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) => AppSkeleton(width: 70 + (i % 3) * 18, height: 34, radius: AppRadius.pill),
      ),
    );
  }
}

/// One list-row-shaped placeholder — avatar/leading circle + two text
/// lines + an optional trailing chip — for the simple "search + filtered
/// row list" screens (transactions, vendors, coaches, staff, programs…).
class SkeletonListRow extends StatelessWidget {
  const SkeletonListRow({super.key, this.trailing = true});

  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return SkeletonCard(
      child: Row(
        children: [
          const AppSkeleton(width: 40, height: 40, radius: AppRadius.md),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                AppSkeleton(width: 140, height: 13),
                SizedBox(height: AppSpacing.sm),
                AppSkeleton(width: 90, height: 11),
              ],
            ),
          ),
          if (trailing) ...[
            const SizedBox(width: AppSpacing.md),
            const AppSkeleton(width: 48, height: 18, radius: AppRadius.pill),
          ],
        ],
      ),
    );
  }
}

/// A stack of card-shaped skeletons — the default page-load placeholder for
/// the app's list screens.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      physics: const NeverScrollableScrollPhysics(),
      // Placed inside a Column / SingleChildScrollView on most screens
      // (ResponsivePage), where the incoming height is unbounded — a
      // non-shrink-wrapped ListView there renders nothing (a blank page)
      // while the request is in flight.
      shrinkWrap: true,
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, _) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: tokens.surface1,
          border: Border.all(color: tokens.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppSkeleton(width: 40, height: 40, radius: AppRadius.md),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeleton(width: 140, height: 13),
                      SizedBox(height: AppSpacing.sm),
                      AppSkeleton(width: 90, height: 11),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.md),
            AppSkeleton(height: 11),
            SizedBox(height: AppSpacing.sm),
            AppSkeleton(width: 200, height: 11),
          ],
        ),
      ),
    );
  }
}
