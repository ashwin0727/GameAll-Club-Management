import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/pressable.dart';
import '../../domain/player_dashboard_models.dart';

/// The slim line on Home (phone) that says how many payments are pending; tapping it opens the reminder popup again.
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({super.key, required this.payments, required this.onTap});

  final List<PendingPayment> payments;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final urgent = payments.any((x) => x.urgent);
    final tint = urgent ? AppColors.danger : AppColors.warning;
    final n = payments.length;
    return Semantics(
      button: true,
      label: '$n payment${n == 1 ? '' : 's'} pending. View',
      child: Pressable(
        key: const ValueKey('payment-prompts'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tint.withValues(alpha: 0.55)),
            color: Color.alphaBlend(
              tint.withValues(alpha: p.isDark ? 0.12 : 0.08),
              p.surface,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 22, color: tint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  n == 1 ? '1 payment pending' : '$n payments pending',
                  style: AppTextStyles.cardHeading(
                    p.primaryText,
                  ).copyWith(fontSize: 15),
                ),
              ),
              Text(
                'View',
                style: AppTextStyles.button(tint).copyWith(fontSize: 14),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: tint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The warning popup: one pending payment at a time with left / right arrows when there are several, and a Pay button that is
/// always enabled. Closing it (X, outside tap or back) just dismisses it (pops null); Pay pops the payment to settle.
class PaymentReminderDialog extends StatefulWidget {
  const PaymentReminderDialog({super.key, required this.payments});

  final List<PendingPayment> payments;

  @override
  State<PaymentReminderDialog> createState() => _PaymentReminderDialogState();
}

class _PaymentReminderDialogState extends State<PaymentReminderDialog> {
  var _i = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = widget.payments;
    final pay = list[_i];
    final copy = paymentPromptCopy(pay);
    final tint = pay.urgent ? AppColors.danger : AppColors.warning;
    final many = list.length > 1;

    Widget arrow(IconData icon, String label, String key, int to) => IconButton(
      key: ValueKey(key),
      tooltip: label,
      onPressed: to < 0 || to >= list.length
          ? null
          : () => setState(() => _i = to),
      icon: Icon(icon, size: 28),
      color: p.primaryText,
      disabledColor: p.mutedText.withValues(alpha: 0.4),
    );

    return Dialog(
      key: const ValueKey('payment-reminder'),
      backgroundColor: p.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: tint.withValues(alpha: 0.6)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 26, color: tint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      many
                          ? 'Payment pending (${_i + 1} of ${list.length})'
                          : 'Payment pending',
                      style: AppTextStyles.cardHeading(
                        tint,
                      ).copyWith(fontSize: 15),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('reminder-close'),
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: p.secondaryText),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                copy.title,
                key: ValueKey('reminder-title-${pay.kind.name}-${pay.id}'),
                style: AppTextStyles.cardHeading(
                  p.primaryText,
                ).copyWith(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(copy.message, style: AppTextStyles.support(p.secondaryText)),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (many)
                    arrow(
                      Icons.chevron_left_rounded,
                      'Previous',
                      'reminder-prev',
                      _i - 1,
                    ),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: copy.button,
                      child: ExcludeSemantics(
                        child: Pressable(
                          key: ValueKey(
                            'reminder-pay-${pay.kind.name}-${pay.id}',
                          ),
                          onTap: () => Navigator.of(context).pop(pay),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: LinearGradient(
                                colors: pay.urgent
                                    ? const [
                                        Color(0xFFFF6B82),
                                        Color(0xFFE0457B),
                                      ]
                                    : const [AppColors.blue, AppColors.violet],
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  copy.button,
                                  style: AppTextStyles.button(Colors.white),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (many)
                    arrow(
                      Icons.chevron_right_rounded,
                      'Next',
                      'reminder-next',
                      _i + 1,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
