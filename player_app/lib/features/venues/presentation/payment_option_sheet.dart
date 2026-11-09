import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/pressable.dart';
import '../../my_bookings/domain/cancellation_quote.dart';
import '../domain/venue.dart' show rupees;

/// The two ways to pay for a court booking: "ADVANCE" (50% now, the rest before the booking ends) or "FULL".
class PaymentOption {
  static const advance = 'ADVANCE';
  static const full = 'FULL';
}

/// Asks "Pay 50% now or pay the full amount?" once the court and time are chosen. Returns [PaymentOption.advance],
/// [PaymentOption.full], or null when the player closes it. [totalMinor] is the booking price in paise (null when it is not known).
Future<String?> showPaymentOptionSheet(
  BuildContext context, {
  required int? totalMinor,
}) {
  final wide =
      MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;
  final content = PaymentOptionPanel(totalMinor: totalMinor);
  if (wide) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ctx.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(padding: const EdgeInsets.all(22), child: content),
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: content,
      ),
    ),
  );
}

class PaymentOptionPanel extends StatefulWidget {
  const PaymentOptionPanel({super.key, required this.totalMinor});

  final int? totalMinor;

  @override
  State<PaymentOptionPanel> createState() => _PaymentOptionPanelState();
}

class _PaymentOptionPanelState extends State<PaymentOptionPanel> {
  String? _picked;

  int? get _total =>
      widget.totalMinor == null ? null : (widget.totalMinor! / 100).round();
  int? get _half => widget.totalMinor == null
      ? null
      : (((widget.totalMinor! + 1) ~/ 2) / 100).ceil();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    Widget option({
      required Key key,
      required String value,
      required String title,
      required String amountLine,
      required String note,
      String? badge,
    }) {
      final on = _picked == value;
      return Pressable(
        key: key,
        onTap: () => setState(() => _picked = value),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? AppColors.violet : p.border,
              width: on ? 2 : 1,
            ),
            color: on
                ? AppColors.violet.withValues(alpha: 0.10)
                : Colors.transparent,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  on
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: on ? AppColors.violet : p.secondaryText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: AppTextStyles.cardHeading(p.primaryText)
                                .copyWith(fontSize: 16),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: AppColors.success.withValues(alpha: 0.16),
                            ),
                            child: Text(
                              badge,
                              style: AppTextStyles.meta(AppColors.success)
                                  .copyWith(fontSize: 11),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      amountLine,
                      style: AppTextStyles.body(p.primaryText)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(note, style: AppTextStyles.support(p.secondaryText)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final total = _total;
    final half = _half;
    final payNow = _picked == PaymentOption.advance
        ? half
        : (_picked == PaymentOption.full ? total : null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How would you like to pay?',
          style: AppTextStyles.sectionHeading(p.primaryText),
        ),
        const SizedBox(height: 4),
        Text(
          'Your court is held once this payment is done.',
          style: AppTextStyles.support(p.secondaryText),
        ),
        const SizedBox(height: 16),
        option(
          key: const ValueKey('pay-opt-advance'),
          value: PaymentOption.advance,
          title: 'Pay 50% now',
          amountLine: half == null
              ? 'Half now, the rest later'
              : '${rupees(half)} now  ·  ${rupees(total! - half)} later',
          note:
              'Pay the balance before your booking ends. The 50% advance is not refundable if you cancel.',
        ),
        const SizedBox(height: 12),
        option(
          key: const ValueKey('pay-opt-full'),
          value: PaymentOption.full,
          title: 'Pay full amount',
          amountLine: total == null ? 'The full amount now' : '${rupees(total)} now',
          note:
              'Nothing more to pay. Cancel early for a refund: 95% back with 12 hours or more to go.',
          badge: 'Best for refunds',
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('pay-opt-rules'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            title: Text(
              'See the refund rules',
              style: AppTextStyles.meta(p.highlight),
            ),
            children: [
              for (final (label, pct) in cancellationSchedule)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Cancel with $label left',
                          style: AppTextStyles.support(p.secondaryText),
                        ),
                      ),
                      Text(
                        '$pct% deducted',
                        style: AppTextStyles.support(p.primaryText),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Applies when the booking is paid in full. Refunds go back to your original payment method.',
                style: AppTextStyles.support(p.mutedText),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GameAllButton.gradient(
          key: const ValueKey('pay-opt-continue'),
          label: payNow == null ? 'Choose an option' : 'Continue · ${rupees(payNow)}',
          expand: true,
          onPressed: _picked == null
              ? null
              : () => Navigator.of(context).pop(_picked),
        ),
      ],
    );
  }
}
