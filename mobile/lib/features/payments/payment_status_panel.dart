import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/misc.dart';
import 'payment_checkout_controller.dart';

/// The one reusable payment-status presentation — mirrors
/// src/features/payments/components/payment-status-panel.tsx (spec
/// §"Payment Status Screen"), used inline inside every payment-triggering
/// sheet instead of each one inventing its own copy. Never claims success
/// for anything short of the server's own [CheckoutSettled] result;
/// [CheckoutPending] always offers a manual recheck rather than implying the
/// payment failed, and a captured-but-unsettled payment surfaces as
/// [CheckoutException] (not silently as success, and not as a failure
/// either — the money is safe). Pass `isProcessing: true` while a checkout
/// attempt is in flight, and the terminal [CheckoutResult] once it resolves —
/// a [CheckoutCancelled] result renders nothing, same as the web component.
class PaymentStatusPanel extends StatelessWidget {
  const PaymentStatusPanel({
    super.key,
    required this.state,
    this.isProcessing = false,
    this.isCheckingAgain = false,
    this.onCheckAgain,
    this.onRetry,
    this.settledLabel = 'Payment Successful',
    this.resourceLabel = 'booking',
  });

  final CheckoutResult? state;
  final bool isProcessing;
  final bool isCheckingAgain;
  final VoidCallback? onCheckAgain;
  final VoidCallback? onRetry;

  /// What "settled" confirmed, e.g. "Booking Confirmed" / "Membership
  /// Activated". Defaults to a generic success message.
  final String settledLabel;

  /// The noun used in the "requires attention" exception copy, e.g.
  /// "booking" / "membership".
  final String resourceLabel;

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return _panel(
        context,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment Processing', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: AppSpacing.xs),
            Text("We're confirming your payment. Please wait…", style: TextStyle(color: AppColors.muted)),
          ],
        ),
      );
    }

    final result = state;
    if (result == null || result is CheckoutCancelled) {
      return const SizedBox.shrink();
    }

    if (result is CheckoutSettled) {
      return _panel(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBadge(label: settledLabel, tone: StatusTone.success),
            const SizedBox(height: AppSpacing.xs),
            const Text('Your payment has been confirmed.', style: TextStyle(color: AppColors.muted)),
          ],
        ),
      );
    }

    if (result is CheckoutException) {
      final resource = resourceLabel.isEmpty
          ? resourceLabel
          : resourceLabel[0].toUpperCase() + resourceLabel.substring(1);
      return _panel(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusBadge(label: 'Payment Received', tone: StatusTone.warning),
            const SizedBox(height: AppSpacing.xs),
            Text('$resource Requires Attention', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your payment was received, but we could not confirm this $resourceLabel. Our team will resolve your payment.',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    if (result is CheckoutFailed) {
      return _panel(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusBadge(label: 'Payment Failed', tone: StatusTone.danger),
            const SizedBox(height: AppSpacing.xs),
            const Text('Your payment could not be completed.', style: TextStyle(color: AppColors.muted)),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: onRetry, child: const Text('Try Again')),
            ],
          ],
        ),
      );
    }

    // CheckoutPending — signature/order checked out but Razorpay hasn't
    // conclusively reported authorized/captured yet, or verification itself
    // couldn't complete. Never presented as a failure.
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusBadge(label: 'Payment Status Pending', tone: StatusTone.warning),
          const SizedBox(height: AppSpacing.xs),
          const Text("We're still confirming your payment. Please check again shortly.", style: TextStyle(color: AppColors.muted)),
          if (onCheckAgain != null) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: isCheckingAgain ? null : onCheckAgain,
              child: Text(isCheckingAgain ? 'Checking…' : 'Check Again'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.mutedBackground.withValues(alpha: 0.4),
      ),
      child: child,
    );
  }
}