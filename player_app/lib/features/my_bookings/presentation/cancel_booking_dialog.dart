import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../venues/domain/venue.dart' show rupees;
import '../domain/cancellation_quote.dart';
import '../domain/guest_booking.dart';

/// "Cancel this booking?": says, before anything happens, how many hours are left, the % that is deducted, and the amount that comes
/// back, in plain words. Returns true when the player confirms.
Future<bool> showCancelBookingDialog(
  BuildContext context, {
  required GuestBooking booking,
  required CancellationQuote quote,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => _CancelDialog(booking: booking, quote: quote),
  );
  return ok == true;
}

/// The sentence shown after the booking is cancelled.
String cancelledMessage(CancellationQuote q) {
  if (q.nothingPaid) return 'Your booking is cancelled.';
  if (q.hasRefund) {
    return 'Your booking is cancelled. ${rupees(q.refundInr)} will be refunded to your original payment method in 5–7 working days.';
  }
  return 'Your booking is cancelled. As per the cancellation rules, no refund applies.';
}

class _CancelDialog extends StatelessWidget {
  const _CancelDialog({required this.booking, required this.quote});

  final GuestBooking booking;
  final CancellationQuote quote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = quote;
    final b = booking;
    final danger = !q.hasRefund && !q.nothingPaid;

    Widget row(String label, String value, {Color? tone, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: AppTextStyles.body(p.secondaryText)),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                style: AppTextStyles.body(tone ?? p.primaryText).copyWith(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        );

    return AlertDialog(
      key: const ValueKey('cancel-dialog'),
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        'Cancel this booking?',
        style: AppTextStyles.sectionHeading(p.primaryText),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${b.venue.name}\n${shortDate(b.start)}  ·  ${timeRange(b.start, b.end)}',
                style: AppTextStyles.support(p.secondaryText),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: (danger ? AppColors.danger : AppColors.cyan).withValues(
                    alpha: 0.10,
                  ),
                  border: Border.all(
                    color: (danger ? AppColors.danger : AppColors.cyan)
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  q.message,
                  key: const ValueKey('cancel-message'),
                  style: AppTextStyles.body(p.primaryText),
                ),
              ),
              if (!q.nothingPaid) ...[
                const SizedBox(height: 12),
                row('Amount paid', rupees(q.paidInr)),
                row(
                  q.rule == 'ADVANCE_ONLY' || q.rule == 'STARTED'
                      ? 'Deduction (100%)'
                      : 'Deduction (${q.deductionPercent}%)',
                  q.deductionMinor == 0 ? '₹0' : '− ${rupees(q.deductionInr)}',
                  tone: q.deductionMinor == 0 ? null : AppColors.danger,
                ),
                Divider(color: p.border),
                row(
                  'You get back',
                  rupees(q.refundInr),
                  tone: q.hasRefund ? AppColors.success : p.primaryText,
                  bold: true,
                ),
                if (q.hasRefund)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Refunds go back to your original payment method in 5–7 working days.',
                      style: AppTextStyles.support(p.mutedText),
                    ),
                  ),
              ],
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const ValueKey('cancel-schedule'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    'See the refund rules',
                    style: AppTextStyles.meta(p.highlight),
                  ),
                  children: [
                    Text(
                      'If the booking is paid in full:',
                      style: AppTextStyles.support(p.secondaryText),
                    ),
                    const SizedBox(height: 6),
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
                    const SizedBox(height: 8),
                    Text(
                      'If only the 50% advance is paid, the advance is not refunded.',
                      style: AppTextStyles.support(p.secondaryText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancel-keep'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep booking'),
        ),
        GameAllButton.gradient(
          key: const ValueKey('cancel-confirm'),
          label: 'Yes, cancel booking',
          height: 44,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
