import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/misc.dart';
import 'payment_checkout_controller.dart';

/// The one reusable payment-status presentation — mirrors
/// src/features/payments/components/payment-status-panel.tsx (spec
/// §"Payment Status Screen"), used inline inside every payment-triggering
/// sheet instead of each one inventing its own copy. Never claims success
/// for anything short of the server's own [CheckoutCaptured] result;
/// [CheckoutPending] always offers a manual recheck rather than implying the
/// payment failed. Pass `isProcessing: true` while a checkout attempt is in
/// flight, and the terminal [CheckoutResult] once it resolves — a
/// [CheckoutCancelled] result renders nothing, same as the web component.
class PaymentStatusPanel extends StatelessWidget {
  const PaymentStatusPanel({
    super.key,
    required this.state,
    this.isProcessing = false,
    this.isCheckingAgain = false,
    this.onCheckAgain,
    this.onRetry,
  });

  final CheckoutResult? state;
  final bool isProcessing;
  final bool isCheckingAgain;
  final VoidCallback? onCheckAgain;
  final VoidCallback? onRetry;

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

    if (result is CheckoutCaptured) {
      return _panel(
        context,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBadge(label: 'Payment Successful', tone: StatusTone.success),
            SizedBox(height: AppSpacing.xs),
            Text('Your payment has been confirmed.', style: TextStyle(color: AppColors.muted)),
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