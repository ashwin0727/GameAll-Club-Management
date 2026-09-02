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
