import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../auth/application/auth_providers.dart';
import '../../my_membership/presentation/details_widgets.dart';
import '../../payments/application/payment_flow.dart';
import '../../payments/data/receipt_pdf.dart';
import '../../payments/domain/payment_receipt.dart';
import '../../venues/domain/venue.dart';
import '../application/profile_providers.dart';
import '../domain/profile_models.dart';
import 'profile_widgets.dart';

/// Payment & Billing: every payment (with its status), the invoices (a receipt to download for each paid one) and the refunds.
class PaymentsBillingPage extends ConsumerStatefulWidget {
  const PaymentsBillingPage({super.key});

  @override
  ConsumerState<PaymentsBillingPage> createState() =>
      _PaymentsBillingPageState();
}

class _PaymentsBillingPageState extends ConsumerState<PaymentsBillingPage> {
  var _tab = 0; // 0 Payments, 1 Invoices, 2 Refunds
  String? _busy;

  PaymentKind _kind(String source) => switch (source) {
    'membership' => PaymentKind.membership,
    'coaching' => PaymentKind.coaching,
    _ => PaymentKind.booking,
  };

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Builds the PDF receipt for the paid item behind a payment and hands it to the saver (download on web, share sheet on Android).
  Future<void> _download(PaymentRecord r) async {
    final repo = ref.read(paymentReceiptRepositoryProvider);
    final player = ref.read(currentPlayerProvider);
    final saver = ref.read(receiptSaverProvider);
    final logoLoader = ref.read(receiptLogoProvider);
    setState(() => _busy = r.id);
    try {
      final receipt = await repo.receipt(_kind(r.source), r.sourceId);
      if (receipt == null) {
        _say("We couldn't find the receipt for this payment.");
        return;
      }
      final logo = await logoLoader();
      final bytes = await buildReceiptPdf(
        receipt,
        playerName: player?.fullName,
        playerPhone: player?.phone,
        logoPng: logo,
      );
      await saver(bytes, receiptFileName(receipt));
      _say('Your receipt is ready.');
    } catch (_) {
      _say("We couldn't create the receipt. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final async = ref.watch(paymentHistoryProvider);
    final all = async.value ?? const <PaymentRecord>[];
    final shown = switch (_tab) {
      1 => [
        for (final r in all)
          if (r.isPaid) r,
      ],
      2 => [
        for (final r in all)
          if (r.isRefund) r,
      ],
      _ => [
        for (final r in all)
          if (!r.isRefund) r,
      ],
    };
    final paidTotal = [
      for (final r in all)
        if (r.isPaid) r.amountInr,
    ].fold<int>(0, (a, b) => a + b);
    final refundTotal = [
      for (final r in all)
        if (r.isRefund && r.status == 'PROCESSED') r.amountInr,
    ].fold<int>(0, (a, b) => a + b);

    Widget row(PaymentRecord r) {
      final tone = r.isRefund
          ? (r.status == 'FAILED' ? AppColors.danger : AppColors.cyan)
          : switch (r.status) {
              'PAID' => AppColors.success,
              'FAILED' => AppColors.danger,
              'REFUNDED' => AppColors.cyan,
              _ => AppColors.warning,
            };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: tone.withValues(alpha: 0.14),
              ),
              child: Icon(
                r.isRefund
                    ? Icons.undo_rounded
                    : switch (r.source) {
                        'membership' => Icons.workspace_premium_outlined,
                        'coaching' => Icons.school_outlined,
                        _ => Icons.calendar_month_outlined,
                      },
                size: 20,
                color: tone,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.isRefund ? 'Refund · ${r.sourceLabel}' : r.sourceLabel,
                    style: AppTextStyles.cardHeading(p.primaryText)
                        .copyWith(fontSize: 15),
                  ),
                  if (r.venueName.isNotEmpty)
                    Text(
                      r.venueName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.support(p.secondaryText),
                    ),
                  Text(
                    '${shortDate(r.at)}${r.method == null || r.method!.isEmpty ? '' : '  ·  ${r.method}'}',
                    style: AppTextStyles.support(p.mutedText),
                  ),
                  if (r.isPaid) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 34,
                      child: GameAllButton.secondary(
                        key: ValueKey('pay-receipt-${r.id}'),
                        label: _busy == r.id
                            ? 'Preparing…'
                            : 'Download receipt',
                        icon: Icons.download_rounded,
                        height: 34,
                        onPressed: _busy == null ? () => _download(r) : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${r.isRefund ? '+' : ''}${rupees(r.amountInr)}',
                  style: AppTextStyles.cardHeading(p.primaryText)
                      .copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: tone.withValues(alpha: 0.16),
                  ),
                  child: Text(
                    r.statusLabel,
                    style: AppTextStyles.meta(tone).copyWith(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return ProfileSubPage(
      title: 'Payment & Billing',
      child: ProfileColumns(
        leftFlex: 2,
        rightFlex: 5,
        left: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfilePanel(
              child: Row(
                children: [
                  Expanded(
                    child: _Total(
                      label: 'Total paid',
                      value: rupees(paidTotal),
                    ),
                  ),
                  Container(width: 1, height: 36, color: p.border),
                  Expanded(
                    child: _Total(
                      label: 'Refunded',
                      value: rupees(refundTotal),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            PillTabs(
              labels: const ['Payments', 'Invoices', 'Refunds'],
              current: _tab,
              onTab: (i) => setState(() => _tab = i),
              keyOf: (i) => 'pb-tab-$i',
            ),
            const SizedBox(height: 8),
          ],
        ),
        right: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (async.isLoading && !async.hasValue)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (async.hasError && !async.hasValue)
              Column(
                key: const ValueKey('pb-error'),
                children: [
                  const SizedBox(height: 40),
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 40,
                    color: p.secondaryText,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "We couldn't load your payments just now.",
                    style: AppTextStyles.body(p.primaryText),
                  ),
                  const SizedBox(height: 14),
                  GameAllButton.secondary(
                    label: 'Try again',
                    onPressed: () => ref.invalidate(paymentHistoryProvider),
                  ),
                ],
              )
            else if (shown.isEmpty)
              ProfileEmpty(switch (_tab) {
                1 => 'No invoices yet. A receipt appears here once you pay.',
                2 => 'No refunds.',
                _ => 'No payments yet.',
              }, icon: Icons.receipt_long_outlined)
            else
              ProfilePanel(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0) const ProfileDivider(),
                      row(shown[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        Text(value, style: AppTextStyles.cardHeading(p.primaryText)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.support(p.secondaryText)),
      ],
    );
  }
}
