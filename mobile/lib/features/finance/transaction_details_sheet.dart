import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import 'finance_presentation.dart';

/// Opens the transaction details view. A modal bottom sheet is this app's
/// established stand-in for the web's dialog (see the members/memberships
/// sheets), so Finance uses the same convention rather than pushing a route.
Future<void> showTransactionDetailsSheet(BuildContext context, {required String transactionId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => TransactionDetailsSheet(transactionId: transactionId),
  );
}

/// Mirrors src/features/finance/components/transaction-details-dialog.tsx.
///
/// Full traceability (spec §"Payment Traceability" / §"Transaction
/// Details"): transaction → payment order → Razorpay order/payment, and →
/// booking/membership. Every field shown is exactly what
/// `get_finance_transaction` returned — including the net amount, which is
/// the view's own `net_minor`, not paid-minus-refunded computed here.
class TransactionDetailsSheet extends ConsumerStatefulWidget {
  const TransactionDetailsSheet({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<TransactionDetailsSheet> createState() => _TransactionDetailsSheetState();
}

class _TransactionDetailsSheetState extends ConsumerState<TransactionDetailsSheet> {
  FinanceTransaction? _transaction;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final transaction = await ref.read(financeRepositoryProvider).getTransaction(widget.transactionId);
      if (!mounted) return;
      setState(() => _transaction = transaction);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = _transaction;
    return SafeArea(
      child: ConstrainedBox(
        // Never taller than most of the screen, and scrollable inside that —
        // a long details list plus a large system font must not overflow.
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Transaction Details', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.destructive))
              else if (transaction == null)
                const LoadingView()
              else ...[
                _DetailRow(label: 'Transaction ID', value: Text(transaction.reference)),
                _DetailRow(label: 'Date', value: Text(Formatters.dateTimeShort(transaction.effectiveAt))),
                _DetailRow(label: 'Customer', value: Text(transaction.customerName ?? '—')),
                if (transaction.customerPhone != null)
                  _DetailRow(label: 'Phone', value: Text(transaction.customerPhone!)),
                _DetailRow(label: 'Source', value: Text(sourceTypeLabel(transaction.sourceType))),
                if (transaction.bookingId != null)
                  _DetailRow(label: 'Booking', value: Text(transaction.bookingId!.substring(0, 8))),
                if (transaction.membershipId != null)
                  _DetailRow(label: 'Membership', value: Text(transaction.membershipId!.substring(0, 8))),
                _DetailRow(label: 'Total Paid', value: Text(financeAmount(transaction.amountMinor))),
                _DetailRow(label: 'Refunded Amount', value: Text(financeAmount(transaction.refundedMinor))),
                if (transaction.pendingRefundMinor > 0)
                  _DetailRow(label: 'Pending Refund', value: Text(financeAmount(transaction.pendingRefundMinor))),
                _DetailRow(label: 'Net Amount', value: Text(financeAmount(transaction.netMinor))),
                _DetailRow(label: 'Payment Method', value: Text(transaction.paymentMethod ?? '—')),
                _DetailRow(
                  label: 'Payment Status',
                  value: StatusBadge(
                    label: transactionStatusLabel(transaction.status),
                    tone: transactionStatusTone(transaction.status),
                  ),
                ),
                _DetailRow(label: 'Razorpay Order ID', value: Text(transaction.razorpayOrderId ?? '—')),
                _DetailRow(label: 'Razorpay Payment ID', value: Text(transaction.razorpayPaymentId ?? '—')),
                _DetailRow(label: 'Created At', value: Text(Formatters.dateTimeShort(transaction.createdAt))),
                _DetailRow(
                  label: 'Paid At',
                  value: Text(transaction.paidAt == null ? '—' : Formatters.dateTimeShort(transaction.paidAt!)),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label on the left, value on the right — both flexible, so a long Razorpay
/// id wraps instead of overflowing on a narrow screen.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppTypography.secondary(context))),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
                child: value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}