import 'package:flutter/material.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'app_button.dart';
import 'skeleton.dart';

/// Centered progress indicator — used instead of ever briefly rendering a
/// real screen with "0"/empty placeholder values (item 37 of the spec,
/// applied consistently across every backend-driven screen).
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message, this.compact = false});

  final String? message;

  /// Spinner instead of skeleton — for small inline areas (a sheet, a card)
  /// where card-shaped placeholders would be more noise than signal.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Page loads get skeletons rather than a spinner on empty space: the
    // placeholder holds the shape of the incoming content, so the screen
    // reads as "loading" instead of "broken" and nothing jumps when the
    // data arrives.
    if (!compact) return const SkeletonList();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A friendly, non-technical error message + retry — never a raw
/// Postgrest/Supabase exception string (item 39).
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ResponsivePage(
        scrollable: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.destructive, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SecondaryButton(label: 'Try Again', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

/// An actionable empty state — never a bare blank screen (item 38).
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;

  /// Short headline above [message]. Falls back to a neutral one so a bare
  /// call site still reads as a designed state rather than stray grey text.
  final String? title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        child: ConstrainedBox(
          // Keeps the block compact and centred instead of letting one line
          // of text float in a large empty page.
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tokens.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon ?? Icons.inbox_outlined,
                  size: 26,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title ?? 'Nothing here yet',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}